-- ############################################################################################
-- 362 - catalogo PUBLICO de planes de visitador (lectura para la landing /planes-visitador sin sesion)
-- ############################################################################################
-- Recon del 4-oct-2026 sobre 2b389bd (solo lectura contra prod):
--   * La landing /planes-visitador (PlanesVisitadorPage + usePlanes) lee planes_base, planes_configuracion y
--     configuracion_pais con el cliente. Desde la 350 anon no tiene SELECT en planes_base ni planes_configuracion (solo en
--     configuracion_pais): sin sesion la landing no muestra precios.
--   * Criterio de compra de public.solicitar_compra_plan_visitador (351), lo que esta funcion replica TEXTUALMENTE:
--     planes_configuracion.activo IS TRUE, planes_base.activo IS TRUE, planes_base.tipo = 'visitador' (CP001);
--     visitas_incluidas, duracion_dias y precio_local no nulos y precio_local > 0 (CP003; los CHECK de la tabla ya exigen
--     visitas > 0 y duracion > 0); la PRIMERA cuenta activa del pais (cuentas_bancarias_pais, ORDER BY created_at) existe
--     (CP004) y su moneda = moneda_local (CP005). Lo que depende del comprador (CP002 pais de la empresa, CP006
--     comprobante, CP007 pendiente) no aplica a un catalogo. La 351 no mira configuracion_pais.activo: esta tampoco.
--   * El front (configComprable) solo filtra visitas > 0 y duracion > 0: muestra configs que la RPC rechaza (sin precio,
--     sin cuenta o con otra moneda). Hoy comprables: solo GT (Bronce 250, Plata 450, Oro 900 GTQ); T9 y ZZ tienen configs
--     activas sin visitas/duracion y no aparecen.
-- Cambio:
--   public.catalogo_planes_visitador_publico() -> TABLE(pais_codigo, pais_nombre, config_id, plan_nombre, plan_descripcion,
--   precio, moneda, visitas, duracion_dias): STABLE, SECURITY DEFINER, search_path ''. Solo esas columnas (nada de ids de
--   empresa ni datos de cuentas bancarias; la cuenta se usa solo para el filtro de moneda). Orden: pais, precio.
--   REVOKE ALL de PUBLIC; GRANT EXECUTE a anon, authenticated y service_role. Excepcion de producto para anon: catalogo
--   publico de precios para la landing; solo lectura; mismas filas que compraria solicitar_compra_plan_visitador. Se
--   agrega a la allowlist de P739 (censo de DEFINER de public ejecutables por anon), que vive en el harness, no en la base.
-- Sin errcodes: no hay entradas ni rechazos (sin filas comprables devuelve 0 filas).
-- Probes: P996-P1000; P739 ajustado (10 -> 11 esperadas). Rollback: 362_rollback.sql (DROP de la funcion).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regprocedure('public.catalogo_planes_visitador_publico()') IS NOT NULL THEN bad := bad||'la funcion ya existe; '; END IF;
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.solicitar_compra_plan_visitador(uuid,text)'::regprocedure);
  IF v IS DISTINCT FROM 'fe5f0ed6630d4eb28282657737040c2c' THEN bad := bad||'solicitar_compra_plan_visitador no es la de la 351 ('||COALESCE(v, '-')||'); '; END IF;
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
  IF v IS DISTINCT FROM 'a01b26ab47262f58c617215636ecf560 378' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG362 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- catalogo publico
CREATE FUNCTION public.catalogo_planes_visitador_publico()
 RETURNS TABLE(pais_codigo text, pais_nombre text, config_id uuid, plan_nombre text, plan_descripcion text, precio numeric, moneda text, visitas integer, duracion_dias integer)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- El mismo predicado con que solicitar_compra_plan_visitador (351) acepta una configuracion (CP001, CP003, CP004,
  -- CP005): lo que aparece aca es exactamente lo que se puede comprar.
  SELECT cp.codigo::text, cp.nombre::text, pc.id, pb.nombre::text, pb.descripcion::text, pc.precio_local, pc.moneda_local::text,
         pc.visitas_incluidas, pc.duracion_dias
    FROM public.planes_configuracion pc
    JOIN public.planes_base pb ON pb.id = pc.plan_base_id
    JOIN public.configuracion_pais cp ON cp.id = pc.pais_id
   WHERE pc.activo IS TRUE AND pb.activo IS TRUE AND pb.tipo::text = 'visitador'
     AND pc.visitas_incluidas IS NOT NULL AND pc.duracion_dias IS NOT NULL
     AND pc.precio_local IS NOT NULL AND pc.precio_local > 0
     AND (SELECT cb.moneda FROM public.cuentas_bancarias_pais cb
           WHERE cb.pais_id = pc.pais_id AND cb.activo ORDER BY cb.created_at LIMIT 1) = pc.moneda_local::text
   ORDER BY cp.codigo, pc.precio_local;
$function$;

REVOKE ALL ON FUNCTION public.catalogo_planes_visitador_publico() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.catalogo_planes_visitador_publico() TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||' -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default')||' md5='||md5(p.prosrc), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'catalogo_planes_visitador_publico');
  IF v IS DISTINCT FROM 'catalogo_planes_visitador_publico() -> TABLE(pais_codigo text, pais_nombre text, config_id uuid, plan_nombre text, plan_descripcion text, precio numeric, moneda text, visitas integer, duracion_dias integer) | definer=true sp=search_path="" vol=s owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres} md5=02d8c32870bce2390a5b859e34fac4f2' THEN bad := bad||'funcion '||COALESCE(v, '-')||'; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG362 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
