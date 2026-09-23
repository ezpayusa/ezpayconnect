-- ############################################################################################
-- Migracion 323 - GATE de estado de empresa (lote 2 de la 322) en 26 superficies + 5 policies
-- ############################################################################################
-- La 322 gateo mi_empresa_proveedor/mi_rol_proveedor/mi_equipo_proveedor/pais_de_proveedor. Quedaron
-- 26 superficies (recon 23-sep) que resuelven identidad de proveedor SIN el gate:
--   Grupo A (9 helpers de valor): devuelven NULL/false si la empresa no esta 'activa' (no lanzan).
--   Grupo B (17 RPCs de accion): exigir_empresa_activa() como primera sentencia -> 42501.
-- Mas supervisa_cuenta_proveedor (gate por empresa del supervisor) y el trigger
-- set_default_estado_propuesta (gatea su EXISTS, degrada a 'propuesta', NO bloquea).
-- 5 policies: 2 SELECT de onboarding pasan a helper que NO gatea estado (mi_empresa_propia /
-- mi_empresa_onboarding) para no romper la pantalla /estado ni la vista de equipo en onboarding;
-- la UPDATE de empresa a mi_empresa_onboarding; y las 2 de solicitudes_campana pierden el fallback S.
-- Exentas: aceptar_invitacion_proveedor, vincular_membresia_proveedor (onboarding).
-- ############################################################################################

-- 0) SNAPSHOT previo (para el autochequeo y para detectar drift)
CREATE TEMP TABLE _snap323 (name text, md5src text, secdef bool, owner text, config text) ON COMMIT DROP;
INSERT INTO _snap323
SELECT p.proname, md5(p.prosrc), p.prosecdef, pg_get_userbyid(p.proowner), COALESCE(array_to_string(p.proconfig,','),'')
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname,p.proname) IN (
  ('public','get_empresa_id_proveedor'),
  ('public','get_empresa_id_session'),
  ('private','mi_pais'),
  ('private','mi_sucursal'),
  ('private','puede_aprobar_visitas'),
  ('public','puede_auditar_chat'),
  ('public','es_miembro_conversacion'),
  ('private','tiene_permiso'),
  ('public','supervisa_cuenta_proveedor'),
  ('public','contactos_chat'),
  ('public','get_visitas_proveedor'),
  ('public','sincronizar_mis_canales'),
  ('public','notificar_visita_resultado'),
  ('public','abrir_canal_administracion'),
  ('public','abrir_canal_equipo'),
  ('public','abrir_directo'),
  ('public','asignar_visitador_equipo'),
  ('public','cambiar_auditoria_chat'),
  ('public','cambiar_estado_miembro_proveedor'),
  ('public','cambiar_rol_proveedor'),
  ('public','asignar_rol_miembro'),
  ('public','asignar_sucursal_a_miembro'),
  ('public','autorizar_invitacion_staff'),
  ('public','alta_miembro_farmacia'),
  ('public','invitar_miembro_farmacia'),
  ('public','invitar_miembro_proveedor'),
  ('public','set_default_estado_propuesta'),
  ('public','aceptar_invitacion_proveedor'),('public','vincular_membresia_proveedor'));


-- 1) Funciones nuevas -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.exigir_empresa_activa()
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_estado text;
BEGIN
  SELECT e.estado INTO v_estado
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo = true
   LIMIT 1;
  -- Fail-closed acotado: solo bloquea a un PROVEEDOR (cuenta activa) cuya empresa no esta 'activa'.
  -- Si el llamante no es proveedor -> v_estado NULL -> no hace nada.
  IF v_estado IS NOT NULL AND v_estado <> 'activa' THEN
    RAISE EXCEPTION 'Empresa proveedora no activa (estado=%): accion no permitida', v_estado
      USING ERRCODE = '42501';
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION private.exigir_empresa_activa() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.mi_empresa_propia()
  RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
  -- USO EXCLUSIVO: lectura de la propia fila de empresa (pantalla de estado). NO usar para
  -- autorizar acciones. NO mira estado: una empresa 'rechazada' debe poder leer su propia fila.
  SELECT cp.empresa_id FROM public.cuentas_proveedor cp WHERE cp.id = auth.uid() AND cp.activo = true LIMIT 1;
$function$;
REVOKE ALL ON FUNCTION private.mi_empresa_propia() FROM public, anon;
GRANT EXECUTE ON FUNCTION private.mi_empresa_propia() TO authenticated;


-- 2) GRUPO A — helpers de valor (gate estado='activa'; devuelven NULL/false) ---------------

CREATE OR REPLACE FUNCTION public.get_empresa_id_proveedor()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT cp.empresa_id FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa' WHERE cp.id = auth.uid() AND cp.rol_en_empresa = 'admin' LIMIT 1;
$function$;


CREATE OR REPLACE FUNCTION public.get_empresa_id_session()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT cp.empresa_id FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa' WHERE cp.id = auth.uid() LIMIT 1;
$function$;


CREATE OR REPLACE FUNCTION private.mi_pais()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(
    (SELECT pais_id FROM public.perfiles WHERE id = auth.uid()),
    (SELECT cp.pais_id FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa' WHERE cp.id = auth.uid()),
    (SELECT e.pais_id FROM public.cuentas_proveedor cp
       JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa'
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
  JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa'
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
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa'
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
AS $function$ SELECT EXISTS (SELECT 1 FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa' WHERE cp.id = auth.uid() AND cp.activo = true AND (cp.rol_en_empresa='admin' OR cp.audita_chat=true)); $function$;


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
  SELECT rol_en_empresa, empresa_id, equipo_id INTO v_rol, v_empresa, v_equipo FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa' WHERE cp.id = auth.uid() AND cp.activo = true;
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
    WHERE cp.id = auth.uid() AND cp.activo = true AND e.estado = 'activa'
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


-- supervisa_cuenta_proveedor: gate por la empresa del SUPERVISOR (auth.uid); search_path '' calificado
CREATE OR REPLACE FUNCTION public.supervisa_cuenta_proveedor(p_cuenta_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.cuentas_proveedor cp
    JOIN public.equipos_visitadores e ON e.id = cp.equipo_id
    WHERE cp.id = p_cuenta_id AND e.supervisor_id = auth.uid()
      AND EXISTS (SELECT 1 FROM public.cuentas_proveedor sup
                    JOIN public.empresas_proveedoras es ON es.id = sup.empresa_id
                   WHERE sup.id = auth.uid() AND es.estado = 'activa')
  );
$function$;


-- 3) GRUPO B — RPCs de accion (PERFORM private.exigir_empresa_activa() como 1a sentencia) ---

CREATE OR REPLACE FUNCTION public.contactos_chat()
 RETURNS TABLE(id uuid, nombre_completo text, rol_en_empresa text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE v_rol text; v_empresa uuid; v_equipo uuid;
BEGIN
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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
  PERFORM private.exigir_empresa_activa();
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


-- 4) trigger set_default_estado_propuesta — gatea el EXISTS (degrada), NO bloquea ----------
CREATE OR REPLACE FUNCTION public.set_default_estado_propuesta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa'
    WHERE cp.id = auth.uid()
      AND cp.rol_en_empresa IN ('admin', 'editor')
  ) THEN
    NEW.estado := 'propuesta';
  END IF;
  RETURN NEW;
END;
$function$;


-- 5) POLICIES (5) ---------------------------------------------------------------------------
DROP POLICY "Proveedor ve su propia empresa" ON public.empresas_proveedoras;
CREATE POLICY "Proveedor ve su propia empresa" ON public.empresas_proveedoras
  FOR SELECT TO authenticated USING (id = private.mi_empresa_propia());

DROP POLICY "Proveedor admin ve cuentas de su empresa" ON public.cuentas_proveedor;
CREATE POLICY "Proveedor admin ve cuentas de su empresa" ON public.cuentas_proveedor
  FOR SELECT TO authenticated USING (empresa_id = private.mi_empresa_onboarding() AND private.mi_rol_onboarding() = 'admin');

DROP POLICY "Proveedor actualiza su propia empresa" ON public.empresas_proveedoras;
CREATE POLICY "Proveedor actualiza su propia empresa" ON public.empresas_proveedoras
  FOR UPDATE TO authenticated
  USING (id = private.mi_empresa_onboarding() AND private.mi_rol_onboarding() = ANY (ARRAY['admin','editor']))
  WITH CHECK (id = private.mi_empresa_onboarding() AND private.mi_rol_onboarding() = ANY (ARRAY['admin','editor']));

-- Se quita el fallback UNGATED `OR EXISTS(cuentas_proveedor cp WHERE cp.id=auth.uid() ...)` y se
-- reemplaza por el helper GATEADO mi_rol_proveedor() IN ('admin','editor'): conserva la autorizacion
-- de admin/editor (que el EXISTS proveia) PERO gateada por estado (322) — no es un nuevo bypass.
DROP POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana;
CREATE POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana
  FOR UPDATE TO authenticated
  USING (COALESCE((empresa_id = mi_empresa_proveedor()), false)
     AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR mi_rol_proveedor() = ANY (ARRAY['admin','editor']))
     AND (estado = ANY (ARRAY['borrador','enviada','rechazada'])))
  WITH CHECK (COALESCE((empresa_id = mi_empresa_proveedor()), false)
     AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR mi_rol_proveedor() = ANY (ARRAY['admin','editor']))
     AND (estado = ANY (ARRAY['borrador','enviada','rechazada'])));

DROP POLICY "Proveedor crea campañas" ON public.solicitudes_campana;
CREATE POLICY "Proveedor crea campañas" ON public.solicitudes_campana
  FOR INSERT TO authenticated
  WITH CHECK (COALESCE((empresa_id = mi_empresa_proveedor()), false)
     AND (COALESCE(private.tiene_permiso('publicidad_gestionar'::text), false) OR mi_rol_proveedor() = ANY (ARRAY['admin','editor']))
     AND (estado = ANY (ARRAY['borrador','enviada']))
     AND COALESCE(private.empresa_opera_en_pais(empresa_id, pais_id), false));


-- 6) AUTOCHEQUEO --------------------------------------------------------------------------------
DO $ac$
DECLARE
  v text := '';
  r record; n int; qa_admin uuid; qa_emp uuid; qa_co uuid; ok boolean;
BEGIN
  -- Grupo A: cuerpo nuevo contiene el gate estado='activa'; metadata sin cambios
  FOR r IN SELECT unnest(ARRAY['get_empresa_id_proveedor','get_empresa_id_session','mi_pais','mi_sucursal',
        'puede_aprobar_visitas','puede_auditar_chat','es_miembro_conversacion','tiene_permiso','supervisa_cuenta_proveedor']) AS nm LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
        WHERE p.proname=r.nm AND p.prosrc ILIKE '%estado%=%''activa''%') THEN
      v := v || E'\n(A) sin gate estado en '||r.nm; END IF;
  END LOOP;
  -- Grupo B: cuerpo nuevo contiene PERFORM private.exigir_empresa_activa()
  FOR r IN SELECT unnest(ARRAY['contactos_chat','get_visitas_proveedor','sincronizar_mis_canales','notificar_visita_resultado',
        'abrir_canal_administracion','abrir_canal_equipo','abrir_directo','asignar_visitador_equipo','cambiar_auditoria_chat',
        'cambiar_estado_miembro_proveedor','cambiar_rol_proveedor','asignar_rol_miembro','asignar_sucursal_a_miembro',
        'autorizar_invitacion_staff','alta_miembro_farmacia','invitar_miembro_farmacia','invitar_miembro_proveedor']) AS nm LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname=r.nm AND p.prosrc ILIKE '%exigir_empresa_activa%') THEN
      v := v || E'\n(B) sin PERFORM en '||r.nm; END IF;
  END LOOP;
  -- Exentas: md5 sin cambios
  FOR r IN SELECT s.name, s.md5src FROM _snap323 s WHERE s.name IN ('aceptar_invitacion_proveedor','vincular_membresia_proveedor') LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname=r.name AND md5(p.prosrc)=r.md5src) THEN
      v := v || E'\n(exenta) cambio inesperado en '||r.name; END IF;
  END LOOP;
  -- metadata (secdef/owner/config) sin cambios en las 26+trigger
  FOR r IN SELECT s.name, s.secdef, s.owner, s.config FROM _snap323 s
           WHERE s.name NOT IN ('supervisa_cuenta_proveedor') LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
        WHERE p.proname=r.name AND p.prosecdef=r.secdef AND pg_get_userbyid(p.proowner)=r.owner
          AND COALESCE(array_to_string(p.proconfig,','),'')=r.config) THEN
      v := v || E'\n(meta) metadata cambio en '||r.name; END IF;
  END LOOP;
  -- policies nuevas presentes
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='empresas_proveedoras' AND policyname='Proveedor ve su propia empresa' AND qual ILIKE '%mi_empresa_propia%') THEN v:=v||E'\n(pol) empresa SELECT'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cuentas_proveedor' AND policyname='Proveedor admin ve cuentas de su empresa' AND qual ILIKE '%mi_empresa_onboarding%' AND qual ILIKE '%mi_rol_onboarding%') THEN v:=v||E'\n(pol) cuentas SELECT sin filtro admin'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='empresas_proveedoras' AND policyname='Proveedor actualiza su propia empresa' AND qual ILIKE '%mi_empresa_onboarding%' AND with_check ILIKE '%mi_rol_onboarding%') THEN v:=v||E'\n(pol) empresa UPDATE'; END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE tablename='solicitudes_campana' AND policyname='Proveedor crea campañas' AND with_check ILIKE '%cuentas_proveedor%') THEN v:=v||E'\n(pol) solicitudes INSERT aun tiene fallback S'; END IF;

  -- EJERCICIO REAL (savepoint interno que SIEMPRE se descarta)
  SELECT cp.id, cp.empresa_id INTO qa_admin, qa_emp FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id=cp.empresa_id
   WHERE cp.activo AND cp.rol_en_empresa='admin' AND e.estado='activa'
     AND EXISTS (SELECT 1 FROM public.cuentas_proveedor c2 WHERE c2.empresa_id=cp.empresa_id AND c2.id<>cp.id AND c2.activo)
   ORDER BY cp.id LIMIT 1;
  IF qa_admin IS NULL THEN
    v := v || E'\n(ej) no hay admin de empresa activa con co-miembro';
  ELSE
    SELECT id INTO qa_co FROM public.cuentas_proveedor WHERE empresa_id=qa_emp AND id<>qa_admin AND activo LIMIT 1;
    BEGIN
      -- ACTIVA: accion B funciona + helper devuelve empresa
      BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub',qa_admin::text,'role','authenticated')::text, true);
        PERFORM set_config('role','authenticated', true);
        PERFORM public.cambiar_estado_miembro_proveedor(qa_co, false);
        IF public.get_empresa_id_proveedor() IS DISTINCT FROM qa_emp THEN v:=v||E'\n(ej) activa: helper no devolvio empresa'; END IF;
        PERFORM set_config('role','none',true);
      EXCEPTION WHEN OTHERS THEN PERFORM set_config('role','none',true); v:=v||E'\n(ej) activa fallo '||SQLSTATE; END;

      -- SUSPENDIDA: B lanza 42501, helper NULL
      UPDATE public.empresas_proveedoras SET estado='suspendida' WHERE id=qa_emp;
      BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub',qa_admin::text,'role','authenticated')::text, true);
        PERFORM set_config('role','authenticated', true);
        BEGIN
          PERFORM public.cambiar_estado_miembro_proveedor(qa_co, true);
          v:=v||E'\n(ej) suspendida: accion B NO fue bloqueada';
        EXCEPTION WHEN insufficient_privilege THEN NULL; END;
        IF public.get_empresa_id_proveedor() IS NOT NULL THEN v:=v||E'\n(ej) suspendida: helper no devolvio NULL'; END IF;
        PERFORM set_config('role','none',true);
      EXCEPTION WHEN OTHERS THEN PERFORM set_config('role','none',true); v:=v||E'\n(ej) suspendida fallo '||SQLSTATE; END;

      -- PENDIENTE: UPDATE del perfil de empresa (policy onboarding) sigue
      UPDATE public.empresas_proveedoras SET estado='pendiente' WHERE id=qa_emp;
      BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub',qa_admin::text,'role','authenticated')::text, true);
        PERFORM set_config('role','authenticated', true);
        UPDATE public.empresas_proveedoras SET telefono = COALESCE(telefono,'') WHERE id=qa_emp;
        GET DIAGNOSTICS n = ROW_COUNT;
        PERFORM set_config('role','none',true);
        IF n <> 1 THEN v:=v||E'\n(ej) pendiente: no pudo UPDATE su empresa (n='||n||')'; END IF;
      EXCEPTION WHEN OTHERS THEN PERFORM set_config('role','none',true); v:=v||E'\n(ej) pendiente fallo '||SQLSTATE; END;

      RAISE EXCEPTION 'SENTINEL323';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'SENTINEL323' THEN RAISE; END IF;
    END;
  END IF;

  PERFORM set_config('role','none',true);
  PERFORM set_config('request.jwt.claims','',true);
  IF v <> '' THEN
    RAISE EXCEPTION 'MIG323 AUTOCHEQUEO FALLA:%', v;
  END IF;
END $ac$;
