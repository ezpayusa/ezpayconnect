-- ############################################################################################
-- 380_rollback - deshace la 380: DROP de listar_mis_medicos_enrolados() y prioridad_para_agendar(uuid)
-- ############################################################################################
-- Precondicion: estado post-380 (las 2 funciones con su md5(prosrc), DEFINER, search_path '' y ACL
--   {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}); huellas con las nuevas: funciones completas
--   76b4b9cdebf22fcf3316c9135cc699c1/401, ACL de funciones 853697ced74926f9b09abe3e74f68d50/401.
-- Lo que NO se toca: nada mas (la 380 es solo lectura: no hay datos que devolver).
-- Autochequeo: las 2 funciones no existen; huellas iguales a las post-379: funciones (cuerpo, DEFINER, config, ACL)
--   a2652baa3738c1b758b0b120eb6d513a/399, ACL de funciones f71eb65210787bd94c899a623d20350b/399, policies
--   cfb5d7632f071052d491e02a6a5e0932/311, ACL de relaciones de public 9da6a3c4ca75cd58b3a3053603bf03fe/2406.
-- Orden global: 380_rollback -> 379_rollback -> 378_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc)||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.listar_mis_medicos_enrolados()'));
  IF v IS DISTINCT FROM '0cea8b586b46708d2ced087d6290e6a8|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'listar_mis_medicos_enrolados '||COALESCE(v, 'no existe')||'; ';
  END IF;
  v := (SELECT md5(p.prosrc)||'|'||p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.prioridad_para_agendar(uuid)'));
  IF v IS DISTINCT FROM '1b65c48238b7d93d187dcafe275bb08a|true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'prioridad_para_agendar '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname IN ('listar_mis_medicos_enrolados', 'prioridad_para_agendar')) <> 2 THEN
    bad := bad||'sobrecargas de las funciones de la 380; ';
  END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG380_ROLLBACK_PRE FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: DROP
DROP FUNCTION public.prioridad_para_agendar(uuid);
DROP FUNCTION public.listar_mis_medicos_enrolados();

-- ---------------------------------------------------------------------------- 2: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname IN ('listar_mis_medicos_enrolados', 'prioridad_para_agendar')) THEN
    bad := bad||'queda una funcion de la 380; ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'a2652baa3738c1b758b0b120eb6d513a 399' THEN bad := bad||'huella de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'f71eb65210787bd94c899a623d20350b 399' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
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

  IF bad <> '' THEN RAISE EXCEPTION 'MIG380_ROLLBACK_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
