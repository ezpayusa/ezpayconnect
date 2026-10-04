-- ############################################################################################
-- 358 - campanas: un solo camino de publicacion, atomico e idempotente (familia CAMPANAS, punto 3)
-- ############################################################################################
-- Recon del 4-oct-2026 sobre 89e1530 (solo lectura contra prod):
--   * public.aprobar_solicitud_campana(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL) RETURNS integer (id de la
--     publicacion): plpgsql, SECURITY DEFINER, search_path '', VOLATILE, ACL postgres/authenticated/service_role,
--     md5(prosrc) f5a46a02... (CRLF). Gate private.puede_admin_pais(pais de la solicitud): deja pasar al super_admin Y
--     al admin_pais de ese pais (el mensaje dice "solo super_admin"). No miraba el estado de la solicitud, ni el pago, ni
--     si ya habia publicacion; no cargaba peso (quedaba el default 1). Unico caller: SolicitudesCampanaPage (aprobar),
--     montada solo en /admin-ezpay (el AdminRoute confina al admin_pais a /admin-ezpay/pais/{su pais}).
--   * Segundo camino: PagosProveedoresPage.verificar() de un pago tipo='campana' hace INSERT directo de la publicacion
--     (peso del plan) -> UPDATE de la solicitud a 'publicada' -> UPDATE del pago a 'verificado'. Como Solicitudes exige
--     el pago verificado para aprobar, los dos caminos publicaban la misma solicitud: grupo duplicado de prod =
--     solicitud 900dc0b3-c2e7-49aa-a89f-ea8e048bfe05 con publicaciones 6, 7 y 8 (4-jun-2026; datos QA).
--   * pagos tipo='campana': 11, todos verificados, referencia_id siempre uuid, ninguna solicitud con mas de un pago.
-- Cambios:
--   A Limpieza: DELETE de las publicaciones 7 y 8 del grupo (se conserva la 6, la mas antigua por created_at, id);
--     campana_metricas y campana_vistas caen por ON DELETE CASCADE. Aborta si no borra exactamente 2.
--   B CREATE UNIQUE INDEX campanas_publicitarias_solicitud_uniq (solicitud_campana_id) WHERE NOT NULL: una publicacion
--     por solicitud, venga del camino que venga (RPC, INSERT directo del front, policy ALL de admin_pais).
--   C CREATE OR REPLACE de aprobar_solicitud_campana: misma firma y RETURNS integer (el front no cambia de contrato),
--     DEFINER, search_path '', todo calificado, en una sola transaccion:
--       gate super_admin (CA001, ANTES de mirar la solicitud) -> solicitud FOR UPDATE (CA002 si no existe) -> si ya hay
--       publicacion, devuelve su id sin tocar nada (idempotente) -> estado 'enviada' (CA003) -> la empresa opera en el pais
--       (CA008; validacion que ya existia, conservada) -> exactamente 1 pago tipo='campana' con referencia_id = la
--       solicitud, FOR UPDATE (CA004 ninguno, CA005 mas de uno, CA006 rechazado) -> peso del plan (CA007 sin plan) ->
--       pago 'pendiente' pasa a 'verificado' (verificado_por = auth.uid(), fecha_verificacion = now()) -> INSERT de la
--       publicacion con peso -> solicitud 'publicada' (+ notas_admin). No llama a las RPC de notificacion (el front ya
--       las llama).
--     El admin_pais pierde el permiso de aprobar (no tenia caller: el front nunca le muestra la pantalla).
--     REVOKE ALL de PUBLIC y anon; GRANT EXECUTE a authenticated y service_role (ACL igual al de partida).
-- Errcodes: CA001-CA008 (prefijo nuevo, libre en prod y en el repo). Proximo libre: CA009.
-- Probes: P967-P974. Ajustados: P507, P508, P509, P510 (el rechazo de autorizacion pasa de P0001 'No autorizado%' a
--   CA001, y P509 ahora exige que el admin_pais sea rechazado al aprobar).
-- Pendiente de front (fuera de esta migracion): PagosProveedoresPage sigue publicando por INSERT directo; con el indice,
--   un segundo intento choca (23505) en vez de duplicar. Pasarlo a la RPC cierra el segundo camino.
-- Rollback: 358_rollback.sql (cuerpo y ACL de partida, DROP del indice; las publicaciones 7 y 8 NO se restauran).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'('||pg_get_function_arguments(p.oid)||') -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM 'aprobar_solicitud_campana(uuid,text)(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text) -> integer | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion de partida'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM 'f5a46a02c2f06a7f5bcea0dda47c0d2b' THEN bad := bad||'md5(prosrc) de partida'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(g.sol||':'||g.ids, ';') FROM (
          SELECT c.solicitud_campana_id::text AS sol, string_agg(c.id::text, ',' ORDER BY c.created_at, c.id) AS ids
            FROM public.campanas_publicitarias c WHERE c.solicitud_campana_id IS NOT NULL
           GROUP BY c.solicitud_campana_id HAVING count(*) > 1) g);
  IF v IS DISTINCT FROM '900dc0b3-c2e7-49aa-a89f-ea8e048bfe05:6,7,8' THEN bad := bad||'grupo duplicado'||' '||COALESCE(v, '-')||'; '; END IF;
  IF to_regclass('public.campanas_publicitarias_solicitud_uniq') IS NOT NULL THEN bad := bad||'el indice ya existe; '; END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')||' owner='||pg_get_userbyid(p.proowner), ';' ORDER BY p.oid::regprocedure::text)
          FROM pg_proc p WHERE p.pronamespace = 'private'::regnamespace AND p.proname IN ('tiene_rol','empresa_opera_en_pais'));
  IF v IS DISTINCT FROM 'private.empresa_opera_en_pais(uuid,uuid) sp=search_path="" owner=postgres;private.tiene_rol(text[]) sp=search_path="" owner=postgres' THEN bad := bad||'helpers'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG358 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A: limpieza del grupo duplicado
DO $limpieza$
DECLARE n int; v_resto int;
BEGIN
  DELETE FROM public.campanas_publicitarias c
   WHERE c.solicitud_campana_id = '900dc0b3-c2e7-49aa-a89f-ea8e048bfe05'
     AND c.id <> (SELECT c2.id FROM public.campanas_publicitarias c2
                   WHERE c2.solicitud_campana_id = '900dc0b3-c2e7-49aa-a89f-ea8e048bfe05'
                   ORDER BY c2.created_at, c2.id LIMIT 1);
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 2 THEN RAISE EXCEPTION 'MIG358 LIMPIEZA: se esperaban 2 publicaciones borradas, se borraron %', n; END IF;
  v_resto := (SELECT count(*) FROM public.campana_metricas m WHERE m.campana_id IN (7, 8))
           + (SELECT count(*) FROM public.campana_vistas v WHERE v.campana_id IN (7, 8));
  IF v_resto <> 0 THEN RAISE EXCEPTION 'MIG358 LIMPIEZA: quedaron % metricas/vistas de 7 y 8', v_resto; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.campanas_publicitarias c WHERE c.id = 6 AND c.solicitud_campana_id = '900dc0b3-c2e7-49aa-a89f-ea8e048bfe05') THEN
    RAISE EXCEPTION 'MIG358 LIMPIEZA: la publicacion 6 no quedo';
  END IF;
END $limpieza$;

-- ---------------------------------------------------------------------------- B: una publicacion por solicitud
CREATE UNIQUE INDEX campanas_publicitarias_solicitud_uniq
  ON public.campanas_publicitarias (solicitud_campana_id)
  WHERE solicitud_campana_id IS NOT NULL;

-- ---------------------------------------------------------------------------- C: aprobacion atomica e idempotente
CREATE OR REPLACE FUNCTION public.aprobar_solicitud_campana(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_s public.solicitudes_campana%ROWTYPE;
  v_pagos uuid[];
  v_pago public.pagos_proveedor%ROWTYPE;
  v_peso integer;
  v_campana_id integer;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin aprueba campañas' USING ERRCODE = 'CA001';
  END IF;

  SELECT * INTO v_s FROM public.solicitudes_campana s WHERE s.id = p_solicitud_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada' USING ERRCODE = 'CA002';
  END IF;

  -- idempotente: si ya esta publicada, devuelve la publicacion existente sin tocar nada
  SELECT c.id INTO v_campana_id FROM public.campanas_publicitarias c
   WHERE c.solicitud_campana_id = p_solicitud_id ORDER BY c.id LIMIT 1;
  IF v_campana_id IS NOT NULL THEN
    RETURN v_campana_id;
  END IF;

  IF v_s.estado IS DISTINCT FROM 'enviada' THEN
    RAISE EXCEPTION 'La solicitud no está enviada (estado %)', v_s.estado USING ERRCODE = 'CA003';
  END IF;

  IF NOT COALESCE(private.empresa_opera_en_pais(v_s.empresa_id, v_s.pais_id), false) THEN
    RAISE EXCEPTION 'La empresa no opera en el país de la campaña' USING ERRCODE = 'CA008';
  END IF;

  SELECT array_agg(x.id) INTO v_pagos FROM (
    SELECT p.id FROM public.pagos_proveedor p
     WHERE p.tipo = 'campana' AND p.referencia_id = p_solicitud_id::text
     FOR UPDATE) x;
  IF COALESCE(cardinality(v_pagos), 0) = 0 THEN
    RAISE EXCEPTION 'La solicitud no tiene pago' USING ERRCODE = 'CA004';
  END IF;
  IF cardinality(v_pagos) > 1 THEN
    RAISE EXCEPTION 'La solicitud tiene % pagos', cardinality(v_pagos) USING ERRCODE = 'CA005';
  END IF;
  SELECT * INTO v_pago FROM public.pagos_proveedor p WHERE p.id = v_pagos[1];
  IF v_pago.estado = 'rechazado' THEN
    RAISE EXCEPTION 'El pago de la solicitud está rechazado' USING ERRCODE = 'CA006';
  END IF;

  SELECT pp.peso INTO v_peso FROM public.planes_publicidad pp WHERE pp.id = v_s.plan_publicidad_id;
  IF v_peso IS NULL THEN
    RAISE EXCEPTION 'La solicitud no tiene plan de publicidad' USING ERRCODE = 'CA007';
  END IF;

  IF v_pago.estado = 'pendiente' THEN
    UPDATE public.pagos_proveedor
       SET estado = 'verificado', verificado_por = auth.uid(), fecha_verificacion = now()
     WHERE id = v_pago.id;
  END IF;

  INSERT INTO public.campanas_publicitarias
    (titulo, descripcion, tipo, imagen_url, link_url, fecha_inicio, fecha_fin,
     activa, condicion_filtro, genero_filtro, edad_min, edad_max, pais_id,
     peso, empresa_id, solicitud_campana_id)
  VALUES
    (v_s.titulo, v_s.descripcion, v_s.tipo, v_s.imagen_url, v_s.link_url,
     v_s.fecha_inicio, v_s.fecha_fin, true, v_s.condicion_filtro, v_s.genero_filtro,
     v_s.edad_min, v_s.edad_max, v_s.pais_id,
     v_peso, v_s.empresa_id, p_solicitud_id)
  RETURNING id INTO v_campana_id;

  UPDATE public.solicitudes_campana
     SET estado = 'publicada', notas_admin = COALESCE(p_notas_admin, notas_admin)
   WHERE id = p_solicitud_id;

  RETURN v_campana_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.aprobar_solicitud_campana(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aprobar_solicitud_campana(uuid, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'('||pg_get_function_arguments(p.oid)||') -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default'), ';')
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM 'aprobar_solicitud_campana(uuid,text)(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text) -> integer | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN bad := bad||'funcion nueva'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT string_agg(md5(p.prosrc), ',') FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'aprobar_solicitud_campana');
  IF v IS DISTINCT FROM '64b305dcaa95e8bd2a881d64afc45413' THEN bad := bad||'md5(prosrc) nuevo'||' '||COALESCE(v, '-')||'; '; END IF;
  IF has_function_privilege('anon', 'public.aprobar_solicitud_campana(uuid,text)', 'EXECUTE') THEN bad := bad||'anon tiene EXECUTE; '; END IF;
  v := (SELECT pg_get_indexdef(i.indexrelid)||' valid='||i.indisvalid::text||' ready='||i.indisready::text||' unique='||i.indisunique::text
          FROM pg_index i WHERE i.indexrelid = to_regclass('public.campanas_publicitarias_solicitud_uniq'));
  IF v IS DISTINCT FROM 'CREATE UNIQUE INDEX campanas_publicitarias_solicitud_uniq ON public.campanas_publicitarias USING btree (solicitud_campana_id) WHERE (solicitud_campana_id IS NOT NULL) valid=true ready=true unique=true' THEN bad := bad||'indice'||' '||COALESCE(v, '-')||'; '; END IF;
  IF EXISTS (SELECT 1 FROM public.campanas_publicitarias c WHERE c.solicitud_campana_id IS NOT NULL GROUP BY c.solicitud_campana_id HAVING count(*) > 1) THEN
    bad := bad||'quedan grupos duplicados; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG358 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
