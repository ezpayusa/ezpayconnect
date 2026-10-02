-- ############################################################################################
-- 347 - familia 1 (privilegios), paso 6: search_path fijo en public.auto_configurar_planes_publicidad()
-- ############################################################################################
-- Es la UNICA funcion SECURITY DEFINER de public/private sin search_path fijo (censo del 2-oct-2026 sobre b2d40fe).
-- Un DEFINER sin search_path resuelve los nombres sin calificar con el search_path DEL LLAMANTE: quien pueda crear
-- un objeto en un schema que este antes en su path (o fijarse el path) hace que la funcion, que corre como
-- postgres, use SU tabla o SU funcion. Es la funcion del trigger trigger_auto_planes_publicidad (AFTER INSERT ON
-- public.configuracion_pais, FOR EACH ROW): al crear un pais le siembra la config de los planes de publicidad activos.
-- Duenio postgres, plpgsql, VOLATILE, ACL {postgres,authenticated,service_role}=X (sin PUBLIC). md5(prosrc) PRE
-- 6d1fe3a9446b63cd76680c238fc80067, proconfig NULL.
-- Referencias sin calificar del cuerpo (con search_path = '' fallarian): las 2 tablas, planes_publicidad_config
-- (INSERT) y planes_publicidad (FROM). El resto (=, true, ON CONFLICT, NEW) es builtin/plpgsql: pg_catalog siempre
-- se resuelve. Por eso CREATE OR REPLACE con el cuerpo vivo EXACTO, calificando solo esas 2, + SET search_path = ''.
-- El prosrc vivo tiene fines de linea CRLF (15 CR): para conservarlos byte a byte sin meter CR en este archivo (LF,
-- regla del repo), el cuerpo nuevo se arma EN SQL desde el prosrc vivo (md5 verificado) con replace() y se ejecuta
-- con EXECUTE format(%L); el md5 del resultado se verifica ANTES de ejecutar.
-- CREATE OR REPLACE conserva oid, duenio y ACL; el trigger apunta al oid y no se toca.
-- Diff PRE -> POST (sin los CR):
--   --- PRE (prod 2-oct-2026)
--   +++ POST (347)
--   @@ -2,16 +2,17 @@
--     RETURNS trigger
--     LANGUAGE plpgsql
--     SECURITY DEFINER
--   + SET search_path TO ''
--    AS $function$
--    BEGIN
--   -  INSERT INTO planes_publicidad_config (pais_id, plan_publicidad_id, precio_local, moneda_local, activo)
--   +  INSERT INTO public.planes_publicidad_config (pais_id, plan_publicidad_id, precio_local, moneda_local, activo)
--      SELECT
--        NEW.id,
--        pp.id,
--        pp.precio,
--        NEW.moneda,
--        true
--   -  FROM planes_publicidad pp
--   +  FROM public.planes_publicidad pp
--      WHERE pp.activo = true
--      ON CONFLICT (pais_id, plan_publicidad_id) DO NOTHING;
--
-- md5(prosrc) POST 5949ef5dfd83880c258646dc5bb90efe. Nada mas cambia: las otras 367 funciones (e65ab12b6b12bd8963b0a9388297b758 367),
-- ACL de funciones b20ef072... (368), relaciones deedb2e6..., columnas dab25af6..., secuencias e1ef3639... (39),
-- pg_default_acl 7143eca7....
-- Probes: P931 (censo: 0 DEFINER sin search_path), P932 (funcional: INSERT de un pais como super_admin, con el
-- search_path normal y con uno hostil, siembra los planes activos). Rollback: 347_rollback.sql.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
-- Una segunda pasada aborta aca: md5(prosrc) y proconfig ya no son los PRE.
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- la funcion: md5(prosrc) | proconfig | duenio | SECURITY DEFINER | volatilidad | ACL
  v := (SELECT md5(p.prosrc)||'|'||COALESCE(p.proconfig::text,'NULL')||'|'||pg_get_userbyid(p.proowner)||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||COALESCE(p.proacl::text,'-')
          FROM pg_proc p WHERE p.oid = 'public.auto_configurar_planes_publicidad()'::regprocedure);
  IF v IS DISTINCT FROM '6d1fe3a9446b63cd76680c238fc80067|NULL|postgres|true|v|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'auto_configurar_planes_publicidad '||COALESCE(v, '-')||'; '; END IF;
  -- el trigger que la usa (AFTER INSERT en configuracion_pais) no cambia
  v := (SELECT string_agg(c.relname||'|'||t.tgname||'|'||t.tgtype||'|'||t.tgenabled::text, ',') FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
         WHERE t.tgfoid = 'public.auto_configurar_planes_publicidad()'::regprocedure);
  IF v IS DISTINCT FROM 'configuracion_pais|trigger_auto_planes_publicidad|5|O' THEN bad := bad||'trigger '||COALESCE(v, '-')||'; '; END IF;
  -- las otras 367 funciones de public/private: firma, duenio, DEFINER, volatilidad, proconfig, md5(prosrc), ACL
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(*) FROM (
    SELECT p.oid::regprocedure::text||'|'||pg_get_userbyid(p.proowner)||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||COALESCE(p.proconfig::text,'-')||'|'||md5(p.prosrc)||'|'||COALESCE(p.proacl::text,'-') AS s
      FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace)
       AND p.oid <> 'public.auto_configurar_planes_publicidad()'::regprocedure) y);
  IF v IS DISTINCT FROM 'e65ab12b6b12bd8963b0a9388297b758 367' THEN bad := bad||'otras funciones '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de todas las funciones de public/private (la 347 no cambia ninguna)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM 'e1ef3639c3367e24c1369c0dbf95a994 39' THEN bad := bad||'ACL de secuencias public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  -- censo: funciones SECURITY DEFINER de public/private sin search_path fijo (la misma regla de P931)
  v := (SELECT COALESCE(string_agg(p.oid::regprocedure::text, ',' ORDER BY p.oid::regprocedure::text), '') FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace) AND p.prosecdef
           AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%'));
  IF v IS DISTINCT FROM 'auto_configurar_planes_publicidad()' THEN bad := bad||'DEFINER sin search_path {'||COALESCE(v, '-')||'}; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG347 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- la funcion (cuerpo calificado + search_path)
DO $crear$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = 'public.auto_configurar_planes_publicidad()'::regprocedure;
  IF md5(v_src) IS DISTINCT FROM '6d1fe3a9446b63cd76680c238fc80067' THEN RAISE EXCEPTION 'MIG347: prosrc de partida inesperado (%)', md5(v_src); END IF;
  v_src := replace(v_src, 'INSERT INTO planes_publicidad_config (', 'INSERT INTO public.planes_publicidad_config (');
  v_src := replace(v_src, 'FROM planes_publicidad pp', 'FROM public.planes_publicidad pp');
  IF md5(v_src) IS DISTINCT FROM '5949ef5dfd83880c258646dc5bb90efe' THEN RAISE EXCEPTION 'MIG347: cuerpo resultante inesperado (%)', md5(v_src); END IF;
  EXECUTE format($f$CREATE OR REPLACE FUNCTION public.auto_configurar_planes_publicidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS %L$f$, v_src);
END $crear$;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- la funcion: md5(prosrc) | proconfig | duenio | SECURITY DEFINER | volatilidad | ACL
  v := (SELECT md5(p.prosrc)||'|'||COALESCE(p.proconfig::text,'NULL')||'|'||pg_get_userbyid(p.proowner)||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||COALESCE(p.proacl::text,'-')
          FROM pg_proc p WHERE p.oid = 'public.auto_configurar_planes_publicidad()'::regprocedure);
  IF v IS DISTINCT FROM '5949ef5dfd83880c258646dc5bb90efe|{"search_path=\"\""}|postgres|true|v|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'auto_configurar_planes_publicidad '||COALESCE(v, '-')||'; '; END IF;
  -- el trigger que la usa (AFTER INSERT en configuracion_pais) no cambia
  v := (SELECT string_agg(c.relname||'|'||t.tgname||'|'||t.tgtype||'|'||t.tgenabled::text, ',') FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
         WHERE t.tgfoid = 'public.auto_configurar_planes_publicidad()'::regprocedure);
  IF v IS DISTINCT FROM 'configuracion_pais|trigger_auto_planes_publicidad|5|O' THEN bad := bad||'trigger '||COALESCE(v, '-')||'; '; END IF;
  -- las otras 367 funciones de public/private: firma, duenio, DEFINER, volatilidad, proconfig, md5(prosrc), ACL
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(*) FROM (
    SELECT p.oid::regprocedure::text||'|'||pg_get_userbyid(p.proowner)||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||COALESCE(p.proconfig::text,'-')||'|'||md5(p.prosrc)||'|'||COALESCE(p.proacl::text,'-') AS s
      FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace)
       AND p.oid <> 'public.auto_configurar_planes_publicidad()'::regprocedure) y);
  IF v IS DISTINCT FROM 'e65ab12b6b12bd8963b0a9388297b758 367' THEN bad := bad||'otras funciones '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de todas las funciones de public/private (la 347 no cambia ninguna)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM 'e1ef3639c3367e24c1369c0dbf95a994 39' THEN bad := bad||'ACL de secuencias public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  -- censo: funciones SECURITY DEFINER de public/private sin search_path fijo (la misma regla de P931)
  v := (SELECT COALESCE(string_agg(p.oid::regprocedure::text, ',' ORDER BY p.oid::regprocedure::text), '') FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace,'private'::regnamespace) AND p.prosecdef
           AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%'));
  IF v IS DISTINCT FROM '' THEN bad := bad||'DEFINER sin search_path {'||COALESCE(v, '-')||'}; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG347 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
