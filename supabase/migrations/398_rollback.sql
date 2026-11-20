-- =====================================================================================================================
-- ROLLBACK de la MIG 398 — facturas vuelve al estado post-397: UPDATE de tabla para authenticated, sin guard ni CHECKs, y
-- las 7 policies (con las 3 duplicadas y «Medico actualiza sus facturas» sin WITH CHECK).
--
-- Va ANTES que 397_rollback (y que el rollback de cualquier migración anterior). Las facturas que se hayan creado o
-- cambiado de estado con la 398 viva quedan como están (el rollback no toca datos).
--
-- Precondición (MIG98R): el estado que deja la 398, medido en el dry-run del 20-nov-2026 (cuerpo con 0 CR):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... ba00350e8ff79624e3e612b6272431ae 421
--   ACL de funciones (solo privilegios), public/private .......................... 709076959d684e3def1a793ea7956984 421
--   ACL de relaciones de public ................................................... b95ff92fa952c65cfcc50233099a8362 2445
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... 1af94c4bbdbe3a2f2ca7920a62432b5a 306
--   private.facturas_guard() md5(prosrc) a65a0861034d439de690c3885ec1a1b5, INVOKER, search_path vacío, EXECUTE solo postgres.
-- Autochequeo: las 5 huellas vuelven a las post-397 (77ae9f73…/420, 6eca74c6…/420, cf5c7c56…/2446, f889b7db…/238,
-- eba82b3f…/309); facturas con relacl authenticated=arw (en cualquier orden), sin attacl, sin triggers ni CHECKs.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/398_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.facturas_guard()'))
     IS DISTINCT FROM 'a65a0861034d439de690c3885ec1a1b5 false {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'private.facturas_guard distinto del de la 398; ';
  END IF;
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.facturas'::regclass)
     IS DISTINCT FROM 'authenticated=ar/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR (SELECT string_agg(a.attname||'='||a.attacl::text, ',' ORDER BY a.attnum) FROM pg_attribute a
          WHERE a.attrelid = 'public.facturas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
        IS DISTINCT FROM 'estado={authenticated=w/postgres}' THEN
    bad := bad||'privilegios de facturas distintos de los que deja la 398; ';
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
    RAISE EXCEPTION 'MIG98R: precondición: %', bad USING ERRCODE = 'MIG98';
  END IF;
END $precondicion$;

DROP TRIGGER trg_facturas_guard ON public.facturas;
DROP FUNCTION private.facturas_guard();

ALTER TABLE public.facturas
  DROP CONSTRAINT facturas_estado_valido,
  DROP CONSTRAINT facturas_cantidad_positiva,
  DROP CONSTRAINT facturas_precio_no_negativo,
  DROP CONSTRAINT facturas_descuento_valido;

-- REVOKE de tabla también quita el UPDATE (estado) por columna; después, UPDATE de tabla como antes de la 398.
REVOKE UPDATE ON TABLE public.facturas FROM authenticated;
GRANT UPDATE ON TABLE public.facturas TO authenticated;

DROP POLICY "Medico actualiza sus facturas" ON public.facturas;
CREATE POLICY "Medico actualiza sus facturas" ON public.facturas FOR UPDATE TO authenticated USING (medico_id = auth.uid());
CREATE POLICY medicos_actualizar_facturas ON public.facturas FOR UPDATE TO authenticated USING (medico_id = auth.uid());
CREATE POLICY medicos_crear_facturas ON public.facturas FOR INSERT TO authenticated WITH CHECK (medico_id = auth.uid());
CREATE POLICY medicos_ver_facturas ON public.facturas FOR SELECT TO authenticated USING (medico_id = auth.uid());

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.facturas'::regclass)
     IS DISTINCT FROM 'authenticated=arw/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.facturas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     OR EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.facturas'::regclass AND NOT t.tgisinternal)
     OR EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.facturas'::regclass AND c.contype = 'c') THEN
    bad := bad||'facturas no volvió al estado post-397 (privilegios, triggers o CHECKs); ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '77ae9f738b13c5b920383d0cf0bda746 420' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '6eca74c670156e3a2d290b96651fc30e 420' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'cf5c7c56aaf30e6dd11b8407134b70d3 2446' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG98R: autochequeo: %', bad USING ERRCODE = 'MIG98';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
