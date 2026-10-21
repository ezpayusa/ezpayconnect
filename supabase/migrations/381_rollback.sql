-- ############################################################################################
-- 381_rollback - deshace la 381: vuelve administrar_visita, notificar_visita_resultado, cancelar_visita y
--   private.gate_visita_pais a su cuerpo pre-381 y borra private.notificar_resultado_visita_interno(uuid).
-- ############################################################################################
-- Precondicion: estado post-381 (md5(prosrc) de las 4 funciones tocadas y de la interna nueva, medidos en el dry-run
--   del 21-oct-2026 00:31 UTC).
-- Fuente de los cuerpos pre: pg_get_functiondef VIVO de prod el 20-oct-2026, antes del apply (md5(prosrc)
--   administrar_visita 5d4a718de9d34fcfcc36e74a0e068bce, notificar_visita_resultado ebdb579ec423c0dbabce62fadfa424f8,
--   cancelar_visita 866159b76f6af88291dffea24430e5bf, private.gate_visita_pais 272120bc46268518ff8617291085b70f).
--   Copiados sin retocar; CREATE OR REPLACE con la misma firma conserva los grants.
-- Lo que NO se toca: las 4 notificaciones que la 381 pasó de la ruta vieja del visitador a /visitador/mis-visitas
--   quedan como estan (volver a una URL que no existe en el router no tiene sentido). Las notificaciones que haya creado
--   administrar_visita con la 381 viva tambien quedan.
-- Efecto funcional del rollback: el supervisor vuelve a poder administrar cualquier visita de su empresa (A3 abierto)
--   y la notificacion vuelve a depender del front (notificar_visita_resultado); al agendar ya no se revalida
--   medico ni cuenta activos (A4 abierto).
-- Autochequeo: los 4 md5 pre, ACL igual a la de antes del rollback, DEFINER + search_path '' en las 4, la interna no
--   existe y huellas iguales a las post-380: funciones (cuerpo, DEFINER, config, ACL) 76b4b9cdebf22fcf3316c9135cc699c1/401,
--   ACL de funciones 853697ced74926f9b09abe3e74f68d50/401, policies cfb5d7632f071052d491e02a6a5e0932/311,
--   ACL de relaciones de public 9da6a3c4ca75cd58b3a3053603bf03fe/2406.
-- Orden global: 381_rollback -> 380_rollback -> 379_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
CREATE TEMP TABLE m381rb_pre ON COMMIT DROP AS
SELECT p.oid AS oid, p.oid::regprocedure::text AS fn, p.proacl::text AS acl_pre
  FROM pg_proc p
 WHERE p.oid IN (to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'),
                 to_regprocedure('public.notificar_visita_resultado(uuid)'),
                 to_regprocedure('public.cancelar_visita(uuid)'),
                 to_regprocedure('private.gate_visita_pais()'));

DO $precondicion$
DECLARE bad text := ''; r record; v_esperado text; v text;
BEGIN
  IF (SELECT count(*) FROM m381rb_pre) <> 4 THEN
    bad := bad||'faltan funciones ('||(SELECT count(*) FROM m381rb_pre)||' de 4); ';
  END IF;
  FOR r IN SELECT m.fn, md5(p.prosrc) AS md5_vivo FROM m381rb_pre m JOIN pg_proc p ON p.oid = m.oid LOOP
    v_esperado := CASE r.fn
      WHEN 'administrar_visita(uuid,text,date,text,text,text)' THEN 'e97d42e596aad84034039644be9da079'
      WHEN 'notificar_visita_resultado(uuid)'                   THEN 'b1b7041518662db7c3d3791e036710be'
      WHEN 'cancelar_visita(uuid)'                              THEN '510d4020cef059c3778df38a2e0efa25'
      WHEN 'private.gate_visita_pais()'                         THEN '7ea4b42ae377f3e5338e6bc603c3121f'
    END;
    IF r.md5_vivo IS DISTINCT FROM v_esperado THEN
      bad := bad||r.fn||' (vivo '||r.md5_vivo||', post-381 '||COALESCE(v_esperado, '?')||'); ';
    END IF;
  END LOOP;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.notificar_resultado_visita_interno(uuid)'));
  IF v IS DISTINCT FROM '4051774b773f93babe8b5f0630343141' THEN
    bad := bad||'private.notificar_resultado_visita_interno '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG81: 381_rollback precondicion (la 381 no esta aplicada o cambio): %', bad USING ERRCODE = 'MIG81';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: cuerpos pre-381
-- administrar_visita(uuid,text,date,text,text,text) (pg_get_functiondef vivo de prod pre-381, 20-oct-2026, sin retocar)
CREATE OR REPLACE FUNCTION public.administrar_visita(p_visita_id uuid, p_accion text, p_nueva_fecha date DEFAULT NULL::date, p_nueva_hora_inicio text DEFAULT NULL::text, p_nueva_hora_fin text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_visita RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  -- Revalidación del caller: aprobada_por referencia cuentas_proveedor → quien
  -- administra es la empresa proveedora (supervisor) o super_admin. El médico es
  -- la parte VISITADA, no el aprobador. COALESCE evita el fail-open trivaluado
  -- (mi_empresa_proveedor() NULL ⇒ 'false OR NULL' = NULL ⇒ RAISE saltado).
  -- HARDENING (mig 210): la rama de empresa proveedora ahora exige, además de pertenecer a la
  -- empresa de la visita, poder aprobar visitas (private.puede_aprobar_visitas, fail-closed).
  -- Antes cualquier miembro de la empresa podía administrar; ahora solo roles admin/supervisor/editor.
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR (
         COALESCE(public.mi_empresa_proveedor() = v_visita.empresa_id, false)
         AND private.puede_aprobar_visitas()
       )
  ) THEN
    RAISE EXCEPTION 'No autorizado para administrar esta visita';
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

  RETURN v_result;
END;
$function$;

-- notificar_visita_resultado(uuid) (pg_get_functiondef vivo de prod pre-381, 20-oct-2026, sin retocar)
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

-- cancelar_visita(uuid) (pg_get_functiondef vivo de prod pre-381, 20-oct-2026, sin retocar)
CREATE OR REPLACE FUNCTION public.cancelar_visita(p_visita_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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
                  CASE WHEN rec.es_medico THEN '/medico' ELSE '/clinica' END)
          RETURNING id INTO v_nid;
        PERFORM private.push_notificar('notificaciones', v_nid::text);
      END LOOP;
      PERFORM private.email_notificar(p_visita_id, 'cancelada_clinica');
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'estado', 'cancelada');
END;
$function$;

-- private.gate_visita_pais() (pg_get_functiondef vivo de prod pre-381, 20-oct-2026, sin retocar)
CREATE OR REPLACE FUNCTION private.gate_visita_pais()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_pais uuid; v_pvc record; v_usadas int;
BEGIN
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

-- ---------------------------------------------------------------------------- 2: DROP de la interna
-- Despues de 1: administrar_visita ya no la llama.
DROP FUNCTION private.notificar_resultado_visita_interno(uuid);

-- ---------------------------------------------------------------------------- 3: datos
-- Sin cambios de datos: el UPDATE de accion_url de la 381 (4 notificaciones) NO se revierte (ver cabecera).

-- ---------------------------------------------------------------------------- 4: autochequeo
DO $autochequeo$
DECLARE bad text := ''; r record; v_esperado text; v text;
BEGIN
  FOR r IN SELECT m.fn, m.acl_pre, md5(p.prosrc) AS md5_post, p.proacl::text AS acl_post, p.prosecdef,
                  COALESCE('search_path=""' = ANY (p.proconfig), false) AS sp_vacio
             FROM m381rb_pre m JOIN pg_proc p ON p.oid = m.oid LOOP
    v_esperado := CASE r.fn
      WHEN 'administrar_visita(uuid,text,date,text,text,text)' THEN '5d4a718de9d34fcfcc36e74a0e068bce'
      WHEN 'notificar_visita_resultado(uuid)'                   THEN 'ebdb579ec423c0dbabce62fadfa424f8'
      WHEN 'cancelar_visita(uuid)'                              THEN '866159b76f6af88291dffea24430e5bf'
      WHEN 'private.gate_visita_pais()'                         THEN '272120bc46268518ff8617291085b70f'
    END;
    IF r.md5_post IS DISTINCT FROM v_esperado THEN bad := bad||r.fn||' md5 '||r.md5_post||' (pre '||COALESCE(v_esperado, '?')||'); '; END IF;
    IF r.acl_post IS DISTINCT FROM r.acl_pre THEN bad := bad||r.fn||' ACL '||COALESCE(r.acl_post, 'NULL')||'; '; END IF;
    IF NOT r.prosecdef OR NOT r.sp_vacio THEN bad := bad||r.fn||' sin DEFINER o sin search_path vacio; '; END IF;
  END LOOP;
  IF (SELECT count(*) FROM m381rb_pre m JOIN pg_proc p ON p.oid = m.oid) <> 4 THEN bad := bad||'falta alguna de las 4 (oid); '; END IF;
  IF to_regprocedure('private.notificar_resultado_visita_interno(uuid)') IS NOT NULL THEN
    bad := bad||'private.notificar_resultado_visita_interno sigue existiendo; ';
  END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '76b4b9cdebf22fcf3316c9135cc699c1 401' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '853697ced74926f9b09abe3e74f68d50 401' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'cfb5d7632f071052d491e02a6a5e0932 311' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9da6a3c4ca75cd58b3a3053603bf03fe 2406' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG81: 381_rollback autochequeo: %', bad USING ERRCODE = 'MIG81'; END IF;
END $autochequeo$;

COMMIT;
