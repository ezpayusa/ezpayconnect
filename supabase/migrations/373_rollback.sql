-- ############################################################################################
-- Rollback de la migracion 373 - quita public.completar_registro_proveedor()
-- ############################################################################################
-- Precondicion: la funcion existe y registrar_proveedor tiene la huella de la 327/373
--   (md5(prosrc) fae23eeeacb393328f774386ccd88479), que la 373 no toca.
-- Autochequeo: la funcion ya no existe, registrar_proveedor sigue con la misma huella y las 3 huellas
--   globales vuelven a las post-372 exactas (mismo calculo que la 372): ACL de funciones
--   5482f6de564741ad445f30d3ccbd9a79/391, policies 8a8dc5cfaf8365f95208fb9e8ba79674/309 y ACL de
--   relaciones de public d065decfec14c0afae8f5d898032e4bb/2394.
-- Efecto de producto: con Confirm email ON el autorregistro de empresas vuelve a fallar en
--   registrar_proveedor ('Usuario no autenticado'). Revertir tambien el front que la llama.
-- ############################################################################################

BEGIN;

DO $$
DECLARE
  v text := '';
BEGIN
  IF to_regprocedure('public.completar_registro_proveedor()') IS NULL THEN
    v := v||E'\n public.completar_registro_proveedor() no existe';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'))
     IS DISTINCT FROM 'fae23eeeacb393328f774386ccd88479' THEN
    v := v||E'\n registrar_proveedor no tiene la huella esperada (md5 fae23eee...)';
  END IF;
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK373 PRECONDICION:%', v; END IF;
END
$$;

DROP FUNCTION public.completar_registro_proveedor();

DO $$
DECLARE
  v text := '';
  h text;
BEGIN
  IF to_regprocedure('public.completar_registro_proveedor()') IS NOT NULL THEN
    v := v||E'\n public.completar_registro_proveedor() sigue existiendo';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)'))
     IS DISTINCT FROM 'fae23eeeacb393328f774386ccd88479' THEN
    v := v||E'\n registrar_proveedor cambio de cuerpo';
  END IF;
  h := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF h IS DISTINCT FROM '5482f6de564741ad445f30d3ccbd9a79 391' THEN v := v||E'\n ACL de funciones '||COALESCE(h, '-')||' (esperado 5482f6de.../391)'; END IF;
  h := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF h IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN v := v||E'\n huella de policies '||COALESCE(h, '-')||' (esperado 8a8dc5cf.../309)'; END IF;
  h := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF h IS DISTINCT FROM 'd065decfec14c0afae8f5d898032e4bb 2394' THEN v := v||E'\n ACL de relaciones de public '||COALESCE(h, '-')||' (esperado d065decf.../2394)'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'ROLLBACK373 AUTOCHEQUEO FALLA:%', v; END IF;
END
$$;

COMMIT;
