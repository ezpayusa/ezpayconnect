-- ============================================================
-- 055: Correcciones del chat (ambigüedad de columnas + NULL en equipo)
-- ============================================================

-- es_miembro_conversacion: COALESCE para que (v_equipo = c_equipo) con NULL sea false.
CREATE OR REPLACE FUNCTION es_miembro_conversacion(p_conv uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE c_empresa uuid; c_tipo text; c_equipo uuid; v_rol text; v_empresa uuid; v_equipo uuid;
BEGIN
  SELECT empresa_id, tipo, equipo_id INTO c_empresa, c_tipo, c_equipo FROM chat_conversaciones WHERE id = p_conv;
  IF c_empresa IS NULL THEN RETURN false; END IF;
  SELECT rol_en_empresa, empresa_id, equipo_id INTO v_rol, v_empresa, v_equipo FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  IF v_empresa IS NULL OR v_empresa <> c_empresa THEN RETURN false; END IF;
  IF c_tipo = 'administracion' THEN
    RETURN v_rol IN ('admin','editor','supervisor','catalogo','marketing','finanzas');
  ELSIF c_tipo = 'equipo' THEN
    RETURN COALESCE(v_equipo = c_equipo, false) OR EXISTS (SELECT 1 FROM equipos_visitadores WHERE id = c_equipo AND supervisor_id = auth.uid());
  ELSIF c_tipo = 'directo' THEN
    RETURN EXISTS (SELECT 1 FROM chat_participantes WHERE conversacion_id = p_conv AND cuenta_id = auth.uid());
  END IF;
  RETURN false;
END; $$;

-- abrir_canal_equipo: COALESCE en la comparación de equipo.
CREATE OR REPLACE FUNCTION abrir_canal_equipo(p_equipo uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_empresa uuid; v_id uuid; v_eq_empresa uuid; v_eq_nombre text;
BEGIN
  SELECT empresa_id INTO v_empresa FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  SELECT empresa_id, nombre INTO v_eq_empresa, v_eq_nombre FROM equipos_visitadores WHERE id = p_equipo;
  IF v_eq_empresa IS NULL OR v_eq_empresa <> v_empresa THEN RAISE EXCEPTION 'Equipo no válido'; END IF;
  IF NOT (COALESCE(mi_equipo_proveedor() = p_equipo, false)
          OR EXISTS (SELECT 1 FROM equipos_visitadores e WHERE e.id = p_equipo AND e.supervisor_id = auth.uid())
          OR puede_auditar_chat()) THEN
    RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT id INTO v_id FROM chat_conversaciones WHERE tipo = 'equipo' AND equipo_id = p_equipo;
  IF v_id IS NULL THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo, equipo_id, nombre) VALUES (v_empresa, 'equipo', p_equipo, v_eq_nombre) RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END; $$;

-- contactos_chat: use_column resuelve la ambigüedad de nombres de columna.
CREATE OR REPLACE FUNCTION contactos_chat()
RETURNS TABLE (id uuid, nombre_completo text, rol_en_empresa text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
#variable_conflict use_column
DECLARE v_rol text; v_empresa uuid; v_equipo uuid;
BEGIN
  SELECT cp.rol_en_empresa, cp.empresa_id, cp.equipo_id INTO v_rol, v_empresa, v_equipo
  FROM cuentas_proveedor cp WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_empresa IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT cp.id, cp.nombre_completo, cp.rol_en_empresa
  FROM cuentas_proveedor cp
  WHERE cp.empresa_id = v_empresa AND cp.activo = true AND cp.id <> auth.uid()
    AND (
      v_rol IN ('admin','editor')
      OR (v_rol IN ('catalogo','marketing','finanzas','supervisor')
          AND cp.rol_en_empresa IN ('admin','editor','catalogo','marketing','finanzas','supervisor'))
      OR (v_rol = 'supervisor'
          AND cp.equipo_id IN (SELECT e.id FROM equipos_visitadores e WHERE e.supervisor_id = auth.uid()))
      OR (v_rol = 'visitador_medico' AND (
            cp.rol_en_empresa IN ('admin','editor')
            OR (v_equipo IS NOT NULL AND cp.equipo_id = v_equipo)
            OR (v_equipo IS NOT NULL AND cp.id IN (SELECT e.supervisor_id FROM equipos_visitadores e WHERE e.id = v_equipo))
      ))
    );
END; $$;

-- mis_conversaciones: use_column.
CREATE OR REPLACE FUNCTION mis_conversaciones()
RETURNS TABLE (id uuid, tipo text, nombre text, equipo_id uuid, ultimo text, ultimo_at timestamptz, no_leidos int, es_auditoria boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  RETURN QUERY
  SELECT
    c.id, c.tipo,
    CASE WHEN c.tipo = 'directo'
      THEN (SELECT cp.nombre_completo FROM chat_participantes p JOIN cuentas_proveedor cp ON cp.id = p.cuenta_id
            WHERE p.conversacion_id = c.id AND p.cuenta_id <> auth.uid() LIMIT 1)
      ELSE c.nombre END,
    c.equipo_id,
    (SELECT m.cuerpo FROM chat_mensajes_internos m WHERE m.conversacion_id = c.id AND NOT m.eliminado ORDER BY m.created_at DESC LIMIT 1),
    (SELECT m.created_at FROM chat_mensajes_internos m WHERE m.conversacion_id = c.id AND NOT m.eliminado ORDER BY m.created_at DESC LIMIT 1),
    (SELECT count(*)::int FROM chat_mensajes_internos m WHERE m.conversacion_id = c.id AND NOT m.eliminado AND m.autor_id <> auth.uid()
       AND m.created_at > COALESCE((SELECT l.last_read_at FROM chat_lecturas l WHERE l.conversacion_id = c.id AND l.cuenta_id = auth.uid()), 'epoch'::timestamptz)),
    (NOT es_miembro_conversacion(c.id))
  FROM chat_conversaciones c
  WHERE c.empresa_id = mi_empresa_proveedor() AND puede_ver_conversacion(c.id)
  ORDER BY 6 DESC NULLS LAST;
END; $$;

-- mensajes_conversacion: use_column.
CREATE OR REPLACE FUNCTION mensajes_conversacion(p_conv uuid)
RETURNS TABLE (id uuid, autor_id uuid, autor_nombre text, cuerpo text, created_at timestamptz, eliminado boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  IF NOT puede_ver_conversacion(p_conv) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  RETURN QUERY
  SELECT m.id, m.autor_id, cp.nombre_completo, m.cuerpo, m.created_at, m.eliminado
  FROM chat_mensajes_internos m
  JOIN cuentas_proveedor cp ON cp.id = m.autor_id
  WHERE m.conversacion_id = p_conv
  ORDER BY m.created_at ASC;
END; $$;
