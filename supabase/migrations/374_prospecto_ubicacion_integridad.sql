-- ############################################################################################
-- 374 - Integridad de la ubicacion del prospecto (review del PR #59, feat/prospecto-ubicacion)
-- ############################################################################################
-- Recon: 17-oct-2026, solo lectura, sobre prod (%TEMP%\recon374\ y %TEMP%\dry374\pre*.sql).
--
-- Que cierra: el asesor asignado pasa private.puede_editar_datos_prospecto (pais_id = mi_pais() AND
--   asesor_id = auth.uid()), asi que por public.actualizar_prospecto podia escribir su propia direccion/lat/lng desde la
--   API y dejarse el check-in verificado: checkin_visita_comercial mide la distancia contra esa coordenada. El front del
--   PR #59 pone la direccion en solo lectura, pero eso era solo UI. Ademas, ni actualizar_prospecto ni
--   crear_prospecto validaban la coordenada (la regla "las dos o ninguna, en rango, nunca (0,0)" vivia solo en el front).
--
-- Cambios:
--   (A) CHECK prospectos_coord_valida en public.prospectos (idempotente por nombre; NOT VALID + VALIDATE en esta misma
--       migracion): lat y lng las dos o ninguna; si estan, lat en [-90, 90], lng en [-180, 180] y nunca (0, 0).
--       Datos vivos medidos el 17-oct-2026: 10 filas, 0 a medias, 0 fuera de rango, 0 en (0,0).
--       No es ADD COLUMN: no toca privilegios por columna ni la ACL de la tabla.
--   (B) public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid): CREATE OR REPLACE con la misma firma,
--       los mismos DEFAULTs, SECURITY DEFINER y search_path = '' (sin DROP: conserva oid y ACL). Cuerpo = el vivo
--       (md5(prosrc) 8c2329374daa6000a03815ef1b5456d1) mas:
--         - el gate puede_editar_datos_prospecto sigue PRIMERO, sin cambios (P520/P521/P531 siguen dando 42501);
--         - despues del gate: relee la fila FOR UPDATE y, si quien llama no es admin del pais del prospecto
--           (private.puede_admin_pais: super_admin o admin_pais de ESE pais) y la direccion, la lat o la lng que manda
--           son distintas de las guardadas, PA035;
--         - PA010 y el UPDATE quedan iguales.
--       crear_prospecto NO cambia: su gate ya es puede_admin_pais (solo el admin crea) y el CHECK cubre su coordenada.
--
-- Numeros: mig 374; errcode PA035 (PA001-PA034 en uso; PA035 era el libre, medido en prod el 17-oct-2026). Probes P1035+
--   (la rama altas/alta-diferida-373 llega a P1034). Proximos libres despues de esta: mig 375, PA036, P1035.
--
-- Privilegios (CLAUDE.md): sin cambios. ACL de actualizar_prospecto {postgres=X/postgres, authenticated=X/postgres,
--   service_role=X/postgres}; ACL de relaciones de public d065decf.../2394, policies 8a8dc5cf.../309 y ACL de funciones
--   027e10a7b66101b4f5bb85c475c34045/392 (estado vivo post-373, medido el 17-oct-2026) SIN cambio.
--
-- Front: PA035 todavia no esta en src/lib/erroresRpc.ts (hoy sale como "[PA035 sin mapear]"); el test de "PA sin mapear"
--   de erroresRpc.test.ts usa PA035 y hay que moverlo a PA036 al mapearlo.
--
-- Rollback: 374_rollback.sql. Orden global: 374_rollback -> 373_rollback -> 372_rollback -> 371_rollback -> ...
--   (la precondicion de 373_rollback exige la ACL de funciones post-373; esta migracion no la cambia, pero el CHECK y el
--   cuerpo nuevo tienen que salir antes para volver al estado exacto que 373_rollback espera encima).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado post-373)
DO $precondicion$
DECLARE bad text := ''; v text;
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
  IF v IS DISTINCT FROM '027e10a7b66101b4f5bb85c475c34045 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  -- cuerpo vivo de actualizar_prospecto (pre) o el de esta migracion (re-ejecucion)
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)'));
  IF v IS NULL OR v NOT IN ('8c2329374daa6000a03815ef1b5456d1', '16f224a2bf1e6d6d0a06068a8e0d9d59') THEN
    bad := bad||'actualizar_prospecto md5(prosrc) '||COALESCE(v, 'no existe')||'; ';
  END IF;

  -- PA035 libre (salvo en la propia actualizar_prospecto, si es re-ejecucion)
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
         WHERE p.prosrc LIKE '%PA035%'
           AND p.oid <> 'public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)'::regprocedure);
  IF v IS NOT NULL THEN bad := bad||'PA035 ya aparece en: '||v||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG374 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- (A) CHECK de la coordenada
DO $check$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c
                  WHERE c.conrelid = 'public.prospectos'::regclass AND c.conname = 'prospectos_coord_valida') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_coord_valida CHECK (
      (lat IS NULL) = (lng IS NULL)
      AND (lat IS NULL OR (lat BETWEEN -90 AND 90 AND lng BETWEEN -180 AND 180 AND NOT (lat = 0 AND lng = 0)))
    ) NOT VALID;
  END IF;
END $check$;

ALTER TABLE public.prospectos VALIDATE CONSTRAINT prospectos_coord_valida;

-- ---------------------------------------------------------------------------- (B) actualizar_prospecto
CREATE OR REPLACE FUNCTION public.actualizar_prospecto(p_prospecto_id uuid, p_nombre text, p_tipo text, p_direccion text DEFAULT NULL::text, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_notas text DEFAULT NULL::text, p_empresa_proveedora_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_pais uuid; v_dir text; v_lat numeric; v_lng numeric;
BEGIN
  -- LA LINEA QUE ATA: p_prospecto_id es una CLAVE, no un scope. El scope lo dice la fila a la
  -- que apunta, y eso vive en el predicado. Si el prospecto no existe el predicado da false y
  -- sale el mismo 42501: existir-y-no-poder y no-existir son indistinguibles desde afuera.
  IF NOT COALESCE(private.puede_editar_datos_prospecto(p_prospecto_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- La ubicacion es la referencia contra la que checkin_visita_comercial mide la distancia del asesor: el medido no la
  -- puede mover. Solo el admin del pais del prospecto (o el super_admin) cambia direccion/lat/lng; el asesor tiene que
  -- mandar las guardadas tal cual (el front las relee frescas). FOR UPDATE: la comparacion y el UPDATE ven la misma fila.
  SELECT pr.pais_id, pr.direccion, pr.lat, pr.lng INTO v_pais, v_dir, v_lat, v_lng
    FROM public.prospectos pr WHERE pr.id = p_prospecto_id FOR UPDATE;
  IF NOT COALESCE(private.puede_admin_pais(v_pais), false)
     AND (p_direccion IS DISTINCT FROM v_dir OR p_lat IS DISTINCT FROM v_lat OR p_lng IS DISTINCT FROM v_lng) THEN
    RAISE EXCEPTION 'PA035: la dirección y la ubicación del prospecto solo las cambia el administrador de país'
      USING ERRCODE = 'PA035';
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

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; p record; i_gate int; i_pa035 int;
BEGIN
  -- (a) CHECK presente, validado y con la definicion esperada
  SELECT c.convalidated, pg_get_constraintdef(c.oid) AS def INTO p
    FROM pg_constraint c WHERE c.conrelid = 'public.prospectos'::regclass AND c.conname = 'prospectos_coord_valida';
  IF NOT FOUND THEN
    bad := bad||'falta prospectos_coord_valida; ';
  ELSE
    IF NOT p.convalidated THEN bad := bad||'prospectos_coord_valida sin validar; '; END IF;
    IF p.def IS DISTINCT FROM 'CHECK ((((lat IS NULL) = (lng IS NULL)) AND ((lat IS NULL) OR (((lat >= (''-90''::integer)::numeric) AND (lat <= (90)::numeric)) AND ((lng >= (''-180''::integer)::numeric) AND (lng <= (180)::numeric)) AND (NOT ((lat = (0)::numeric) AND (lng = (0)::numeric)))))))' THEN
      bad := bad||'prospectos_coord_valida con otra definicion: '||p.def||'; ';
    END IF;
  END IF;

  -- (b) funcion: firma, DEFINER, search_path, cuerpo, gate antes de PA035, ACL
  SELECT f.prosecdef, f.proconfig::text AS cfg, f.prosrc, md5(f.prosrc) AS m, f.proacl::text AS acl INTO p
    FROM pg_proc f WHERE f.oid = to_regprocedure('public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)');
  IF NOT FOUND THEN
    bad := bad||'falta actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid); ';
  ELSE
    IF NOT p.prosecdef THEN bad := bad||'actualizar_prospecto no es SECURITY DEFINER; '; END IF;
    IF p.cfg IS DISTINCT FROM '{"search_path=\"\""}' THEN bad := bad||'proconfig '||COALESCE(p.cfg, '-')||'; '; END IF;
    IF p.m IS DISTINCT FROM '16f224a2bf1e6d6d0a06068a8e0d9d59' THEN bad := bad||'md5(prosrc) '||p.m||'; '; END IF;
    IF position('FOR UPDATE' in p.prosrc) = 0 THEN bad := bad||'sin FOR UPDATE; '; END IF;
    i_gate  := position('puede_editar_datos_prospecto' in p.prosrc);
    i_pa035 := position('PA035' in p.prosrc);
    IF i_pa035 = 0 THEN bad := bad||'sin PA035; '; END IF;
    IF i_gate = 0 OR i_gate >= i_pa035 THEN bad := bad||'el gate no corre antes de PA035 ('||i_gate||' / '||i_pa035||'); '; END IF;
    IF p.acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
      bad := bad||'proacl '||COALESCE(p.acl, 'NULL')||'; ';
    END IF;
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)', 'EXECUTE') THEN
    bad := bad||'authenticated sin EXECUTE; ';
  END IF;
  IF has_function_privilege('anon', 'public.actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)', 'EXECUTE') THEN
    bad := bad||'anon con EXECUTE; ';
  END IF;

  -- (c) PA035 solo en actualizar_prospecto
  v := (SELECT string_agg(f.oid::regprocedure::text, ', ' ORDER BY f.oid::regprocedure::text) FROM pg_proc f WHERE f.prosrc LIKE '%PA035%');
  IF v IS DISTINCT FROM 'actualizar_prospecto(uuid,text,text,text,numeric,numeric,text,uuid)' THEN bad := bad||'PA035 en ['||COALESCE(v, 'ninguna')||']; '; END IF;

  -- (d) huellas sin cambio (ni policies, ni ACL de relaciones, ni ACL de funciones)
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

  IF bad <> '' THEN RAISE EXCEPTION 'MIG374 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
