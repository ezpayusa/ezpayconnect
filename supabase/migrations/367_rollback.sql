-- ############################################################################################
-- 367 ROLLBACK - campana_vistas vuelve a tener UPDATE de authenticated
-- ############################################################################################
-- GRANT UPDATE ON public.campana_vistas TO authenticated (privilegio muerto: no hay policy de UPDATE). Si se corre, hay que
-- volver a poner 'campana_vistas|authenticated|UPDATE' en la allowlist de P930.
-- Precondicion: la 367 esta viva (relacl sin UPDATE de authenticated, ACL de public e2bb57f4... 2370).
-- Autochequeo: relacl de partida y ACL de public d05a8b3a... 2371.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 367)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.campana_vistas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=ar/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'e2bb57f40da44965e21590fb92d7f9c3 2370' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK367 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

GRANT UPDATE ON public.campana_vistas TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.campana_vistas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd05a8b3a6e300f40365ddc3a5c1c7cde 2371' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK367 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
