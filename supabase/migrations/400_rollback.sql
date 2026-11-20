-- =====================================================================================================================
-- ROLLBACK de la MIG 400 — expediente_notas vuelve al estado post-399: UPDATE de tabla para authenticated, sin privilegios
-- por columna, sin el trigger de país ni su función. El guard (private.expediente_notas_guardia) no se toca: la 400 tampoco
-- lo tocó.
--
-- Va ANTES que 399_rollback (y que el rollback de cualquier migración anterior). Las notas escritas con la 400 viva quedan
-- como están, con el pais_id que les puso el trigger (el rollback no toca datos).
--
-- Precondición (MIG00R): el estado que deja la 400, medido en el dry-run del 20-nov-2026 (txid 464684, cuerpos con 0 CR):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... f1581e8802f3a06dc7d1737c6aad51dd 424
--   ACL de funciones (solo privilegios), public/private .......................... d026ae246b0262142684e187b7b8710f 424
--   ACL de relaciones de public ................................................... d17d651fdbe1b592147983a9b133dbcf 2442
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... dabf9556bae56bcb910de70405314ad8 310
--   private.expediente_notas_fija_pais md5(prosrc) 95e689efe029bb47b6c9718f4e3c8d7b (DEFINER, search_path vacío, EXECUTE
--   solo postgres); expediente_notas con relacl authenticated=ar, UPDATE por columna en las 9 columnas del front y 3 triggers.
-- Autochequeo: las 5 huellas vuelven a las post-399 (c290831c…/423, a14a1f17…/423, 5fb4dc54…/2443, f889b7db…/238,
-- dabf9556…/310); expediente_notas con relacl authenticated=arw, sin attacl y con sus 2 triggers (el guard con su md5).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/400_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.expediente_notas_fija_pais()'))
     IS DISTINCT FROM '95e689efe029bb47b6c9718f4e3c8d7b true {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'private.expediente_notas_fija_pais distinta de la de la 400; ';
  END IF;
  IF (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgtype::text, ',' ORDER BY t.tgname COLLATE "C")
        FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_calcular_imc_expediente O 23,trg_expediente_notas_guardia O 23,trg_expediente_notas_pais O 23' THEN
    bad := bad||'triggers de expediente_notas distintos de los que deja la 400; ';
  END IF;
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.expediente_notas'::regclass)
     IS DISTINCT FROM 'authenticated=ar/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND a.attacl::text = '{authenticated=w/postgres}') <> 9
     OR (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND a.attacl IS NOT NULL) <> 9 THEN
    bad := bad||'privilegios de expediente_notas distintos de los que deja la 400; ';
  END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'f1581e8802f3a06dc7d1737c6aad51dd 424' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'd026ae246b0262142684e187b7b8710f 424' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd17d651fdbe1b592147983a9b133dbcf 2442' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
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
    RAISE EXCEPTION 'MIG00R: precondición: %', bad USING ERRCODE = 'MIG00';
  END IF;

  PERFORM set_config('mig400r.filas', (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.expediente_notas t), true);
END $precondicion$;

DROP TRIGGER trg_expediente_notas_pais ON public.expediente_notas;
DROP FUNCTION private.expediente_notas_fija_pais();
-- REVOKE de tabla también quita el UPDATE por columna; después, UPDATE de tabla como antes de la 400.
REVOKE UPDATE ON TABLE public.expediente_notas FROM authenticated;
GRANT UPDATE ON TABLE public.expediente_notas TO authenticated;

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.expediente_notas'::regclass)
     IS DISTINCT FROM 'authenticated=arw/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
    bad := bad||'privilegios de expediente_notas distintos de los post-399; ';
  END IF;
  IF to_regprocedure('private.expediente_notas_fija_pais()') IS NOT NULL
     OR (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgtype::text, ',' ORDER BY t.tgname COLLATE "C")
           FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND NOT t.tgisinternal)
        IS DISTINCT FROM 'trg_calcular_imc_expediente O 23,trg_expediente_notas_guardia O 23'
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.expediente_notas_guardia()')) IS DISTINCT FROM '950c36d4959f5568e3a6fbf351713541' THEN
    bad := bad||'triggers o funciones de expediente_notas distintos de los post-399; ';
  END IF;
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.expediente_notas t)
     IS DISTINCT FROM current_setting('mig400r.filas', true) THEN
    bad := bad||'cambiaron filas de expediente_notas; ';
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
    RAISE EXCEPTION 'MIG00R: autochequeo: %', bad USING ERRCODE = 'MIG00';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
