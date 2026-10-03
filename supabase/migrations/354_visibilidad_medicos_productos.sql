-- ############################################################################################
-- 354 - pieza 3 (visibilidad): el proveedor deja de leer la tabla medicos; nombres por RPC acotadas
-- ############################################################################################
-- Recon del 3-oct-2026 sobre 62365a2 (tmp/354/r1-r6, r7_recon.md, a1-a4; solo lectura contra prod):
--   * La policy "Proveedor ve medicos de su pais" (pais_id = private.pais_de_proveedor()) da TODAS las columnas de
--     TODOS los medicos del pais a cualquier cuenta de proveedor (cajero y repartidor incluidos; medido: 6 roles ven
--     los 5 medicos de GT con email). Su unico consumidor es VisitadorDetallePage (from('medicos')). Las 24
--     funciones que leen medicos son DEFINER, ninguna vista ni policy de otra tabla la consulta, y las edges usan
--     service_role.
--   * ProveedorReporteVisitasPage embebe medico:medico_id(...): la FK de visitas_agendadas apunta a perfiles, que el
--     proveedor no lee -> "Desconocido". useVisitasAgendadas resolvia nombres con buscar_medicos_proveedor(null)
--     (tope de 50, solo activos).
--   * buscar_medicos_proveedor no tiene gate de rol: cualquier cuenta de proveedor lista medicos del pais con email.
--   * get_visitas_proveedor() no filtra por rol y devuelve el email del medico; 0 llamadores (src, edges, SQL).
--   * "Medico ve productos activos" de productos_empresa no mira el rol: cualquier usuario con pais (proveedores de
--     otras empresas, admin_clinica, enfermeria, admin_pais) ve el catalogo activo ajeno. El medico, en cambio, no
--     ve el nombre del laboratorio (empresas_proveedoras solo es legible por super_admin y la propia empresa).
--   * A1: las 3 empresas que agendan (QA Laboratorio, La nueva, QA Farmacia) tienen la capacidad 'visitadores'
--     activa sin fecha de fin. A4: ningun usuario con rol distinto de 'medico' emite recetas ni escribe notas hoy.
-- Decisiones (Oscar, 3-oct-2026):
--   1 DROP de "Proveedor ve medicos de su pais", sin reemplazo.
--   2 buscar_medicos_proveedor solo para admin/editor/supervisor/visitador_medico con la capacidad 'visitadores';
--     sin autoridad, 0 filas (no 42501).
--   3 buscar_medicos_proveedor sin email: (id, nombre_completo, especialidad). DROP + CREATE.
--   4 DROP de get_visitas_proveedor().
--   5 "Medico ve productos activos" + gate de rol medico o super_admin (opcion 1: el personal de clinica que llega a
--     /buscar-medicamentos por "Iniciar consulta" ve "En proveedores" vacio; backlog de familia 7).
-- Cambios:
--   A public.nombres_medicos_visitas(uuid[]) -> (medico_id, nombre_completo, especialidad): solo medicos de visitas
--     que el llamante puede ver (mismo predicado que "Proveedor ve visitas segun rol"). Sin email.
--   B public.nombre_empresa_por_productos(uuid[]) -> (empresa_id, nombre_empresa): gate medico/super_admin; solo
--     empresas con un producto activo, no afin y del pais del llamante (super_admin: de cualquier pais, como su policy).
--   C public.buscar_medicos_proveedor(text): DROP + CREATE con gate y sin email; mismo filtro (mi_pais, rol medico,
--     activo, ilike, LIMIT 50); 'no_auth' sin sesion, igual que antes.
--   D DROP POLICY "Proveedor ve medicos de su pais" ON public.medicos.
--   E DROP FUNCTION public.get_visitas_proveedor().
--   F ALTER POLICY "Medico ve productos activos": mismo qual AND COALESCE(private.tiene_rol(ARRAY['medico',
--     'super_admin']), false). tiene_rol = private.rol_usuario() (perfiles.rol con activo) = ANY(...); EXECUTE para
--     authenticated ya otorgado.
-- Sin errcodes nuevos: las RPCs devuelven 0 filas sin autoridad.
-- Probes: P944 (censo), P945 (medicos por rol), P946 (nombres_medicos_visitas), P947 (nombre_empresa_por_productos),
-- P948 (buscar_medicos_proveedor), P949 (productos_empresa por rol), P950 (catalogo).
-- Rollback: 354_rollback.sql (restaura las 2 policies, get_visitas_proveedor y buscar_medicos_proveedor con sus
-- cuerpos exactos y ACL; borra las 2 RPCs nuevas).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.proname, ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname IN ('nombres_medicos_visitas','nombre_empresa_por_productos'));
  IF v IS NOT NULL THEN bad := bad||'funciones ya existen: '||v||'; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text||'->'||pg_get_function_result(p.oid)||'='||md5(p.prosrc), ',' ORDER BY p.proname) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('buscar_medicos_proveedor','get_visitas_proveedor'));
  IF v IS DISTINCT FROM 'buscar_medicos_proveedor(text)->TABLE(id uuid, nombre_completo text, email text)=a85168dd34bea5855ae27bbbd7b7c5f5,'
                     || 'get_visitas_proveedor()->jsonb=2362c2bf42decd1d858fb159630a9e92' THEN
    bad := bad||'funciones de partida '||COALESCE(v, 'no existen')||'; ';
  END IF;
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid))||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||pl.polroles::regrole[]::text
          FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polname = 'Proveedor ve medicos de su pais');
  IF v IS DISTINCT FROM '83b832a0e38ab8f6d412abf409da53e5|r|true|{authenticated}' THEN bad := bad||'policy de medicos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid))||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||pl.polroles::regrole[]::text
          FROM pg_policy pl WHERE pl.polrelid = 'public.productos_empresa'::regclass AND pl.polname = 'Médico ve productos activos');
  IF v IS DISTINCT FROM 'ad6b03c22d9f688f723194795b5fefd4|r|true|{authenticated}' THEN bad := bad||'policy de productos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  -- helpers que usan las RPCs y la policy nueva
  v := (SELECT string_agg(p.oid::regprocedure::text, ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE (p.pronamespace = 'private'::regnamespace AND p.proname IN ('tiene_rol','mi_pais','empresa_tiene_capacidad','empresa_es_afin'))
            OR (p.pronamespace = 'public'::regnamespace AND p.proname IN ('mi_empresa_proveedor','mi_rol_proveedor','supervisa_cuenta_proveedor')));
  IF v IS DISTINCT FROM 'mi_empresa_proveedor(),mi_rol_proveedor(),private.empresa_es_afin(uuid),private.empresa_tiene_capacidad(uuid,text),private.mi_pais(),private.tiene_rol(text[]),supervisa_cuenta_proveedor(uuid)' THEN
    bad := bad||'helpers '||COALESCE(v, '-')||'; ';
  END IF;
  IF NOT has_function_privilege('authenticated', 'private.tiene_rol(text[])', 'EXECUTE') THEN bad := bad||'authenticated sin EXECUTE en private.tiene_rol; '; END IF;
  -- huellas
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '700082376ca04bcbb59eb743fe79c5ee 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
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
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '70a9dc38e222ca940d755103c7940c5a 374' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG354 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A. nombres de medicos de mis visitas
CREATE FUNCTION public.nombres_medicos_visitas(p_medico_ids uuid[])
RETURNS TABLE (medico_id uuid, nombre_completo text, especialidad text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
#variable_conflict use_column
DECLARE
  v_uid uuid := auth.uid();
  v_emp uuid := public.mi_empresa_proveedor();
  v_rol text := public.mi_rol_proveedor();
BEGIN
  -- fail-closed: sin sesion, sin cuenta de proveedor activa o sin ids -> 0 filas
  IF v_uid IS NULL OR v_emp IS NULL OR p_medico_ids IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT p.id, p.nombre_completo, m.especialidad
    FROM public.perfiles p
    LEFT JOIN public.medicos m ON m.id = p.id
   WHERE p.id = ANY (p_medico_ids)
     -- el medico aparece en una visita que el llamante puede ver: mismo predicado que la policy
     -- "Proveedor ve visitas segun rol" de visitas_agendadas
     AND EXISTS (
       SELECT 1 FROM public.visitas_agendadas v
        WHERE v.medico_id = p.id
          AND v.empresa_id = v_emp
          AND (   COALESCE(v_rol = ANY (ARRAY['admin','editor']), false)
               OR COALESCE(v.cuenta_proveedor_id = v_uid, false)
               OR COALESCE(v.propuesta_por = v_uid, false)
               OR (COALESCE(v_rol = 'supervisor', false)
                   AND COALESCE(public.supervisa_cuenta_proveedor(v.cuenta_proveedor_id), false))));
END;
$fn$;

REVOKE ALL ON FUNCTION public.nombres_medicos_visitas(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nombres_medicos_visitas(uuid[]) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- B. nombre del laboratorio para el medico
CREATE FUNCTION public.nombre_empresa_por_productos(p_empresa_ids uuid[])
RETURNS TABLE (empresa_id uuid, nombre_empresa text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
#variable_conflict use_column
DECLARE v_super boolean;
BEGIN
  -- Gate: solo medico/super_admin (mismo molde que nombre_cadena_por_farmacias). Otro -> 0 filas (fail-closed).
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico','super_admin']), false) OR p_empresa_ids IS NULL THEN RETURN; END IF;
  v_super := COALESCE(private.tiene_rol(ARRAY['super_admin']), false);
  RETURN QUERY
  SELECT e.id, e.nombre_empresa                 -- SOLO id + nombre; NUNCA ruc_nit/email_contacto/telefono/direccion
    FROM public.empresas_proveedoras e
   WHERE e.id = ANY (p_empresa_ids)
     -- empresas con al menos un producto que el llamante ve por "Medico ve productos activos"
     -- (super_admin: de cualquier pais, como su propia policy)
     AND EXISTS (
       SELECT 1 FROM public.productos_empresa pe
        WHERE pe.empresa_id = e.id
          AND pe.estado = 'activo'
          AND NOT COALESCE(private.empresa_es_afin(pe.empresa_id), false)
          AND (v_super OR COALESCE(pe.pais_id = private.mi_pais(), false)));
END;
$fn$;

REVOKE ALL ON FUNCTION public.nombre_empresa_por_productos(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nombre_empresa_por_productos(uuid[]) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- C. buscar_medicos_proveedor: gate y sin email
DROP FUNCTION public.buscar_medicos_proveedor(text);

CREATE FUNCTION public.buscar_medicos_proveedor(p_query text DEFAULT NULL::text)
RETURNS TABLE (id uuid, nombre_completo text, especialidad text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
#variable_conflict use_column
DECLARE
  v_uid  uuid := auth.uid();
  v_pais uuid;
  v_emp  uuid;
  v_rol  text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_auth';
  END IF;

  -- Gate (354): cuenta de proveedor activa con un rol que agenda o aprueba visitas, en una empresa con la
  -- capacidad 'visitadores'. Sin autoridad -> 0 filas (no 42501: el agendar no se rompe con un error).
  v_emp := public.mi_empresa_proveedor();
  v_rol := public.mi_rol_proveedor();
  IF v_emp IS NULL
     OR NOT COALESCE(v_rol = ANY (ARRAY['admin','editor','supervisor','visitador_medico']), false)
     OR NOT COALESCE(private.empresa_tiene_capacidad(v_emp, 'visitadores'), false) THEN
    RETURN;
  END IF;

  v_pais := private.mi_pais();

  RETURN QUERY
  SELECT p.id, p.nombre_completo, m.especialidad
  FROM public.perfiles p
  LEFT JOIN public.medicos m ON m.id = p.id
  WHERE p.rol = 'medico'
    AND p.activo = true
    AND (v_pais IS NOT NULL AND p.pais_id = v_pais)
    AND (p_query IS NULL OR p_query = ''
         OR p.nombre_completo ILIKE '%' || p_query || '%')
  ORDER BY p.nombre_completo
  LIMIT 50;
END;
$fn$;

REVOKE ALL ON FUNCTION public.buscar_medicos_proveedor(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buscar_medicos_proveedor(text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- D. el proveedor deja de leer medicos
DROP POLICY "Proveedor ve medicos de su pais" ON public.medicos;

-- ---------------------------------------------------------------------------- E. funcion muerta
DROP FUNCTION public.get_visitas_proveedor();

-- ---------------------------------------------------------------------------- F. catalogo ajeno solo para medico/super_admin
ALTER POLICY "Médico ve productos activos" ON public.productos_empresa TO authenticated
  USING (((estado = 'activo'::text) AND (NOT COALESCE(private.empresa_es_afin(empresa_id), false)) AND (pais_id = private.mi_pais()))
         AND COALESCE(private.tiene_rol(ARRAY['medico'::text, 'super_admin'::text]), false));

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.proname||':'||p.prosecdef::text||':'||COALESCE(array_to_string(p.proconfig, ','), '-')||':'||pg_get_function_result(p.oid)||':'||
           (SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'='||a.privilege_type, '+'
                               ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END)
              FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a), ',' ORDER BY p.proname)
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname IN ('nombres_medicos_visitas','nombre_empresa_por_productos','buscar_medicos_proveedor','get_visitas_proveedor'));
  IF v IS DISTINCT FROM
       'buscar_medicos_proveedor:true:search_path="":TABLE(id uuid, nombre_completo text, especialidad text):authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE,'
    || 'nombre_empresa_por_productos:true:search_path="":TABLE(empresa_id uuid, nombre_empresa text):authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE,'
    || 'nombres_medicos_visitas:true:search_path="":TABLE(medico_id uuid, nombre_completo text, especialidad text):authenticated=EXECUTE+postgres=EXECUTE+service_role=EXECUTE' THEN
    bad := bad||'funciones '||COALESCE(v, '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.medicos'::regclass AND polname = 'Proveedor ve medicos de su pais') THEN
    bad := bad||'la policy de medicos sigue; ';
  END IF;
  v := (SELECT md5(pg_get_expr(pl.polqual, pl.polrelid))||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||pl.polroles::regrole[]::text
          FROM pg_policy pl WHERE pl.polrelid = 'public.productos_empresa'::regclass AND pl.polname = 'Médico ve productos activos');
  IF v IS DISTINCT FROM '69e1a69c8f46627efe6a09445d919ffb|r|true|{authenticated}' THEN bad := bad||'policy de productos '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
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
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG354 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
