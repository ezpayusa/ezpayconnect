-- ############################################################################################
-- 371_rollback - deshace 371_textos_legales.sql (GL-02: catalogo, aceptaciones append-only y RPCs)
-- ############################################################################################
-- Va ANTES que 370_rollback (la precondicion de 370_rollback exige la ACL de funciones post-370 4878afd5.../384, y la
-- 371 la deja en 389). Orden global: 371_rollback -> 370_rollback -> 369_rollback -> ...
-- Exige revertir ANTES el front de GL-02: su gate falla cerrado sin las RPCs (D-11) y dejaria a todos afuera.
-- ABORTA si hay aceptaciones registradas: son evidencia legal y el rollback no la destruye en silencio. Si hace falta
-- revertir con filas, exportarlas primero y decidirlo aparte (el trigger LG005 impide borrarlas; el DROP TABLE no).
-- Precondicion: el estado post-371 exacto (huellas post-371, objetos presentes, censo de la 370). Autochequeo: las huellas
-- vuelven a las post-370 (policies 9ad61756.../307, relaciones 64ff833d.../2368, funciones 4878afd5.../384).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado post-371)
DO $precondicion$
DECLARE bad text := ''; v text; n int; r record;
BEGIN
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '4c1f611c29b8b37d8076536d065069e0 389' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 0 THEN bad := bad||n||' funciones con PUBLIC (esperado 0); '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  IF v IS DISTINCT FROM 'catalogo_planes_visitador_publico()' THEN bad := bad||'anon ejecuta ['||COALESCE(v, 'ninguna')||']; '; END IF;

  FOR r IN SELECT x.t FROM (VALUES ('public.textos_legales'), ('public.aceptaciones_legales')) x(t) LOOP
    IF to_regclass(r.t) IS NULL THEN bad := bad||r.t||' no existe; '; END IF;
  END LOOP;
  FOR r IN SELECT x.f FROM (VALUES ('public.aceptar_textos_legales(jsonb,text,text)'), ('public.textos_legales_pendientes()'),
      ('private.textos_legales_pendientes_de(uuid)'), ('private.textos_legales_al_dia(uuid)'),
      ('private.aceptaciones_legales_solo_append()')) x(f) LOOP
    IF to_regprocedure(r.f) IS NULL THEN bad := bad||r.f||' no existe; '; END IF;
  END LOOP;
  IF to_regclass('public.aceptaciones_legales') IS NOT NULL THEN
    n := (SELECT count(*) FROM public.aceptaciones_legales);
    IF n <> 0 THEN bad := bad||n||' aceptaciones registradas (exportarlas y decidir aparte; este rollback no las borra); '; END IF;
  END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK371 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- DROP en orden inverso (sin CASCADE)
DROP FUNCTION public.aceptar_textos_legales(jsonb, text, text);
DROP FUNCTION public.textos_legales_pendientes();
DROP FUNCTION private.textos_legales_al_dia(uuid);
DROP FUNCTION private.textos_legales_pendientes_de(uuid);
DROP TABLE public.aceptaciones_legales;          -- se lleva su policy, sus 2 triggers y su secuencia IDENTITY
DROP FUNCTION private.aceptaciones_legales_solo_append();
DROP TABLE public.textos_legales;                -- se lleva su policy y la semilla

-- ---------------------------------------------------------------------------- autochequeo (estado post-370)
DO $autochequeo$
DECLARE bad text := ''; v text; n int;
BEGIN
  IF to_regclass('public.textos_legales') IS NOT NULL OR to_regclass('public.aceptaciones_legales') IS NOT NULL THEN
    bad := bad||'quedan tablas de la 371; ';
  END IF;
  IF to_regclass('public.aceptaciones_legales_id_seq') IS NOT NULL THEN bad := bad||'queda la secuencia de aceptaciones_legales; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND p.proname IN ('aceptar_textos_legales', 'textos_legales_pendientes', 'textos_legales_pendientes_de',
                             'textos_legales_al_dia', 'aceptaciones_legales_solo_append'));
  IF v IS NOT NULL THEN bad := bad||'quedan funciones: '||v||'; '; END IF;

  n := (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
          AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));
  IF n <> 0 THEN bad := bad||n||' funciones con PUBLIC; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND has_function_privilege('anon', p.oid, 'EXECUTE'));
  IF v IS DISTINCT FROM 'catalogo_planes_visitador_publico()' THEN bad := bad||'anon ejecuta ['||COALESCE(v, 'ninguna')||']; '; END IF;

  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '64ff833d25666534b8de9171d1e5d404 2368' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '4878afd5e7fa74667b466d6994d565ff 384' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK371 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
