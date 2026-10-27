-- =====================================================================================================================
-- ROLLBACK MIG 385 — vuelve registrar_clinica_desde_invitacion a la v1 viva exacta del 26-oct-2026: RETURNS integer,
-- SET search_path TO 'public', cuerpo con CRLF (md5(prosrc) 76d52027eeca678aca8e28354088e07f) y ACL
-- {postgres=X/postgres,service_role=X/postgres}. El texto de pg_get_functiondef viaja como literales E'…' línea por
-- línea con \r\n explícito (la huella no depende del fin de línea del archivo); md5 de la definición
-- f2ebc873947a5ca2f71af9d945c3dbad, verificado antes de ejecutar.
-- Cambia el tipo de retorno (uuid -> integer): DROP + CREATE, con la ACL repuesta en este mismo archivo.
-- Efecto esperado al revertir: el registro de clínica por invitación vuelve a fallar siempre (el estado de antes, a
-- propósito). Las clínicas, perfiles, filas de medicos y membresías creadas con la v2 QUEDAN (el rollback no borra datos).
-- Orden: primero la edge registrar-clinica-invitacion de vuelta a v18 (la v19 espera la v2), después este archivo.
-- Cadena: 385_rollback -> 384_rollback -> 383_rollback -> ...
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/385_rollback.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) PRECONDICIÓN: la 385 está aplicada tal cual (si no, no se toca nada)
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := '';
  c_f CONSTANT text := 'public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)';
BEGIN
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'registrar_clinica_desde_invitacion') <> 1 THEN
    bad := bad||'sobrecargas de registrar_clinica_desde_invitacion; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(c_f)
                   AND md5(p.prosrc) = 'ed19aae358ba091ef9e82ed18451615b' AND p.prorettype = 'uuid'::regtype AND p.prosecdef
                   AND p.proconfig = ARRAY['search_path=""']
                   AND p.proacl::text = '{postgres=X/postgres,service_role=X/postgres}') THEN
    bad := bad||'registrar_clinica_desde_invitacion no es la v2 de la 385 (md5 '||COALESCE((SELECT md5(p.prosrc) FROM pg_proc p
           WHERE p.oid = to_regprocedure(c_f)), 'no existe')||'); ';
  END IF;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG85R: precondición: %', bad USING ERRCODE = 'MIG85';
  END IF;
END $precondicion$;

-- huellas antes del rollback: el autochequeo exige que solo se mueva esta función
CREATE TEMP TABLE m385r_huellas ON COMMIT DROP AS
SELECT
  (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                         COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                         ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
     FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
      AND f.proname <> 'registrar_clinica_desde_invitacion') AS funciones_sin_esta,
  (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
     SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
       FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
      WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y) AS acl_funciones,
  (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
     FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
    WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x) AS acl_relaciones_public,
  (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
     SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
        ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
        COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
       FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
      WHERE n.nspname IN ('public','private','storage')) y) AS policies;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) RESTAURACIÓN: DROP de la v2 + el CREATE vivo de la v1, md5 verificado antes de ejecutar
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION public.registrar_clinica_desde_invitacion(uuid, uuid, text, text, text);

DO $restaurar$
DECLARE v_def text :=
    E'CREATE OR REPLACE FUNCTION public.registrar_clinica_desde_invitacion(p_token uuid, p_user_id uuid, p_email text, p_nombre_contacto text, p_telefono text DEFAULT NULL::text)\n'
    || E' RETURNS integer\n'
    || E' LANGUAGE plpgsql\n'
    || E' SECURITY DEFINER\n'
    || E' SET search_path TO \'public\'\n'
    || E'AS $function$\r\n'
    || E'DECLARE v_invitacion RECORD; v_pais_id UUID; v_clinica_id INTEGER;\r\n'
    || E'BEGIN\r\n'
    || E'  SELECT * INTO v_invitacion FROM invitaciones_clinica\r\n'
    || E'  WHERE token = p_token AND estado = \'pendiente\' AND expires_at > NOW() FOR UPDATE;\r\n'
    || E'  IF NOT FOUND THEN RAISE EXCEPTION \'Invitación no válida o expirada\'; END IF;\r\n'
    || E'  v_pais_id := v_invitacion.pais_id;\r\n'
    || E'  IF LOWER(v_invitacion.email) != LOWER(p_email) THEN RAISE EXCEPTION \'El email no coincide con la invitación\'; END IF;\r\n'
    || E'  UPDATE perfiles SET rol = \'admin_clinica\', pais_id = v_pais_id, nombre_completo = COALESCE(p_nombre_contacto, v_invitacion.nombre_contacto) WHERE id = p_user_id;\r\n'
    || E'  INSERT INTO clinicas (nombre, direccion, telefono, email, pais_id, activa)\r\n'
    || E'  VALUES (v_invitacion.nombre_clinica, v_invitacion.direccion, COALESCE(p_telefono, v_invitacion.telefono), p_email, v_pais_id, true) RETURNING id INTO v_clinica_id;\r\n'
    || E'  INSERT INTO medico_clinicas (medico_id, clinica_id, es_principal) VALUES (p_user_id, v_clinica_id, true) ON CONFLICT DO NOTHING;\r\n'
    || E'  UPDATE invitaciones_clinica SET estado = \'usada\', used_at = NOW() WHERE id = v_invitacion.id;\r\n'
    || E'  RETURN v_clinica_id;\r\n'
    || E'END; $function$\n';
BEGIN
  IF md5(v_def) IS DISTINCT FROM 'f2ebc873947a5ca2f71af9d945c3dbad' THEN
    RAISE EXCEPTION 'MIG85R: el texto a restaurar no es el medido (md5 %)', md5(v_def) USING ERRCODE = 'MIG85';
  END IF;
  EXECUTE v_def;
END $restaurar$;

-- la ACL de la v1: solo service_role (la función recreada nace con EXECUTE para authenticated por los defaults de la 344)
REVOKE ALL ON FUNCTION public.registrar_clinica_desde_invitacion(uuid, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_clinica_desde_invitacion(uuid, uuid, text, text, text) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) AUTOCHEQUEO
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; h record;
  c_f CONSTANT text := 'public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)';
BEGIN
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'registrar_clinica_desde_invitacion') <> 1 THEN bad := bad||'sobrecargas; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(c_f)
                   AND md5(p.prosrc) = '76d52027eeca678aca8e28354088e07f' AND p.prorettype = 'integer'::regtype AND p.prosecdef
                   AND p.proconfig = ARRAY['search_path=public']
                   AND p.proacl::text = '{postgres=X/postgres,service_role=X/postgres}') THEN
    bad := bad||'la v1 no quedó exacta (md5/retorno/DEFINER/config/ACL); ';
  END IF;
  IF has_function_privilege('anon', c_f, 'EXECUTE') OR has_function_privilege('authenticated', c_f, 'EXECUTE') THEN
    bad := bad||'anon o authenticated con EXECUTE; ';
  END IF;

  SELECT * INTO h FROM pg_temp.m385r_huellas;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'registrar_clinica_desde_invitacion');
  IF v IS DISTINCT FROM h.funciones_sin_esta THEN bad := bad||'cambió otra función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM h.acl_funciones THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM h.acl_relaciones_public THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM h.policies THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG85R: autochequeo: %', bad USING ERRCODE = 'MIG85';
  END IF;
END $autochequeo$;

COMMIT;
