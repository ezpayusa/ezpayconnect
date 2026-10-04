-- ############################################################################################
-- 362 ROLLBACK - saca el catalogo publico de planes de visitador
-- ############################################################################################
-- DROP de public.catalogo_planes_visitador_publico(). La allowlist de anon (P739) vive en el harness, no en la base: con
-- este rollback aplicado, P739 marca la funcion como "falta" hasta que se saque de su lista, y P996-P1000 dan ROJO o FALLO.
-- Precondicion: la 362 esta viva (catalogo y md5 de la funcion). Autochequeo: la funcion no existe y la huella de ACL de
-- funciones vuelve a a01b26ab... 378.
-- ############################################################################################

BEGIN;

DO $precondicion$
DECLARE v text;
BEGIN
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'catalogo_planes_visitador_publico');
  IF v IS DISTINCT FROM '02d8c32870bce2390a5b859e34fac4f2' THEN RAISE EXCEPTION 'ROLLBACK362 PRECONDICION FALLA: la funcion de la 362 no esta viva (md5 %)', COALESCE(v, '-'); END IF;
END $precondicion$;

DROP FUNCTION public.catalogo_planes_visitador_publico();

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regprocedure('public.catalogo_planes_visitador_publico()') IS NOT NULL THEN bad := bad||'la funcion sigue; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'a01b26ab47262f58c617215636ecf560 378' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK362 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
