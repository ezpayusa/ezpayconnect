-- 203 Activar módulo visitadores = acción atómica de 2 partes: (1) capacidad 'visitadores' (ACCESO, permanente)
-- + (2) plan de CORTESÍA gratis en planes_visitador_contratados (COMBUSTIBLE, vence). El gate de saldo
-- (private.gate_visita_pais) ya cuenta ese plan sin cambios. Cuando se agota, el lab compra un plan normal.
-- Muro ético: solo toca empresa_capacidades y planes_visitador_contratados. No toca agenda de paciente.

-- ============================================================
-- PARTE 1 — columna origen en planes_visitador_contratados
-- ============================================================
-- 'comprado' = plan pagado por la empresa; 'cortesia' = saldo inicial gratis otorgado por admin al activar
-- el módulo visitadores. Los 2 planes existentes quedan 'comprado' por el DEFAULT (correcto).
ALTER TABLE public.planes_visitador_contratados
  ADD COLUMN IF NOT EXISTS origen text NOT NULL DEFAULT 'comprado'
    CHECK (origen IN ('comprado','cortesia'));

COMMENT ON COLUMN public.planes_visitador_contratados.origen IS
  'comprado = plan pagado por la empresa; cortesia = saldo inicial gratis otorgado por admin al activar el módulo visitadores.';

-- ============================================================
-- PARTE 2 — RPC activar_modulo_visitadores (super_admin)
-- ============================================================
-- ERRCODEs (familia PC): PC001 no_autorizado · PC002 empresa_no_existe · PC011 visitas_cortesia_invalida
--                        · PC012 fecha_fin_invalida · PC013 empresa_sin_pais.
CREATE OR REPLACE FUNCTION public.activar_modulo_visitadores(
  p_empresa_id uuid, p_visitas_cortesia int, p_fecha_fin date)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_pais    uuid;
  v_cap     jsonb;
  v_plan    jsonb;
  v_plan_id uuid;
  v_creada  boolean := false;
BEGIN
  -- 1) gate super_admin
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
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

REVOKE ALL     ON FUNCTION public.activar_modulo_visitadores(uuid, int, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.activar_modulo_visitadores(uuid, int, date) TO authenticated;
