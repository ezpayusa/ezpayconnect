-- =====================================================================================================================
-- ROLLBACK de la MIG 397 — devuelve el SELECT de TABLA de authenticated sobre recetas_avanzadas y dispensaciones.
--
-- Va ANTES que 396_rollback (y que el rollback de cualquier migración anterior).
-- LA ROTACIÓN NO SE REVIERTE: los dispatch_token y confirmacion_token que la 397 regeneró quedan como están (los viejos
-- no se guardaron y no deben volver: estuvieron expuestos). Solo vuelven los privilegios.
-- Con este rollback, authenticated vuelve a leer los tokens por SELECT directo (el estado post-396): el front del paciente
-- sigue funcionando igual (lee el token por mis_despachos_receta).
--
-- Precondición (MIG97R): el estado que deja la 397, medido en el dry-run del 20-nov-2026:
--   recetas_avanzadas y dispensaciones con relacl {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres} (sin
--   authenticated) y SELECT por columna para authenticated en todas las columnas MENOS dispatch_token y confirmacion_token
--   (recetas_avanzadas) y codigo_qr (dispensaciones); huellas:
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... 77ae9f738b13c5b920383d0cf0bda746 420
--   ACL de funciones (solo privilegios), public/private .......................... 6eca74c670156e3a2d290b96651fc30e 420
--   ACL de relaciones de public ................................................... cf5c7c56aaf30e6dd11b8407134b70d3 2446
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... eba82b3fc822926313534f04caa4f853 309
-- Autochequeo: relacl con authenticated=r (en cualquier orden), sin attacl, y la ACL de relaciones de public vuelve a
-- 88e7fd697ef0703f8f1deb153e9c68d0 2448 (post-396).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/397_rollback.sql
-- =====================================================================================================================

BEGIN;

DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('public.recetas_avanzadas', '{dispatch_token,confirmacion_token}'::text[]),
                                 ('public.dispensaciones', '{codigo_qr}'::text[])) AS t(tabla, tokens) LOOP
    IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = r.tabla::regclass)
       IS DISTINCT FROM 'postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres' THEN
      bad := bad||'relacl de '||r.tabla||' distinto del que deja la 397; ';
    END IF;
    v := (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
           WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped
             AND COALESCE(a.attacl::text, '-') IS DISTINCT FROM CASE WHEN a.attname = ANY (r.tokens) THEN '-' ELSE '{authenticated=r/postgres}' END);
    IF v IS NOT NULL THEN bad := bad||'attacl de '||r.tabla||' distinto del que deja la 397 en: '||v||'; '; END IF;
  END LOOP;

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
    RAISE EXCEPTION 'MIG97R: precondición: %', bad USING ERRCODE = 'MIG97';
  END IF;
END $precondicion$;

-- REVOKE de tabla también revoca los privilegios por columna; después, SELECT de tabla como antes de la 397.
REVOKE SELECT ON TABLE public.recetas_avanzadas FROM authenticated;
GRANT SELECT ON TABLE public.recetas_avanzadas TO authenticated;
REVOKE SELECT ON TABLE public.dispensaciones FROM authenticated;
GRANT SELECT ON TABLE public.dispensaciones TO authenticated;

DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('public.recetas_avanzadas'), ('public.dispensaciones')) AS t(tabla) LOOP
    IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = r.tabla::regclass)
       IS DISTINCT FROM 'authenticated=r/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
       OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = r.tabla::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN
      bad := bad||'relacl o attacl de '||r.tabla||' no volvieron al estado post-396; ';
    END IF;
  END LOOP;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '88e7fd697ef0703f8f1deb153e9c68d0 2448' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG97R: autochequeo: %', bad USING ERRCODE = 'MIG97';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
