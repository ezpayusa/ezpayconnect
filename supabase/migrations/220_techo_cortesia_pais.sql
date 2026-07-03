-- ============================================================================
-- Migración 220: techo de cortesía de visitas configurable por país +
--                activar_modulo_visitadores lo respeta para admin_pais (fail-closed)
-- ============================================================================
-- CONTEXTO: configuracion_pais no tenía columna de techo. El maestro (super_admin) configura el
-- techo por país con un UPDATE DIRECTO — la RLS existente de configuracion_pais
-- ("Allow admin write configuracion_pais", ALL, qual=super_admin) ya lo permite → NO hace falta
-- ninguna RPC nueva de configuración. admin_pais puede LEER la tabla (policy separada) pero NO
-- escribirla, y así se mantiene: el techo lo define el maestro, no el propio admin_pais.
--
-- DECISIÓN CONFIRMADA (fail-closed): si techo_cortesia_visitas es NULL (nunca configurado para ese
-- país), un admin_pais NO puede crear cortesías. super_admin NUNCA tiene esta restricción (es quien
-- define los techos, autoridad global).
--
-- Se usa el país de la EMPRESA destino (v_pais, ya obtenido en el paso 5 de la función y confirmado
-- no-NULL), no el país del caller: aunque el gate (admin_puede_gestionar_empresa) garantiza que
-- coinciden, así el chequeo no depende de esa asunción implícita.
-- ERRCODEs nuevos (verificados libres): PC017 cortesia_no_configurada_para_pais,
-- PC018 visitas_cortesia_excede_techo.
-- ============================================================================

BEGIN;

-- 1a) columna de techo (NULL = "no configurado") + CHECK de validez (>0 o NULL).
ALTER TABLE public.configuracion_pais
  ADD COLUMN techo_cortesia_visitas int,
  ADD CONSTRAINT techo_cortesia_visitas_valido CHECK (techo_cortesia_visitas IS NULL OR techo_cortesia_visitas > 0);

-- 1b) activar_modulo_visitadores: respeta el techo para admin_pais. MISMA firma; único cambio vs la
--     versión de mig 219 = el bloque "5b) TECHO DE CORTESÍA" (+ la variable v_techo). Todo lo demás igual.
CREATE OR REPLACE FUNCTION public.activar_modulo_visitadores(p_empresa_id uuid, p_visitas_cortesia integer, p_fecha_fin date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pais    uuid;
  v_techo   int;
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

  -- 5b) TECHO DE CORTESÍA (mig 220): SOLO admin_pais. Usa el país de la EMPRESA (v_pais). Fail-closed:
  --     techo NULL (no configurado) => no puede crear cortesías. super_admin NO pasa por esta validación.
  IF get_auth_user_rol() = 'admin_pais' THEN
    SELECT techo_cortesia_visitas INTO v_techo FROM public.configuracion_pais WHERE id = v_pais;
    IF v_techo IS NULL THEN
      RAISE EXCEPTION 'cortesia_no_configurada_para_pais' USING ERRCODE = 'PC017';
    END IF;
    IF p_visitas_cortesia > v_techo THEN
      RAISE EXCEPTION 'visitas_cortesia_excede_techo' USING ERRCODE = 'PC018';
    END IF;
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
