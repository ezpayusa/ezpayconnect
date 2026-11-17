-- =====================================================================================================================
-- MIG 387 — Familia B: detalle de una empresa proveedora para el super_admin y el admin de SU país (solo lectura).
--
-- Por qué: el front de la 386 lista las empresas por listar_empresas_pais, que no trae los datos del modal "Ver detalle"
-- (RUC/NIT, ciudad, dirección, logo) ni los 4 conteos que pintaba la página en 03f6ad7. Antes salían de una consulta
-- directa a empresas_proveedoras con embedding de PostgREST (EmpresasProveedorasPage.tsx:78-100 en 03f6ad7):
--   cuentas_count:cuentas_proveedor(count), productos_count:productos_empresa(count),
--   campanas_count:solicitudes_campana(count), pagos_count:pagos_proveedor(count)
-- El admin de país no ve empresas_proveedoras por RLS (0 filas), así que el detalle va por una RPC DEFINER, sin ampliar
-- policies ni grants de tabla.
--
-- Qué hace:
--   public.obtener_empresa_pais(p_empresa_id uuid) RETURNS TABLE: id, nombre_empresa, tipo, estado, pais_id, ruc_nit,
--   ciudad, direccion, email_contacto, telefono, logo_url, created_at y los 4 conteos (bigint). Cada conteo usa la FK
--   empresa_id -> empresas_proveedoras(id) de su tabla (la misma relación que resolvía el embedding) y cuenta TODAS las
--   filas, como las veía el super_admin, que era el único que llegaba a ver el modal con datos.
--   Gate idéntico al de resolver_empresa y ANTES de revelar existencia: sin sesión -> EP001; empresa inexistente o sin
--   autoridad sobre su país (super_admin, o admin_pais de ESE país por private.puede_admin_pais, COALESCE fail-closed)
--   -> EP002 con el mismo mensaje para los dos casos. Solo lectura (STABLE, ninguna escritura).
--   ACL: EXECUTE para authenticated y service_role; se revoca PUBLIC y anon.
--   El cuerpo de la función NO lleva líneas de comentario: harness_run.py las quita antes de enviar, y con una adentro
--   el md5(prosrc) de la corrida con la 387 inyectada no coincidiría con el del apply por `db query -f`.
--
-- Errores: reusa EP001 y EP002 de la 386 (mensajes en tú, sin eco de datos). Sin errcodes nuevos. MIG87 = guarda.
--
-- Huellas medidas el 17-nov-2026 16:39:08 UTC (estado post-386):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ........ dbbdc911a558d5287e51d7a242a75206 413
--   ACL de funciones (solo privilegios), public/private ............................. de2f5ecc9543965dcb4b799ade18a09c 413
--   ACL de relaciones de public ...................................................... 9b8f5af8892d3a5b87db15e15092eb77 2445
--   policies public/private/storage .................................................. 938d7e4111a9d332e6c55a645fafed86 314
-- Después: funciones completas y ACL de funciones se mueven SOLO por obtener_empresa_pais (sin ella siguen en
-- dbbdc911…/413 y de2f5ecc…/413; el total pasa a 414); relaciones y policies IDÉNTICAS.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/387_empresa_detalle_pais.sql
-- Rollback: supabase/migrations/387_rollback.sql (cadena: 387_rollback -> 386_rollback -> 385_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 387 no está aplicada
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'obtener_empresa_pais') THEN
    bad := bad||'obtener_empresa_pais ya existe (387 aplicada); ';
  END IF;
  -- la 386 aplicada y las funciones de las que depende, exactas (md5(prosrc) + SECURITY DEFINER + config + ACL)
  FOR r IN SELECT * FROM (VALUES
      ('public.listar_empresas_pais(uuid,text)', 'f554317d0b1b0976df9cca289b092ca4', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.resolver_empresa(uuid,text,text)', '25c8bd889bba705487e8a81516122b24', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.puede_admin_pais(uuid,text[])', '8bc2928e369d98e305355440df8b52ac', '{postgres=X/postgres,authenticated=X/postgres}')) AS t(firma, md5_vivo, acl)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_vivo||' true {"search_path=\"\""} '||r.acl THEN
      bad := bad||r.firma||' distinta de la medida ('||COALESCE(v, 'no existe')||'); ';
    END IF;
  END LOOP;
  -- las FKs de los 4 conteos: una sola columna empresa_id hacia empresas_proveedoras(id) en cada tabla
  FOR r IN SELECT unnest(ARRAY['cuentas_proveedor', 'productos_empresa', 'solicitudes_campana', 'pagos_proveedor']) AS t
  LOOP
    IF (SELECT count(*) FROM pg_constraint c
         WHERE c.conrelid = to_regclass('public.'||r.t) AND c.contype = 'f'
           AND c.confrelid = 'public.empresas_proveedoras'::regclass
           AND pg_get_constraintdef(c.oid) LIKE 'FOREIGN KEY (empresa_id) REFERENCES empresas_proveedoras(id)%') <> 1 THEN
      bad := bad||r.t||': no tiene exactamente una FK empresa_id -> empresas_proveedoras(id); ';
    END IF;
  END LOOP;

  -- huellas post-386 (17-nov-2026 16:39:08 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'dbbdc911a558d5287e51d7a242a75206 413' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'de2f5ecc9543965dcb4b799ade18a09c 413' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9b8f5af8892d3a5b87db15e15092eb77 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '938d7e4111a9d332e6c55a645fafed86 314' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG87: precondición: %', bad USING ERRCODE = 'MIG87';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) obtener_empresa_pais (solo lectura)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.obtener_empresa_pais(p_empresa_id uuid)
 RETURNS TABLE (id uuid, nombre_empresa text, tipo text, estado text, pais_id uuid, ruc_nit text, ciudad text,
                direccion text, email_contacto text, telefono text, logo_url text, created_at timestamptz,
                cuentas_count bigint, productos_count bigint, campanas_count bigint, pagos_count bigint)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path = ''
AS $fn$
DECLARE
  v_pais uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Tu sesión no está activa. Vuelve a iniciar sesión.' USING ERRCODE = 'EP001';
  END IF;

  SELECT e.pais_id INTO v_pais
    FROM public.empresas_proveedoras e
   WHERE e.id = p_empresa_id;
  IF NOT FOUND OR NOT COALESCE(private.puede_admin_pais(v_pais, ARRAY['super_admin'::text]), false) THEN
    RAISE EXCEPTION 'La empresa no existe o no puedes gestionarla.' USING ERRCODE = 'EP002';
  END IF;

  RETURN QUERY
  SELECT e.id, e.nombre_empresa, e.tipo, e.estado, e.pais_id, e.ruc_nit, e.ciudad, e.direccion, e.email_contacto,
         e.telefono, e.logo_url, e.created_at,
         (SELECT count(*) FROM public.cuentas_proveedor cp WHERE cp.empresa_id = e.id),
         (SELECT count(*) FROM public.productos_empresa pe WHERE pe.empresa_id = e.id),
         (SELECT count(*) FROM public.solicitudes_campana sc WHERE sc.empresa_id = e.id),
         (SELECT count(*) FROM public.pagos_proveedor pp WHERE pp.empresa_id = e.id)
    FROM public.empresas_proveedoras e
   WHERE e.id = p_empresa_id;
END
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) ACL (sin grants nuevos de tabla)
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.obtener_empresa_pais(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_empresa_pais(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'obtener_empresa_pais') <> 1 THEN bad := bad||'obtener_empresa_pais: sobrecargas <> 1; '; END IF;
  v := (SELECT p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||md5(p.prosrc)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.obtener_empresa_pais(uuid)'));
  IF v IS DISTINCT FROM 'true s {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} e2d732d47724d5bcc5fafd794334e4a1' THEN
    bad := bad||'obtener_empresa_pais '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF has_function_privilege('anon', 'public.obtener_empresa_pais(uuid)', 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;
  IF has_function_privilege('public', 'public.obtener_empresa_pais(uuid)', 'EXECUTE') THEN bad := bad||'PUBLIC con EXECUTE; '; END IF;

  -- funciones completas: solo se movió obtener_empresa_pais
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'obtener_empresa_pais');
  IF v IS DISTINCT FROM 'dbbdc911a558d5287e51d7a242a75206 413' THEN bad := bad||'cambió otra función (funciones completas sin la nueva) '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 414 THEN
    bad := bad||'el total de funciones no es 414; ';
  END IF;
  -- ACL de funciones: sin la nueva, idéntica
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname <> 'obtener_empresa_pais') y);
  IF v IS DISTINCT FROM 'de2f5ecc9543965dcb4b799ade18a09c 413' THEN bad := bad||'huella de ACL de funciones sin la nueva '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones de public: idéntica
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9b8f5af8892d3a5b87db15e15092eb77 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  -- policies: idénticas
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '938d7e4111a9d332e6c55a645fafed86 314' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- 0 DEFINER sin search_path (criterio de P931)
  IF EXISTS (SELECT 1 FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
               AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%')) THEN
    bad := bad||'hay funciones DEFINER sin search_path; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG87: autochequeo: %', bad USING ERRCODE = 'MIG87';
  END IF;
END $autochequeo$;

COMMIT;
