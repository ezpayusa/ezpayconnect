-- ############################################################################################
-- 350 - familia 2 (policies), paso 3 (F2-c): las 17 {public} de las tablas de la WL_ANON_LEGACY -> TO authenticated
-- ############################################################################################
-- anon tiene SELECT en las 8 tablas de la WL_ANON_LEGACY (P800), asi que al leerlas evalua TODAS sus policies
-- {public}. Medido el 2/3-oct-2026 sobre e6e95612: hay 18 {public} en esas tablas; 17 dependen de la sesion
-- (auth.uid(), get_auth_user_rol()/get_auth_user_pais_id(), mi_rol_proveedor()/mi_empresa_proveedor()/
-- supervisa_cuenta_proveedor(), private.tiene_rol()) y para anon dan 0 filas. Medido como anon (BEGIN/ROLLBACK):
-- configuracion_pais 21 (= las 21 activas, por "Publico lee paises activos"), configuracion_sistema 16 (= las 16 claves
-- no bancarias, por configuracion_sistema_select_anon TO anon), las otras 6 tablas 0. Ninguna de las 17 le da filas.
-- Consumidores sin sesion: ninguno de estas 17. Los login (Farmacia/Lab/Proveedor/LoginPage) leen cuentas_proveedor o
-- perfiles DESPUES de login(); el registro lee configuracion_pais (cubierta por la de paises); ninguna edge usa la
-- anon key sin Authorization.
-- Por que importa: hoy, cada SELECT de anon sobre perfiles/pacientes/recetas/cuentas_proveedor ejecuta los helpers
-- get_auth_user_*/mi_*/supervisa_* (por eso necesitan EXECUTE para anon) y las subconsultas inline sobre perfiles y
-- pacientes (por eso anon necesita SELECT ahi: la WL). Con las 17 en TO authenticated, anon no evalua ninguna: es el
-- prerequisito del paso de EXECUTE (ultimo de la familia 2) y de achicar la WL.
-- Las 17 (tabla, cmd, nombre):
--   configuracion_sistema  ALL    Admin ezpay actualiza configuracion
--   cuentas_proveedor      SELECT Admin ezpay ve cuentas proveedor
--   cuentas_proveedor      SELECT Proveedor ve su propia cuenta
--   cuentas_proveedor      SELECT Supervisor ve cuentas de su equipo
--   empresas_proveedoras   UPDATE Admin ezpay actualiza empresas
--   empresas_proveedoras   SELECT Admin ezpay ve todas las empresas
--   pacientes              ALL    Admin ve pacientes de su pais
--   pacientes              INSERT Paciente crea su perfil
--   pacientes              SELECT Paciente ve su perfil
--   perfiles               UPDATE Actualizar propio perfil
--   perfiles               UPDATE Admin actualiza perfiles de su pais
--   perfiles               DELETE Admin borra perfiles de su pais
--   perfiles               SELECT Admin lee perfiles de su pais
--   perfiles               INSERT Admins pueden insertar perfiles
--   perfiles               SELECT Ver propio perfil
--   recetas                SELECT Admin ve recetas de su pais
--   recetas                SELECT Paciente ve sus recetas
-- Quedan: "Publico lee paises activos" (TO public, la lectura publica deliberada) y configuracion_sistema_select_anon
-- (TO anon). Solo cambia polroles: USING/CHECK/cmd/permissive identicos (contenido sin roles de las 17 cb6b0d4d... 17;
-- de todas 2003cbbf... 309). RLS de las 8 tablas (activa, sin FORCE), privilegios de tabla/columna de anon y
-- authenticated, secuencias, funciones y pg_default_acl sin cambio.
-- Huella de policies de public/private/storage fc06b02c0b09efd90f774e612e53d454 309 -> d1aae5eba7362ec479a3995bf2d29827 309.
-- Probe: P936 (anon 0 filas sin 42501 en las 6 tablas, configuracion_pais 21 y configuracion_sistema 16 por sus policies
-- de anon; authenticated igual antes y despues; las 17 en {authenticated}).
-- Rollback: 350_rollback.sql (correrlo ANTES que 349_rollback: su precondicion exige la huella fc06b02c...).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
-- Una segunda pasada aborta aca: las 17 ya no estan en {public} y la huella cambio.
DO $precondicion$
DECLARE bad text := ''; v text; n_falta int; n_rol int;
BEGIN
  -- las 17 policies de la lista: existen, todas con roles = {public}, y su contenido sin roles
  -- (tabla|nombre|cmd|permissive|USING|CHECK) es el medido
  SELECT count(*) FILTER (WHERE pl.oid IS NULL), count(*) FILTER (WHERE pl.polroles = '{0}'::oid[]),
         md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n'
           ORDER BY c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') COLLATE "C"))||' '||count(pl.oid)
    INTO n_falta, n_rol, v
    FROM (VALUES
      ('configuracion_sistema', 'Admin ezpay actualiza configuracion'),
      ('cuentas_proveedor', 'Admin ezpay ve cuentas proveedor'),
      ('cuentas_proveedor', 'Proveedor ve su propia cuenta'),
      ('cuentas_proveedor', 'Supervisor ve cuentas de su equipo'),
      ('empresas_proveedoras', 'Admin ezpay actualiza empresas'),
      ('empresas_proveedoras', 'Admin ezpay ve todas las empresas'),
      ('pacientes', 'Admin ve pacientes de su pais'),
      ('pacientes', 'Paciente crea su perfil'),
      ('pacientes', 'Paciente ve su perfil'),
      ('perfiles', 'Actualizar propio perfil'),
      ('perfiles', 'Admin actualiza perfiles de su pais'),
      ('perfiles', 'Admin borra perfiles de su pais'),
      ('perfiles', 'Admin lee perfiles de su pais'),
      ('perfiles', 'Admins pueden insertar perfiles'),
      ('perfiles', 'Ver propio perfil'),
      ('recetas', 'Admin ve recetas de su pais'),
      ('recetas', 'Paciente ve sus recetas')) s(tab, pol)
    LEFT JOIN pg_class c ON c.relnamespace = 'public'::regnamespace AND c.relname = s.tab
    LEFT JOIN pg_policy pl ON pl.polrelid = c.oid AND pl.polname = s.pol;
  IF n_falta <> 0 THEN bad := bad||n_falta||' policies de la lista no existen; '; END IF;
  IF n_rol <> 17 THEN bad := bad||'policies de la lista con roles {public}: '||n_rol||' de 17; '; END IF;
  IF v IS DISTINCT FROM 'cb6b0d4d88d67610aa480d985fe6be29 17' THEN bad := bad||'contenido del conjunto '||COALESCE(v, '-')||'; '; END IF;
  -- "Publico lee paises activos" (la lectura publica deliberada) existe y no se toca: md5(USING)|cmd|roles
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid))||'|'||pl.polcmd::text||'|'||pl.polroles::text FROM pg_policy pl
         WHERE pl.polrelid = 'public.configuracion_pais'::regclass AND pl.polname = 'Publico lee paises activos');
  IF v IS DISTINCT FROM 'aa5f67c1b4b372648c73cdece0e68d46|r|{0}' THEN bad := bad||'Publico lee paises activos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  -- policies {public} en las tablas de la WL: las 17 + la de paises (PRE) o solo la de paises (POST)
  v := (SELECT string_agg(c.relname||'/'||pl.polname, ', ' ORDER BY c.relname, pl.polname) FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE c.relnamespace = 'public'::regnamespace AND c.relname = ANY (ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas']) AND pl.polroles = '{0}'::oid[]
           AND pl.polname <> 'Publico lee paises activos');
  IF COALESCE(array_length(string_to_array(v, ', '), 1), 0) <> 17 THEN
    bad := bad||'policies {public} en la WL (salvo paises): '||COALESCE(v, 'ninguna')||'; ';
  END IF;
  -- contenido sin roles de TODAS las policies (no cambia nunca: la 350 solo toca polroles)
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '2003cbbf2f93bca4e050d3bcc4aab2c3 309' THEN bad := bad||'contenido sin roles de las policies '||COALESCE(v, '-')||'; '; END IF;
  -- huella de TODAS las policies de public/private/storage: tabla|nombre|cmd|permissive|roles|USING|CHECK
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'fc06b02c0b09efd90f774e612e53d454 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- RLS de las 8 tablas de la WL: activa, sin FORCE (no cambia)
  v := (SELECT string_agg(c.relname||':'||c.relrowsecurity::text||'/'||c.relforcerowsecurity::text, ',' ORDER BY c.relname) FROM pg_class c
         WHERE c.relnamespace = 'public'::regnamespace AND c.relname = ANY (ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas']));
  IF v IS DISTINCT FROM 'configuracion_pais:true/false,configuracion_sistema:true/false,cuentas_proveedor:true/false,empresas_proveedoras:true/false,liquidaciones_comision:true/false,pacientes:true/false,perfiles:true/false,recetas:true/false' THEN bad := bad||'RLS de la WL '||COALESCE(v, '-')||'; '; END IF;
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
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG350 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- ALTER POLICY ... TO authenticated (17)
ALTER POLICY "Admin ezpay actualiza configuracion" ON public.configuracion_sistema TO authenticated;
ALTER POLICY "Admin ezpay ve cuentas proveedor" ON public.cuentas_proveedor TO authenticated;
ALTER POLICY "Proveedor ve su propia cuenta" ON public.cuentas_proveedor TO authenticated;
ALTER POLICY "Supervisor ve cuentas de su equipo" ON public.cuentas_proveedor TO authenticated;
ALTER POLICY "Admin ezpay actualiza empresas" ON public.empresas_proveedoras TO authenticated;
ALTER POLICY "Admin ezpay ve todas las empresas" ON public.empresas_proveedoras TO authenticated;
ALTER POLICY "Admin ve pacientes de su pais" ON public.pacientes TO authenticated;
ALTER POLICY "Paciente crea su perfil" ON public.pacientes TO authenticated;
ALTER POLICY "Paciente ve su perfil" ON public.pacientes TO authenticated;
ALTER POLICY "Actualizar propio perfil" ON public.perfiles TO authenticated;
ALTER POLICY "Admin actualiza perfiles de su pais" ON public.perfiles TO authenticated;
ALTER POLICY "Admin borra perfiles de su pais" ON public.perfiles TO authenticated;
ALTER POLICY "Admin lee perfiles de su pais" ON public.perfiles TO authenticated;
ALTER POLICY "Admins pueden insertar perfiles" ON public.perfiles TO authenticated;
ALTER POLICY "Ver propio perfil" ON public.perfiles TO authenticated;
ALTER POLICY "Admin ve recetas de su pais" ON public.recetas TO authenticated;
ALTER POLICY "Paciente ve sus recetas" ON public.recetas TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; n_falta int; n_rol int;
BEGIN
  -- las 17 policies de la lista: existen, todas con roles = {authenticated}, y su contenido sin roles
  -- (tabla|nombre|cmd|permissive|USING|CHECK) es el medido
  SELECT count(*) FILTER (WHERE pl.oid IS NULL), count(*) FILTER (WHERE pl.polroles = ARRAY['authenticated'::regrole::oid]),
         md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n'
           ORDER BY c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') COLLATE "C"))||' '||count(pl.oid)
    INTO n_falta, n_rol, v
    FROM (VALUES
      ('configuracion_sistema', 'Admin ezpay actualiza configuracion'),
      ('cuentas_proveedor', 'Admin ezpay ve cuentas proveedor'),
      ('cuentas_proveedor', 'Proveedor ve su propia cuenta'),
      ('cuentas_proveedor', 'Supervisor ve cuentas de su equipo'),
      ('empresas_proveedoras', 'Admin ezpay actualiza empresas'),
      ('empresas_proveedoras', 'Admin ezpay ve todas las empresas'),
      ('pacientes', 'Admin ve pacientes de su pais'),
      ('pacientes', 'Paciente crea su perfil'),
      ('pacientes', 'Paciente ve su perfil'),
      ('perfiles', 'Actualizar propio perfil'),
      ('perfiles', 'Admin actualiza perfiles de su pais'),
      ('perfiles', 'Admin borra perfiles de su pais'),
      ('perfiles', 'Admin lee perfiles de su pais'),
      ('perfiles', 'Admins pueden insertar perfiles'),
      ('perfiles', 'Ver propio perfil'),
      ('recetas', 'Admin ve recetas de su pais'),
      ('recetas', 'Paciente ve sus recetas')) s(tab, pol)
    LEFT JOIN pg_class c ON c.relnamespace = 'public'::regnamespace AND c.relname = s.tab
    LEFT JOIN pg_policy pl ON pl.polrelid = c.oid AND pl.polname = s.pol;
  IF n_falta <> 0 THEN bad := bad||n_falta||' policies de la lista no existen; '; END IF;
  IF n_rol <> 17 THEN bad := bad||'policies de la lista con roles {authenticated}: '||n_rol||' de 17; '; END IF;
  IF v IS DISTINCT FROM 'cb6b0d4d88d67610aa480d985fe6be29 17' THEN bad := bad||'contenido del conjunto '||COALESCE(v, '-')||'; '; END IF;
  -- "Publico lee paises activos" (la lectura publica deliberada) existe y no se toca: md5(USING)|cmd|roles
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid))||'|'||pl.polcmd::text||'|'||pl.polroles::text FROM pg_policy pl
         WHERE pl.polrelid = 'public.configuracion_pais'::regclass AND pl.polname = 'Publico lee paises activos');
  IF v IS DISTINCT FROM 'aa5f67c1b4b372648c73cdece0e68d46|r|{0}' THEN bad := bad||'Publico lee paises activos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  -- policies {public} en las tablas de la WL: las 17 + la de paises (PRE) o solo la de paises (POST)
  v := (SELECT string_agg(c.relname||'/'||pl.polname, ', ' ORDER BY c.relname, pl.polname) FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE c.relnamespace = 'public'::regnamespace AND c.relname = ANY (ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas']) AND pl.polroles = '{0}'::oid[]
           AND pl.polname <> 'Publico lee paises activos');
  IF v IS NOT NULL THEN
    bad := bad||'policies {public} en la WL (salvo paises): '||COALESCE(v, 'ninguna')||'; ';
  END IF;
  -- contenido sin roles de TODAS las policies (no cambia nunca: la 350 solo toca polroles)
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '2003cbbf2f93bca4e050d3bcc4aab2c3 309' THEN bad := bad||'contenido sin roles de las policies '||COALESCE(v, '-')||'; '; END IF;
  -- huella de TODAS las policies de public/private/storage: tabla|nombre|cmd|permissive|roles|USING|CHECK
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'd1aae5eba7362ec479a3995bf2d29827 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- RLS de las 8 tablas de la WL: activa, sin FORCE (no cambia)
  v := (SELECT string_agg(c.relname||':'||c.relrowsecurity::text||'/'||c.relforcerowsecurity::text, ',' ORDER BY c.relname) FROM pg_class c
         WHERE c.relnamespace = 'public'::regnamespace AND c.relname = ANY (ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas']));
  IF v IS DISTINCT FROM 'configuracion_pais:true/false,configuracion_sistema:true/false,cuentas_proveedor:true/false,empresas_proveedoras:true/false,liquidaciones_comision:true/false,pacientes:true/false,perfiles:true/false,recetas:true/false' THEN bad := bad||'RLS de la WL '||COALESCE(v, '-')||'; '; END IF;
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
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG350 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
