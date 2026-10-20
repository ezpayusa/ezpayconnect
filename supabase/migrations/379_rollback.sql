-- ############################################################################################
-- 379_rollback - deshace la 379: registrar_medico_desde_invitacion vuelve al cuerpo de antes (search_path public,
--                sin enrolar por la solicitud)
-- ############################################################################################
-- Precondicion: estado post-379 (md5(prosrc) 72889dea4724bc61f4b21ec3a3da158e, search_path '', DEFINER, ACL
--   {postgres=X/postgres,service_role=X/postgres}).
-- Lo que NO se toca: las solicitudes que quedaron en 'registrada' con su medico_id (estado valido de la 377), los
--   enrolamientos hechos al registrar (lab_enrolador_id/lab_enrolador_fecha: el guard de medicos no deja quitarlos) y
--   las notificaciones 'solicitud_alta_registrada' ya enviadas.
-- La funcion vuelve EXACTA: el cuerpo de abajo es el pg_get_functiondef vivo medido en prod el 20-oct-2026
--   (md5(prosrc) 8ee9ef3ed53ca1f3195903dd5c1a5564); el autochequeo lo exige.
-- Autochequeo: md5, DEFINER, search_path=public y ACL exacta; huellas iguales a las post-378: funciones (cuerpo,
--   DEFINER, config, ACL) 426a70e13cf08e09d5705852309e540b/399, ACL de funciones f71eb652.../399, policies
--   cfb5d763.../311, ACL de relaciones de public 9da6a3c4.../2406.
-- Orden global: 379_rollback -> 378_rollback -> 377_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc)||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)'));
  IF v IS DISTINCT FROM '72889dea4724bc61f4b21ec3a3da158e|true|{"search_path=\"\""}|{postgres=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'registrar_medico_desde_invitacion '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'registrar_medico_desde_invitacion') <> 1 THEN
    bad := bad||'sobrecargas de registrar_medico_desde_invitacion; ';
  END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG379_ROLLBACK_PRE FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: cuerpo vivo de antes de la 379
CREATE OR REPLACE FUNCTION public.registrar_medico_desde_invitacion(p_token uuid, p_user_id uuid, p_email text, p_nombre_completo text, p_telefono text DEFAULT NULL::text, p_especialidad text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_invitacion RECORD; v_pais_id UUID; v_clinica_id UUID;
BEGIN
  SELECT * INTO v_invitacion FROM invitaciones_medico
  WHERE token = p_token AND estado = 'pendiente' AND expires_at > NOW() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitacion no valida o expirada'; END IF;
  v_pais_id := v_invitacion.pais_id; v_clinica_id := v_invitacion.clinica_id;
  IF LOWER(v_invitacion.email) != LOWER(p_email) THEN RAISE EXCEPTION 'El email no coincide con la invitacion'; END IF;
  IF EXISTS (SELECT 1 FROM medicos WHERE id = p_user_id) THEN RAISE EXCEPTION 'Este usuario ya esta registrado como medico'; END IF;

  -- Crear medico. NO se setea clinica_id (se elimina; requiere medicos.clinica_id nullable = FASE 4).
  INSERT INTO medicos (id, nombre_completo, email, telefono, especialidad, especialidad_id, pais_id)
  VALUES (p_user_id, p_nombre_completo, p_email,
          COALESCE(p_telefono, v_invitacion.telefono),
          COALESCE(p_especialidad, v_invitacion.especialidad),  -- texto legacy en paralelo (intacto)
          v_invitacion.especialidad_id,                          -- NULL si "sin especialidad" -> no falla
          v_pais_id);

  UPDATE perfiles SET rol = 'medico', pais_id = v_pais_id, nombre_completo = p_nombre_completo WHERE id = p_user_id;

  IF v_clinica_id IS NOT NULL THEN
    -- Ruta A: la clinica invito al medico -> membresia en ESA clinica (comportamiento actual).
    INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal)
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

  UPDATE invitaciones_medico SET estado = 'usada', used_at = NOW() WHERE id = v_invitacion.id;
  RETURN p_user_id;
END; $function$
;

REVOKE ALL ON FUNCTION public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) TO service_role;

-- ---------------------------------------------------------------------------- 2: autochequeo
DO $autochequeo$
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
  IF has_function_privilege('authenticated', 'public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)', 'EXECUTE') THEN
    bad := bad||'authenticated o anon ejecutan la funcion; ';
  END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '426a70e13cf08e09d5705852309e540b 399' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;
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

  IF bad <> '' THEN RAISE EXCEPTION 'MIG379_ROLLBACK_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
