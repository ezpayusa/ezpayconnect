-- ############################################################################################
-- 338 ROLLBACK - vuelve el DELETE directo sobre examenes y ordenes_examen y el MAINTAIN de
--                ordenes_examen, con las 5 policies de DELETE con su texto EXACTO pre-338
-- ############################################################################################
-- ORDEN DE ROLLBACK: este archivo va ANTES que 337_rollback, 336_rollback y 335_rollback.
-- El autochequeo exige la huella del catalogo PRE-338 completa (policies, ACL de tabla y de columnas,
-- md5 de las RPCs de la 332 y de liberacion/correccion post-336): si antes se deshizo la 337, la 336 o
-- la 335, la huella no coincide y aborta sin dejar nada a medias.
-- Precondicion: estado POST-338 exacto (0 policies DELETE/ALL, authenticated = SELECT en las dos
-- tablas, sin MAINTAIN). Si ya se corrio una vez, aborta ahi.
--
-- Costo de volver atras: el lab, el medico y super_admin vuelven a poder borrar examenes y ordenes
-- por PostgREST, y borrar una orden sin historia vuelve a borrar en cascada sus examenes (la FK
-- examenes_orden_id_fkey sigue CASCADE). Las filas con historia siguen protegidas por las FK RESTRICT
-- de examen_revisiones y examen_liberacion_eventos (23503).
-- ############################################################################################

BEGIN;

DO $pre$
DECLARE bad text := ''; x text;
BEGIN
  SELECT string_agg(tablename||'.'||policyname||':'||cmd, ',') INTO x
    FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('examenes','ordenes_examen') AND cmd IN ('DELETE','ALL');
  IF x IS NOT NULL THEN bad := bad||'ya hay policies DELETE/ALL: '||x||'; '; END IF;
  SELECT md5(string_agg(tablename||'|'||policyname||'|'||cmd||'|'||permissive||'|'||roles::text||'|'||COALESCE(qual,'')||'|'||COALESCE(with_check,''), E'\n' ORDER BY tablename, policyname))||' '||count(*)
    INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('examenes','ordenes_examen');
  IF x IS DISTINCT FROM '9b00f7f65a4d8e0c48a5561d1e1d3dbb 9' THEN bad := bad||'policies SELECT/UPDATE: '||COALESCE(x, '-')||'; '; END IF;
  SELECT string_agg(a.privilege_type, ',' ORDER BY a.privilege_type) INTO x
    FROM aclexplode((SELECT relacl FROM pg_class WHERE oid = 'public.examenes'::regclass)) a WHERE a.grantee = 'authenticated'::regrole;
  IF x IS DISTINCT FROM 'SELECT' THEN bad := bad||'authenticated en examenes: '||COALESCE(x, '-')||'; '; END IF;
  SELECT string_agg(a.privilege_type, ',' ORDER BY a.privilege_type) INTO x
    FROM aclexplode((SELECT relacl FROM pg_class WHERE oid = 'public.ordenes_examen'::regclass)) a WHERE a.grantee = 'authenticated'::regrole;
  IF x IS DISTINCT FROM 'SELECT' THEN bad := bad||'authenticated en ordenes_examen: '||COALESCE(x, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG338 ROLLBACK PRECONDICION FALLA:%', bad; END IF;
END $pre$;

-- ------------------------------------------------------- las 5 policies, texto exacto pre-338
CREATE POLICY examenes_laboratorio_delete ON public.examenes
  AS PERMISSIVE FOR DELETE TO public
  USING (laboratorio_id = public.mi_empresa_proveedor());
CREATE POLICY examenes_medico_delete ON public.examenes
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (medico_id = auth.uid());
CREATE POLICY examenes_superadmin_delete ON public.examenes
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY ordenes_lab_delete ON public.ordenes_examen
  AS PERMISSIVE FOR DELETE TO public
  USING (laboratorio_id = public.mi_empresa_proveedor());
CREATE POLICY ordenes_medico_delete ON public.ordenes_examen
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (medico_id = auth.uid());

-- ---------------------------------------------------------------------------------- grants
GRANT DELETE ON TABLE public.examenes, public.ordenes_examen TO authenticated;
GRANT MAINTAIN ON TABLE public.ordenes_examen TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo
-- huella del catalogo PRE-338 medida en prod el 30-sep-2026 (tmp/338/A_pre_catalogo.txt)
DO $chk$
DECLARE bad text := ''; v_pol text; v_acl text; v_col text; v_rpc text;
BEGIN
  SELECT string_agg(tablename||'|'||policyname||'|'||cmd||'|'||permissive||'|'||roles::text||'|'||COALESCE(qual,'')||'|'||COALESCE(with_check,''), E'\n' ORDER BY tablename, policyname)
    INTO v_pol FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('examenes','ordenes_examen');
  SELECT string_agg(c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||a.privilege_type||'|'||pg_get_userbyid(a.grantor)||'|'||a.is_grantable, E'\n' ORDER BY c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||a.privilege_type||'|'||pg_get_userbyid(a.grantor)||'|'||a.is_grantable)
    INTO v_acl FROM pg_class c, aclexplode(c.relacl) a WHERE c.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass);
  SELECT string_agg(y.s, E'\n' ORDER BY y.s) INTO v_col FROM (
    SELECT t.relname||'.'||at.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||a.privilege_type AS s
      FROM pg_class t JOIN pg_attribute at ON at.attrelid = t.oid AND at.attnum > 0 AND NOT at.attisdropped, aclexplode(at.attacl) a
     WHERE t.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass)) y;
  SELECT string_agg(p.oid::regprocedure::text||'|'||md5(p.prosrc)||'|'||COALESCE(p.proacl::text,'-'), E'\n' ORDER BY p.oid::regprocedure::text)
    INTO v_rpc FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND (p.proname LIKE 'crear_orden_examen%' OR p.proname IN
      ('liberar_examen_al_paciente','liberar_orden_al_paciente','revertir_liberacion_examen','corregir_resultado_examen'));
  IF md5(v_pol) IS DISTINCT FROM 'ebfb45023af1cb07d2b7befe0ac2d357' THEN bad := bad||'policies md5 '||COALESCE(md5(v_pol), '-')||'; '; END IF;
  IF md5(v_acl) IS DISTINCT FROM 'a49d7b64048265f3a416de015dd9fab0' THEN bad := bad||'ACL de tabla md5 '||COALESCE(md5(v_acl), '-')||'; '; END IF;
  IF md5(v_col) IS DISTINCT FROM '5045e37d7f1927888f662b64eed93425' THEN bad := bad||'ACL por columna md5 '||COALESCE(md5(v_col), '-')||'; '; END IF;
  IF md5(v_rpc) IS DISTINCT FROM 'cd57942f6f0fe7811a11225d5e25d5f0' THEN bad := bad||'RPCs md5 '||COALESCE(md5(v_rpc), '-')||'; '; END IF;
  IF md5(v_pol||'#'||v_acl||'#'||v_col||'#'||v_rpc) IS DISTINCT FROM '7543ff9eda0d0054c372fe49d91fb8c1' THEN
    bad := bad||'huella del catalogo distinta de la PRE; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG338 ROLLBACK AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
