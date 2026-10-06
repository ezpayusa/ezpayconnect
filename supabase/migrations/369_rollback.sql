-- ############################################################################################
-- 369 ROLLBACK - examenes_catalogo vuelve a catalogo_lab_all y a la escritura directa
-- ############################################################################################
-- Restaura catalogo_lab_all con su texto EXACTO previo (ALL TO authenticated, USING y WITH CHECK laboratorio_id =
-- mi_empresa_proveedor()), borra catalogo_lab_select, devuelve los GRANT exactos (INSERT y DELETE de tabla + UPDATE de
-- columna en categoria y activo) y hace DROP de las 3 RPCs. El front de la 369 deja de funcionar: hay que volver
-- useLaboratorio a la escritura directa. Va ANTES que 368_rollback y que 367_rollback (la precondicion de 367_rollback
-- exige la ACL de public e2bb57f4... 2370, que la 369 cambio y este rollback restaura).
-- Precondicion: la 369 esta viva (policies, relacl, huellas post). Autochequeo: huellas de antes.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado de la 369)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(pl.polname, ',' ORDER BY pl.polname) FROM pg_policy pl WHERE pl.polrelid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM 'catalogo_lab_select,catalogo_read_activos' THEN bad := bad||'policies ['||COALESCE(v, '-')||']; '; END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '9ad617568275d4b7f27b1e2115f8978f 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE proname IN ('crear_examen_catalogo', 'actualizar_examen_catalogo', 'eliminar_examen_catalogo')) <> 3 THEN
    bad := bad||'faltan RPCs de la 369; ';
  END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK369 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

DROP POLICY catalogo_lab_select ON public.examenes_catalogo;
CREATE POLICY catalogo_lab_all ON public.examenes_catalogo
  AS PERMISSIVE FOR ALL TO authenticated
  USING (laboratorio_id = public.mi_empresa_proveedor())
  WITH CHECK (laboratorio_id = public.mi_empresa_proveedor());
GRANT INSERT, DELETE ON public.examenes_catalogo TO authenticated;
GRANT UPDATE (categoria, activo) ON public.examenes_catalogo TO authenticated;
DROP FUNCTION public.crear_examen_catalogo(text, text);
DROP FUNCTION public.actualizar_examen_catalogo(uuid, text, boolean);
DROP FUNCTION public.eliminar_examen_catalogo(uuid);

-- ---------------------------------------------------------------------------- autochequeo (estado de partida)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(pl.polname||' | '||pl.polcmd::text||' | '||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text
          ||' | '||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||' | '||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM 'catalogo_lab_all | * | {authenticated} | (laboratorio_id = mi_empresa_proveedor()) | (laboratorio_id = mi_empresa_proveedor())'||E'\n'
                      ||'catalogo_read_activos | r | {authenticated} | ((activo = true) AND private.lab_en_mi_pais(laboratorio_id)) | -' THEN
    bad := bad||'policies ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=ard/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(attname||'='||attacl::text, '; ' ORDER BY attnum) FROM pg_attribute WHERE attrelid = 'public.examenes_catalogo'::regclass AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL);
  IF v IS DISTINCT FROM 'categoria={authenticated=w/postgres}; activo={authenticated=w/postgres}' THEN bad := bad||'attacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '2c6e39d704ebd6a2e28542b9d3b4fbc0 307' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'e2bb57f40da44965e21590fb92d7f9c3 2370' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '0ee90ba6869cce295105d3b32b893aed 381' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK369 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
