-- =====================================================================================================================
-- ROLLBACK de la MIG 399 — disponibilidad_medico vuelve al estado post-398: INSERT y UPDATE de tabla para authenticated,
-- sin privilegios por columna, sin guard ni la función de validación, y las 2 policies ALL originales en lugar de las 6
-- partidas.
--
-- Va ANTES que 398_rollback (y que el rollback de cualquier migración anterior). Las franjas que se hayan creado con la 399
-- viva quedan como están, con el pais_id que les puso el guard (el rollback no toca datos).
--
-- Precondición (MIG99R): el estado que deja la 399, medido en el dry-run del 20-nov-2026 (cuerpos con 0 CR):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... c290831c4ccc8e33706d9097a5d97182 423
--   ACL de funciones (solo privilegios), public/private .......................... a14a1f17ee0fc72d9271147e4925297e 423
--   ACL de relaciones de public ................................................... 5fb4dc549e169a4129f72d9d92e3113b 2443
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... dabf9556bae56bcb910de70405314ad8 310
--   private.disponibilidad_medico_pais md5(prosrc) 0c623026703eae1c8a6380fb3cec9bcf (DEFINER, EXECUTE postgres y
--   authenticated); private.disponibilidad_medico_guard md5(prosrc) a8b697e85dc0e3d40d80360ade2900ed (INVOKER, EXECUTE solo
--   postgres).
-- Autochequeo: las 5 huellas vuelven a las post-398 (ba00350e…/421, 70907695…/421, b95ff92f…/2445, f889b7db…/238,
-- 1af94c4b…/306); disponibilidad_medico con relacl authenticated=arwd, sin attacl ni triggers, y sus 5 policies (md5 del
-- listado ed98dda92e5bf94706ad470ee90b1967).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/399_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||
             (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM unnest(p.proacl) x)
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.disponibilidad_medico_pais(uuid,uuid)'))
     IS DISTINCT FROM '0c623026703eae1c8a6380fb3cec9bcf true {"search_path=\"\""} authenticated=X/postgres,postgres=X/postgres' THEN
    bad := bad||'private.disponibilidad_medico_pais distinta de la de la 399; ';
  END IF;
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.disponibilidad_medico_guard()'))
     IS DISTINCT FROM 'a8b697e85dc0e3d40d80360ade2900ed false {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'private.disponibilidad_medico_guard distinto del de la 399; ';
  END IF;
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.disponibilidad_medico'::regclass)
     IS DISTINCT FROM 'authenticated=rd/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = 'public.disponibilidad_medico'::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND a.attacl::text = '{authenticated=a/postgres}') <> 8
     OR (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = 'public.disponibilidad_medico'::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND a.attacl IS NOT NULL) <> 8 THEN
    bad := bad||'privilegios de disponibilidad_medico distintos de los que deja la 399; ';
  END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'c290831c4ccc8e33706d9097a5d97182 423' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'a14a1f17ee0fc72d9271147e4925297e 423' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '5fb4dc549e169a4129f72d9d92e3113b 2443' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'dabf9556bae56bcb910de70405314ad8 310' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG99R: precondición: %', bad USING ERRCODE = 'MIG99';
  END IF;
END $precondicion$;

DROP TRIGGER trg_disponibilidad_medico_guard ON public.disponibilidad_medico;
DROP FUNCTION private.disponibilidad_medico_guard();
DROP FUNCTION private.disponibilidad_medico_pais(uuid, uuid);

DROP POLICY "Médico ve su disponibilidad" ON public.disponibilidad_medico;
DROP POLICY "Médico crea su disponibilidad" ON public.disponibilidad_medico;
DROP POLICY "Médico borra su disponibilidad" ON public.disponibilidad_medico;
DROP POLICY "Admin clinica ve disponibilidad de sus medicos" ON public.disponibilidad_medico;
DROP POLICY "Admin clinica crea disponibilidad de sus medicos" ON public.disponibilidad_medico;
DROP POLICY "Admin clinica borra disponibilidad de sus medicos" ON public.disponibilidad_medico;
CREATE POLICY "Médico gestiona su disponibilidad" ON public.disponibilidad_medico
  FOR ALL TO authenticated USING (medico_id = auth.uid());
CREATE POLICY "Admin clinica gestiona disponibilidad de sus medicos" ON public.disponibilidad_medico
  FOR ALL TO authenticated USING (public.admin_clinica_de_medico(medico_id)) WITH CHECK (public.admin_clinica_de_medico(medico_id));

-- REVOKE de tabla también quita el INSERT por columna; después, INSERT y UPDATE de tabla como antes de la 399.
REVOKE INSERT ON TABLE public.disponibilidad_medico FROM authenticated;
GRANT INSERT, UPDATE ON TABLE public.disponibilidad_medico TO authenticated;

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.disponibilidad_medico'::regclass)
     IS DISTINCT FROM 'authenticated=arwd/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.disponibilidad_medico'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     OR EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.disponibilidad_medico'::regclass AND NOT t.tgisinternal) THEN
    bad := bad||'disponibilidad_medico no volvió al estado post-398 (privilegios o triggers); ';
  END IF;
  IF (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                            COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C"))
        FROM pg_policy pl WHERE pl.polrelid = 'public.disponibilidad_medico'::regclass)
     IS DISTINCT FROM 'ed98dda92e5bf94706ad470ee90b1967' THEN
    bad := bad||'policies de disponibilidad_medico distintas de las post-398; ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'ba00350e8ff79624e3e612b6272431ae 421' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '709076959d684e3def1a793ea7956984 421' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'b95ff92fa952c65cfcc50233099a8362 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '1af94c4bbdbe3a2f2ca7920a62432b5a 306' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG99R: autochequeo: %', bad USING ERRCODE = 'MIG99';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
