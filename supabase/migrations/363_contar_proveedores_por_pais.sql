-- ############################################################################################
-- 363 - conteo de proveedores por pais para el dashboard de pais (familia DASHBOARDS)
-- ############################################################################################
-- Recon del 4-oct-2026 sobre 936f659 (solo lectura contra prod):
--   * PaisDashboardPage.tsx:126 (tarjeta "Proveedores"): SELECT count(*) FROM empresas_proveedoras WHERE pais_id = :pais
--     (head, count exact) con el cliente. empresas_proveedoras solo tiene policies SELECT para el super_admin ("Admin
--     ezpay ve todas las empresas") y para el proveedor (la propia): un admin_pais ve 0. Como postgres, GT = 7 (6 activa,
--     1 pendiente).
--   * empresa_paises_operacion existe: por esa via operan en GT 5 empresas. La 363 usa el MISMO criterio que la query de
--     hoy (empresas_proveedoras.pais_id) para que el admin_pais vea lo mismo que hoy ve el super_admin.
--   * private.puede_admin_pais(p_pais_id uuid, p_roles text[] DEFAULT ARRAY['super_admin']): DEFINER, search_path '',
--     EXECUTE postgres/authenticated. PC028 libre (en prosrc y en el repo).
-- Cambio:
--   public.contar_proveedores_por_pais(p_pais_id uuid) -> integer: STABLE, SECURITY DEFINER, search_path ''. Gate ANTES de
--   contar: sin sesion -> PC027; sin autoridad sobre el pais (super_admin, o admin_pais de ESE pais) -> PC028. REVOKE ALL
--   de PUBLIC y anon; GRANT EXECUTE a authenticated y service_role. No toca policies ni datos.
-- Errcodes: PC028. Proximo libre: PC029.
-- Probes: P1001-P1006. Rollback: 363_rollback.sql (DROP de la funcion).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regprocedure('public.contar_proveedores_por_pais(uuid)') IS NOT NULL THEN bad := bad||'la funcion ya existe; '; END IF;
  v := (SELECT p.oid::regprocedure::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')||' owner='||pg_get_userbyid(p.proowner)
          FROM pg_proc p WHERE p.oid = to_regprocedure('private.puede_admin_pais(uuid,text[])'));
  IF v IS DISTINCT FROM 'private.puede_admin_pais(uuid,text[]) sp=search_path="" owner=postgres' THEN bad := bad||'helper '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '6fd0d66ddce6b6d6d3ac349911c31153 311' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '83031eae1174a411499a06fcc3edf95b 379' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG363 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- conteo por pais con gate
CREATE FUNCTION public.contar_proveedores_por_pais(p_pais_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'no autenticado' USING ERRCODE = 'PC027';
  END IF;
  -- super_admin, o admin_pais de ESE pais (COALESCE fail-closed)
  IF NOT COALESCE(private.puede_admin_pais(p_pais_id), false) THEN
    RAISE EXCEPTION 'No autorizado para ver los proveedores de este país' USING ERRCODE = 'PC028';
  END IF;
  -- el mismo criterio que la tarjeta "Proveedores" de PaisDashboardPage (empresas_proveedoras.pais_id)
  RETURN (SELECT count(*)::integer FROM public.empresas_proveedoras e WHERE e.pais_id = p_pais_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.contar_proveedores_por_pais(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contar_proveedores_por_pais(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'('||pg_get_function_arguments(p.oid)||') -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default')||' md5='||md5(p.prosrc), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'contar_proveedores_por_pais');
  IF v IS DISTINCT FROM 'contar_proveedores_por_pais(uuid)(p_pais_id uuid) -> integer | definer=true sp=search_path="" vol=s owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} md5=43c82022e80d0b36212e36f2c0a0912f' THEN bad := bad||'funcion '||COALESCE(v, '-')||'; '; END IF;
  IF has_function_privilege('anon', 'public.contar_proveedores_por_pais(uuid)', 'EXECUTE') THEN bad := bad||'anon tiene EXECUTE; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '6fd0d66ddce6b6d6d3ac349911c31153 311' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'c7f89c6df3048083e3722d6eec7d1998 380' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG363 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
