-- ############################################################################################
-- 344 - familia 1 (privilegios), paso 3: default privileges de postgres en public
-- ############################################################################################
-- pg_default_acl (huella 1f07b802bdb4ee70eb46bd21f46a8d3d) hace que cada objeto que postgres crea en public nazca con:
--   tablas     -> authenticated arwdDxtm (los 8, incluidos TRUNCATE/TRIGGER/REFERENCES/MAINTAIN);
--   secuencias -> authenticated rwU (SELECT, UPDATE, USAGE).
-- Sin esto, la proxima migracion que cree una tabla o una secuencia vuelve a meter lo que sacaron la 342/343.
-- Las migraciones y el harness corren como postgres (current_user = session_user = postgres, medido).
--
-- Cambio (dos ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public):
--   tablas:     REVOKE TRUNCATE, TRIGGER, REFERENCES, MAINTAIN -> authenticated queda arwd (SELECT/INSERT/
--               UPDATE/DELETE: ese contrato no cambia aca);
--   secuencias: REVOKE SELECT, UPDATE -> authenticated queda U (USAGE, lo que pide un INSERT con nextval()).
-- FROM authenticated, anon, PUBLIC: anon y PUBLIC no tienen nada en esas entradas (mig 298/301); se nombran
-- para cerrar la clase.
-- Funciones: YA ESTA. Existe la entrada GLOBAL postgres|f {postgres=X/postgres} (sin PUBLIC): una funcion nueva de
-- postgres en cualquier schema NO nace con EXECUTE para PUBLIC. La de public suma authenticated y
-- service_role. Por eso NO hay ALTER de funciones aca (seria un no-op). Consecuencia que ya rige: una funcion
-- nueva de private nace con EXECUTE solo para postgres (private no tiene entrada de default): toda funcion
-- de private que use una policy o una RPC de authenticated necesita GRANT EXECUTE ... TO authenticated
-- explicito en su migracion. Las 21 funciones de public con EXECUTE para PUBLIC son anteriores a esa
-- entrada global o tienen grant explicito (familia 1, 348).
-- Fuera de alcance (medido, sin tocar): las entradas de supabase_admin (public, graphql, graphql_public,
-- realtime, cron, extensions) -> postgres no es miembro de supabase_admin y ALTER DEFAULT PRIVILEGES FOR
-- ROLE supabase_admin da 42501 "permission denied to change default privileges" (inertes mientras postgres
-- cree todo en public: P724 lo vigila); las de postgres en storage (anon/authenticated con todo) -> postgres
-- no tiene CREATE en storage (de supabase_admin): inertes.
-- Nada existente cambia: ACL de relaciones de public 855f079761052808e9593a8911baaac2, grants por columna dab25af63754e06d699ac3bd454011a6,
-- secuencias public/private 2b8162b517a99df0b708977911009183 39, funciones public/private b20ef072973cc2cc56515e6820851d05 368.
-- Probes: P926 (catalogo de pg_default_acl), P927 (funcional: crea y descarta objetos de prueba).
-- Rollback: 344_rollback.sql (independiente de 342/343 y de 334-341).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
-- Estado PRE medido en prod el 2-oct-2026. Una segunda pasada aborta aca: las entradas ya no son las PRE.
DO $precondicion$
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG344 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- --------------------------------------------------------------------------- los defaults
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON TABLES FROM authenticated, anon, PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, UPDATE ON SEQUENCES FROM authenticated, anon, PUBLIC;

-- ---------------------------------------------------------------------------- autochequeo
-- Esperado: postgres|public|r {postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}
--           postgres|public|S {postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}
--           postgres|public|f y postgres|global|f sin cambio; resto de pg_default_acl y objetos existentes = PRE.
DO $autochequeo$
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG344 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
