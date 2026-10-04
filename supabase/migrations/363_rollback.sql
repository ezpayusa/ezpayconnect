-- ############################################################################################
-- 363 ROLLBACK - saca el conteo de proveedores por pais
-- ############################################################################################
-- DROP de public.contar_proveedores_por_pais(uuid). Un front que ya la llame vuelve a ver 0 proveedores para el
-- admin_pais (su SELECT directo no pasa las policies de empresas_proveedoras). Precondicion: la 363 esta viva (md5
-- 43c82022...). Autochequeo: la funcion no existe y la huella de ACL de funciones vuelve a 83031eae... 379.
-- Probes: con este rollback aplicado, P1001-P1006 dan ROJO o FALLO.
-- ############################################################################################

BEGIN;

DO $precondicion$
DECLARE v text;
BEGIN
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.contar_proveedores_por_pais(uuid)'));
  IF v IS DISTINCT FROM '43c82022e80d0b36212e36f2c0a0912f' THEN RAISE EXCEPTION 'ROLLBACK363 PRECONDICION FALLA: la funcion de la 363 no esta viva (md5 %)', COALESCE(v, '-'); END IF;
END $precondicion$;

DROP FUNCTION public.contar_proveedores_por_pais(uuid);

DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF to_regprocedure('public.contar_proveedores_por_pais(uuid)') IS NOT NULL THEN bad := bad||'la funcion sigue; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '83031eae1174a411499a06fcc3edf95b 379' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK363 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
