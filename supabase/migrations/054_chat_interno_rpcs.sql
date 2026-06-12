-- ============================================================
-- 054: RPCs del chat interno del proveedor
-- ============================================================

-- Contactos con los que el usuario puede iniciar un DM (según la matriz).
CREATE OR REPLACE FUNCTION contactos_chat()
RETURNS TABLE (id uuid, nombre_completo text, rol_en_empresa text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_rol text; v_empresa uuid; v_equipo uuid;
BEGIN
  SELECT rol_en_empresa, empresa_id, equipo_id INTO v_rol, v_empresa, v_equipo
  FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
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
GRANT EXECUTE ON FUNCTION contactos_chat() TO authenticated;

-- Abrir (o crear) el canal de Administración de mi empresa.
CREATE OR REPLACE FUNCTION abrir_canal_administracion()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_empresa uuid; v_rol text; v_id uuid;
BEGIN
  SELECT empresa_id, rol_en_empresa INTO v_empresa, v_rol FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  IF v_empresa IS NULL OR v_rol NOT IN ('admin','editor','supervisor','catalogo','marketing','finanzas') THEN
    RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT id INTO v_id FROM chat_conversaciones WHERE empresa_id = v_empresa AND tipo = 'administracion';
  IF v_id IS NULL THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo, nombre) VALUES (v_empresa, 'administracion', 'Administración') RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END; $$;
GRANT EXECUTE ON FUNCTION abrir_canal_administracion() TO authenticated;

-- Abrir (o crear) el canal de un equipo.
CREATE OR REPLACE FUNCTION abrir_canal_equipo(p_equipo uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_empresa uuid; v_id uuid; v_eq_empresa uuid; v_eq_nombre text;
BEGIN
  SELECT empresa_id INTO v_empresa FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  SELECT empresa_id, nombre INTO v_eq_empresa, v_eq_nombre FROM equipos_visitadores WHERE id = p_equipo;
  IF v_eq_empresa IS NULL OR v_eq_empresa <> v_empresa THEN RAISE EXCEPTION 'Equipo no válido'; END IF;
  IF NOT (mi_equipo_proveedor() = p_equipo
          OR EXISTS (SELECT 1 FROM equipos_visitadores e WHERE e.id = p_equipo AND e.supervisor_id = auth.uid())
          OR puede_auditar_chat()) THEN
    RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT id INTO v_id FROM chat_conversaciones WHERE tipo = 'equipo' AND equipo_id = p_equipo;
  IF v_id IS NULL THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo, equipo_id, nombre) VALUES (v_empresa, 'equipo', p_equipo, v_eq_nombre) RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END; $$;
GRANT EXECUTE ON FUNCTION abrir_canal_equipo(uuid) TO authenticated;

-- Abrir (o crear) un DM 1-a-1 con un contacto permitido.
CREATE OR REPLACE FUNCTION abrir_directo(p_otro uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_empresa uuid; v_id uuid;
BEGIN
  SELECT empresa_id INTO v_empresa FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  IF v_empresa IS NULL THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF NOT EXISTS (SELECT 1 FROM contactos_chat() WHERE id = p_otro) THEN
    RAISE EXCEPTION 'No puedes iniciar chat con esa persona'; END IF;
  SELECT c.id INTO v_id FROM chat_conversaciones c
  WHERE c.tipo = 'directo' AND c.empresa_id = v_empresa
    AND EXISTS (SELECT 1 FROM chat_participantes p WHERE p.conversacion_id = c.id AND p.cuenta_id = auth.uid())
    AND EXISTS (SELECT 1 FROM chat_participantes p WHERE p.conversacion_id = c.id AND p.cuenta_id = p_otro)
    AND (SELECT count(*) FROM chat_participantes p WHERE p.conversacion_id = c.id) = 2
  LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo) VALUES (v_empresa, 'directo') RETURNING id INTO v_id;
    INSERT INTO chat_participantes (conversacion_id, cuenta_id) VALUES (v_id, auth.uid()), (v_id, p_otro);
  END IF;
  RETURN v_id;
END; $$;
GRANT EXECUTE ON FUNCTION abrir_directo(uuid) TO authenticated;

-- Enviar mensaje.
CREATE OR REPLACE FUNCTION enviar_mensaje_chat(p_conv uuid, p_cuerpo text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  IF p_cuerpo IS NULL OR length(trim(p_cuerpo)) = 0 THEN RAISE EXCEPTION 'Mensaje vacío'; END IF;
  IF NOT es_miembro_conversacion(p_conv) THEN RAISE EXCEPTION 'No puedes escribir en esta conversación'; END IF;
  INSERT INTO chat_mensajes_internos (conversacion_id, autor_id, cuerpo) VALUES (p_conv, auth.uid(), trim(p_cuerpo)) RETURNING id INTO v_id;
  INSERT INTO chat_lecturas (conversacion_id, cuenta_id, last_read_at) VALUES (p_conv, auth.uid(), now())
    ON CONFLICT (conversacion_id, cuenta_id) DO UPDATE SET last_read_at = now();
  RETURN v_id;
END; $$;
GRANT EXECUTE ON FUNCTION enviar_mensaje_chat(uuid, text) TO authenticated;

-- Marcar conversación como leída.
CREATE OR REPLACE FUNCTION marcar_leido_chat(p_conv uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT puede_ver_conversacion(p_conv) THEN RETURN; END IF;
  INSERT INTO chat_lecturas (conversacion_id, cuenta_id, last_read_at) VALUES (p_conv, auth.uid(), now())
    ON CONFLICT (conversacion_id, cuenta_id) DO UPDATE SET last_read_at = now();
END; $$;
GRANT EXECUTE ON FUNCTION marcar_leido_chat(uuid) TO authenticated;

-- Mis conversaciones con último mensaje y no-leídos.
CREATE OR REPLACE FUNCTION mis_conversaciones()
RETURNS TABLE (id uuid, tipo text, nombre text, equipo_id uuid, ultimo text, ultimo_at timestamptz, no_leidos int, es_auditoria boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
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
GRANT EXECUTE ON FUNCTION mis_conversaciones() TO authenticated;

-- Mensajes de una conversación con nombre del autor.
CREATE OR REPLACE FUNCTION mensajes_conversacion(p_conv uuid)
RETURNS TABLE (id uuid, autor_id uuid, autor_nombre text, cuerpo text, created_at timestamptz, eliminado boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT puede_ver_conversacion(p_conv) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  RETURN QUERY
  SELECT m.id, m.autor_id, cp.nombre_completo, m.cuerpo, m.created_at, m.eliminado
  FROM chat_mensajes_internos m
  JOIN cuentas_proveedor cp ON cp.id = m.autor_id
  WHERE m.conversacion_id = p_conv
  ORDER BY m.created_at ASC;
END; $$;
GRANT EXECUTE ON FUNCTION mensajes_conversacion(uuid) TO authenticated;

-- Admin: delegar/retirar acceso de auditoría de chat.
CREATE OR REPLACE FUNCTION cambiar_auditoria_chat(p_id uuid, p_activo boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_caller_rol text; v_caller_empresa uuid; v_target_empresa uuid;
BEGIN
  SELECT rol_en_empresa, empresa_id INTO v_caller_rol, v_caller_empresa FROM cuentas_proveedor WHERE id = auth.uid();
  IF v_caller_rol IS DISTINCT FROM 'admin' THEN RAISE EXCEPTION 'Solo un administrador puede delegar la auditoría'; END IF;
  SELECT empresa_id INTO v_target_empresa FROM cuentas_proveedor WHERE id = p_id;
  IF v_target_empresa IS NULL OR v_target_empresa <> v_caller_empresa THEN RAISE EXCEPTION 'Ese usuario no es de tu empresa'; END IF;
  UPDATE cuentas_proveedor SET audita_chat = p_activo, updated_at = now() WHERE id = p_id;
END; $$;
GRANT EXECUTE ON FUNCTION cambiar_auditoria_chat(uuid, boolean) TO authenticated;
