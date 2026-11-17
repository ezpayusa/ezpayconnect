-- =====================================================================================================================
-- ROLLBACK DE LA MIG 390 — vuelve al estado post-389 EXACTO de public.medicos: INSERT/UPDATE/DELETE de tabla para
-- authenticated, policy medicos_update_propio, y "Admin ve medicos de su pais" / medicos_admin_clinica como ALL (la segunda
-- con su WITH CHECK explícito). Va ANTES que 389_rollback.
--
-- La guarda exige el estado post-390 exacto en medicos y el resto sin cambio. El autochequeo exige el relacl y las 5
-- policies exactas de antes (md5 b6ae15146d9eb9afb43d15e6c94ef727 5) y las 4 huellas post-389.
-- Para que el relacl vuelva con el mismo ORDEN ({postgres, authenticated, service_role}) se saca y se vuelve a dar ALL a
-- service_role después de authenticated (el autochequeo compara el texto del relacl).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/390_rollback.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN: estado post-390
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de medicos distinto del post-390; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polname = 'medicos_update_propio') THEN
    bad := bad||'medicos_update_propio existe (la 390 no está aplicada); ';
  END IF;
  IF (SELECT count(*) FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass) <> 4
     OR EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polcmd <> 'r') THEN
    bad := bad||'medicos no tiene las 4 policies SELECT del post-390; ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'b7fa10f3493ad056a9ccba88db348511 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'medicos') x);
  IF v IS DISTINCT FROM '4dc4aa6105a3ec55c413ffdb0630de6f 2425' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.medicos'::regclass) y);
  IF v IS DISTINCT FROM 'bf1bfba9adf6f04c20939687ed68cbc6 308' THEN bad := bad||'cambió una policy de otra tabla '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG90: rollback, precondición: %', bad USING ERRCODE = 'MIG90';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Privilegios de tabla de authenticated, con el orden exacto del relacl
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON public.medicos FROM service_role;
GRANT INSERT, UPDATE, DELETE ON public.medicos TO authenticated;
GRANT ALL ON public.medicos TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Policies de antes de la 390
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY "Admin ve medicos de su pais" ON public.medicos;
CREATE POLICY "Admin ve medicos de su pais" ON public.medicos
  AS PERMISSIVE FOR ALL TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text)
         OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

DROP POLICY medicos_admin_clinica ON public.medicos;
CREATE POLICY medicos_admin_clinica ON public.medicos
  AS PERMISSIVE FOR ALL TO authenticated
  USING (private.tiene_rol(ARRAY['admin_clinica'::text, 'gerente'::text])
         AND (clinica_id IN (SELECT private.clinicas_del_usuario() AS clinicas_del_usuario)))
  WITH CHECK (private.tiene_rol(ARRAY['admin_clinica'::text, 'gerente'::text])
              AND (clinica_id IN (SELECT private.clinicas_del_usuario() AS clinicas_del_usuario)));

CREATE POLICY medicos_update_propio ON public.medicos
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO: estado post-389 exacto
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=awd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de medicos '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id={authenticated=r/postgres}; clinica_id={authenticated=r/postgres}; nombre_completo={authenticated=r/postgres}; especialidad={authenticated=r/postgres}; telefono={authenticated=r/postgres}; email={authenticated=r/postgres}; cedula_profesional={authenticated=r/postgres}; horario_atencion={authenticated=r/postgres}; activo={authenticated=r/postgres}; created_at={authenticated=r/postgres}; updated_at={authenticated=r/postgres}; pais_id={authenticated=r/postgres}; foto_url={authenticated=r/postgres}; especialidad_id={authenticated=r/postgres}; lab_enrolador_id=-; lab_enrolador_fecha=-' THEN
    bad := bad||'attacl de medicos cambió; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass);
  IF v IS DISTINCT FROM 'b6ae15146d9eb9afb43d15e6c94ef727 5' THEN bad := bad||'policies de medicos '||COALESCE(v, '-')||'; '; END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'b7fa10f3493ad056a9ccba88db348511 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '3cf6dfbb1762182068245ac7c3e816f8 2444' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '4b9da3e2955e1156feca9c8585c37fab 313' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG90: rollback, autochequeo: %', bad USING ERRCODE = 'MIG90';
  END IF;
END $autochequeo$;

COMMIT;
