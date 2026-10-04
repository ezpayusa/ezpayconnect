-- ############################################################################################
-- 357 - obtener_medicos_por_ids acotada a relacion
-- ############################################################################################
-- Recon del 4-oct-2026 sobre de5404a (solo lectura contra prod):
--   * public.obtener_medicos_por_ids(uuid[]): plpgsql, SECURITY DEFINER, search_path '', VOLATILE, ACL postgres/
--     authenticated/service_role (sin PUBLIC ni anon), md5(prosrc) 2d646322.... La mig 307 le dejo el search_path y el
--     guard de auth.uid() IS NULL (PC027) y nada mas: CUALQUIER sesion autenticada (paciente, proveedor, visitador, staff
--     de clinica) le pasaba ids arbitrarios y recibia nombre_completo y especialidad de cualquier medico, de cualquier
--     pais y sin relacion. No devuelve datos de contacto.
--   * Tenia una segunda rama de fallback sobre la tabla de perfiles (rol 'medico' sin fila en medicos): muerta en prod
--     (0 filas) e innecesaria, porque citas.medico_id y medico_clinicas.medico_id son FK a medicos(id).
--   * Callers (los tres resuelven nombres de medicos que ya vieron en citas que su RLS/RPC les deja ver):
--       - src/clinica/hooks/useAdmisionCitas.ts:64 (/clinica/admision): ids de obtener_citas_clinica(clinica propia).
--       - src/pages/CitasPage.tsx:134 (/citas): ids de un SELECT directo de citas bajo su RLS.
--       - src/webapp/hooks/useWebAppCitas.ts:38 (portal paciente): ids de sus propias citas.
--     Ninguna funcion, vista, policy, trigger, cron ni edge la llama.
-- Cambio:
--   A CREATE OR REPLACE con la MISMA firma, RETURNS, DEFINER, search_path '' y volatilidad. Se conserva el guard PC027.
--     Sin la rama de fallback. Un medico se devuelve solo si el llamante tiene relacion con el (fail-closed: COALESCE
--     a false):
--       (a) super_admin;
--       (b) es el propio medico;
--       (c) el medico aparece en una cita que el llamante ve: es su paciente (pacientes.auth_user_id), es admin_pais
--           del pais de la cita (private.puede_admin_pais) o gestiona las citas de la clinica de la cita
--           (private.puede_gestionar_citas: admin_clinica, gerente, secretaria);
--       (d) el medico es miembro (medico_clinicas) de una clinica del llamante (private.clinicas_del_usuario), que cubre
--           al staff no gestor de la admision (asistente_medico, enfermeria).
--     REVOKE ALL de PUBLIC y anon; GRANT EXECUTE a authenticated y service_role (ACL igual al de partida).
-- FUERA a proposito: public.contar_medicos_por_ids (ClinicaDashboardPage) tiene la misma clase de defecto pero solo
--   devuelve un conteo; va en el lote 2 (backlog).
-- Sin errcodes nuevos. Probes: P958-P965 (por actor) y P966 (catalogo); el fixture PM_FX elige pm_pac determinista
--   (paciente real de GT con cita con pm_med) para que P701 siga dando 1.
-- Rollback: 357_rollback.sql (restaura el cuerpo de partida con sus CRLF, md5 verificado).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||' -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM 'obtener_medicos_por_ids(uuid[]) -> TABLE(id uuid, nombre_completo text, especialidad text) | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion de partida'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM '2d646322d21e4f5d8cae0b20de7723f5' THEN bad := bad||'md5(prosrc) de partida'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')||' owner='||pg_get_userbyid(p.proowner)||' auth='||has_function_privilege('authenticated', p.oid, 'EXECUTE')::text, ';' ORDER BY p.oid::regprocedure::text)
          FROM pg_proc p WHERE p.pronamespace = 'private'::regnamespace AND p.proname IN ('tiene_rol','puede_admin_pais','puede_gestionar_citas','clinicas_del_usuario'));
  IF v IS DISTINCT FROM 'private.clinicas_del_usuario() sp=search_path="" owner=postgres auth=true;private.puede_admin_pais(uuid,text[]) sp=search_path="" owner=postgres auth=true;private.puede_gestionar_citas(uuid) sp=search_path="" owner=postgres auth=true;private.tiene_rol(text[]) sp=search_path="" owner=postgres auth=true' THEN bad := bad||'helpers'||' '||COALESCE(v, '-')||'; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG357 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A: acotada a relacion
CREATE OR REPLACE FUNCTION public.obtener_medicos_por_ids(p_medico_ids uuid[])
 RETURNS TABLE(id uuid, nombre_completo text, especialidad text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'no autenticado' USING ERRCODE = 'PC027';
  END IF;
  RETURN QUERY
  SELECT m.id, m.nombre_completo, m.especialidad
    FROM public.medicos m
   WHERE m.id = ANY (p_medico_ids)
     AND COALESCE(
           -- (a) super_admin
           private.tiene_rol(ARRAY['super_admin'])
           -- (b) el propio medico
        OR m.id = auth.uid()
           -- (c) el medico aparece en una cita que el llamante ve
        OR EXISTS (
             SELECT 1 FROM public.citas c
              WHERE c.medico_id = m.id
                AND (   EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = c.paciente_id AND pa.auth_user_id = auth.uid())
                     OR (c.pais_id IS NOT NULL AND private.puede_admin_pais(c.pais_id))
                     OR (c.clinica_id IS NOT NULL AND private.puede_gestionar_citas(c.clinica_id))))
           -- (d) el medico es miembro de una clinica del llamante
        OR EXISTS (
             SELECT 1 FROM public.medico_clinicas mc
              WHERE mc.medico_id = m.id
                AND mc.clinica_id IN (SELECT private.clinicas_del_usuario())),
         false);
END;
$function$;

REVOKE ALL ON FUNCTION public.obtener_medicos_por_ids(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_medicos_por_ids(uuid[]) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||' -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM 'obtener_medicos_por_ids(uuid[]) -> TABLE(id uuid, nombre_completo text, especialidad text) | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion nueva'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(p.prorettype::regtype::text||' | '||array_to_string(p.proallargtypes::regtype[], ',')||' | '||array_to_string(p.proargmodes, ',')||' | '||array_to_string(p.proargnames, ','), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS DISTINCT FROM 'record | uuid[],uuid,text,text | i,t,t,t | p_medico_ids,id,nombre_completo,especialidad' THEN bad := bad||'columnas de salida'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids');
  IF v IS NOT DISTINCT FROM '2d646322d21e4f5d8cae0b20de7723f5' THEN bad := bad||'md5(prosrc) sigue siendo el de partida; '; END IF;
  IF v IS DISTINCT FROM '8ee6016630226077501fc1933e7d9dbc' THEN bad := bad||'md5(prosrc) nuevo'||' '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'obtener_medicos_por_ids' AND position('perfiles' IN p.prosrc) > 0) THEN
    bad := bad||'el cuerpo todavia nombra perfiles; ';
  END IF;
  IF has_function_privilege('anon', 'public.obtener_medicos_por_ids(uuid[])', 'EXECUTE') THEN bad := bad||'anon tiene EXECUTE; '; END IF;
  IF NOT has_function_privilege('authenticated', 'public.obtener_medicos_por_ids(uuid[])', 'EXECUTE') THEN bad := bad||'authenticated sin EXECUTE; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG357 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
