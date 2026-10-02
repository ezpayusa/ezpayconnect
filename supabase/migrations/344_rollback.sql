-- ############################################################################################
-- 344 ROLLBACK - devuelve los defaults de postgres en public al estado PRE (pg_default_acl 1f07b802bdb4ee70eb46bd21f46a8d3d)
-- ############################################################################################
-- Tablas: authenticated vuelve a TRUNCATE/TRIGGER/REFERENCES/MAINTAIN; secuencias: authenticated vuelve a
-- SELECT/UPDATE. Funciones: la 344 no las toco (la entrada global sin PUBLIC ya existia en el PRE), asi que
-- NO se otorga EXECUTE a PUBLIC: hacerlo dejaria pg_default_acl DISTINTO del PRE.
-- Precondicion = estado POST de la 344; autochequeo = pg_default_acl completo = PRE y objetos existentes intactos.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado POST)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- pg_default_acl de postgres: las dos entradas que cambia la 344 y las dos de funciones (no cambian)
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'r'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'postgres|public|tablas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'S'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}' THEN bad := bad||'postgres|public|secuencias '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'f'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'postgres|public|funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 0 AND d.defaclobjtype = 'f'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=X/postgres}' THEN bad := bad||'postgres|global|funciones (sin PUBLIC) '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT count(*)::text FROM pg_default_acl d WHERE d.defaclnamespace = 'private'::regnamespace), '-'));
  IF v IS DISTINCT FROM '0' THEN bad := bad||'entradas de private '||COALESCE(v, '-')||'; '; END IF;
  -- el resto de pg_default_acl (supabase_admin, supabase_auth_admin, storage, etc.) no se toca
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d
       WHERE NOT (d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype IN ('r','S'))) y);
  IF v IS DISTINCT FROM '9355f8b223dfb60745b0d1a14ff4d34d' THEN bad := bad||'resto de pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  -- objetos existentes: la 344 solo cambia defaults; ninguna ACL existente se mueve
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '855f079761052808e9593a8911baaac2' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM '2b8162b517a99df0b708977911009183 39' THEN bad := bad||'ACL de secuencias public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK344 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- --------------------------------------------------------------------------- los defaults
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON TABLES TO authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, UPDATE ON SEQUENCES TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (= PRE)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- pg_default_acl de postgres: las dos entradas que cambia la 344 y las dos de funciones (no cambian)
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'r'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'postgres|public|tablas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'S'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}' THEN bad := bad||'postgres|public|secuencias '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'f'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'postgres|public|funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT d.defaclacl::text FROM pg_default_acl d WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 0 AND d.defaclobjtype = 'f'), 'NO EXISTE'));
  IF v IS DISTINCT FROM '{postgres=X/postgres}' THEN bad := bad||'postgres|global|funciones (sin PUBLIC) '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT COALESCE((SELECT count(*)::text FROM pg_default_acl d WHERE d.defaclnamespace = 'private'::regnamespace), '-'));
  IF v IS DISTINCT FROM '0' THEN bad := bad||'entradas de private '||COALESCE(v, '-')||'; '; END IF;
  -- el resto de pg_default_acl (supabase_admin, supabase_auth_admin, storage, etc.) no se toca
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d
       WHERE NOT (d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype IN ('r','S'))) y);
  IF v IS DISTINCT FROM '9355f8b223dfb60745b0d1a14ff4d34d' THEN bad := bad||'resto de pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '1f07b802bdb4ee70eb46bd21f46a8d3d' THEN bad := bad||'pg_default_acl completo '||COALESCE(v, '-')||'; '; END IF;
  -- objetos existentes: la 344 solo cambia defaults; ninguna ACL existente se mueve
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '855f079761052808e9593a8911baaac2' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM '2b8162b517a99df0b708977911009183 39' THEN bad := bad||'ACL de secuencias public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK344 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
