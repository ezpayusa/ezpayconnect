-- ############################################################################################
-- 379 - registrar_medico_desde_invitacion enrola por la solicitud de alta (paso 6 de la familia enrolamiento)
-- ############################################################################################
-- Recon: 20-oct-2026, solo lectura, sobre prod (C:\tmp\mig379\). Estado vivo medido:
--   - public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) RETURNS uuid, plpgsql VOLATILE,
--     SECURITY DEFINER, dueno postgres, SET search_path TO 'public', ACL {postgres=X/postgres,service_role=X/postgres},
--     md5(prosrc) 8ee9ef3ed53ca1f3195903dd5c1a5564. Referencias sin calificar: invitaciones_medico, medicos, perfiles,
--     medico_clinicas (private.crear_clinica_con_dueno_interno ya va calificada). La unica funcion que la nombra es
--     reenviar_solicitud_alta (en un comentario).
--   - Triggers que dispara (todos con search_path propio, no heredan el ''): medicos trigger_medicos_lab_enrolador_inmutable
--     (search_path '', md5 2af30509d27efef4ed649c5785883381), perfiles trg_perfiles_guard_rol_update (search_path ''),
--     clinicas trigger_guard_tema_clinicas (search_path public). notificaciones, invitaciones_medico y
--     solicitudes_alta_medico sin triggers.
--   - md5(prosrc): aprobar_solicitud_alta e7a2bea305a4f4dfe564f7b14157835b, private.push_notificar
--     90e6e8ec7eb37240e400a7c5768a8997, private.crear_clinica_con_dueno_interno bdd97d7989bdddf4ddfe4dce49da7fae.
--   - Huellas post-378: funciones (cuerpo, DEFINER, config, ACL) 426a70e13cf08e09d5705852309e540b/399 (sin la tocada
--     f6edd044170da00f5bf23211af4e335f/398); ACL de funciones f71eb65210787bd94c899a623d20350b/399; ACL de relaciones de
--     public 9da6a3c4ca75cd58b3a3053603bf03fe/2406; policies cfb5d7632f071052d491e02a6a5e0932/311.
--   - Edge registrar-medico-invitacion (service_role): valida la invitacion -> auth.admin.createUser(email de la
--     invitacion) -> INSERT perfiles (id, email, nombre_completo, rol 'medico', pais_id de la invitacion, activo) ->
--     rpc(p_token, p_user_id, p_email = email de la invitacion, p_nombre_completo, p_telefono, p_especialidad).
--
-- Que hace (misma firma, retorno, DEFINER y ACL; mensajes de error iguales letra por letra):
--   1. SET search_path = '' y todas las referencias calificadas con public.
--   2. Despues de crear el medico (y su clinica o membresia) y antes de marcar la invitacion 'usada': si hay una
--      solicitud de alta en 'invitada' con invitacion_id = esta invitacion (FOR UPDATE), enrola al medico con la
--      empresa de la solicitud (GUC app.enrolamiento_rpc, el mismo de enrolar_medico, encendido solo alrededor del
--      UPDATE; WHERE lab_enrolador_id IS NULL), pasa la solicitud a 'registrada' con medico_id y updated_at, y avisa al
--      visitador que la pidio (in-app tipo 'solicitud_alta_registrada' + push, texto generico, accion_url
--      '/visitador/solicitudes'). Sin solicitud (o en otro estado): comportamiento identico al de antes.
--
-- Errcodes: ninguno nuevo (los 3 RAISE siguen sin ERRCODE, P0001, como hoy).
--
-- md5(prosrc) de la funcion nueva (calculado sobre este archivo, sin CR; el autochequeo lo exige):
--   registrar_medico_desde_invitacion 72889dea4724bc61f4b21ec3a3da158e.
--
-- Huellas esperadas despues: ACL de funciones, ACL de relaciones de public y policies sin cambio; funciones completas
--   iguales a las de antes excluyendo la tocada.
--
-- Orden de locks: esta funcion toma la invitacion y despues la solicitud; reenviar_solicitud_alta toma la solicitud y
--   despues la invitacion. Si corren a la vez sobre el mismo par, Postgres aborta una con 40P01 (sin estado a medias).
--
-- Front: nada (la solicitud 'registrada' ya la pinta listar_solicitudes_alta).
--
-- Rollback: 379_rollback.sql (vuelve el cuerpo vivo exacto; las solicitudes 'registrada' y los enrolamientos hechos
--   quedan). Orden global: 379_rollback -> 378_rollback -> 377_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc)||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')||'|'||
               pg_get_function_result(p.oid)||'|'||p.provolatile::text||'|'||pg_get_userbyid(p.proowner)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)'));
  IF v IS DISTINCT FROM '8ee9ef3ed53ca1f3195903dd5c1a5564|true|{search_path=public}|{postgres=X/postgres,service_role=X/postgres}|uuid|v|postgres' THEN
    bad := bad||'registrar_medico_desde_invitacion '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'registrar_medico_desde_invitacion') <> 1 THEN
    bad := bad||'sobrecargas de registrar_medico_desde_invitacion; ';
  END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.trg_medicos_lab_enrolador_inmutable()'));
  IF v IS DISTINCT FROM '2af30509d27efef4ed649c5785883381' THEN bad := bad||'trg_medicos_lab_enrolador_inmutable md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.aprobar_solicitud_alta(uuid)'));
  IF v IS DISTINCT FROM 'e7a2bea305a4f4dfe564f7b14157835b' THEN bad := bad||'aprobar_solicitud_alta md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.push_notificar(text,text)'));
  IF v IS DISTINCT FROM '90e6e8ec7eb37240e400a7c5768a8997' THEN bad := bad||'push_notificar md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  -- huellas post-378
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
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'f71eb65210787bd94c899a623d20350b 399' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '426a70e13cf08e09d5705852309e540b 399' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG379_PRE FALLA:%', bad; END IF;

  -- huella de las funciones de public/private sin la tocada: el autochequeo exige que quede igual
  CREATE TEMP TABLE mig379_huella ON COMMIT DROP AS
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid <> 'public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)'::regprocedure;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: registrar_medico_desde_invitacion
CREATE OR REPLACE FUNCTION public.registrar_medico_desde_invitacion(p_token uuid, p_user_id uuid, p_email text, p_nombre_completo text, p_telefono text DEFAULT NULL::text, p_especialidad text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_invitacion RECORD; v_pais_id UUID; v_clinica_id UUID; v_sol RECORD; v_nid UUID;
BEGIN
  SELECT * INTO v_invitacion FROM public.invitaciones_medico
  WHERE token = p_token AND estado = 'pendiente' AND expires_at > NOW() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitacion no valida o expirada'; END IF;
  v_pais_id := v_invitacion.pais_id; v_clinica_id := v_invitacion.clinica_id;
  IF LOWER(v_invitacion.email) != LOWER(p_email) THEN RAISE EXCEPTION 'El email no coincide con la invitacion'; END IF;
  IF EXISTS (SELECT 1 FROM public.medicos WHERE id = p_user_id) THEN RAISE EXCEPTION 'Este usuario ya esta registrado como medico'; END IF;

  -- Crear medico. NO se setea clinica_id (se elimina; requiere medicos.clinica_id nullable = FASE 4).
  INSERT INTO public.medicos (id, nombre_completo, email, telefono, especialidad, especialidad_id, pais_id)
  VALUES (p_user_id, p_nombre_completo, p_email,
          COALESCE(p_telefono, v_invitacion.telefono),
          COALESCE(p_especialidad, v_invitacion.especialidad),  -- texto legacy en paralelo (intacto)
          v_invitacion.especialidad_id,                          -- NULL si "sin especialidad" -> no falla
          v_pais_id);

  UPDATE public.perfiles SET rol = 'medico', pais_id = v_pais_id, nombre_completo = p_nombre_completo WHERE id = p_user_id;

  IF v_clinica_id IS NOT NULL THEN
    -- Ruta A: la clinica invito al medico -> membresia en ESA clinica (comportamiento actual).
    INSERT INTO public.medico_clinicas (medico_id, clinica_id, es_principal)
    VALUES (p_user_id, v_clinica_id, true) ON CONFLICT DO NOTHING;
  ELSE
    -- Ruta B: invitacion de admin EzPay sin clinica -> el medico crea su propia clinica.
    -- Va DIRECTO al privado: aca auth.uid() es NULL (la edge llama con service_role antes de que
    -- exista sesion) y el gate de la publica, que es fail-closed, la rechazaria con 42501.
    PERFORM private.crear_clinica_con_dueno_interno(
      p_user_id,
      'Consultorio ' || p_nombre_completo,
      v_pais_id
    );
  END IF;

  -- Mig 379: si la invitacion nacio de una solicitud de alta (aprobar/reenviar), el medico queda enrolado por la
  -- empresa de la solicitud y la solicitud pasa a 'registrada'. Sin solicitud en 'invitada': nada cambia.
  SELECT s.id, s.empresa_id, s.solicitado_por, s.pais_id INTO v_sol
    FROM public.solicitudes_alta_medico s
   WHERE s.invitacion_id = v_invitacion.id AND s.estado = 'invitada'
   FOR UPDATE;
  IF FOUND THEN
    -- el guard de medicos (PV015) solo deja escribir el par con el GUC encendido (el mismo de enrolar_medico)
    PERFORM set_config('app.enrolamiento_rpc', 'on', true);
    UPDATE public.medicos
       SET lab_enrolador_id = v_sol.empresa_id, lab_enrolador_fecha = now()
     WHERE id = p_user_id AND lab_enrolador_id IS NULL;
    PERFORM set_config('app.enrolamiento_rpc', '', true);

    UPDATE public.solicitudes_alta_medico
       SET estado = 'registrada', medico_id = p_user_id, updated_at = now()
     WHERE id = v_sol.id;

    -- aviso al visitador que la pidio (texto generico)
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata, pais_id)
    VALUES (v_sol.solicitado_por, 'solicitud_alta_registrada', 'Médico registrado',
            'Un médico de tus solicitudes de alta completó su registro en MED.',
            '/visitador/solicitudes', jsonb_build_object('solicitud_id', v_sol.id), v_sol.pais_id)
    RETURNING id INTO v_nid;
    PERFORM private.push_notificar('notificaciones', v_nid::text);
  END IF;

  UPDATE public.invitaciones_medico SET estado = 'usada', used_at = NOW() WHERE id = v_invitacion.id;
  RETURN p_user_id;
END; $function$;

-- ACL igual a la viva (CREATE OR REPLACE la conserva; esto es documental)
REVOKE ALL ON FUNCTION public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) TO service_role;

-- ---------------------------------------------------------------------------- 2: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text; r_act record; r_ini record;
BEGIN
  v := (SELECT md5(p.prosrc)||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')||'|'||
               pg_get_function_result(p.oid)||'|'||p.provolatile::text||'|'||pg_get_userbyid(p.proowner)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)'));
  IF v IS DISTINCT FROM '72889dea4724bc61f4b21ec3a3da158e|true|{"search_path=\"\""}|{postgres=X/postgres,service_role=X/postgres}|uuid|v|postgres' THEN
    bad := bad||'registrar_medico_desde_invitacion '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'registrar_medico_desde_invitacion') <> 1 THEN
    bad := bad||'sobrecargas de registrar_medico_desde_invitacion; ';
  END IF;
  IF has_function_privilege('authenticated', 'public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)', 'EXECUTE') THEN
    bad := bad||'authenticated o anon ejecutan la funcion; ';
  END IF;

  -- el resto de las funciones de public/private, igual que antes
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n INTO r_act
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid <> 'public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)'::regprocedure;
  SELECT t.h, t.n INTO r_ini FROM pg_temp.mig379_huella t;
  IF r_act.h IS DISTINCT FROM r_ini.h OR r_act.n IS DISTINCT FROM r_ini.n THEN
    bad := bad||'cambio otra funcion: '||COALESCE(r_act.h, '-')||'/'||COALESCE(r_act.n::text, '-')||' vs '||COALESCE(r_ini.h, '-')||'/'||COALESCE(r_ini.n::text, '-')||'; ';
  END IF;

  -- huellas globales sin cambio
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
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'f71eb65210787bd94c899a623d20350b 399' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG379_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
