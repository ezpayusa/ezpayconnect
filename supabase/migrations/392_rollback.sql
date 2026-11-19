-- =====================================================================================================================
-- ROLLBACK DE LA MIG 392 — vuelve al estado post-391 EXACTO de public.clinicas: INSERT/UPDATE/DELETE de tabla para
-- authenticated, las 3 policies de escritura del dueño ("Doctores pueden crear/actualizar/eliminar ...") y "Admin ve
-- clinicas de su pais" como ALL (mismo USING, sin WITH CHECK). La 392 no tocó funciones ni secuencias.
-- Va ANTES que 391_rollback.
--
-- La guarda exige el estado post-392 exacto en clinicas y el resto sin cambio. El GRANT devuelve a authenticated=arwd en
-- su mismo lugar del relacl ({postgres, authenticated, service_role}): authenticated=r sigue ahí y el GRANT lo amplía.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/392_rollback.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN: estado post-392
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.clinicas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de clinicas distinto del post-392; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.clinicas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; doctor_id=-; nombre=-; direccion=-; telefono=-; email=-; horarios=-; activa=-; created_at=-; updated_at=-; pais_id=-; logo_url=-; color_primario=-; color_secundario=-; color_fondo=-' THEN
    bad := bad||'attacl de clinicas distinto del post-392; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.clinicas'::regclass);
  IF v IS DISTINCT FROM 'c5c8342eb321cebc7b49c1930b934ec9 4' THEN bad := bad||'policies de clinicas distintas del post-392 ('||COALESCE(v, '-')||'); '; END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'ba4eb8a509c74d2ff82d61193ec6c201 415' THEN bad := bad||'cambió una función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'clinicas') x);
  IF v IS DISTINCT FROM 'b3db143c292843ccbc3f1279badea2b1 2418' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'fdaa79023984e271fe2922f357fb7a98 232' THEN bad := bad||'cambió la ACL de alguna secuencia '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.clinicas'::regclass) y);
  IF v IS DISTINCT FROM '0598c3a5369c356715e17f45ef26fc14 304' THEN bad := bad||'cambió una policy de otra tabla '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG92: rollback, precondición: %', bad USING ERRCODE = 'MIG92';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Privilegios de antes
-- ---------------------------------------------------------------------------------------------------------------------
GRANT INSERT, UPDATE, DELETE ON public.clinicas TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Policies de antes de la 392
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY "Admin ve clinicas de su pais" ON public.clinicas;
CREATE POLICY "Admin ve clinicas de su pais" ON public.clinicas
  AS PERMISSIVE FOR ALL TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text)
         OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

CREATE POLICY "Doctores pueden crear clinicas" ON public.clinicas
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (doctor_id = auth.uid());

CREATE POLICY "Doctores pueden actualizar sus clinicas" ON public.clinicas
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (doctor_id = auth.uid());

CREATE POLICY "Doctores pueden eliminar sus clinicas" ON public.clinicas
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (doctor_id = auth.uid());

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO: estado post-391 exacto
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.clinicas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de clinicas '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.clinicas'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.clinicas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; doctor_id=-; nombre=-; direccion=-; telefono=-; email=-; horarios=-; activa=-; created_at=-; updated_at=-; pais_id=-; logo_url=-; color_primario=-; color_secundario=-; color_fondo=-' THEN
    bad := bad||'attacl de clinicas cambió; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.clinicas'::regclass);
  IF v IS DISTINCT FROM '66d88cbf341b3d8607949fd024e865ff 7' THEN bad := bad||'policies de clinicas '||COALESCE(v, '-')||'; '; END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'ba4eb8a509c74d2ff82d61193ec6c201 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '09f3ee5bed234919c828c33092abced8 2438' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'fdaa79023984e271fe2922f357fb7a98 232' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'cc5aec00f4bf6e8c88925aa44cf64b4e 311' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG92: rollback, autochequeo: %', bad USING ERRCODE = 'MIG92';
  END IF;
END $autochequeo$;

COMMIT;
