-- ############################################################################################
-- 356 - get_ubicaciones_con_medico sin email del medico
-- ############################################################################################
-- Recon del 3-oct-2026 sobre 101d12a (tmp/356/a1, a2, a2b; solo lectura contra prod):
--   * public.get_ubicaciones_con_medico(uuid): LANGUAGE sql, SECURITY DEFINER, search_path '', ACL postgres/
--     authenticated/service_role (sin PUBLIC ni anon), md5(prosrc) 07f1a9cf.... Devuelve p.email del medico (perfiles) a
--     cualquier cuenta de la empresa: el unico gate es u.empresa_id = public.mi_empresa_proveedor(), sin gate de rol.
--     Es la misma clase de fuga que cerro la decision 3 de la 354 (buscar_medicos_proveedor sin email). Hallazgo del
--     review del PR #29.
--   * Unico consumidor: src/proveedor/hooks/useUbicacionesMedico.ts:34 (AdminUbicacionesMedicosPage,
--     /proveedor/visitador/ubicaciones-medicos), que lee medico_id, direccion, lat, lng y notas; nadie lee email.
--     Ninguna funcion, vista, policy ni trigger la llama.
-- Decision (Oscar, 3-oct-2026): sacar el email del RETURNS. Alcance acotado: mismo gate y demas columnas.
-- Cambios:
--   A DROP + CREATE de public.get_ubicaciones_con_medico(uuid): misma firma, RETURNS sin email, cuerpo identico salvo
--     p.email; SECURITY DEFINER y SET search_path = '' (todo ya calificado); REVOKE ALL de PUBLIC y anon; GRANT
--     EXECUTE a authenticated y service_role (ACL igual al de partida).
-- Sin errcodes nuevos. Probes: P955 (catalogo), P956 (admin = oraculo > 0), P957 (otra empresa 0).
-- Rollback: 356_rollback.sql (restaura cuerpo, RETURNS y ACL originales desde el objeto vivo, md5 verificado).
-- Orden de deploy: base primero (el front viejo declara email en el tipo pero no lo lee: sigue andando).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||' -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'get_ubicaciones_con_medico');
  IF v IS DISTINCT FROM 'get_ubicaciones_con_medico(uuid) -> TABLE(ubicacion_id uuid, medico_id uuid, nombre_completo text, email text, direccion text, lat double precision, lng double precision, notas text, updated_at timestamp with time zone) | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion de partida'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'get_ubicaciones_con_medico');
  IF v IS DISTINCT FROM '07f1a9cfb0888d0b3797758c59fa9216' THEN bad := bad||'md5(prosrc) de partida'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG356 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A: sin email
DROP FUNCTION public.get_ubicaciones_con_medico(uuid);

CREATE FUNCTION public.get_ubicaciones_con_medico(p_empresa_id uuid)
 RETURNS TABLE(ubicacion_id uuid, medico_id uuid, nombre_completo text, direccion text, lat double precision, lng double precision, notas text, updated_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT u.id AS ubicacion_id, u.medico_id, p.nombre_completo,
         u.direccion, u.lat, u.lng, u.notas, u.updated_at
  FROM public.ubicaciones_medico_proveedor u
  JOIN public.perfiles p ON p.id = u.medico_id
  WHERE u.empresa_id = p_empresa_id
    AND u.empresa_id = public.mi_empresa_proveedor();  -- gate: sólo la empresa del caller (NULL⇒0 filas)
$function$;

REVOKE ALL ON FUNCTION public.get_ubicaciones_con_medico(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ubicaciones_con_medico(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||' -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'get_ubicaciones_con_medico');
  IF v IS DISTINCT FROM 'get_ubicaciones_con_medico(uuid) -> TABLE(ubicacion_id uuid, medico_id uuid, nombre_completo text, direccion text, lat double precision, lng double precision, notas text, updated_at timestamp with time zone) | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion nueva'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'get_ubicaciones_con_medico');
  IF v IS DISTINCT FROM '67f86b9d17695258bc4cdcafd6b553e2' THEN bad := bad||'md5(prosrc) nuevo'||' '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'get_ubicaciones_con_medico'
             AND (position('email' IN p.prosrc) > 0 OR position('email' IN pg_get_function_result(p.oid)) > 0)) THEN
    bad := bad||'la funcion todavia nombra email; ';
  END IF;
  IF has_function_privilege('anon', 'public.get_ubicaciones_con_medico(uuid)', 'EXECUTE') THEN bad := bad||'anon tiene EXECUTE; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG356 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
