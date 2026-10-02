-- ############################################################################################
-- 347 ROLLBACK - devuelve public.auto_configurar_planes_publicidad() al estado PRE exacto
-- ############################################################################################
-- Cuerpo PRE (md5(prosrc) 6d1fe3a9446b63cd76680c238fc80067, CRLF) armado en SQL desde el prosrc POST con el replace()
-- inverso, sin SET: CREATE OR REPLACE reemplaza proconfig entero, asi que vuelve a NULL. Conserva oid, duenio y ACL.
-- Precondicion = estado POST de la 347; autochequeo = estado PRE.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado POST)
DO $precondicion$
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
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK347 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- la funcion PRE
DO $restaurar$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = 'public.auto_configurar_planes_publicidad()'::regprocedure;
  IF md5(v_src) IS DISTINCT FROM '5949ef5dfd83880c258646dc5bb90efe' THEN RAISE EXCEPTION 'ROLLBACK347: prosrc de partida inesperado (%)', md5(v_src); END IF;
  v_src := replace(v_src, 'INSERT INTO public.planes_publicidad_config (', 'INSERT INTO planes_publicidad_config (');
  v_src := replace(v_src, 'FROM public.planes_publicidad pp', 'FROM planes_publicidad pp');
  IF md5(v_src) IS DISTINCT FROM '6d1fe3a9446b63cd76680c238fc80067' THEN RAISE EXCEPTION 'ROLLBACK347: cuerpo resultante inesperado (%)', md5(v_src); END IF;
  -- sin SET: CREATE OR REPLACE reemplaza proconfig entero y vuelve a NULL
  EXECUTE format($f$CREATE OR REPLACE FUNCTION public.auto_configurar_planes_publicidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS %L$f$, v_src);
END $restaurar$;

-- ---------------------------------------------------------------------------- autochequeo (estado PRE)
DO $autochequeo$
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
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK347 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
