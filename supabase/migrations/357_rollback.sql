-- ############################################################################################
-- 357 ROLLBACK - restaura public.obtener_medicos_por_ids tal como estaba antes de la 357
-- ############################################################################################
-- El cuerpo de partida se saco del objeto VIVO (pg_get_functiondef, 4-oct-2026), no del archivo de la 307, e incluye la
-- rama de fallback sobre la tabla de perfiles. Su prosrc tiene CRLF y el repo exige LF (.gitattributes eol=lf), asi que
-- el cuerpo NO se escribe literal en este archivo: se arma como string E'...' con \r\n explicitos, se verifica que su
-- md5 sea el de partida (2d646322...) ANTES de ejecutar, y se aplica con EXECUTE format(... %L) (variante del patron de
-- la 347: alli el cuerpo se armaba con replace() sobre el prosrc vivo; aca el prosrc vivo es el de la 357, del que no se
-- puede derivar el viejo, asi que se lo reconstruye y se lo valida por md5).
-- Precondicion: la version de la 357 esta viva (md5 8ee60166...). Autochequeo: md5 = 2d646322..., ACL
-- {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}, mismas huellas globales.
-- Probes: con este rollback aplicado, P958, P959, P961 y P966 vuelven a ROJO (es lo esperado: miden el cierre).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 357)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||' -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM 'obtener_medicos_por_ids(uuid[]) -> TABLE(id uuid, nombre_completo text, especialidad text) | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion de la 357'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM '8ee6016630226077501fc1933e7d9dbc' THEN bad := bad||'md5(prosrc) de la 357'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK357 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- restaurar el cuerpo de partida
DO $restaurar$
DECLARE
  v_body text := E'\r\nBEGIN\r\n  IF auth.uid() IS NULL THEN\r\n    RAISE EXCEPTION ''no autenticado'' USING ERRCODE = ''PC027'';\r\n  END IF;\r\n  RETURN QUERY\r\n  SELECT m.id, m.nombre_completo, m.especialidad FROM public.medicos m WHERE m.id = ANY(p_medico_ids)\r\n  UNION\r\n  SELECT p.id, p.nombre_completo, NULL::TEXT FROM public.perfiles p\r\n  WHERE p.id = ANY(p_medico_ids) AND p.rol = ''medico''\r\n    AND NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = p.id);\r\nEND;\r\n';
BEGIN
  IF md5(v_body) IS DISTINCT FROM '2d646322d21e4f5d8cae0b20de7723f5' THEN
    RAISE EXCEPTION 'ROLLBACK357: el cuerpo armado no es el de partida (md5 %)', md5(v_body);
  END IF;
  EXECUTE format($f$CREATE OR REPLACE FUNCTION public.obtener_medicos_por_ids(p_medico_ids uuid[])
 RETURNS TABLE(id uuid, nombre_completo text, especialidad text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS %L$f$, v_body);
END $restaurar$;

REVOKE ALL ON FUNCTION public.obtener_medicos_por_ids(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_medicos_por_ids(uuid[]) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||' -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM 'obtener_medicos_por_ids(uuid[]) -> TABLE(id uuid, nombre_completo text, especialidad text) | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion restaurada'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM '2d646322d21e4f5d8cae0b20de7723f5' THEN bad := bad||'md5(prosrc) restaurado'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK357 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
