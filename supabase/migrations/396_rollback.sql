-- =====================================================================================================================
-- ROLLBACK de la MIG 396 — DROP de public.mis_despachos_receta().
--
-- Va ANTES que 395_rollback (y que el rollback de cualquier migración anterior). Si la 397 (cierre del SELECT por columna
-- de los tokens) está aplicada, primero va 397_rollback: sin esta función, el paciente no tiene cómo leer su token.
-- Antes de correrlo, el front del paciente tiene que volver a leer el token por SELECT directo (revert del commit
-- «fix(paciente): el QR de despacho sale de mis_despachos_receta»): sin la RPC, ese front deja de mostrar el QR.
--
-- Precondición (MIG96R): la función existe tal como la dejó la 396 (firma, retorno, cuerpo, DEFINER, STABLE,
-- search_path vacío, ACL) y las huellas son las post-396 medidas en el dry-run del 20-nov-2026:
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... 77ae9f738b13c5b920383d0cf0bda746 420
--   ACL de funciones (solo privilegios), public/private .......................... 6eca74c670156e3a2d290b96651fc30e 420
--   ACL de relaciones de public ................................................... 88e7fd697ef0703f8f1deb153e9c68d0 2448
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... eba82b3fc822926313534f04caa4f853 309
-- Autochequeo: las huellas vuelven a las post-395 (d20a1172…/419, 311350db…/419; relaciones, secuencias y policies igual).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/396_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'mis_despachos_receta') <> 1 THEN
    bad := bad||'mis_despachos_receta no tiene exactamente una sobrecarga; ';
  END IF;
  v := (SELECT pg_get_function_identity_arguments(p.oid)||' -> '||pg_get_function_result(p.oid)||' '||md5(p.prosrc)||' '||p.prosecdef::text||' '||
               p.provolatile::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.mis_despachos_receta()'));
  IF v IS DISTINCT FROM ' -> TABLE(receta_id bigint, dispatch_token text, dispatch_token_expira_at timestamp with time zone, estado_dispensacion text) 3e0fe1250d0c85b7ac7daeab3344ff35 true s {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'mis_despachos_receta distinta de la de la 396 ('||COALESCE(v, 'no existe')||'); ';
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
  IF v IS DISTINCT FROM '88e7fd697ef0703f8f1deb153e9c68d0 2448' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||' (¿la 397 sigue aplicada?); '; END IF;
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
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG96R: precondición: %', bad USING ERRCODE = 'MIG96';
  END IF;
END $precondicion$;

DROP FUNCTION public.mis_despachos_receta();

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'mis_despachos_receta') THEN
    bad := bad||'mis_despachos_receta sigue existiendo; ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'd20a117271a2a187c6f461b1af1d8014 419' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '311350dbe0717e9737372034623b434b 419' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG96R: autochequeo: %', bad USING ERRCODE = 'MIG96';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
