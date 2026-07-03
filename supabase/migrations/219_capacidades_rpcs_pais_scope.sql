-- ============================================================================
-- Migración 219: acotar las 6 RPCs de capacidades por país (super_admin global, admin_pais su país)
-- ============================================================================
-- GAP QUE CIERRA: las 6 RPCs de gestión de capacidades (mig 200 + 203) tenían gate SOLO super_admin
-- (`private.tiene_rol(['super_admin'])`). Con admin_pais reintroducido (migs 216-218), estas RPCs
-- deben admitir a un admin_pais pero ACOTADO a empresas de SU propio país. Hoy NINGUNA tiene
-- call-site en el front → no rompe nada en uso; prepara el terreno para el panel de admin_pais.
--
-- HELPER nuevo `private.admin_puede_gestionar_empresa(p_empresa_id)`: super_admin (global) O
-- admin_pais cuya empresa destino sea de su país (empresas_proveedoras.pais_id = get_auth_user_pais_id()).
-- Envuelto en COALESCE(...,false) → NUNCA devuelve NULL (preserva el fail-closed que daba el
-- COALESCE del gate original; sin él, tiene_rol NULL + no-admin_pais daría NULL → IF NOT NULL no
-- dispara el RAISE = fail-open). Si la empresa no existe, el EXISTS no matchea → el helper da false →
-- un admin_pais con un empresa_id inexistente ve 'no_autorizado' (PC001) en vez de 'empresa_no_existe'
-- (PC002); es aceptable a propósito: no revela si la empresa existe a alguien sin acceso.
--
-- VALIDACIÓN DE SCOPE DE CATÁLOGO: solo en las 2 RPCs que ASIGNAN (activar_capacidad_suelta,
-- asignar_tier) — un admin_pais no puede asignar una capacidad/tier de OTRO país (aunque la empresa
-- destino sea suya). super_admin sin esta restricción (autoridad global). NO aplica a
-- desactivar/quitar (quitar algo ya asignado no revalida el catálogo, solo la empresa = ya cubierta
-- por el helper), ni a listar (solo lectura de lo asignado), ni a activar_modulo_visitadores (activa
-- la capacidad fija 'visitadores', global por diseño desde mig 200, no referencia catálogo con scope).
-- ERRCODEs nuevos: PC015 capacidad_de_otro_pais, PC016 tier_de_otro_pais (PC014 ya lo usa mig 204).
-- ============================================================================

BEGIN;

-- ========================= HELPER =========================
CREATE OR REPLACE FUNCTION private.admin_puede_gestionar_empresa(p_empresa_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT COALESCE(
    private.tiene_rol(ARRAY['super_admin'])
    OR (
      get_auth_user_rol() = 'admin_pais'
      AND EXISTS (
        SELECT 1 FROM empresas_proveedoras e
        WHERE e.id = p_empresa_id AND e.pais_id = get_auth_user_pais_id()
      )
    ),
    false
  );
$function$;

REVOKE ALL     ON FUNCTION private.admin_puede_gestionar_empresa(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.admin_puede_gestionar_empresa(uuid) TO authenticated, service_role;


-- ========================= 1) activar_capacidad_suelta =========================
CREATE OR REPLACE FUNCTION public.activar_capacidad_suelta(p_empresa_id uuid, p_capacidad_codigo text, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS SETOF empresa_capacidades
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE id = p_empresa_id) THEN
    RAISE EXCEPTION 'empresa_no_existe' USING ERRCODE = 'PC002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.capacidades_catalogo WHERE codigo = p_capacidad_codigo) THEN
    RAISE EXCEPTION 'capacidad_no_existe' USING ERRCODE = 'PC003';
  END IF;

  -- SCOPE (mig 219): un admin_pais no puede asignar una capacidad de OTRO país (super_admin sí, global).
  IF get_auth_user_rol() = 'admin_pais' THEN
    IF EXISTS (
      SELECT 1 FROM public.capacidades_catalogo
      WHERE codigo = p_capacidad_codigo
        AND pais_id IS NOT NULL
        AND pais_id <> get_auth_user_pais_id()
    ) THEN
      RAISE EXCEPTION 'capacidad_de_otro_pais' USING ERRCODE = 'PC015';
    END IF;
  END IF;

  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  VALUES (p_empresa_id, p_capacidad_codigo, true, 'suelta', NULL, now(), p_hasta, auth.uid())
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = EXCLUDED.hasta, activada_por = EXCLUDED.activada_por;
    -- NO se toca origen/tier_id: si venía de un tier, se queda como estaba (solo re-activa). updated_at por trigger.

  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND capacidad_codigo = p_capacidad_codigo;
END;
$function$;


-- ========================= 2) desactivar_capacidad =========================
CREATE OR REPLACE FUNCTION public.desactivar_capacidad(p_empresa_id uuid, p_capacidad_codigo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  UPDATE public.empresa_capacidades
    SET activa = false
    WHERE empresa_id = p_empresa_id AND capacidad_codigo = p_capacidad_codigo;
  -- no-op idempotente si no existe la fila. updated_at por trigger.
END;
$function$;


-- ========================= 3) asignar_tier =========================
CREATE OR REPLACE FUNCTION public.asignar_tier(p_empresa_id uuid, p_tier_id uuid, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS SETOF empresa_capacidades
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE id = p_empresa_id) THEN
    RAISE EXCEPTION 'empresa_no_existe' USING ERRCODE = 'PC002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tiers_catalogo WHERE id = p_tier_id) THEN
    RAISE EXCEPTION 'tier_no_existe' USING ERRCODE = 'PC004';
  END IF;

  -- SCOPE (mig 219): un admin_pais no puede asignar un tier de OTRO país (super_admin sí, global).
  IF get_auth_user_rol() = 'admin_pais' THEN
    IF EXISTS (
      SELECT 1 FROM public.tiers_catalogo
      WHERE id = p_tier_id
        AND pais_id IS NOT NULL
        AND pais_id <> get_auth_user_pais_id()
    ) THEN
      RAISE EXCEPTION 'tier_de_otro_pais' USING ERRCODE = 'PC016';
    END IF;
  END IF;

  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  SELECT p_empresa_id, tc.capacidad_codigo, true, 'tier', p_tier_id, now(), p_hasta, auth.uid()
  FROM public.tier_capacidades tc
  WHERE tc.tier_id = p_tier_id
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = EXCLUDED.hasta, activada_por = EXCLUDED.activada_por,
        origen = 'tier', tier_id = EXCLUDED.tier_id;  -- el tier adopta la capacidad. updated_at por trigger.

  -- set resultante: capacidades activas vigentes de la empresa (las sueltas ajenas al tier se mantienen)
  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND activa = true AND (hasta IS NULL OR hasta > now());
END;
$function$;


-- ========================= 4) quitar_tier =========================
CREATE OR REPLACE FUNCTION public.quitar_tier(p_empresa_id uuid, p_tier_id uuid)
 RETURNS SETOF empresa_capacidades
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  UPDATE public.empresa_capacidades
    SET activa = false
    WHERE empresa_id = p_empresa_id AND origen = 'tier' AND tier_id = p_tier_id;
  -- updated_at por trigger.

  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND activa = true AND (hasta IS NULL OR hasta > now());
END;
$function$;


-- ========================= 5) listar_capacidades_empresa =========================
CREATE OR REPLACE FUNCTION public.listar_capacidades_empresa(p_empresa_id uuid)
 RETURNS SETOF empresa_capacidades
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id
    ORDER BY capacidad_codigo;
END;
$function$;


-- ========================= 6) activar_modulo_visitadores =========================
CREATE OR REPLACE FUNCTION public.activar_modulo_visitadores(p_empresa_id uuid, p_visitas_cortesia integer, p_fecha_fin date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pais    uuid;
  v_cap     jsonb;
  v_plan    jsonb;
  v_plan_id uuid;
  v_creada  boolean := false;
BEGIN
  -- 1) gate: super_admin (global) o admin_pais de la empresa (mig 219)
  IF NOT private.admin_puede_gestionar_empresa(p_empresa_id) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  -- 2) empresa existe
  IF NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE id = p_empresa_id) THEN
    RAISE EXCEPTION 'empresa_no_existe' USING ERRCODE = 'PC002';
  END IF;
  -- 3) visitas de cortesía positivas
  IF p_visitas_cortesia IS NULL OR p_visitas_cortesia <= 0 THEN
    RAISE EXCEPTION 'visitas_cortesia_invalida' USING ERRCODE = 'PC011';
  END IF;
  -- 4) fecha de vencimiento futura
  IF p_fecha_fin IS NULL OR p_fecha_fin <= CURRENT_DATE THEN
    RAISE EXCEPTION 'fecha_fin_invalida' USING ERRCODE = 'PC012';
  END IF;
  -- 5) país de la empresa (obligatorio para la cortesía)
  SELECT pais_id INTO v_pais FROM public.empresas_proveedoras WHERE id = p_empresa_id;
  IF v_pais IS NULL THEN
    RAISE EXCEPTION 'empresa_sin_pais' USING ERRCODE = 'PC013';
  END IF;

  -- 6) activar capacidad 'visitadores' = ACCESO permanente (hasta=NULL). Independiente del vencimiento de la cortesía.
  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  VALUES (p_empresa_id, 'visitadores', true, 'suelta', NULL, now(), NULL, auth.uid())
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = NULL, activada_por = auth.uid();  -- garantiza acceso permanente; NO pisa origen (tier). updated_at por trigger.

  SELECT to_jsonb(ec) INTO v_cap
  FROM public.empresa_capacidades ec
  WHERE ec.empresa_id = p_empresa_id AND ec.capacidad_codigo = 'visitadores';

  -- 7) plan de cortesía — IDEMPOTENCIA: si ya hay una cortesía activa y vigente para ese país, NO apilar otra.
  SELECT id INTO v_plan_id
  FROM public.planes_visitador_contratados
  WHERE empresa_id = p_empresa_id AND origen = 'cortesia' AND estado = 'activo'
    AND pais_id = v_pais AND CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin
  LIMIT 1;

  IF v_plan_id IS NOT NULL THEN
    v_creada := false;  -- ya tiene cortesía vigente
  ELSE
    INSERT INTO public.planes_visitador_contratados
      (empresa_id, plan_visitador_id, pais_id, cantidad_visitas_incluidas, visitas_usadas,
       precio_pagado, fecha_inicio, fecha_fin, estado, origen)
    VALUES
      (p_empresa_id, 1, v_pais, p_visitas_cortesia, 0,
       0.00, CURRENT_DATE, p_fecha_fin, 'activo', 'cortesia')
    RETURNING id INTO v_plan_id;
    v_creada := true;
  END IF;

  SELECT to_jsonb(p) INTO v_plan
  FROM public.planes_visitador_contratados p WHERE p.id = v_plan_id;

  -- 8) retorno
  RETURN jsonb_build_object(
    'estado',          CASE WHEN v_creada THEN 'activado' ELSE 'cortesia_ya_activa' END,
    'cortesia_creada', v_creada,
    'capacidad',       v_cap,
    'plan_cortesia',   v_plan
  );
END;
$function$;

COMMIT;
