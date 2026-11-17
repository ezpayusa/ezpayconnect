-- =====================================================================================================================
-- ROLLBACK MIG 387 — DROP de public.obtener_empresa_pais(uuid); vuelve al estado post-386, exacto.
-- La función es de solo lectura: no hay datos que perder.
-- Va ANTES que 386_rollback (cadena: 387_rollback -> 386_rollback -> 385_rollback -> ...).
-- Si ya entró el front que llama a obtener_empresa_pais, revertir el front primero (si no, el detalle da 404/PGRST202).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/387_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- la 387 aplicada, exacta
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.obtener_empresa_pais(uuid)'));
  IF v IS DISTINCT FROM 'e2d732d47724d5bcc5fafd794334e4a1' THEN
    bad := bad||'obtener_empresa_pais no es la de la 387 ('||COALESCE(v, 'no existe')||'); ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'obtener_empresa_pais') <> 1 THEN
    bad := bad||'obtener_empresa_pais: sobrecargas <> 1; ';
  END IF;
  -- nada más se movió desde post-386: sin la función, las huellas son las de post-386
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'obtener_empresa_pais');
  IF v IS DISTINCT FROM 'dbbdc911a558d5287e51d7a242a75206 413' THEN bad := bad||'cambió otra función (funciones completas sin la 387) '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname <> 'obtener_empresa_pais') y);
  IF v IS DISTINCT FROM 'de2f5ecc9543965dcb4b799ade18a09c 413' THEN bad := bad||'huella de ACL de funciones sin la 387 '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG87 rollback: precondición: %', bad USING ERRCODE = 'MIG87';
  END IF;
END $precondicion$;

DROP FUNCTION public.obtener_empresa_pais(uuid);

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'obtener_empresa_pais') THEN bad := bad||'obtener_empresa_pais sigue existiendo; '; END IF;
  -- huellas: las de post-386 (17-nov-2026 16:39:08 UTC)
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
    RAISE EXCEPTION 'MIG87 rollback: autochequeo: %', bad USING ERRCODE = 'MIG87';
  END IF;
END $autochequeo$;

COMMIT;
