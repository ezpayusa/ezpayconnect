-- =====================================================================================================================
-- ROLLBACK MIG 384 — vuelve listar_medicos_por_pais y contar_medicos_por_pais a sus cuerpos vivos exactos del 26-oct-2026
-- (pg_get_functiondef medido antes de la 384, con su CRLF). El texto viaja como literales E'…' línea por línea, con
-- \r\n explícito: la huella no depende del fin de línea del archivo en disco.
--
-- md5(prosrc):  listar_medicos_por_pais  838b41eb8b782f7a54d88d60b0c725ff -> 489479f0f952afde7fd353f3b70c6d58
--               contar_medicos_por_pais  2eb35e1dcc8e864314048570c51e63c2 -> 4d7ebf5dd516e7d83985df8347d7ba04
-- md5(pg_get_functiondef) de lo que se restaura: listar 218ac01ed94524b5dd5b63b011963179,
--                                                contar a401ab3e54a482f77273c9c7d80047cc
-- Cadena: 385_rollback -> 384_rollback -> 383_rollback -> ...
-- Efecto esperado al revertir: el staff de clínica con medicos.pais_id vuelve a aparecer en listar_medicos_por_pais y a
-- sumar en contar_medicos_por_pais (el estado de antes, a propósito).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/384_rollback.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) PRECONDICIÓN: la 384 está aplicada tal cual (si no, no se toca nada)
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.listar_medicos_por_pais(uuid)', '838b41eb8b782f7a54d88d60b0c725ff'),
      ('public.contar_medicos_por_pais(uuid)', '2eb35e1dcc8e864314048570c51e63c2')) AS t(firma, md5_384)
  LOOP
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_384 THEN bad := bad||r.firma||' md5(prosrc) '||COALESCE(v, 'no existe')||' (se esperaba el de la 384); '; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)
                     AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']
                     AND p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}') THEN
      bad := bad||r.firma||' secdef/config/ACL distintos; ';
    END IF;
  END LOOP;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG84R: precondición: %', bad USING ERRCODE = 'MIG84';
  END IF;
END $precondicion$;

-- huellas antes del rollback: el autochequeo exige que solo se muevan estas 2 funciones
CREATE TEMP TABLE m384r_huellas ON COMMIT DROP AS
SELECT
  (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                         COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                         ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
     FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
      AND f.oid NOT IN ('public.listar_medicos_por_pais(uuid)'::regprocedure, 'public.contar_medicos_por_pais(uuid)'::regprocedure)) AS funciones_sin_las_2,
  (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
     SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
       FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
      WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y) AS acl_funciones,
  (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
     FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
    WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x) AS acl_relaciones_public,
  (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
     SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
        ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
        COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
       FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
      WHERE n.nspname IN ('public','private','storage')) y) AS policies;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) RESTAURACIÓN: los CREATE OR REPLACE vivos de antes de la 384, md5 verificado antes de ejecutar
-- ---------------------------------------------------------------------------------------------------------------------
DO $restaurar$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.listar_medicos_por_pais(uuid)', '218ac01ed94524b5dd5b63b011963179',
    E'CREATE OR REPLACE FUNCTION public.listar_medicos_por_pais(p_pais_id uuid DEFAULT NULL::uuid)\n'
    || E' RETURNS TABLE(id uuid, nombre_completo text, especialidad text, foto_url text, activo boolean, pais_id uuid)\n'
    || E' LANGUAGE plpgsql\n'
    || E' SECURITY DEFINER\n'
    || E' SET search_path TO \'\'\n'
    || E'AS $function$\r\n'
    || E'DECLARE\r\n'
    || E'  v_pais uuid;\r\n'
    || E'BEGIN\r\n'
    || E'  v_pais := COALESCE(p_pais_id, private.mi_pais_viewer());\r\n'
    || E'  IF v_pais IS NULL THEN\r\n'
    || E'    RAISE EXCEPTION \'pais requerido\' USING ERRCODE = \'PC025\';\r\n'
    || E'  END IF;\r\n'
    || E'  IF NOT COALESCE(\r\n'
    || E'    private.puede_admin_pais(v_pais)\r\n'
    || E'    OR v_pais = private.mi_pais_viewer()\r\n'
    || E'    OR EXISTS (\r\n'
    || E'         SELECT 1 FROM public.medico_clinicas mc\r\n'
    || E'         JOIN public.clinicas c ON c.id = mc.clinica_id\r\n'
    || E'         WHERE mc.medico_id = auth.uid()\r\n'
    || E'           AND c.pais_id IS NOT NULL\r\n'
    || E'           AND c.pais_id = v_pais\r\n'
    || E'       ),\r\n'
    || E'    false\r\n'
    || E'  ) THEN\r\n'
    || E'    RAISE EXCEPTION \'no autorizado para este pais\' USING ERRCODE = \'PC026\';\r\n'
    || E'  END IF;\r\n'
    || E'\r\n'
    || E'  RETURN QUERY\r\n'
    || E'  SELECT m.id, m.nombre_completo, m.especialidad, m.foto_url, m.activo, m.pais_id\r\n'
    || E'  FROM public.medicos m\r\n'
    || E'  WHERE m.pais_id = v_pais AND m.activo = true\r\n'
    || E'  UNION\r\n'
    || E'  SELECT p.id, p.nombre_completo, NULL::TEXT, p.avatar_url, p.activo, p.pais_id\r\n'
    || E'  FROM public.perfiles p\r\n'
    || E'  WHERE p.rol = \'medico\' AND p.activo = true AND p.pais_id = v_pais\r\n'
    || E'    AND NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = p.id)\r\n'
    || E'  ORDER BY nombre_completo;\r\n'
    || E'END;\r\n'
    || E'$function$\n'),
      ('public.contar_medicos_por_pais(uuid)', 'a401ab3e54a482f77273c9c7d80047cc',
    E'CREATE OR REPLACE FUNCTION public.contar_medicos_por_pais(p_pais_id uuid)\n'
    || E' RETURNS integer\n'
    || E' LANGUAGE plpgsql\n'
    || E' SECURITY DEFINER\n'
    || E' SET search_path TO \'\'\n'
    || E'AS $function$\r\n'
    || E'DECLARE\r\n'
    || E'  v_count INTEGER;\r\n'
    || E'BEGIN\r\n'
    || E'  IF p_pais_id IS NULL THEN\r\n'
    || E'    RAISE EXCEPTION \'pais requerido\' USING ERRCODE = \'PC025\';\r\n'
    || E'  END IF;\r\n'
    || E'  IF NOT COALESCE(\r\n'
    || E'    private.puede_admin_pais(p_pais_id)\r\n'
    || E'    OR p_pais_id = private.mi_pais_viewer()\r\n'
    || E'    OR EXISTS (\r\n'
    || E'         SELECT 1 FROM public.medico_clinicas mc\r\n'
    || E'         JOIN public.clinicas c ON c.id = mc.clinica_id\r\n'
    || E'         WHERE mc.medico_id = auth.uid()\r\n'
    || E'           AND c.pais_id IS NOT NULL\r\n'
    || E'           AND c.pais_id = p_pais_id\r\n'
    || E'       ),\r\n'
    || E'    false\r\n'
    || E'  ) THEN\r\n'
    || E'    RAISE EXCEPTION \'no autorizado para este pais\' USING ERRCODE = \'PC026\';\r\n'
    || E'  END IF;\r\n'
    || E'\r\n'
    || E'  SELECT COUNT(*) INTO v_count FROM public.medicos WHERE pais_id = p_pais_id;\r\n'
    || E'  RETURN v_count;\r\n'
    || E'END;\r\n'
    || E'$function$\n')) AS t(firma, md5_def, def)
  LOOP
    IF md5(r.def) IS DISTINCT FROM r.md5_def THEN
      RAISE EXCEPTION 'MIG84R: % el texto a restaurar no es el medido (md5 %)', r.firma, md5(r.def) USING ERRCODE = 'MIG84';
    END IF;
    EXECUTE r.def;
  END LOOP;
END $restaurar$;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) AUTOCHEQUEO
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record; h record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.listar_medicos_por_pais(uuid)', '489479f0f952afde7fd353f3b70c6d58',
       'TABLE(id uuid, nombre_completo text, especialidad text, foto_url text, activo boolean, pais_id uuid)'),
      ('public.contar_medicos_por_pais(uuid)', '4d7ebf5dd516e7d83985df8347d7ba04', 'integer')) AS t(firma, md5_vivo, ret)
  LOOP
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_vivo THEN bad := bad||r.firma||' md5(prosrc) '||COALESCE(v, '-')||'; '; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)
                     AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']
                     AND p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
                     AND pg_get_function_result(p.oid) = r.ret) THEN
      bad := bad||r.firma||' cambió secdef/config/ACL/retorno; ';
    END IF;
  END LOOP;

  SELECT * INTO h FROM pg_temp.m384r_huellas;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid NOT IN ('public.listar_medicos_por_pais(uuid)'::regprocedure, 'public.contar_medicos_por_pais(uuid)'::regprocedure));
  IF v IS DISTINCT FROM h.funciones_sin_las_2 THEN bad := bad||'cambió otra función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM h.acl_funciones THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM h.acl_relaciones_public THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM h.policies THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG84R: autochequeo: %', bad USING ERRCODE = 'MIG84';
  END IF;
END $autochequeo$;

COMMIT;
