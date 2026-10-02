-- ############################################################################################
-- 339 ROLLBACK - borra public.contexto_ia_ultima_visita(bigint)
-- ############################################################################################
-- Precondicion: estado POST-339 exacto (la funcion existe con el md5 que dejo la 339, medido en el
-- dry-run del 1-oct-2026, DEFINER con search_path vacio y EXECUTE solo para authenticated y
-- service_role). Si ya se corrio una vez, aborta ahi.
-- Las 3 funciones vecinas (gate_accion_phi, contexto_ia_paciente, obtener_contexto_visita) no se tocan:
-- el autochequeo exige sus md5 de antes de la 339.
--
-- Costo de volver atras: el edge que llame a contexto_ia_ultima_visita recibe "function does not
-- exist". Antes de esto hay que sacar el modo resumen_visita del edge (fase 1 front/edge), si ya se
-- desplego. No hay datos que restaurar: la 339 no escribe filas.
-- ############################################################################################

BEGIN;

DO $pre$
DECLARE bad text := ''; x text; v_oid oid := to_regprocedure('public.contexto_ia_ultima_visita(bigint)');
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'MIG339 ROLLBACK PRECONDICION FALLA: la funcion no existe'; END IF;
  SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-') INTO x FROM pg_proc p WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'a755ff5be772cd2079e19c8ad62a92ea true {"search_path=\"\""}' THEN bad := bad||'funcion: '||COALESCE(x, '-')||'; '; END IF;
  SELECT string_agg(CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type, ','
                    ORDER BY CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||':'||a.privilege_type)
    INTO x FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_oid;
  IF x IS DISTINCT FROM 'authenticated:EXECUTE,postgres:EXECUTE,service_role:EXECUTE' THEN bad := bad||'ACL: '||COALESCE(x, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG339 ROLLBACK PRECONDICION FALLA:%', bad; END IF;
END $pre$;

DROP FUNCTION public.contexto_ia_ultima_visita(bigint);

DO $chk$
DECLARE bad text := ''; x text; r record;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'contexto_ia_ultima_visita') THEN
    bad := bad||'la funcion sigue existiendo; '; END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.gate_accion_phi(bigint,text)',         '790e09208a5c67102a2b5c378c500940'),
      ('public.contexto_ia_paciente(bigint)',         '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('public.obtener_contexto_visita(bigint)',      '24c3825b9c8fc6d172f8963191025097')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG339 ROLLBACK AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
