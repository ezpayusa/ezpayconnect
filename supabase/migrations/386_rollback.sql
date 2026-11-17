-- =====================================================================================================================
-- ROLLBACK MIG 386 — vuelve empresas_proveedoras y su guard al estado post-385, exacto.
--   - DROP de public.resolver_empresa(uuid,text,text) y public.listar_empresas_pais(uuid,text);
--   - private.empresas_proveedoras_guard_update con su cuerpo previo EXACTO (md5(prosrc) 9737a58927e36a2355b592fd1861f8a5);
--   - DROP del CHECK empresas_proveedoras_motivo_rechazo_chk, de la FK empresas_proveedoras_revisado_por_fkey y de las
--     columnas motivo_rechazo, revisado_por y revisado_at.
-- ABORTA (MIG86) si alguna empresa ya tiene datos de revisión (motivo_rechazo, revisado_por o revisado_at cargados): el
-- DROP de columnas los perdería. Antes de correrlo con datos reales hay que exportarlos y decidir.
-- Va ANTES que 385_rollback (cadena: 386_rollback -> 385_rollback -> 384_rollback -> ...).
-- Si ya entró el front que llama a las 2 RPCs, revertir el front primero.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/386_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 386 aplicada, exacta
  FOR r IN SELECT * FROM (VALUES
      ('private.empresas_proveedoras_guard_update()', '2f248d00366785c4c1e569f814a7e27c'),
      ('public.listar_empresas_pais(uuid,text)', 'f554317d0b1b0976df9cca289b092ca4'),
      ('public.resolver_empresa(uuid,text,text)', '25c8bd889bba705487e8a81516122b24')) AS t(firma, md5_esperado)
  LOOP
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_esperado THEN bad := bad||r.firma||' no es la de la 386 ('||COALESCE(v, 'no existe')||'); '; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass
        AND a.attname IN ('motivo_rechazo', 'revisado_por', 'revisado_at') AND NOT a.attisdropped) <> 3 THEN
    bad := bad||'faltan columnas de revisión de la 386; ';
  ELSIF EXISTS (SELECT 1 FROM public.empresas_proveedoras e
                 WHERE e.motivo_rechazo IS NOT NULL OR e.revisado_por IS NOT NULL OR e.revisado_at IS NOT NULL) THEN
    bad := bad||'hay empresas con datos de revisión: el DROP de columnas los perdería (exportarlos y decidir antes); ';
  END IF;
  -- funciones completas: solo se movieron las 2 nuevas y el guard
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname NOT IN ('listar_empresas_pais', 'resolver_empresa', 'empresas_proveedoras_guard_update'));
  IF v IS DISTINCT FROM 'f0a72054b27c11410c469b59336f46ac 410' THEN bad := bad||'cambió otra función (funciones completas sin las 3) '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 413 THEN
    bad := bad||'el total de funciones no es 413; ';
  END IF;
  -- ACL de funciones: sin las 2 nuevas, idéntica
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname NOT IN ('listar_empresas_pais', 'resolver_empresa')) y);
  IF v IS DISTINCT FROM 'af6b7bf22f370f6ee5ff89ff59eb0ea5 411' THEN bad := bad||'huella de ACL de funciones sin las 2 nuevas '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de relaciones de public: idéntica (ADD COLUMN no toca relacl ni crea ACL por columna)
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

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG86 rollback: precondición: %', bad USING ERRCODE = 'MIG86';
  END IF;
END $precondicion$;

DROP FUNCTION public.resolver_empresa(uuid, text, text);
DROP FUNCTION public.listar_empresas_pais(uuid, text);

CREATE OR REPLACE FUNCTION private.empresas_proveedoras_guard_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = ''
AS $fn$
DECLARE v_exento boolean;
BEGIN
  v_exento := current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin')
              OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false);

  IF TG_OP = 'INSERT' THEN
    IF NOT v_exento AND NEW.estado IS DISTINCT FROM 'pendiente' THEN
      NEW.estado := 'pendiente';   -- toda empresa creada por un no-privilegiado nace pendiente
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF ( NEW.estado                     IS DISTINCT FROM OLD.estado
    OR NEW.tipo                       IS DISTINCT FROM OLD.tipo
    OR NEW.pais_id                    IS DISTINCT FROM OLD.pais_id
    OR NEW.dias_ventaja_reserva       IS DISTINCT FROM OLD.dias_ventaja_reserva
    OR NEW.ventana_prioridad_visitas  IS DISTINCT FROM OLD.ventana_prioridad_visitas )
  THEN
    IF NOT v_exento THEN
      RAISE EXCEPTION 'No autorizado a modificar estado/tipo/pais/plan de la empresa'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $fn$;

ALTER TABLE public.empresas_proveedoras
  DROP CONSTRAINT empresas_proveedoras_motivo_rechazo_chk,
  DROP CONSTRAINT empresas_proveedoras_revisado_por_fkey,
  DROP COLUMN motivo_rechazo,
  DROP COLUMN revisado_por,
  DROP COLUMN revisado_at;

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname IN ('listar_empresas_pais', 'resolver_empresa')) THEN
    bad := bad||'quedan RPCs de la 386; ';
  END IF;
  v := (SELECT p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||md5(p.prosrc)
          FROM pg_proc p WHERE p.oid = to_regprocedure('private.empresas_proveedoras_guard_update()'));
  IF v IS DISTINCT FROM 'false {"search_path=\"\""} {postgres=X/postgres} 9737a58927e36a2355b592fd1861f8a5' THEN bad := bad||'guard '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(c.conname, ',' ORDER BY c.conname) FROM pg_constraint c WHERE c.conrelid = 'public.empresas_proveedoras'::regclass);
  IF v IS DISTINCT FROM 'empresas_proveedoras_estado_chk,empresas_proveedoras_pais_id_fkey,empresas_proveedoras_pkey,empresas_proveedoras_tipo_check' THEN
    bad := bad||'constraints '||COALESCE(v, '-')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass AND a.attnum > 0 AND NOT a.attisdropped) <> 18 THEN
    bad := bad||'empresas_proveedoras no tiene las 18 columnas de antes; ';
  END IF;
  -- huellas: las de post-385 (27-oct-2026 19:11:18 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'cb4ab540ceea52520740a6e03133522e 411' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'af6b7bf22f370f6ee5ff89ff59eb0ea5 411' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
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
    RAISE EXCEPTION 'MIG86 rollback: autochequeo: %', bad USING ERRCODE = 'MIG86';
  END IF;
END $autochequeo$;

COMMIT;
