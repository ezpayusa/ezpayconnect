-- ############################################################################################
-- 369 - examenes_catalogo: la policy ALL del lab se parte; escrituras por RPC DEFINER (familia 2, F2-f parte 3)
-- ############################################################################################
-- Recon del 6-oct-2026 (solo lectura contra prod, sobre main 8ae8403):
--   * La policy ALL del lab = ALL TO authenticated USING/CHECK (laboratorio_id = mi_empresa_proveedor()). Medido: TODA cuenta
--     activa del lab (recepcion, tecnico) podia por API crear, borrar y activar/desactivar los examenes de su catalogo sin
--     el permiso 'catalogo_examenes_editar' (en permisos_empresa_rol solo lo tiene laboratorio_clinico/admin; el front ya
--     oculta los botones con tienePermiso). Y cualquier empresa activa (p. ej. una farmacia) pasaba el WITH CHECK con su
--     propio id (la FK acepta cualquier empresa_proveedora).
--   * ACL: authenticated=ard + UPDATE de columna en categoria y activo. 9 filas, todas del lab QA; 4 referenciadas por
--     examenes.catalogo_id (FK RESTRICT). UNIQUE (laboratorio_id, lower(btrim(nombre))).
-- Decision (Oscar): las escrituras van por RPC DEFINER con el gate adentro, no por policy con WITH CHECK que llame funciones
-- DEFINER (leccion rls-with-check-definer-flaky-postgrest).
-- Cambio:
--   1 public.crear_examen_catalogo(p_nombre, p_categoria) -> uuid; public.actualizar_examen_catalogo(p_id, p_categoria,
--     p_activo) -> uuid (solo categoria y activo; NULL = sin cambio; categoria '' = sin categoria);
--     public.eliminar_examen_catalogo(p_id) -> uuid. DEFINER, search_path ''. Gate PRIMERO, antes de mirar la fila:
--     empresa = mi_empresa_proveedor() (cuenta activa y empresa activa) de tipo laboratorio_clinico y
--     COALESCE(private.tiene_permiso('catalogo_examenes_editar'), false). Errcodes:
--       EX035 sin permiso para editar el catalogo; EX036 el examen no existe en tu catalogo (tambien si es de otro lab);
--       EX037 nombre o categoria invalidos; EX038 ya fue ordenado: no se borra, se desactiva; EX039 nombre repetido.
--     EXECUTE solo authenticated y service_role (sin PUBLIC ni anon).
--   2 DROP de la policy ALL del lab; CREATE POLICY catalogo_lab_select (SELECT TO authenticated, el lab ve lo propio, activo o
--     no; NULL deniega). catalogo_read_activos sin cambios.
--   3 REVOKE INSERT, UPDATE, DELETE (y el UPDATE de columna en categoria y activo) de authenticated. SELECT se queda.
-- Huellas: policies 2c6e39d7... 307 -> 9ad617568275d4b7f27b1e2115f8978f 307; ACL de public e2bb57f4... 2370 -> 64ff833d25666534b8de9171d1e5d404 2368; ACL de funciones
-- 0ee90ba6... 381 -> e5c9770e31312d34601dc45f0c545173 384.
-- Probes: P1011-P1014 (nuevos); P873 usa las RPCs con la 369 aplicada.
-- Front: useLaboratorio llama a las 3 RPCs. Rollback: 369_rollback.sql (va antes que 368_rollback).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(pl.polname||' | '||pl.polcmd::text||' | '||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text
          ||' | '||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||' | '||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM 'catalogo_lab_all | * | {authenticated} | (laboratorio_id = mi_empresa_proveedor()) | (laboratorio_id = mi_empresa_proveedor())'||E'\n'
                      ||'catalogo_read_activos | r | {authenticated} | ((activo = true) AND private.lab_en_mi_pais(laboratorio_id)) | -' THEN
    bad := bad||'policies de examenes_catalogo ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=ard/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(attname||'='||attacl::text, '; ' ORDER BY attnum) FROM pg_attribute WHERE attrelid = 'public.examenes_catalogo'::regclass AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL);
  IF v IS DISTINCT FROM 'categoria={authenticated=w/postgres}; activo={authenticated=w/postgres}' THEN bad := bad||'attacl '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('crear_examen_catalogo', 'actualizar_examen_catalogo', 'eliminar_examen_catalogo')) THEN
    bad := bad||'alguna de las 3 RPCs ya existe; ';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'private.tiene_permiso(text)'::regprocedure) IS DISTINCT FROM '0dd4dc69757e1c6a2a26c23f16c3e4a7' THEN bad := bad||'tiene_permiso cambio; '; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.mi_empresa_proveedor()'::regprocedure) IS DISTINCT FROM '24e34b8449187e38be50f621ce1c5fc9' THEN bad := bad||'mi_empresa_proveedor cambio; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG369 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: las 3 RPCs
CREATE FUNCTION public.crear_examen_catalogo(p_nombre text, p_categoria text DEFAULT NULL)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
AS $fn$
DECLARE
  v_emp uuid := public.mi_empresa_proveedor();
  v_nombre text := btrim(p_nombre);
  v_cat text := NULLIF(btrim(p_categoria), '');
  v_id uuid;
BEGIN
  -- gate primero: lab clinico activo (mi_empresa_proveedor ya exige cuenta y empresa activas) con el permiso
  IF v_emp IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras e WHERE e.id = v_emp AND e.tipo = 'laboratorio_clinico' AND e.estado = 'activa')
     OR NOT COALESCE(private.tiene_permiso('catalogo_examenes_editar'), false) THEN
    RAISE EXCEPTION 'No tienes permiso para editar el catálogo de exámenes' USING ERRCODE = 'EX035';
  END IF;
  IF v_nombre IS NULL OR v_nombre = '' OR length(v_nombre) > 200 THEN
    RAISE EXCEPTION 'El nombre del examen es obligatorio y no puede superar 200 caracteres' USING ERRCODE = 'EX037';
  END IF;
  IF length(v_cat) > 100 THEN
    RAISE EXCEPTION 'La categoría no puede superar 100 caracteres' USING ERRCODE = 'EX037';
  END IF;
  BEGIN
    INSERT INTO public.examenes_catalogo (laboratorio_id, nombre, categoria) VALUES (v_emp, v_nombre, v_cat) RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Ya existe un examen con ese nombre en tu catálogo' USING ERRCODE = 'EX039';
  END;
  RETURN v_id;
END;
$fn$;

CREATE FUNCTION public.actualizar_examen_catalogo(p_id uuid, p_categoria text DEFAULT NULL, p_activo boolean DEFAULT NULL)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
AS $fn$
DECLARE
  v_emp uuid := public.mi_empresa_proveedor();
  v_id uuid;
BEGIN
  IF v_emp IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras e WHERE e.id = v_emp AND e.tipo = 'laboratorio_clinico' AND e.estado = 'activa')
     OR NOT COALESCE(private.tiene_permiso('catalogo_examenes_editar'), false) THEN
    RAISE EXCEPTION 'No tienes permiso para editar el catálogo de exámenes' USING ERRCODE = 'EX035';
  END IF;
  -- una fila de otro laboratorio da el MISMO error que una inexistente
  SELECT c.id INTO v_id FROM public.examenes_catalogo c WHERE c.id = p_id AND c.laboratorio_id = v_emp FOR UPDATE;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'El examen no existe en tu catálogo' USING ERRCODE = 'EX036';
  END IF;
  IF length(btrim(p_categoria)) > 100 THEN
    RAISE EXCEPTION 'La categoría no puede superar 100 caracteres' USING ERRCODE = 'EX037';
  END IF;
  -- NULL = sin cambio; categoria '' = sin categoria. Solo categoria y activo (el nombre no se renombra: mig 332/333)
  UPDATE public.examenes_catalogo
     SET categoria = CASE WHEN p_categoria IS NULL THEN categoria ELSE NULLIF(btrim(p_categoria), '') END,
         activo = COALESCE(p_activo, activo)
   WHERE id = v_id;
  RETURN v_id;
END;
$fn$;

CREATE FUNCTION public.eliminar_examen_catalogo(p_id uuid)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
AS $fn$
DECLARE
  v_emp uuid := public.mi_empresa_proveedor();
  v_id uuid;
BEGIN
  IF v_emp IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras e WHERE e.id = v_emp AND e.tipo = 'laboratorio_clinico' AND e.estado = 'activa')
     OR NOT COALESCE(private.tiene_permiso('catalogo_examenes_editar'), false) THEN
    RAISE EXCEPTION 'No tienes permiso para editar el catálogo de exámenes' USING ERRCODE = 'EX035';
  END IF;
  SELECT c.id INTO v_id FROM public.examenes_catalogo c WHERE c.id = p_id AND c.laboratorio_id = v_emp FOR UPDATE;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'El examen no existe en tu catálogo' USING ERRCODE = 'EX036';
  END IF;
  IF EXISTS (SELECT 1 FROM public.examenes ex WHERE ex.catalogo_id = v_id) THEN
    RAISE EXCEPTION 'Este examen ya fue ordenado y no se puede borrar. Puedes desactivarlo.' USING ERRCODE = 'EX038';
  END IF;
  BEGIN
    DELETE FROM public.examenes_catalogo WHERE id = v_id;
  EXCEPTION WHEN foreign_key_violation THEN   -- carrera: lo ordenaron entre el chequeo y el DELETE
    RAISE EXCEPTION 'Este examen ya fue ordenado y no se puede borrar. Puedes desactivarlo.' USING ERRCODE = 'EX038';
  END;
  RETURN v_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.crear_examen_catalogo(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.actualizar_examen_catalogo(uuid, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.eliminar_examen_catalogo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crear_examen_catalogo(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.actualizar_examen_catalogo(uuid, text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.eliminar_examen_catalogo(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 2: policies
DROP POLICY catalogo_lab_all ON public.examenes_catalogo;
CREATE POLICY catalogo_lab_select ON public.examenes_catalogo
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (COALESCE(laboratorio_id = public.mi_empresa_proveedor(), false));

-- ---------------------------------------------------------------------------- 3: privilegios
REVOKE INSERT, UPDATE, DELETE ON public.examenes_catalogo FROM authenticated;
REVOKE UPDATE (categoria, activo) ON public.examenes_catalogo FROM authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  v := (SELECT string_agg(pl.polname||' | '||pl.polcmd::text||' | '||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text
          ||' | '||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||' | '||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM 'catalogo_lab_select | r | {authenticated} | COALESCE((laboratorio_id = mi_empresa_proveedor()), false) | -'||E'\n'
                      ||'catalogo_read_activos | r | {authenticated} | ((activo = true) AND private.lab_en_mi_pais(laboratorio_id)) | -' THEN
    bad := bad||'policies de examenes_catalogo ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.examenes_catalogo'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.examenes_catalogo'::regclass AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL) THEN
    bad := bad||'quedan privilegios por columna; ';
  END IF;
  IF has_table_privilege('authenticated', 'public.examenes_catalogo', 'INSERT') OR has_table_privilege('authenticated', 'public.examenes_catalogo', 'DELETE')
     OR has_any_column_privilege('authenticated', 'public.examenes_catalogo', 'UPDATE') OR NOT has_table_privilege('authenticated', 'public.examenes_catalogo', 'SELECT') THEN
    bad := bad||'privilegios de authenticated; ';
  END IF;
  FOR r IN SELECT * FROM (VALUES ('public.crear_examen_catalogo(text,text)'), ('public.actualizar_examen_catalogo(uuid,text,boolean)'), ('public.eliminar_examen_catalogo(uuid)')) x(f) LOOP
    v := (SELECT p.prosecdef::text||' '||COALESCE(array_to_string(p.proconfig, ','), '-')||' '||p.proacl::text||' '||pg_get_userbyid(p.proowner)
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.f));
    IF v IS DISTINCT FROM 'true search_path="" {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} postgres' THEN bad := bad||r.f||' '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
    IF has_function_privilege('anon', to_regprocedure(r.f), 'EXECUTE') THEN bad := bad||r.f||' ejecutable por anon; '; END IF;
  END LOOP;
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
  IF v IS DISTINCT FROM 'e5c9770e31312d34601dc45f0c545173 384' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG369 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
