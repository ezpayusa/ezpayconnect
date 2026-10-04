-- ############################################################################################
-- 361 - campanas: la duracion no puede superar los dias del plan (familia CAMPANAS, Medio 1 del review del #33)
-- ############################################################################################
-- Recon del 4-oct-2026 (solo lectura contra prod, 358-360 aplicadas):
--   * planes_publicidad: 1 Banner Basico 7 dias, 2 Banner Profesional 15, 3 Campana Premium 30 (todos activos).
--   * Ninguna RPC miraba las fechas: una campana del plan de 7 dias podia durar 30 (hoy hay 4 publicadas asi: 13, 14, 29
--     y 30 dias con el plan 1). Las publicadas NO se tocan.
--   * md5 de partida: aprobar_solicitud_campana 64b305dc... (358), solicitar_pago_campana 49a10261... (359); sin CRLF.
-- Cambios (mismas firmas, mismo RETURNS, DEFINER, search_path '', ACL igual; el resto de cada cuerpo identico):
--   A solicitar_pago_campana: despues de CA011 (no esta en borrador) y antes de CA010 (precio): fecha_fin < fecha_inicio
--     -> CA015; fecha_fin - fecha_inicio > planes_publicidad.dias del plan -> CA014. Sin plan, la comparacion es NULL y
--     sigue a CA010 como antes.
--   B aprobar_solicitud_campana: las mismas dos validaciones DESPUES de la rama idempotente y de CA003, asi una
--     solicitud ya publicada sigue devolviendo su id aunque exceda.
-- Errcodes: CA014, CA015. Proximo libre: CA016. Sin tocar datos.
-- Probes: P990-P995. Rollback: 361_rollback.sql (los dos cuerpos exactos de la 358/359; sin CRLF, van literales).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'('||pg_get_function_arguments(p.oid)||') -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default')||' md5='||md5(p.prosrc), ' ;; ' ORDER BY p.oid::regprocedure::text)
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('aprobar_solicitud_campana', 'solicitar_pago_campana'));
  IF v IS DISTINCT FROM 'aprobar_solicitud_campana(uuid,text)(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text) -> integer | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} md5=64b305dcaa95e8bd2a881d64afc45413 ;; solicitar_pago_campana(uuid,text)(p_solicitud_id uuid, p_comprobante_path text) -> uuid | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} md5=49a10261bb1ad8c5ac49722afb295a15' THEN
    bad := bad||'funciones de partida '||COALESCE(v, '-')||'; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '6fd0d66ddce6b6d6d3ac349911c31153 311' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'a01b26ab47262f58c617215636ecf560 378' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG361 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A: solicitar_pago_campana
CREATE OR REPLACE FUNCTION public.solicitar_pago_campana(p_solicitud_id uuid, p_comprobante_path text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_empresa uuid := private.mi_empresa_onboarding();
  v_rol text := private.mi_rol_onboarding();
  v_s public.solicitudes_campana%ROWTYPE;
  v_monto numeric; v_moneda text; v_pago uuid;
BEGIN
  IF v_empresa IS NULL OR NOT COALESCE(v_rol = ANY (ARRAY['admin','editor','finanzas','marketing','supervisor']), false) THEN
    RAISE EXCEPTION 'No autorizado: la solicitud no es de tu empresa' USING ERRCODE = 'CA009';
  END IF;
  SELECT * INTO v_s FROM public.solicitudes_campana s WHERE s.id = p_solicitud_id AND s.empresa_id = v_empresa FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No autorizado: la solicitud no es de tu empresa' USING ERRCODE = 'CA009';
  END IF;

  IF EXISTS (SELECT 1 FROM public.pagos_proveedor p WHERE p.tipo = 'campana' AND p.referencia_id = p_solicitud_id::text) THEN
    RAISE EXCEPTION 'La campaña ya tiene un pago registrado' USING ERRCODE = 'CA012';
  END IF;
  IF v_s.estado IS DISTINCT FROM 'borrador' THEN
    RAISE EXCEPTION 'La campaña no está en borrador (estado %)', v_s.estado USING ERRCODE = 'CA011';
  END IF;

  -- 361: la duracion no puede superar los dias del plan (ni terminar antes de empezar)
  IF v_s.fecha_fin < v_s.fecha_inicio THEN
    RAISE EXCEPTION 'La fecha de fin es anterior a la de inicio' USING ERRCODE = 'CA015';
  END IF;
  IF v_s.fecha_fin - v_s.fecha_inicio > (SELECT pp.dias FROM public.planes_publicidad pp WHERE pp.id = v_s.plan_publicidad_id) THEN
    RAISE EXCEPTION 'La duración de la campaña supera los días del plan' USING ERRCODE = 'CA014';
  END IF;

  SELECT x.monto, x.moneda INTO v_monto, v_moneda FROM private.precio_plan_publicidad(v_s.pais_id, v_s.plan_publicidad_id) x;
  IF v_monto IS NULL OR v_monto <= 0 OR v_moneda IS NULL THEN
    RAISE EXCEPTION 'El plan de la campaña no tiene precio para tu país' USING ERRCODE = 'CA010';
  END IF;

  IF p_comprobante_path IS NULL OR NOT starts_with(p_comprobante_path, v_empresa::text || '/')
     OR NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'comprobantes' AND o.name = p_comprobante_path) THEN
    RAISE EXCEPTION 'Comprobante inválido: subilo de nuevo' USING ERRCODE = 'CA013';
  END IF;

  INSERT INTO public.pagos_proveedor
    (empresa_id, tipo, referencia_id, monto, moneda, metodo_pago, comprobante_url, estado, fecha_pago)
  VALUES
    (v_empresa, 'campana', p_solicitud_id::text, v_monto, v_moneda, 'transferencia', p_comprobante_path, 'pendiente', CURRENT_DATE)
  RETURNING id INTO v_pago;

  UPDATE public.solicitudes_campana SET estado = 'enviada', monto_pagado = v_monto WHERE id = p_solicitud_id;

  RETURN v_pago;
END;
$function$;

-- ---------------------------------------------------------------------------- B: aprobar_solicitud_campana
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

  -- 361: la duracion no puede superar los dias del plan (ni terminar antes de empezar)
  IF v_s.fecha_fin < v_s.fecha_inicio THEN
    RAISE EXCEPTION 'La fecha de fin es anterior a la de inicio' USING ERRCODE = 'CA015';
  END IF;
  IF v_s.fecha_fin - v_s.fecha_inicio > (SELECT pp.dias FROM public.planes_publicidad pp WHERE pp.id = v_s.plan_publicidad_id) THEN
    RAISE EXCEPTION 'La duración de la campaña supera los días del plan' USING ERRCODE = 'CA014';
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
REVOKE ALL ON FUNCTION public.solicitar_pago_campana(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.solicitar_pago_campana(uuid, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT string_agg(p.oid::regprocedure::text||'('||pg_get_function_arguments(p.oid)||') -> '||pg_get_function_result(p.oid)||' | definer='||p.prosecdef::text||' sp='||COALESCE(array_to_string(p.proconfig, ','), '-')
          ||' vol='||p.provolatile::text||' owner='||pg_get_userbyid(p.proowner)||' acl='||COALESCE(p.proacl::text, 'default')||' md5='||md5(p.prosrc), ' ;; ' ORDER BY p.oid::regprocedure::text)
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('aprobar_solicitud_campana', 'solicitar_pago_campana'));
  IF v IS DISTINCT FROM 'aprobar_solicitud_campana(uuid,text)(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text) -> integer | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} md5=b0492c9d72db61d9bc9b6f43f0c580ce ;; solicitar_pago_campana(uuid,text)(p_solicitud_id uuid, p_comprobante_path text) -> uuid | definer=true sp=search_path="" vol=v owner=postgres acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} md5=9d8a997a3ec046356641af1ce015b905' THEN
    bad := bad||'funciones nuevas '||COALESCE(v, '-')||'; ';
  END IF;
  IF has_function_privilege('anon', 'public.aprobar_solicitud_campana(uuid,text)', 'EXECUTE') OR has_function_privilege('anon', 'public.solicitar_pago_campana(uuid,text)', 'EXECUTE') THEN
    bad := bad||'anon tiene EXECUTE; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '6fd0d66ddce6b6d6d3ac349911c31153 311' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'a01b26ab47262f58c617215636ecf560 378' THEN bad := bad||'ACL de funciones public/private'||' '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG361 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
