-- =====================================================================================================================
-- ROLLBACK DE LA MIG 389 — vuelve al estado post-388 EXACTO (guard con la exención del super_admin, policy
-- "Admin ezpay actualiza empresas", UPDATE de authenticated a nivel tabla, EXECUTE de notificar_empresa_estado para
-- authenticated). Va ANTES que 388_rollback.
--
-- La guarda exige el estado post-389 exacto en lo que toca la 389 y el resto sin cambio (mismas invariantes que el
-- autochequeo de la 389). El autochequeo exige las 4 huellas post-388 (17-nov-2026 19:56:19 UTC) y el guard con su md5
-- 2f248d00366785c4c1e569f814a7e27c.
-- OJO: el cuerpo del guard que se restaura es el VIVO post-386 letra por letra y trae 5 líneas de comentario adentro
-- (no se pueden sacar sin cambiar el md5). Por eso este rollback NO se puede inyectar en una corrida del harness
-- (harness_run.py quita las líneas de comentario y el md5 no daría): se aplica con `npx supabase db query --linked -f`.
-- Para restaurar el orden exacto del proacl de notificar_empresa_estado ({postgres, authenticated, service_role}) se
-- saca y se vuelve a dar service_role después de authenticated (la huella de funciones completas incluye proacl::text).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/389_rollback.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN: estado post-389
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('private.empresas_proveedoras_guard_update()'));
  IF v IS DISTINCT FROM '8e7102b67317e97ada88884ac7783b1e false {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'guard distinto del post-389 ('||COALESCE(v, 'no existe')||'); ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.empresas_proveedoras'::regclass AND pl.polname = 'Admin ezpay actualiza empresas') THEN
    bad := bad||'la policy Admin ezpay actualiza empresas existe (la 389 no está aplicada); ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.empresas_proveedoras'::regclass);
  IF v IS DISTINCT FROM '257c5ba14604d9baf3b37d81c0b2d80a 3' THEN bad := bad||'policies de la tabla '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de la tabla distinta de la post-389; ';
  END IF;
  v := (SELECT string_agg(a.attname||'='||a.attacl::text, '; ' ORDER BY a.attname)
          FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass AND a.attnum > 0 AND a.attacl IS NOT NULL);
  IF v IS DISTINCT FROM 'ciudad={authenticated=w/postgres}; direccion={authenticated=w/postgres}; email_contacto={authenticated=w/postgres}; nombre_empresa={authenticated=w/postgres}; ruc_nit={authenticated=w/postgres}; telefono={authenticated=w/postgres}' THEN
    bad := bad||'grants por columna '||COALESCE(v, '(ninguno)')||'; ';
  END IF;
  v := (SELECT md5(p.prosrc)||' '||COALESCE(p.proacl::text, '-') FROM pg_proc p WHERE p.oid = to_regprocedure('public.notificar_empresa_estado(uuid)'));
  IF v IS DISTINCT FROM '72cf7417810b164753223c49d88dc8c4 {postgres=X/postgres,service_role=X/postgres}' THEN bad := bad||'notificar_empresa_estado '||COALESCE(v, '-')||'; '; END IF;
  -- el resto, sin cambio desde la 389
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid NOT IN (to_regprocedure('private.empresas_proveedoras_guard_update()'), to_regprocedure('public.notificar_empresa_estado(uuid)')));
  IF v IS DISTINCT FROM '7fa35a9772eaa8febde0772a270d6803 413' THEN bad := bad||'cambió otra función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'empresas_proveedoras') x);
  IF v IS DISTINCT FROM '485ce08f3b5972d1ea24ed0c7d599062 2426' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '4b9da3e2955e1156feca9c8585c37fab 313' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG89: rollback, precondición: %', bad USING ERRCODE = 'MIG89';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Guard post-386 (cuerpo vivo exacto, md5 2f248d00366785c4c1e569f814a7e27c)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.empresas_proveedoras_guard_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = ''
AS $fn$
DECLARE v_exento boolean; v_rpc boolean;
BEGIN
  v_exento := current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin')
              OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false);
  -- mig 386: el camino de resolver_empresa (DEFINER de postgres que pone el GUC de transacción)
  v_rpc := current_user = 'postgres'
           AND COALESCE(pg_catalog.current_setting('app.resolver_empresa_rpc', true), '') = 'on';

  IF TG_OP = 'INSERT' THEN
    IF NOT v_exento AND NEW.estado IS DISTINCT FROM 'pendiente' THEN
      NEW.estado := 'pendiente';   -- toda empresa creada por un no-privilegiado nace pendiente
    END IF;
    -- mig 386: una empresa no nace revisada
    IF NOT v_rpc AND (NEW.motivo_rechazo IS NOT NULL OR NEW.revisado_por IS NOT NULL OR NEW.revisado_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Los datos de revisión de la empresa solo se escriben al resolverla'
        USING ERRCODE = '42501';
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

  -- mig 386: columnas de revisión, solo por resolver_empresa (para todos, super_admin incluido)
  IF ( NEW.motivo_rechazo IS DISTINCT FROM OLD.motivo_rechazo
    OR NEW.revisado_por   IS DISTINCT FROM OLD.revisado_por
    OR NEW.revisado_at    IS DISTINCT FROM OLD.revisado_at )
     AND NOT v_rpc THEN
    RAISE EXCEPTION 'Los datos de revisión de la empresa solo se escriben al resolverla'
      USING ERRCODE = '42501';
  END IF;

  -- mig 386: pendiente -> activa|rechazada por resolver_empresa o, hasta la 387, por un exento
  IF OLD.estado = 'pendiente' AND NEW.estado IN ('activa', 'rechazada') AND NOT (v_rpc OR v_exento) THEN
    RAISE EXCEPTION 'No autorizado a resolver la empresa'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Policy del super_admin (misma definición que antes de la 389)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE POLICY "Admin ezpay actualiza empresas" ON public.empresas_proveedoras
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin'::text));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) UPDATE de authenticated a nivel tabla (sin grants por columna)
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE UPDATE (nombre_empresa, ruc_nit, ciudad, direccion, email_contacto, telefono) ON public.empresas_proveedoras FROM authenticated;
GRANT UPDATE ON public.empresas_proveedoras TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) EXECUTE de notificar_empresa_estado para authenticated, con el orden exacto del proacl
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.notificar_empresa_estado(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.notificar_empresa_estado(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notificar_empresa_estado(uuid) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5) AUTOCHEQUEO: estado post-388 exacto
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('private.empresas_proveedoras_guard_update()'));
  IF v IS DISTINCT FROM '2f248d00366785c4c1e569f814a7e27c false {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'guard '||COALESCE(v, 'no existe')||'; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.empresas_proveedoras'::regclass);
  IF v IS DISTINCT FROM '2b53ef56aeca25f25ee491ca89d02ea7 4' THEN bad := bad||'policies de la tabla '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=rw/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'ACL de la tabla '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.empresas_proveedoras'::regclass), '-')||'; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass AND a.attnum > 0 AND a.attacl IS NOT NULL) THEN
    bad := bad||'quedaron grants por columna: '||(SELECT string_agg(a.attname||'='||a.attacl::text, '; ') FROM pg_attribute a WHERE a.attrelid = 'public.empresas_proveedoras'::regclass AND a.attnum > 0 AND a.attacl IS NOT NULL)||'; ';
  END IF;
  v := (SELECT md5(p.prosrc)||' '||COALESCE(p.proacl::text, '-') FROM pg_proc p WHERE p.oid = to_regprocedure('public.notificar_empresa_estado(uuid)'));
  IF v IS DISTINCT FROM '72cf7417810b164753223c49d88dc8c4 {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'notificar_empresa_estado '||COALESCE(v, '-')||'; '; END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'f8e2dd272b161f3f0d69f31b32c9c877 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '51d87b443777a680da5891b25fe41e6f 415' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
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
    RAISE EXCEPTION 'MIG89: rollback, autochequeo: %', bad USING ERRCODE = 'MIG89';
  END IF;
END $autochequeo$;

COMMIT;
