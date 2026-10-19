-- ############################################################################################
-- 374_rollback - deshace 374_prospecto_ubicacion_integridad.sql y deja el estado post-373 EXACTO
-- ############################################################################################
-- Orden global: 374_rollback -> 373_rollback -> 372_rollback -> 371_rollback -> ...
-- Si el front ya mapea PA035, puede quedar: con este rollback PA035 deja de existir (no se emite mas).
-- Cambios: DROP CONSTRAINT IF EXISTS prospectos_coord_valida; actualizar_prospecto vuelve al cuerpo vivo anterior a la 374
-- COPIADO TEXTUAL de pg_get_functiondef (17-oct-2026, md5(prosrc) 8c2329374daa6000a03815ef1b5456d1, sin CR), con
-- CREATE OR REPLACE (conserva oid y ACL).
-- Precondicion: actualizar_prospecto con el cuerpo de la 374 (md5 16f224a2bf1e6d6d0a06068a8e0d9d59) o ya con el anterior
-- (re-ejecucion), y las huellas de policies/relaciones/funciones post-373 (la 374 no las cambia).
-- Autochequeo: sin el CHECK, md5(prosrc) = 8c232937..., sin PA035 en ninguna funcion, misma ACL, huellas post-373.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)'));
  IF v IS NULL OR v NOT IN ('16f224a2bf1e6d6d0a06068a8e0d9d59', '8c2329374daa6000a03815ef1b5456d1') THEN
    bad := bad||'actualizar_prospecto md5(prosrc) '||COALESCE(v, 'no existe')||'; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '027e10a7b66101b4f5bb85c475c34045 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK374 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: CHECK
ALTER TABLE public.prospectos DROP CONSTRAINT IF EXISTS prospectos_coord_valida;

-- ---------------------------------------------------------------------------- 2: cuerpo anterior (textual)
CREATE OR REPLACE FUNCTION public.actualizar_prospecto(p_prospecto_id uuid, p_nombre text, p_tipo text, p_direccion text DEFAULT NULL::text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_notas text DEFAULT NULL::text, p_empresa_proveedora_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- LA LINEA QUE ATA: p_prospecto_id es una CLAVE, no un scope. El scope lo dice la fila a la
  -- que apunta, y eso vive en el predicado. Si el prospecto no existe el predicado da false y
  -- sale el mismo 42501: existir-y-no-poder y no-existir son indistinguibles desde afuera.
  IF NOT COALESCE(private.puede_editar_datos_prospecto(p_prospecto_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.catalogo_prospecto_tipo c WHERE c.codigo = p_tipo AND c.activo) THEN
    RAISE EXCEPTION 'PA010: el tipo % no existe o esta inactivo en catalogo_prospecto_tipo', COALESCE(p_tipo,'(nulo)')
      USING ERRCODE = 'PA010';
  END IF;

  -- NO se tocan asesor_id (eso es reasignar_prospecto) ni pais_id (se deriva del asesor).
  UPDATE public.prospectos SET
    nombre = btrim(p_nombre), tipo = p_tipo, direccion = p_direccion,
    lat = p_lat, lng = p_lng, notas = p_notas,
    empresa_proveedora_id = p_empresa_proveedora_id,
    updated_at = now()
  WHERE id = p_prospecto_id;
END
$function$;

-- ---------------------------------------------------------------------------- autochequeo (estado post-373)
DO $autochequeo$
DECLARE bad text := ''; v text; p record;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.prospectos'::regclass AND c.conname = 'prospectos_coord_valida') THEN
    bad := bad||'prospectos_coord_valida sigue; ';
  END IF;
  SELECT f.prosecdef, f.proconfig::text AS cfg, md5(f.prosrc) AS m, f.proacl::text AS acl INTO p
    FROM pg_proc f WHERE f.oid = to_regprocedure('public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)');
  IF NOT FOUND THEN
    bad := bad||'falta actualizar_prospecto; ';
  ELSE
    IF NOT p.prosecdef THEN bad := bad||'no es SECURITY DEFINER; '; END IF;
    IF p.cfg IS DISTINCT FROM '{"search_path=\"\""}' THEN bad := bad||'proconfig '||COALESCE(p.cfg, '-')||'; '; END IF;
    IF p.m IS DISTINCT FROM '8c2329374daa6000a03815ef1b5456d1' THEN bad := bad||'md5(prosrc) '||p.m||' (esperado 8c232937...); '; END IF;
    IF p.acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
      bad := bad||'proacl '||COALESCE(p.acl, 'NULL')||'; ';
    END IF;
  END IF;
  v := (SELECT string_agg(f.oid::regprocedure::text, ', ' ORDER BY f.oid::regprocedure::text) FROM pg_proc f WHERE f.prosrc LIKE '%PA035%');
  IF v IS NOT NULL THEN bad := bad||'PA035 sigue en ['||v||']; '; END IF;

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
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '027e10a7b66101b4f5bb85c475c34045 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK374 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
