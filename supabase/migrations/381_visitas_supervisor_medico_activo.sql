-- =====================================================================================================================
-- MIG 381 — hardening de visitas (A3 + A4 + A11). Recon del 20-oct-2026 (C:\tmp\visitas\01.out), contra el objeto vivo.
--
-- A3  administrar_visita dejaba administrar a un SUPERVISOR cualquier visita de su empresa: el gate usaba
--     private.puede_aprobar_visitas() (admin/supervisor/editor) y no lo acotaba a su equipo, mientras la policy SELECT
--     "Proveedor ve visitas segun rol" sí lo acota con supervisa_cuenta_proveedor (medido: sup1 llegaba al UPDATE de una
--     visita que por RLS le daba 0 filas). Y notificar_visita_resultado, que llamaba el front DESPUÉS, solo admitía
--     admin/editor: con un supervisor daba PT002 y el front no leía el error (useVisitasAgendadas.ts:308/:325), así que
--     el visitador nunca se enteraba.
--     Ahora: gate = super_admin, o admin/editor de la empresa de la visita, o supervisor del equipo de la cuenta de la
--     visita; visita inexistente y sin autoridad dan el MISMO error (PV027). La notificación la hace administrar_visita
--     en la misma transacción (private.notificar_resultado_visita_interno), en las tres acciones en que la llamaba el
--     front (aprobar, rechazar, modificar). notificar_visita_resultado queda como compat no-op para bundles viejos.
-- A4  Al agendar nadie revalidaba el médico ni la cuenta: la FK medico_id apunta a perfiles (no a medicos) y la policy de
--     INSERT usa private.cuenta_en_empresa (sin activo). private.gate_visita_pais (BEFORE INSERT OR UPDATE OF medico_id)
--     ahora exige un médico con fila en medicos, activo en medicos y en perfiles, y en INSERT una cuenta_proveedor
--     activa (PV028, mismo mensaje para todos los casos). Datos al 20-oct: 0 visitas inconsistentes.
-- A11 accion_url: el visitador iba a una ruta que no existe en el router (ahora /visitador/mis-visitas; si la cuenta
--     de la visita no es visitador_medico, /proveedor/notificaciones); el staff de clínica iba al index de /clinica,
--     que exige rol de admin (ahora /clinica/calendario); el médico sigue en /medico. Se corrigen las 4 notificaciones
--     viejas.
--
-- Errcodes nuevos (familia PV, el front los mapea por código):
--   PV027  no autorizado para administrar esta visita (también: la visita no existe)
--   PV028  no se puede agendar una visita con este médico (médico inexistente/inactivo, o cuenta del visitador inactiva)
-- Precondición (guarda MIG81): md5(prosrc) vivos de las 4 funciones tocadas, capturados el 20-oct-2026.
-- Sin DROP: CREATE OR REPLACE con la misma firma y retorno conserva los grants. La función nueva de private nace solo
-- con EXECUTE de postgres (pg_default_acl global) y además lleva REVOKE explícito.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/381_visitas_supervisor_medico_activo.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) GUARDA DE ENTRADA
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE m381_pre ON COMMIT DROP AS
SELECT p.oid AS oid, p.oid::regprocedure::text AS fn, md5(p.prosrc) AS md5_pre, p.proacl::text AS acl_pre
  FROM pg_proc p
 WHERE p.oid IN (to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'),
                 to_regprocedure('public.notificar_visita_resultado(uuid)'),
                 to_regprocedure('public.cancelar_visita(uuid)'),
                 to_regprocedure('private.gate_visita_pais()'));

DO $$
DECLARE r record; v_esperado text; v_malos text := '';
BEGIN
  IF (SELECT count(*) FROM m381_pre) <> 4 THEN
    RAISE EXCEPTION 'MIG81: faltan funciones de la precondición (% de 4)', (SELECT count(*) FROM m381_pre) USING ERRCODE = 'MIG81';
  END IF;
  FOR r IN SELECT * FROM m381_pre LOOP
    v_esperado := CASE r.fn
      WHEN 'administrar_visita(uuid,text,date,text,text,text)' THEN '5d4a718de9d34fcfcc36e74a0e068bce'
      WHEN 'notificar_visita_resultado(uuid)'                   THEN 'ebdb579ec423c0dbabce62fadfa424f8'
      WHEN 'cancelar_visita(uuid)'                              THEN '866159b76f6af88291dffea24430e5bf'
      WHEN 'private.gate_visita_pais()'                         THEN '272120bc46268518ff8617291085b70f'
    END;
    IF r.md5_pre IS DISTINCT FROM v_esperado THEN
      v_malos := v_malos || r.fn || ' (vivo ' || r.md5_pre || ', esperado ' || COALESCE(v_esperado, '?') || '); ';
    END IF;
  END LOOP;
  IF v_malos <> '' THEN
    RAISE EXCEPTION 'MIG81: el objeto vivo no es el de la precondición: %', v_malos USING ERRCODE = 'MIG81';
  END IF;
  IF to_regprocedure('private.notificar_resultado_visita_interno(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'MIG81: private.notificar_resultado_visita_interno ya existe' USING ERRCODE = 'MIG81';
  END IF;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) private.notificar_resultado_visita_interno — el cuerpo de notificar_visita_resultado sin su gate (lo llama
--    administrar_visita, que ya hizo el gate). Cambios: accion_url (A11) y sin exigir_empresa_activa (es del llamante y
--    lo cubre el gate de administrar_visita: mi_empresa_proveedor exige cuenta y empresa activas).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.notificar_resultado_visita_interno(p_visita_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; v_tipo text; v_email_tipo text; v_url_visitador text;
        v_medico_nom text; v_empresa_nom text; v_fecha text; v_hora text; v_clinica_msg text; v_nid uuid; rec record;
BEGIN
  SELECT empresa_id, cuenta_proveedor_id, estado, medico_id, fecha_visita, hora_inicio
    INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF v.estado NOT IN ('confirmada','rechazada') THEN RETURN; END IF;
  -- GATE RELACIÓN: cuenta_proveedor_id pertenece a la empresa y está activa (si no → skip sin abortar)
  IF v.cuenta_proveedor_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.cuentas_proveedor WHERE id = v.cuenta_proveedor_id AND empresa_id = v.empresa_id AND activo = true) THEN
    RETURN; END IF;

  -- (A) Notif al VISITADOR. A11: el visitador vive en el PWA /visitador/*; otro rol, a su bandeja del portal.
  IF v.estado = 'confirmada' THEN
    v_tipo := 'visita_aprobada';  v_titulo := 'Visita aprobada';  v_msg := 'Tu visita propuesta fue confirmada.'; v_email_tipo := 'aprobada';
  ELSIF v.estado = 'rechazada' THEN
    v_tipo := 'visita_rechazada'; v_titulo := 'Visita rechazada'; v_msg := 'Tu visita propuesta no fue aprobada.'; v_email_tipo := 'rechazada';
  END IF;
  v_url_visitador := CASE WHEN (SELECT cp.rol_en_empresa FROM public.cuentas_proveedor cp WHERE cp.id = v.cuenta_proveedor_id) = 'visitador_medico'
                          THEN '/visitador/mis-visitas' ELSE '/proveedor/notificaciones' END;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.cuenta_proveedor_id, v_tipo, v_titulo, v_msg, v_url_visitador);
  UPDATE public.visitas_agendadas SET email_resultado_enviado = now()
    WHERE id = p_visita_id AND email_resultado_enviado IS NULL;
  IF FOUND THEN PERFORM private.email_notificar(p_visita_id, v_email_tipo); END IF;

  -- (B) Notif a CLÍNICA/MÉDICO — SOLO en aprobación (confirmada). Claim idempotente propio.
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
                  CASE WHEN rec.es_medico THEN '/medico' ELSE '/clinica/calendario' END)
          RETURNING id INTO v_nid;
        PERFORM private.push_notificar('notificaciones', v_nid::text);   -- push best-effort
      END LOOP;
      PERFORM private.email_notificar(p_visita_id, 'aprobada_clinica');  -- email fan-out (edge re-deriva)
    END IF;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION private.notificar_resultado_visita_interno(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) public.administrar_visita — misma firma y retorno. Gate por equipo para el supervisor (A3), PV027 único para
--    "no existe" y "no autorizado", y la notificación adentro (antes la llamaba el front, en las tres acciones).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.administrar_visita(p_visita_id uuid, p_accion text, p_nueva_fecha date DEFAULT NULL::date, p_nueva_hora_inicio text DEFAULT NULL::text, p_nueva_hora_fin text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_visita RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;

  -- Gate (mig 381, antes de cualquier otra validación). Quien administra: super_admin, admin/editor de la empresa de
  -- la visita, o el SUPERVISOR del equipo de la cuenta de la visita (el mismo predicado que la policy SELECT
  -- "Proveedor ve visitas segun rol": no se administra lo que no se ve). El médico es la parte VISITADA, no aprueba.
  -- COALESCE en cada término: fail-closed (un NULL no abre). Visita inexistente → el mismo PV027 (sin oráculo de ids).
  IF NOT FOUND OR NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR (
         COALESCE(public.mi_empresa_proveedor() = v_visita.empresa_id, false)
         AND (
              COALESCE(public.mi_rol_proveedor() IN ('admin', 'editor'), false)
           OR (
                COALESCE(public.mi_rol_proveedor() = 'supervisor', false)
                AND COALESCE(public.supervisa_cuenta_proveedor(v_visita.cuenta_proveedor_id), false)
              )
         )
       )
  ) THEN
    RAISE EXCEPTION 'No autorizado para administrar esta visita.' USING ERRCODE = 'PV027';
  END IF;

  -- aprobada_por solo si el caller es proveedor (su uid ∈ cuentas_proveedor);
  -- para super_admin se preserva el valor previo (no viola la FK).
  IF p_accion = 'aprobar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada');
  ELSIF p_accion = 'rechazar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'rechazada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'rechazada');
  ELSIF p_accion = 'modificar' THEN
    -- mig 376: las horas llegan como text ('HH:MM' del <input type="time"> del front) y las columnas son time. Sin el
    -- cast, COALESCE(text, time) no compilaba (42804) y 'modificar' fallaba siempre, aun cambiando solo la fecha.
    -- Una hora que no es HH:MM (o HH:MM:SS) da PV003 antes del UPDATE; NULL = sin cambio.
    IF p_nueva_hora_inicio IS NOT NULL AND p_nueva_hora_inicio !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' THEN
      RAISE EXCEPTION 'La hora debe tener formato HH:MM.' USING ERRCODE = 'PV003';
    END IF;
    IF p_nueva_hora_fin IS NOT NULL AND p_nueva_hora_fin !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' THEN
      RAISE EXCEPTION 'La hora debe tener formato HH:MM.' USING ERRCODE = 'PV003';
    END IF;
    UPDATE public.visitas_agendadas
    SET fecha_visita = COALESCE(p_nueva_fecha, fecha_visita),
        hora_inicio = COALESCE(p_nueva_hora_inicio::time, hora_inicio),
        hora_fin = COALESCE(p_nueva_hora_fin::time, hora_fin),
        estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada', 'modificado', true);
  ELSE
    RETURN jsonb_build_object('error', 'Acción no válida');
  END IF;

  -- mig 381: aviso al visitador (y a la clínica en la aprobación) en la misma transacción. Antes lo pedía el front
  -- después, con notificar_visita_resultado, en estas mismas tres acciones; con un supervisor daba PT002 y se perdía.
  PERFORM private.notificar_resultado_visita_interno(p_visita_id);

  RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- d) public.notificar_visita_resultado — COMPAT no-op para bundles viejos del front, que la siguen llamando después de
--    administrar_visita. La notificación ahora la hace administrar_visita (mig 381): si esta función volviera a
--    notificar, el bundle viejo duplicaría el aviso. Conserva la firma, el retorno (void) y los errores de hoy:
--    cuenta proveedora inactiva / empresa no activa (42501, exigir_empresa_activa), PT001 si la visita no existe y
--    PT002 si el llamante no pasa el gate, que es el mismo de administrar_visita.
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notificar_visita_resultado(p_visita_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE v RECORD;
BEGIN
  PERFORM private.exigir_empresa_activa();
  SELECT empresa_id, cuenta_proveedor_id INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE (mismo que administrar_visita, mig 381). COALESCE fail-closed.
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR (
         COALESCE(public.mi_empresa_proveedor() = v.empresa_id, false)
         AND (
              COALESCE(public.mi_rol_proveedor() IN ('admin', 'editor'), false)
           OR (
                COALESCE(public.mi_rol_proveedor() = 'supervisor', false)
                AND COALESCE(public.supervisa_cuenta_proveedor(v.cuenta_proveedor_id), false)
              )
         )
       )
  ) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002';
  END IF;
  -- Sin efectos: la notificación ya la hizo administrar_visita.
  RETURN;
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- e) public.cancelar_visita — idéntica a la viva salvo el accion_url del staff de clínica (A11).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancelar_visita(p_visita_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE v_visita RECORD; v_prev text;
        v_medico_nom text; v_empresa_nom text; v_fecha text; v_hora text; v_clinica_msg text; v_nid uuid; rec record;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Visita no encontrada'); END IF;
  -- Ownership: super_admin o el visitador dueño. COALESCE fail-open-guard.
  IF NOT ( private.tiene_rol(ARRAY['super_admin']) OR COALESCE(v_visita.cuenta_proveedor_id = auth.uid(), false) ) THEN
    RAISE EXCEPTION 'No autorizado para cancelar esta visita';
  END IF;
  v_prev := v_visita.estado;
  -- Máquina de estados (regla de ventana idéntica).
  IF v_visita.estado = 'propuesta' THEN
    NULL;
  ELSIF v_visita.estado IN ('confirmada', 'aprobada', 'pendiente') THEN
    IF NOT (v_visita.fecha_limite_cancelacion IS NULL OR CURRENT_DATE <= v_visita.fecha_limite_cancelacion) THEN
      RETURN jsonb_build_object('error', 'Ya pasó la fecha límite para cancelar esta visita');
    END IF;
  ELSE
    RETURN jsonb_build_object('error', 'Esta visita no se puede cancelar en su estado actual');
  END IF;

  UPDATE public.visitas_agendadas SET estado = 'cancelada' WHERE id = p_visita_id;

  -- NUEVO: notif a clínica/médico SOLO si el estado previo era conocido por el lado clínico
  -- (confirmada/aprobada/pendiente). NO si venía de 'propuesta'. Claim idempotente propio.
  IF v_prev IN ('confirmada','aprobada','pendiente') THEN
    UPDATE public.visitas_agendadas SET email_cancelacion_enviado = now()
      WHERE id = p_visita_id AND email_cancelacion_enviado IS NULL;
    IF FOUND THEN
      v_medico_nom  := COALESCE((SELECT nombre_completo FROM public.perfiles WHERE id = v_visita.medico_id), 'el médico');
      v_empresa_nom := COALESCE((SELECT nombre_empresa FROM public.empresas_proveedoras WHERE id = v_visita.empresa_id), 'un laboratorio');
      v_fecha := to_char(v_visita.fecha_visita, 'DD/MM/YYYY'); v_hora := substr(v_visita.hora_inicio::text, 1, 5);
      v_clinica_msg := 'Se canceló la visita de ' || v_empresa_nom || ' con ' || v_medico_nom || ' del ' || v_fecha || ' a las ' || v_hora || '.';
      FOR rec IN SELECT usuario_id, es_medico FROM public.destinatarios_visita_clinica(p_visita_id) LOOP
        INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
          VALUES (rec.usuario_id, 'visita_clinica_cancelada', 'Visita de laboratorio cancelada', v_clinica_msg,
                  CASE WHEN rec.es_medico THEN '/medico' ELSE '/clinica/calendario' END)
          RETURNING id INTO v_nid;
        PERFORM private.push_notificar('notificaciones', v_nid::text);
      END LOOP;
      PERFORM private.email_notificar(p_visita_id, 'cancelada_clinica');
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'estado', 'cancelada');
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- f) private.gate_visita_pais — todo lo vivo intacto + médico activo y cuenta activa (A4). La función viva no tiene
--    ningún bypass (ni por rol, ni por service_role, ni por TG_OP): las dos reglas nuevas van PRIMERO, antes del
--    lookup del plan, para que un médico inválido no gaste el FOR UPDATE del pvc ni se confunda con un error de país.
--    El trigger (BEFORE INSERT OR UPDATE OF medico_id) no cambia: el médico se revalida en los dos eventos; la cuenta,
--    solo en INSERT (el UPDATE de medico_id no cambia de visitador).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.gate_visita_pais()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_pvc record; v_usadas int;
BEGIN
  -- mig 381 (A4): el médico tiene que existir como médico (fila en medicos; la FK de medico_id apunta a perfiles) y
  -- estar activo en medicos y en perfiles. Mismo mensaje para todos los casos.
  IF NOT EXISTS (
       SELECT 1 FROM public.medicos m JOIN public.perfiles p ON p.id = m.id
        WHERE m.id = NEW.medico_id AND COALESCE(m.activo, false) AND COALESCE(p.activo, false)) THEN
    RAISE EXCEPTION 'No se puede agendar una visita con este médico.' USING ERRCODE = 'PV028';
  END IF;
  -- mig 381 (A4): al crear, la cuenta del visitador tiene que estar activa (la policy de INSERT usa
  -- private.cuenta_en_empresa, que no mira activo).
  IF TG_OP = 'INSERT' AND NOT EXISTS (
       SELECT 1 FROM public.cuentas_proveedor cp WHERE cp.id = NEW.cuenta_proveedor_id AND cp.activo = true) THEN
    RAISE EXCEPTION 'No se puede agendar una visita con este médico.' USING ERRCODE = 'PV028';
  END IF;

  SELECT p.pais_id INTO v_pais FROM public.perfiles p WHERE p.id = NEW.medico_id;

  -- pvc activo+vigente de la empresa del visitador que cubre el país del médico (= visitador_ve_medico)
  SELECT pvc.* INTO v_pvc
  FROM public.planes_visitador_contratados pvc
  WHERE pvc.empresa_id = public.mi_empresa_proveedor()
    AND pvc.estado = 'activo'
    AND CURRENT_DATE BETWEEN pvc.fecha_inicio AND pvc.fecha_fin
    AND COALESCE(pvc.pais_id = v_pais, false)
  ORDER BY pvc.fecha_fin DESC
  LIMIT 1
  FOR UPDATE;                                          -- serializa el check de bolsa (anti-TOCTOU)

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No autorizado: sin plan de visitas activo que cubra el país del médico'
      USING ERRCODE = 'P0001';                         -- error PAÍS
  END IF;

  NEW.pais_id := v_pais;                               -- ESTAMPAR (atribución congelada)

  IF v_pvc.cantidad_visitas_incluidas IS NULL THEN
    RETURN NEW;                                        -- ilimitado
  END IF;

  v_usadas := private.pvc_usadas(v_pvc.empresa_id, v_pvc.pais_id, v_pvc.fecha_inicio, v_pvc.fecha_fin, NEW.id);
  IF v_usadas >= v_pvc.cantidad_visitas_incluidas THEN
    RAISE EXCEPTION 'Bolsa de visitas agotada para el país (% de % usadas)', v_usadas, v_pvc.cantidad_visitas_incluidas
      USING ERRCODE = 'PV001';                         -- error BUCKET. SQLSTATE custom (NO P0002=no_data_found
                                                       -- reservado): distinguible de país (P0001) sin pisar built-ins.
  END IF;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- g) Datos (A11): las notificaciones viejas del visitador apuntaban a una ruta inexistente. Medido el 20-oct: 4.
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  UPDATE public.notificaciones SET accion_url = '/visitador/mis-visitas' WHERE accion_url = '/proveedor/visitador';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 4 THEN
    RAISE EXCEPTION 'MIG81: se esperaban 4 notificaciones con la ruta vieja y se corrigieron %', n USING ERRCODE = 'MIG81';
  END IF;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- h) AUTOCHEQUEO FINAL
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r record; v_malos text := ''; v_src text; v_fn regprocedure;
BEGIN
  -- las 4 funciones de la precondición cambiaron de cuerpo y conservan su ACL
  FOR r IN SELECT m.fn, m.md5_pre, m.acl_pre, md5(p.prosrc) AS md5_post, p.proacl::text AS acl_post
             FROM m381_pre m JOIN pg_proc p ON p.oid = m.oid LOOP
    IF r.md5_post = r.md5_pre THEN v_malos := v_malos || r.fn || ' no cambió; '; END IF;
    IF r.acl_post IS DISTINCT FROM r.acl_pre THEN v_malos := v_malos || r.fn || ' cambió de ACL (' || COALESCE(r.acl_post, 'NULL') || '); '; END IF;
  END LOOP;
  IF (SELECT count(*) FROM m381_pre m JOIN pg_proc p ON p.oid = m.oid) <> 4 THEN v_malos := v_malos || 'falta alguna de las 4 (oid); '; END IF;

  -- las 5 funciones tocadas/creadas: DEFINER con search_path=''
  FOREACH v_fn IN ARRAY ARRAY[
      to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'), to_regprocedure('public.notificar_visita_resultado(uuid)'),
      to_regprocedure('public.cancelar_visita(uuid)'), to_regprocedure('private.gate_visita_pais()'),
      to_regprocedure('private.notificar_resultado_visita_interno(uuid)')] LOOP
    IF v_fn IS NULL THEN v_malos := v_malos || 'una de las 5 no existe; '; CONTINUE; END IF;
    IF NOT COALESCE((SELECT p.prosecdef AND 'search_path=""' = ANY (p.proconfig) FROM pg_proc p WHERE p.oid = v_fn), false) THEN
      v_malos := v_malos || v_fn::text || ' sin DEFINER o sin search_path vacío; ';
    END IF;
  END LOOP;

  -- la interna no la ejecuta nadie más que su dueño
  v_fn := to_regprocedure('private.notificar_resultado_visita_interno(uuid)');
  IF v_fn IS NOT NULL THEN
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
                   WHERE p.oid = v_fn AND a.grantee = 0) THEN
      v_malos := v_malos || 'notificar_resultado_visita_interno ejecutable por PUBLIC/anon/authenticated; ';
    END IF;
  END IF;

  v_src := (SELECT p.prosrc FROM pg_proc p WHERE p.oid = to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'));
  IF position('PV027' in v_src) = 0 OR position('supervisa_cuenta_proveedor' in v_src) = 0
     OR position('notificar_resultado_visita_interno' in v_src) = 0 OR position('Visita no encontrada' in v_src) > 0 THEN
    v_malos := v_malos || 'administrar_visita sin PV027/supervisa_cuenta_proveedor/notificación interna, o con Visita no encontrada; ';
  END IF;

  v_src := (SELECT p.prosrc FROM pg_proc p WHERE p.oid = to_regprocedure('public.notificar_visita_resultado(uuid)'));
  IF position('INSERT' in v_src) > 0 OR position('email_notificar' in v_src) > 0 OR position('net.' in v_src) > 0 THEN
    v_malos := v_malos || 'notificar_visita_resultado sigue con efectos (INSERT/email_notificar/net.); ';
  END IF;

  v_src := (SELECT p.prosrc FROM pg_proc p WHERE p.oid = to_regprocedure('private.gate_visita_pais()'));
  IF position('PV028' in v_src) = 0 THEN v_malos := v_malos || 'gate_visita_pais sin PV028; '; END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
              AND p.prosrc LIKE '%/proveedor/visitador''%') THEN
    v_malos := v_malos || 'queda una función con la ruta vieja del visitador: '
      || (SELECT string_agg(p.oid::regprocedure::text, ', ') FROM pg_proc p
           WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND p.prosrc LIKE '%/proveedor/visitador''%') || '; ';
  END IF;
  IF position('/proveedor/visitador/aprobar' in
       COALESCE((SELECT p.prosrc FROM pg_proc p WHERE p.oid = to_regprocedure('public.notificar_visita_propuesta(uuid)')), '')) = 0 THEN
    v_malos := v_malos || 'notificar_visita_propuesta perdió /proveedor/visitador/aprobar; ';
  END IF;

  IF EXISTS (SELECT 1 FROM public.notificaciones WHERE accion_url = '/proveedor/visitador') THEN
    v_malos := v_malos || 'quedan notificaciones con la ruta vieja; ';
  END IF;

  IF v_malos <> '' THEN
    RAISE EXCEPTION 'MIG81: autochequeo: %', v_malos USING ERRCODE = 'MIG81';
  END IF;
END $$;

COMMIT;
