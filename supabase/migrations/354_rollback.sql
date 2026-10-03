-- ############################################################################################
-- 354_rollback - deshace la 354 (visibilidad de medicos y productos)
-- ############################################################################################
-- * Restaura "Proveedor ve medicos de su pais" (medicos) y el qual original de "Médico ve productos activos".
-- * Restaura get_visitas_proveedor() y buscar_medicos_proveedor(text) (con email) con sus cuerpos EXACTOS del
--   prosrc vivo previo a la 354 (generados por tmp/354/gen_rollback.py; md5 verificado) y su ACL.
-- * DROP de nombres_medicos_visitas y nombre_empresa_por_productos.
-- * Estado final = huellas de partida de la 354: policies 700082376ca04bcbb59eb743fe79c5ee 309, ACL de funciones
--   70a9dc38e222ca940d755103c7940c5a 374; relaciones, columnas, defaults y publicacion sin cambio.
-- * El front nuevo (nombres por RPC) deja de mostrar nombres si se corre este rollback sin revertir el front.
-- Orden global: 354_rollback -> 353_rollback -> 352_rollback -> ...
-- ############################################################################################

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'->'||pg_get_function_result(p.oid)||'='||md5(p.prosrc), ',' ORDER BY p.proname) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname IN ('buscar_medicos_proveedor','get_visitas_proveedor','nombres_medicos_visitas','nombre_empresa_por_productos'));
  IF v IS DISTINCT FROM 'buscar_medicos_proveedor(text)->TABLE(id uuid, nombre_completo text, especialidad text)=b9432e00735e70ec15dc9d73508953e6,'
                     || 'nombre_empresa_por_productos(uuid[])->TABLE(empresa_id uuid, nombre_empresa text)=1931f7c53b47df4df9cdebbcdfbf49ae,'
                     || 'nombres_medicos_visitas(uuid[])->TABLE(medico_id uuid, nombre_completo text, especialidad text)=f26cb04d1e763e0ebb532d006e669837' THEN
    bad := bad||'funciones de la 354 '||COALESCE(v, '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.medicos'::regclass AND polname = 'Proveedor ve medicos de su pais') THEN
    bad := bad||'la policy de medicos ya existe; ';
  END IF;
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid)) FROM pg_policy pl WHERE pl.polrelid = 'public.productos_empresa'::regclass AND pl.polname = 'Médico ve productos activos');
  IF v IS DISTINCT FROM '69e1a69c8f46627efe6a09445d919ffb' THEN bad := bad||'qual de productos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;

  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK354 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

DROP FUNCTION public.nombres_medicos_visitas(uuid[]);
DROP FUNCTION public.nombre_empresa_por_productos(uuid[]);
DROP FUNCTION public.buscar_medicos_proveedor(text);

-- cuerpo EXACTO previo a la 354 (md5 a85168dd34bea5855ae27bbbd7b7c5f5)
CREATE FUNCTION public.buscar_medicos_proveedor(p_query text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, nombre_completo text, email text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $orig$
DECLARE
  v_uid  uuid := auth.uid();
  v_pais uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_auth';
  END IF;

  v_pais := private.mi_pais();

  RETURN QUERY
  SELECT p.id, p.nombre_completo, p.email
  FROM public.perfiles p
  WHERE p.rol = 'medico'
    AND p.activo = true
    AND (v_pais IS NOT NULL AND p.pais_id = v_pais)
    AND (p_query IS NULL OR p_query = ''
         OR p.nombre_completo ILIKE '%' || p_query || '%')
  ORDER BY p.nombre_completo
  LIMIT 50;
END;
$orig$;
REVOKE ALL ON FUNCTION public.buscar_medicos_proveedor(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buscar_medicos_proveedor(text) TO authenticated, service_role;

-- cuerpo EXACTO previo a la 354 (md5 2362c2bf42decd1d858fb159630a9e92)
CREATE FUNCTION public.get_visitas_proveedor()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $orig$
DECLARE
  v_empresa_id UUID;
  result jsonb;
BEGIN
  PERFORM private.exigir_empresa_activa();
  SELECT c.empresa_id INTO v_empresa_id 
  FROM cuentas_proveedor c 
  WHERE c.id = auth.uid();
  
  SELECT jsonb_agg(
    jsonb_build_object(
      'visita_id', v.id,
      'visita_medico_id', v.medico_id,
      'nombre_medico', p.nombre_completo,
      'email_medico', p.email,
      'fecha_visita', v.fecha_visita,
      'hora_inicio', v.hora_inicio,
      'hora_fin', v.hora_fin,
      'tipo_visita', v.tipo_visita,
      'estado', v.estado,
      'notas_empresa', v.notas_empresa,
      'created_at', v.created_at
    ) ORDER BY v.fecha_visita DESC, v.hora_inicio DESC
  ) INTO result
  FROM visitas_agendadas v
  JOIN perfiles p ON p.id = v.medico_id
  WHERE v.empresa_id = v_empresa_id;
  
  RETURN COALESCE(result, '[]'::jsonb);
END;
$orig$;
REVOKE ALL ON FUNCTION public.get_visitas_proveedor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_visitas_proveedor() TO authenticated, service_role;

CREATE POLICY "Proveedor ve medicos de su pais" ON public.medicos AS PERMISSIVE FOR SELECT TO authenticated
  USING (((pais_id IS NOT NULL) AND (pais_id = private.pais_de_proveedor())));

ALTER POLICY "Médico ve productos activos" ON public.productos_empresa TO authenticated
  USING (((estado = 'activo'::text) AND (NOT COALESCE(private.empresa_es_afin(empresa_id), false)) AND (pais_id = private.mi_pais())));

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'->'||pg_get_function_result(p.oid)||'='||md5(p.prosrc)||':'||p.prosecdef::text||':'||COALESCE(array_to_string(p.proconfig, ','), '-'), ',' ORDER BY p.proname) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname IN ('buscar_medicos_proveedor','get_visitas_proveedor','nombres_medicos_visitas','nombre_empresa_por_productos'));
  IF v IS DISTINCT FROM 'buscar_medicos_proveedor(text)->TABLE(id uuid, nombre_completo text, email text)=a85168dd34bea5855ae27bbbd7b7c5f5:true:search_path="",'
                     || 'get_visitas_proveedor()->jsonb=2362c2bf42decd1d858fb159630a9e92:true:search_path=public' THEN
    bad := bad||'funciones restauradas '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid))||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||pl.polroles::regrole[]::text
          FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polname = 'Proveedor ve medicos de su pais');
  IF v IS DISTINCT FROM '83b832a0e38ab8f6d412abf409da53e5|r|true|{authenticated}' THEN bad := bad||'policy de medicos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid))||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||pl.polroles::regrole[]::text
          FROM pg_policy pl WHERE pl.polrelid = 'public.productos_empresa'::regclass AND pl.polname = 'Médico ve productos activos');
  IF v IS DISTINCT FROM 'ad6b03c22d9f688f723194795b5fefd4|r|true|{authenticated}' THEN bad := bad||'policy de productos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;

  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '70a9dc38e222ca940d755103c7940c5a 374' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK354 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
