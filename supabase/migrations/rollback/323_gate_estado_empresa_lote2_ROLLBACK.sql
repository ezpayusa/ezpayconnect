-- ROLLBACK mig 323 — restaura 27 funciones + 5 policies desde el snapshot vivo, DROP de las nuevas.


DROP POLICY "Proveedor ve su propia empresa" ON public.empresas_proveedoras;
CREATE POLICY "Proveedor ve su propia empresa" ON public.empresas_proveedoras
  FOR SELECT USING (id = get_empresa_id_session());
DROP POLICY "Proveedor admin ve cuentas de su empresa" ON public.cuentas_proveedor;
CREATE POLICY "Proveedor admin ve cuentas de su empresa" ON public.cuentas_proveedor
  FOR SELECT USING (empresa_id = get_empresa_id_proveedor());
DROP POLICY "Proveedor actualiza su propia empresa" ON public.empresas_proveedoras;
CREATE POLICY "Proveedor actualiza su propia empresa" ON public.empresas_proveedoras
  FOR UPDATE USING ((id = get_empresa_id_session()) AND (EXISTS ( SELECT 1 FROM cuentas_proveedor
    WHERE ((cuentas_proveedor.id = auth.uid()) AND (cuentas_proveedor.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text]))))));
DROP POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana;
CREATE POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana
  FOR UPDATE TO authenticated
  USING ((COALESCE((empresa_id = mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (EXISTS ( SELECT 1 FROM cuentas_proveedor cp WHERE ((cp.id = auth.uid()) AND (cp.empresa_id = solicitudes_campana.empresa_id) AND (cp.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text])))))) AND (estado = ANY (ARRAY['borrador'::text, 'enviada'::text, 'rechazada'::text]))))
  WITH CHECK ((COALESCE((empresa_id = mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (EXISTS ( SELECT 1 FROM cuentas_proveedor cp WHERE ((cp.id = auth.uid()) AND (cp.empresa_id = solicitudes_campana.empresa_id) AND (cp.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text])))))) AND (estado = ANY (ARRAY['borrador'::text, 'enviada'::text, 'rechazada'::text]))));
DROP POLICY "Proveedor crea campañas" ON public.solicitudes_campana;
CREATE POLICY "Proveedor crea campañas" ON public.solicitudes_campana
  FOR INSERT TO authenticated
  WITH CHECK ((COALESCE((empresa_id = mi_empresa_proveedor()), false) AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR (EXISTS ( SELECT 1 FROM cuentas_proveedor cp WHERE ((cp.id = auth.uid()) AND (cp.empresa_id = solicitudes_campana.empresa_id) AND (cp.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text])))))) AND (estado = ANY (ARRAY['borrador'::text, 'enviada'::text])) AND COALESCE(private.empresa_opera_en_pais(empresa_id, pais_id), false)));


DROP FUNCTION IF EXISTS private.exigir_empresa_activa();
DROP FUNCTION IF EXISTS private.mi_empresa_propia();


CREATE OR REPLACE FUNCTION public.get_empresa_id_proveedor()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa = 'admin' LIMIT 1;
$function$;


CREATE OR REPLACE FUNCTION public.get_empresa_id_session()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() LIMIT 1;
$function$;


CREATE OR REPLACE FUNCTION private.mi_pais()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(
    (SELECT pais_id FROM public.perfiles WHERE id = auth.uid()),
    (SELECT pais_id FROM public.cuentas_proveedor WHERE id = auth.uid()),
    (SELECT e.pais_id FROM public.cuentas_proveedor cp
       JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
      WHERE cp.id = auth.uid())
  );
$function$;


CREATE OR REPLACE FUNCTION private.mi_sucursal()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT cp.sucursal_id
  FROM public.cuentas_proveedor cp
  WHERE cp.id = auth.uid()
  LIMIT 1;   -- PK garantiza ≤1 fila; LIMIT 1 evita "more than one row" ante cualquier anomalía
$function$;


CREATE OR REPLACE FUNCTION private.puede_aprobar_visitas()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.cuentas_proveedor cp
    WHERE cp.id = auth.uid()
      AND cp.activo = true
      AND cp.rol_en_empresa IN ('admin', 'supervisor', 'editor')
  );
$function$;


CREATE OR REPLACE FUNCTION public.puede_auditar_chat()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT EXISTS (SELECT 1 FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true AND (rol_en_empresa='admin' OR audita_chat=true)); $function$;


CREATE OR REPLACE FUNCTION public.es_miembro_conversacion(p_conv uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END; $function$;


CREATE OR REPLACE FUNCTION private.tiene_permiso(p_accion text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH me AS (
    SELECT cp.empresa_id AS emp, cp.rol_en_empresa AS rol, e.tipo AS tipo
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
    WHERE cp.id = auth.uid() AND cp.activo = true
    LIMIT 1
  ),
  cat AS (   -- default del catálogo para (tipo de SU empresa, su rol, accion)
    SELECT EXISTS (
      SELECT 1 FROM public.permisos_empresa_rol per JOIN me ON per.tipo_empresa = me.tipo AND per.rol = me.rol
      WHERE per.accion = p_accion
    ) AS d
  ),
  ovr AS (   -- override per (empresa, rol, accion)
    SELECT o.concedido AS c
    FROM public.permisos_empresa_rol_override o JOIN me ON o.empresa_id = me.emp AND o.rol = me.rol
    WHERE o.accion = p_accion
    LIMIT 1
  )
  SELECT COALESCE(
    CASE
      WHEN EXISTS (SELECT 1 FROM public.acciones_techo t WHERE t.accion = p_accion)
        THEN (SELECT d FROM cat)                           -- TECHO: ignora el override
      ELSE COALESCE((SELECT c FROM ovr), (SELECT d FROM cat))
    END, false);                                            -- fail-closed
$function$;


CREATE OR REPLACE FUNCTION public.supervisa_cuenta_proveedor(p_cuenta_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM cuentas_proveedor cp
    JOIN equipos_visitadores e ON e.id = cp.equipo_id
    WHERE cp.id = p_cuenta_id AND e.supervisor_id = auth.uid()
  );
$function$;


CREATE OR REPLACE FUNCTION public.contactos_chat()
 RETURNS TABLE(id uuid, nombre_completo text, rol_en_empresa text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END; $function$;


CREATE OR REPLACE FUNCTION public.get_visitas_proveedor()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa_id UUID;
  result jsonb;
BEGIN
  SELECT c.empresa_id INTO v_empresa_id 
  FROM cuentas_proveedor c 
  WHERE c.id = auth.uid();
  
  SELECT jsonb_agg(
    jsonb_build_object(
      'visita_id', v.id,
      'visita_medico_id', v.medico_id,
      'nombre_medico', p.nombre_completo,
      'email_medico', p.email,
      'fecha_visita', v.fecha_visita,
      'hora_inicio', v.hora_inicio,
      'hora_fin', v.hora_fin,
      'tipo_visita', v.tipo_visita,
      'estado', v.estado,
      'notas_empresa', v.notas_empresa,
      'created_at', v.created_at
    ) ORDER BY v.fecha_visita DESC, v.hora_inicio DESC
  ) INTO result
  FROM visitas_agendadas v
  JOIN perfiles p ON p.id = v.medico_id
  WHERE v.empresa_id = v_empresa_id;
  
  RETURN COALESCE(result, '[]'::jsonb);
END;
$function$;


CREATE OR REPLACE FUNCTION public.sincronizar_mis_canales()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_rol text; v_empresa uuid; v_equipo uuid; r RECORD;
BEGIN
  SELECT rol_en_empresa, empresa_id, equipo_id INTO v_rol, v_empresa, v_equipo
  FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  IF v_empresa IS NULL THEN RETURN; END IF;

  IF v_rol IN ('admin','editor','supervisor','catalogo','marketing','finanzas')
     AND NOT EXISTS (SELECT 1 FROM chat_conversaciones WHERE empresa_id = v_empresa AND tipo = 'administracion') THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo, nombre) VALUES (v_empresa, 'administracion', 'Administración');
  END IF;

  IF v_equipo IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM chat_conversaciones WHERE tipo = 'equipo' AND equipo_id = v_equipo) THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo, equipo_id, nombre)
    SELECT v_empresa, 'equipo', e.id, e.nombre FROM equipos_visitadores e WHERE e.id = v_equipo;
  END IF;

  FOR r IN SELECT e.id, e.nombre FROM equipos_visitadores e WHERE e.supervisor_id = auth.uid() AND e.empresa_id = v_empresa LOOP
    IF NOT EXISTS (SELECT 1 FROM chat_conversaciones WHERE tipo = 'equipo' AND equipo_id = r.id) THEN
      INSERT INTO chat_conversaciones (empresa_id, tipo, equipo_id, nombre) VALUES (v_empresa, 'equipo', r.id, r.nombre);
    END IF;
  END LOOP;
END; $function$;


CREATE OR REPLACE FUNCTION public.notificar_visita_resultado(p_visita_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; v_tipo text; v_email_tipo text;
        v_medico_nom text; v_empresa_nom text; v_fecha text; v_hora text; v_clinica_msg text; v_nid uuid; rec record;
BEGIN
  SELECT empresa_id, cuenta_proveedor_id, estado, medico_id, fecha_visita, hora_inicio
    INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller = admin/editor de la empresa de la visita. COALESCE fail-closed.
  IF NOT COALESCE((SELECT true FROM public.cuentas_proveedor WHERE id = auth.uid() AND empresa_id = v.empresa_id
                   AND activo = true AND rol_en_empresa IN ('admin','editor') LIMIT 1), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  IF v.estado NOT IN ('confirmada','rechazada') THEN RETURN; END IF;
  -- GATE RELACIÓN: cuenta_proveedor_id pertenece a la empresa (si no → skip sin abortar)
  IF v.cuenta_proveedor_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.cuentas_proveedor WHERE id = v.cuenta_proveedor_id AND empresa_id = v.empresa_id AND activo = true) THEN
    RETURN; END IF;

  -- (A) Notif al VISITADOR (comportamiento EXISTENTE, sin cambios).
  IF v.estado = 'confirmada' THEN
    v_tipo := 'visita_aprobada';  v_titulo := 'Visita aprobada';  v_msg := 'Tu visita propuesta fue confirmada.'; v_email_tipo := 'aprobada';
  ELSIF v.estado = 'rechazada' THEN
    v_tipo := 'visita_rechazada'; v_titulo := 'Visita rechazada'; v_msg := 'Tu visita propuesta no fue aprobada.'; v_email_tipo := 'rechazada';
  END IF;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.cuenta_proveedor_id, v_tipo, v_titulo, v_msg, '/proveedor/visitador');
  UPDATE public.visitas_agendadas SET email_resultado_enviado = now()
    WHERE id = p_visita_id AND email_resultado_enviado IS NULL;
  IF FOUND THEN PERFORM private.email_notificar(p_visita_id, v_email_tipo); END IF;

  -- (B) NUEVO: notif a CLÍNICA/MÉDICO — SOLO en aprobación (confirmada). Claim idempotente propio.
  IF v.estado = 'confirmada' THEN
    UPDATE public.visitas_agendadas SET email_aprobada_clinica_enviado = now()
      WHERE id = p_visita_id AND email_aprobada_clinica_enviado IS NULL;
    IF FOUND THEN
      v_medico_nom  := COALESCE((SELECT nombre_completo FROM public.perfiles WHERE id = v.medico_id), 'el médico');
      v_empresa_nom := COALESCE((SELECT nombre_empresa FROM public.empresas_proveedoras WHERE id = v.empresa_id), 'un laboratorio');
      v_fecha := to_char(v.fecha_visita, 'DD/MM/YYYY'); v_hora := substr(v.hora_inicio::text, 1, 5);
      v_clinica_msg := 'Se aprobó una visita de ' || v_empresa_nom || ' con ' || v_medico_nom || ' el ' || v_fecha || ' a las ' || v_hora || '.';
      FOR rec IN SELECT usuario_id, es_medico FROM public.destinatarios_visita_clinica(p_visita_id) LOOP
        INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
          VALUES (rec.usuario_id, 'visita_clinica_aprobada', 'Visita de laboratorio aprobada', v_clinica_msg,
                  CASE WHEN rec.es_medico THEN '/medico' ELSE '/clinica' END)
          RETURNING id INTO v_nid;
        PERFORM private.push_notificar('notificaciones', v_nid::text);   -- push best-effort
      END LOOP;
      PERFORM private.email_notificar(p_visita_id, 'aprobada_clinica');  -- email fan-out (edge re-deriva)
    END IF;
  END IF;
END;
$function$;


CREATE OR REPLACE FUNCTION public.abrir_canal_administracion()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END; $function$;


CREATE OR REPLACE FUNCTION public.abrir_canal_equipo(p_equipo uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END; $function$;


CREATE OR REPLACE FUNCTION public.abrir_directo(p_otro uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END; $function$;


CREATE OR REPLACE FUNCTION public.asignar_visitador_equipo(p_visitador_id uuid, p_equipo_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_rol text;
  v_caller_empresa uuid;
  v_vis_empresa uuid;
  v_vis_equipo uuid;
  v_target_sup uuid;
  v_current_sup uuid;
BEGIN
  SELECT rol_en_empresa, empresa_id INTO v_caller_rol, v_caller_empresa
  FROM cuentas_proveedor WHERE id = auth.uid();

  SELECT empresa_id, equipo_id INTO v_vis_empresa, v_vis_equipo
  FROM cuentas_proveedor WHERE id = p_visitador_id;
  IF v_vis_empresa IS NULL OR v_vis_empresa IS DISTINCT FROM v_caller_empresa THEN
    RAISE EXCEPTION 'El visitador no pertenece a tu empresa';
  END IF;

  IF p_equipo_id IS NOT NULL THEN
    SELECT supervisor_id INTO v_target_sup FROM equipos_visitadores
    WHERE id = p_equipo_id AND empresa_id = v_caller_empresa;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo no válido'; END IF;
  END IF;
  IF v_vis_equipo IS NOT NULL THEN
    SELECT supervisor_id INTO v_current_sup FROM equipos_visitadores WHERE id = v_vis_equipo;
  END IF;

  IF v_caller_rol IN ('admin', 'editor') THEN
    NULL; -- admin sin límite
  ELSIF v_caller_rol = 'supervisor' THEN
    IF v_vis_equipo IS NOT NULL AND v_current_sup IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Ese visitador pertenece al equipo de otro supervisor';
    END IF;
    IF p_equipo_id IS NOT NULL AND v_target_sup IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Solo puedes asignar visitadores a tus propios equipos';
    END IF;
  ELSE
    RAISE EXCEPTION 'No autorizado';
  END IF;

  UPDATE cuentas_proveedor SET equipo_id = p_equipo_id, updated_at = now()
  WHERE id = p_visitador_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.cambiar_auditoria_chat(p_id uuid, p_activo boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller_rol text; v_caller_empresa uuid; v_target_empresa uuid;
BEGIN
  SELECT rol_en_empresa, empresa_id INTO v_caller_rol, v_caller_empresa FROM cuentas_proveedor WHERE id = auth.uid();
  IF v_caller_rol IS DISTINCT FROM 'admin' THEN RAISE EXCEPTION 'Solo un administrador puede delegar la auditoría'; END IF;
  SELECT empresa_id INTO v_target_empresa FROM cuentas_proveedor WHERE id = p_id;
  IF v_target_empresa IS NULL OR v_target_empresa <> v_caller_empresa THEN RAISE EXCEPTION 'Ese usuario no es de tu empresa'; END IF;
  UPDATE cuentas_proveedor SET audita_chat = p_activo, updated_at = now() WHERE id = p_id;
END; $function$;


CREATE OR REPLACE FUNCTION public.cambiar_estado_miembro_proveedor(p_id uuid, p_activo boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_rol text;
  v_caller_empresa uuid;
  v_target_empresa uuid;
BEGIN
  SELECT rol_en_empresa, empresa_id INTO v_caller_rol, v_caller_empresa
  FROM cuentas_proveedor WHERE id = auth.uid();

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Solo un administrador puede dar de baja o reactivar miembros';
  END IF;
  IF p_id = auth.uid() THEN
    RAISE EXCEPTION 'No puedes cambiar tu propio estado';
  END IF;

  SELECT empresa_id INTO v_target_empresa FROM cuentas_proveedor WHERE id = p_id;
  IF v_target_empresa IS NULL OR v_target_empresa IS DISTINCT FROM v_caller_empresa THEN
    RAISE EXCEPTION 'Ese usuario no pertenece a tu empresa';
  END IF;

  UPDATE cuentas_proveedor SET activo = p_activo, updated_at = now() WHERE id = p_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.cambiar_rol_proveedor(p_cuenta_id uuid, p_rol text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_empresa uuid; v_caller_rol text; v_caller_tipo text; v_target_empresa uuid;
BEGIN
  SELECT cp.empresa_id, cp.rol_en_empresa, e.tipo
    INTO v_caller_empresa, v_caller_rol, v_caller_tipo
  FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid();

  -- Tipos data-driven: la jerarquía la impone asignar_rol_miembro
  IF v_caller_tipo IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'En este tipo de empresa los roles se cambian con asignar_rol_miembro (jerarquía data-driven)';
  END IF;

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'No autorizado: solo un administrador puede cambiar roles';
  END IF;
  IF p_rol NOT IN ('admin','supervisor','visitador_medico','catalogo','marketing','finanzas','lectura') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_rol;
  END IF;
  SELECT empresa_id INTO v_target_empresa FROM cuentas_proveedor WHERE id = p_cuenta_id;
  IF v_target_empresa IS NULL THEN RAISE EXCEPTION 'La cuenta no existe'; END IF;
  IF v_target_empresa IS DISTINCT FROM v_caller_empresa THEN
    RAISE EXCEPTION 'La cuenta no pertenece a tu empresa';
  END IF;
  IF p_cuenta_id = auth.uid() AND p_rol <> 'admin'
     AND (SELECT count(*) FROM cuentas_proveedor
          WHERE empresa_id = v_caller_empresa AND rol_en_empresa = 'admin' AND activo = true) <= 1 THEN
    RAISE EXCEPTION 'No puedes quitarte el rol de administrador: la empresa quedaría sin administradores';
  END IF;
  UPDATE cuentas_proveedor SET rol_en_empresa = p_rol, updated_at = now() WHERE id = p_cuenta_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.asignar_rol_miembro(p_target_id uuid, p_nuevo_rol text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_emp uuid; v_tipo text; v_asig_rol text;
  v_asig_nivel integer; v_asig_admin boolean;
  v_target_emp uuid; v_target_rol text; v_target_admin boolean; v_target_tipo text;
  v_nuevo_nivel integer; v_nuevo_admin boolean;
BEGIN
  -- (a) El asignador debe poder gestionar usuarios_roles
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes asignar roles';
  END IF;

  -- datos del asignador (su empresa, tipo y rol)
  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Asignador sin empresa activa'; END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_asig_rol;

  -- target: debe existir y ser de LA MISMA empresa (scope). Resolvemos su TIPO
  -- explícitamente para validar el rol nuevo contra el tipo del TARGET (ajuste b).
  SELECT cp.empresa_id, cp.rol_en_empresa, e.tipo INTO v_target_emp, v_target_rol, v_target_tipo
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = p_target_id;
  IF v_target_emp IS NULL THEN RAISE EXCEPTION 'Miembro destino no existe'; END IF;
  IF v_target_emp <> v_emp THEN
    RAISE EXCEPTION 'No autorizado: el miembro no pertenece a tu empresa';
  END IF;

  -- (b) el rol nuevo debe existir en el catálogo para el TIPO DEL TARGET
  SELECT nivel, es_admin INTO v_nuevo_nivel, v_nuevo_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_target_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para el tipo de empresa del miembro (%)', p_nuevo_rol, v_target_tipo;
  END IF;

  -- es_admin del rol ACTUAL del target (en su propio tipo)
  SELECT es_admin INTO v_target_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_target_tipo AND rol = v_target_rol;

  -- (b) Nadie modifica/degrada a un Admin salvo otro Admin
  IF COALESCE(v_target_admin, false) AND NOT COALESCE(v_asig_admin, false) THEN
    RAISE EXCEPTION 'No autorizado: solo un Admin puede modificar a otro Admin';
  END IF;

  -- (c) Admin asigna cualquier rol; un NO-admin solo roles de nivel ESTRICTAMENTE inferior
  --     (bloquea Gerente→Admin y Gerente→Gerente).
  IF NOT COALESCE(v_asig_admin, false) THEN
    IF v_nuevo_nivel IS NULL OR v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes asignar roles de nivel inferior al tuyo';
    END IF;
  END IF;

  -- (d) Protección del ÚLTIMO Admin: la operación no puede dejar a la empresa sin Admin activo.
  IF COALESCE(v_target_admin, false) AND NOT COALESCE(v_nuevo_admin, false)
     AND (SELECT count(*) FROM public.cuentas_proveedor cp2
          JOIN public.roles_empresa_catalogo rc
            ON rc.tipo_empresa = v_target_tipo AND rc.rol = cp2.rol_en_empresa
          WHERE cp2.empresa_id = v_emp AND cp2.activo = true AND rc.es_admin) <= 1
  THEN
    RAISE EXCEPTION 'No autorizado: la empresa quedaría sin ningún Admin activo';
  END IF;

  UPDATE public.cuentas_proveedor SET rol_en_empresa = p_nuevo_rol WHERE id = p_target_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.asignar_sucursal_a_miembro(p_target_id uuid, p_sucursal_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_caller uuid := auth.uid(); v_emp uuid;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000'; END IF;
  SELECT cp.empresa_id INTO v_emp FROM public.cuentas_proveedor cp WHERE cp.id = v_caller AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Sin cuenta de proveedor activa' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: requiere permiso usuarios_roles' USING ERRCODE = '42501';
  END IF;
  -- target ∈ mi empresa (no asignar a miembro de otra empresa)
  IF NOT EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = p_target_id AND empresa_id = v_emp) THEN
    RAISE EXCEPTION 'El miembro no pertenece a tu empresa' USING ERRCODE = '42501';
  END IF;
  -- sucursal (solo si no-NULL): propia, no-global, activa. NULL = desasignar → grandfather/empresa-wide.
  IF p_sucursal_id IS NOT NULL AND NOT COALESCE(private.sucursal_de_empresa_activa(p_sucursal_id, v_emp), false) THEN
    RAISE EXCEPTION 'La sucursal no pertenece a tu empresa, es global o está inactiva' USING ERRCODE = '42501';
  END IF;
  UPDATE public.cuentas_proveedor SET sucursal_id = p_sucursal_id WHERE id = p_target_id AND empresa_id = v_emp;
END $function$;


CREATE OR REPLACE FUNCTION public.autorizar_invitacion_staff(p_rol text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_caller uuid := auth.uid(); v_emp uuid; v_tipo text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000'; END IF;
  SELECT cp.empresa_id INTO v_emp FROM public.cuentas_proveedor cp WHERE cp.id = v_caller AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Invitador sin cuenta de proveedor activa' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: requiere permiso usuarios_roles' USING ERRCODE = '42501';
  END IF;
  SELECT e.tipo INTO v_tipo FROM public.empresas_proveedoras e WHERE e.id = v_emp;
  IF NOT EXISTS (SELECT 1 FROM public.roles_empresa_catalogo c WHERE c.tipo_empresa = v_tipo AND c.rol = p_rol) THEN
    RAISE EXCEPTION 'Rol % no concedible para tipo %', p_rol, COALESCE(v_tipo,'(desconocido)') USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('empresa_id', v_emp, 'tipo', v_tipo);
END $function$;


CREATE OR REPLACE FUNCTION public.alta_miembro_farmacia(p_user_id uuid, p_empresa_id uuid, p_nombre text, p_email text, p_nuevo_rol text, p_telefono text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_emp uuid; v_tipo text; v_asig_rol text; v_asig_nivel integer; v_asig_admin boolean;
  v_nuevo_nivel integer;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes dar de alta miembros';
  END IF;

  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Asignador sin empresa activa'; END IF;

  IF p_empresa_id IS DISTINCT FROM v_emp THEN
    RAISE EXCEPTION 'No autorizado: solo puedes dar de alta en tu propia empresa';
  END IF;

  -- Alta data-driven: tipos con seed en roles_empresa_catalogo (farmacia + afín).
  IF v_tipo NOT IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'Alta data-driven no disponible para empresas tipo %', v_tipo;
  END IF;

  SELECT nivel INTO v_nuevo_nivel
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para tipo %', p_nuevo_rol, v_tipo;
  END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_asig_rol;

  IF NOT COALESCE(v_asig_admin, false) THEN
    IF v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes dar de alta roles de nivel inferior al tuyo';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'El usuario ya tiene una cuenta de proveedor';
  END IF;

  INSERT INTO public.cuentas_proveedor (id, empresa_id, nombre_completo, email, telefono, rol_en_empresa, activo)
  VALUES (p_user_id, v_emp, p_nombre, p_email, p_telefono, p_nuevo_rol, true);
END;
$function$;


CREATE OR REPLACE FUNCTION public.invitar_miembro_farmacia(p_email text, p_nombre text, p_nuevo_rol text, p_telefono text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_emp uuid; v_tipo text; v_asig_rol text; v_asig_nivel integer; v_asig_admin boolean;
  v_nuevo_nivel integer; v_token uuid;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes invitar personal';
  END IF;

  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Invitador sin empresa activa'; END IF;

  IF v_tipo NOT IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'Invitación data-driven no disponible para empresas tipo %', v_tipo;
  END IF;
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'El email es obligatorio';
  END IF;

  SELECT nivel INTO v_nuevo_nivel
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para tipo %', p_nuevo_rol, v_tipo;
  END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_asig_rol;

  IF NOT COALESCE(v_asig_admin, false) THEN
    IF v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes invitar roles de nivel inferior al tuyo';
    END IF;
  END IF;

  -- empresa_id y rol quedan FIJADOS en la invitación (el invitado no los elige).
  INSERT INTO public.invitaciones_visitador (empresa_id, email, nombre_completo, telefono, rol, estado, expires_at)
  VALUES (v_emp, lower(trim(p_email)), p_nombre, p_telefono, p_nuevo_rol, 'pendiente', now() + interval '7 days')
  RETURNING token INTO v_token;

  RETURN v_token;
END;
$function$;


CREATE OR REPLACE FUNCTION public.invitar_miembro_proveedor(p_email text, p_nombre text, p_rol text, p_telefono text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa_id uuid; v_caller_rol text; v_caller_tipo text; v_token uuid;
BEGIN
  SELECT cp.empresa_id, cp.rol_en_empresa, e.tipo
    INTO v_empresa_id, v_caller_rol, v_caller_tipo
  FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid();

  -- Tipos data-driven: el alta/rol pasa por el flujo data-driven (no esta invitación legada)
  IF v_caller_tipo IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'En este tipo de empresa el alta de personal usa el flujo data-driven (no esta invitación legada)';
  END IF;

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'No autorizado: solo un administrador puede invitar miembros';
  END IF;
  IF p_rol NOT IN ('admin','supervisor','visitador_medico','catalogo','marketing','finanzas','lectura') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_rol;
  END IF;
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'El email es obligatorio';
  END IF;
  INSERT INTO invitaciones_visitador (empresa_id, email, nombre_completo, telefono, rol, estado, expires_at)
  VALUES (v_empresa_id, lower(trim(p_email)), p_nombre, p_telefono, p_rol, 'pendiente', now() + interval '7 days')
  RETURNING token INTO v_token;
  RETURN v_token;
END;
$function$;


CREATE OR REPLACE FUNCTION public.set_default_estado_propuesta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.cuentas_proveedor
    WHERE id = auth.uid()
      AND rol_en_empresa IN ('admin', 'editor')
  ) THEN
    NEW.estado := 'propuesta';
  END IF;
  RETURN NEW;
END;
$function$;


-- Autochequeo: md5(prosrc) restaurado == snapshot vivo; funciones nuevas ausentes.
DO $rbchk$
DECLARE v text := '';
BEGIN

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='get_empresa_id_proveedor' AND md5(p.prosrc)='317374eaa6b533519ed0cf54a18f31e4') THEN v:=v||' get_empresa_id_proveedor'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='get_empresa_id_session' AND md5(p.prosrc)='4f166290d2667f1690abee9b7b6ebdd1') THEN v:=v||' get_empresa_id_session'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='private' AND p.proname='mi_pais' AND md5(p.prosrc)='a59c9ade8438f5999a757c1210f2a805') THEN v:=v||' mi_pais'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='private' AND p.proname='mi_sucursal' AND md5(p.prosrc)='5466d6b3c5d509fea87fdca5e3b0b0ad') THEN v:=v||' mi_sucursal'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='private' AND p.proname='puede_aprobar_visitas' AND md5(p.prosrc)='f4bd4d86f4d71f7de182a1635f79ed9c') THEN v:=v||' puede_aprobar_visitas'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='puede_auditar_chat' AND md5(p.prosrc)='4a837c1a4f2536c591d06f93085b41d9') THEN v:=v||' puede_auditar_chat'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='es_miembro_conversacion' AND md5(p.prosrc)='ae2bbf1b6a5890afb69dd077c0675603') THEN v:=v||' es_miembro_conversacion'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='private' AND p.proname='tiene_permiso' AND md5(p.prosrc)='036ab9ab042cf9af2098ddeb35e46e2f') THEN v:=v||' tiene_permiso'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='supervisa_cuenta_proveedor' AND md5(p.prosrc)='185827147dd0b1fd970046df5c54773a') THEN v:=v||' supervisa_cuenta_proveedor'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='contactos_chat' AND md5(p.prosrc)='e9f9003d073a0ceb4acf161fbd063ead') THEN v:=v||' contactos_chat'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='get_visitas_proveedor' AND md5(p.prosrc)='6b0025fe7de597e1008dd4084e56e16a') THEN v:=v||' get_visitas_proveedor'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='sincronizar_mis_canales' AND md5(p.prosrc)='547c6773e94940bfa4670a45c7904b15') THEN v:=v||' sincronizar_mis_canales'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='notificar_visita_resultado' AND md5(p.prosrc)='2aee56ad094f707073d2fad91b44f689') THEN v:=v||' notificar_visita_resultado'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='abrir_canal_administracion' AND md5(p.prosrc)='5fcac6442a288204885c4147126adf24') THEN v:=v||' abrir_canal_administracion'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='abrir_canal_equipo' AND md5(p.prosrc)='623813585bb9a0682651ebff9dd902c5') THEN v:=v||' abrir_canal_equipo'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='abrir_directo' AND md5(p.prosrc)='fc38eaf5eebb8e16121f9e6b741053f7') THEN v:=v||' abrir_directo'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='asignar_visitador_equipo' AND md5(p.prosrc)='78bedae393569374372a28d1315f9ac9') THEN v:=v||' asignar_visitador_equipo'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='cambiar_auditoria_chat' AND md5(p.prosrc)='e28060fe078a9a30e239ac7e804c57ff') THEN v:=v||' cambiar_auditoria_chat'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='cambiar_estado_miembro_proveedor' AND md5(p.prosrc)='a501d9c03ba8991cfafa142f63e93657') THEN v:=v||' cambiar_estado_miembro_proveedor'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='cambiar_rol_proveedor' AND md5(p.prosrc)='3c81473800b249eba382b20fc05ec80e') THEN v:=v||' cambiar_rol_proveedor'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='asignar_rol_miembro' AND md5(p.prosrc)='24f9b4c6e651b2edbef36bde22f28a6d') THEN v:=v||' asignar_rol_miembro'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='asignar_sucursal_a_miembro' AND md5(p.prosrc)='4bc5930336c828d68be73f947acb3fb6') THEN v:=v||' asignar_sucursal_a_miembro'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='autorizar_invitacion_staff' AND md5(p.prosrc)='fa89b0aade3894a803716cd53be517e3') THEN v:=v||' autorizar_invitacion_staff'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='alta_miembro_farmacia' AND md5(p.prosrc)='615391996a7855033dc3ef844750ee9e') THEN v:=v||' alta_miembro_farmacia'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='invitar_miembro_farmacia' AND md5(p.prosrc)='98c1f8780c75e6cfea5946912d349500') THEN v:=v||' invitar_miembro_farmacia'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='invitar_miembro_proveedor' AND md5(p.prosrc)='f2160cf33e514af595e4717510ecfedd') THEN v:=v||' invitar_miembro_proveedor'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname='set_default_estado_propuesta' AND md5(p.prosrc)='9cc4cda35aaee4598e4b19abd425fab3') THEN v:=v||' set_default_estado_propuesta'; END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='private' AND p.proname IN ('exigir_empresa_activa','mi_empresa_propia')) THEN v:=v||' fn_nueva_presente'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK323: md5 no coincide o residuo:%', v; END IF;
END $rbchk$;
