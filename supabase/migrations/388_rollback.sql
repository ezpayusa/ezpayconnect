-- =====================================================================================================================
-- ROLLBACK MIG 388 — DROP de public.cambiar_estado_empresa(uuid, text); vuelve al estado post-387, exacto.
-- Los cambios de estado que ya se hicieron por la RPC (empresas suspendidas, reactivadas o reabiertas) y sus avisos
-- QUEDAN: el rollback solo retira la función, no revierte datos.
-- Va ANTES que 387_rollback (cadena: 388_rollback -> 387_rollback -> 386_rollback -> ...).
-- Si ya entró el front que llama a cambiar_estado_empresa, revertir el front primero (si no, Suspender/Reactivar/Reabrir
-- dan 404/PGRST202). Si ya se aplicó la 389, revertir la 389 primero (su precondición exige esta función).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/388_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- la 388 aplicada, exacta
  v := (SELECT p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||md5(p.prosrc)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.cambiar_estado_empresa(uuid,text)'));
  IF v IS DISTINCT FROM 'true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} be01192509075ca4acb18cfc8c6502ab' THEN
    bad := bad||'cambiar_estado_empresa no es la de la 388 ('||COALESCE(v, 'no existe')||'); ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'cambiar_estado_empresa') <> 1 THEN
    bad := bad||'cambiar_estado_empresa: sobrecargas <> 1; ';
  END IF;
  -- nada más se movió desde post-387: sin la función, las huellas son las de post-387
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'cambiar_estado_empresa');
  IF v IS DISTINCT FROM '6ef5bdb38d4a4a33a594943ad611865d 414' THEN bad := bad||'cambió otra función (funciones completas sin la 388) '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname <> 'cambiar_estado_empresa') y);
  IF v IS DISTINCT FROM 'faf529bf0e6934677f743e35fa899f8d 414' THEN bad := bad||'huella de ACL de funciones sin la 388 '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG88 rollback: precondición: %', bad USING ERRCODE = 'MIG88';
  END IF;
END $precondicion$;

DROP FUNCTION public.cambiar_estado_empresa(uuid, text);

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'cambiar_estado_empresa') THEN bad := bad||'cambiar_estado_empresa sigue existiendo; '; END IF;
  -- huellas: las de post-387 (17-nov-2026 18:18:45 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '6ef5bdb38d4a4a33a594943ad611865d 414' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'faf529bf0e6934677f743e35fa899f8d 414' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
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
    RAISE EXCEPTION 'MIG88 rollback: autochequeo: %', bad USING ERRCODE = 'MIG88';
  END IF;
END $autochequeo$;

COMMIT;
