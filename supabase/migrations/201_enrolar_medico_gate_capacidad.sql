-- 201 Primer enganche del gate de capacidades a una RPC de negocio.
-- enrolar_medico ahora exige que la empresa del visitador tenga la capacidad 'enrolamiento' activa/vigente,
-- ANTES del chequeo de plan/país (PV011). Orden de gates:
--   (1) ¿visitador activo? PV010 → (2) ¿empresa tiene módulo 'enrolamiento'? PV014 (NUEVO)
--   → (3) ¿plan que cubre al médico? PV011 → (4) enrolamiento (PV012/PV013).
-- La capacidad es más fundamental que el plan ("¿tu empresa contrató esto?") → mensaje correcto (módulo, no plan).
-- Reproduce la def viva (mig 197) SIN otros cambios. CREATE OR REPLACE preserva grants (no re-otorgo).
-- Muro ético: sin cambios — solo medicos + helpers. No toca agenda de paciente.

CREATE OR REPLACE FUNCTION public.enrolar_medico(p_medico_id uuid)
RETURNS TABLE (estado text, lab_enrolador_id uuid, lab_enrolador_fecha timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_empresa uuid;
  v_actual  uuid;
BEGIN
  -- 1) Debe ser un visitador activo (empresa derivada de la sesión).
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'No autorizado: no eres un visitador activo.' USING ERRCODE = 'PV010';
  END IF;

  -- 2) Gate de CAPACIDAD (NUEVO): la empresa debe tener el módulo 'enrolamiento' activo/vigente.
  --    Va antes del plan/país porque es la pregunta más fundamental ("¿tu empresa contrató esto?").
  IF NOT private.empresa_tiene_capacidad(v_empresa, 'enrolamiento') THEN
    RAISE EXCEPTION 'Tu empresa no tiene activado el módulo de enrolamiento. Contactá a soporte para activarlo.' USING ERRCODE = 'PV014';
  END IF;

  -- 3) Puerta comercial: MISMA que ver disponibilidad/agendar (plan activo que cubre el país del médico).
  --    NO se restringe por rol_en_empresa (decisión de producto).
  IF NOT private.visitador_ve_medico(p_medico_id) THEN
    RAISE EXCEPTION 'No tienes un plan activo que cubra a este médico en su país.' USING ERRCODE = 'PV011';
  END IF;

  -- 4) El médico debe existir. Lock de la fila → serializa enrolamientos concurrentes del mismo médico.
  SELECT m.lab_enrolador_id INTO v_actual
  FROM public.medicos m
  WHERE m.id = p_medico_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Médico no encontrado.' USING ERRCODE = 'PV012';
  END IF;

  -- 5) Enrolamiento según estado previo.
  IF v_actual IS NULL THEN
    -- Libre → enrolar con este lab.
    UPDATE public.medicos
      SET lab_enrolador_id = v_empresa, lab_enrolador_fecha = now()
      WHERE id = p_medico_id;
    RETURN QUERY
      SELECT 'enrolado'::text, m.lab_enrolador_id, m.lab_enrolador_fecha
      FROM public.medicos m WHERE m.id = p_medico_id;

  ELSIF v_actual = v_empresa THEN
    -- Ya enrolado por ESTE lab → no-op idempotente (no error).
    RETURN QUERY
      SELECT 'ya_enrolado_por_ti'::text, m.lab_enrolador_id, m.lab_enrolador_fecha
      FROM public.medicos m WHERE m.id = p_medico_id;

  ELSE
    -- Otro lab → mensaje de negocio claro (defensa en profundidad; el trigger de inmutabilidad
    -- de la mig 193 bloquearía el UPDATE de todas formas).
    RAISE EXCEPTION 'Este médico ya fue enrolado por otro laboratorio.' USING ERRCODE = 'PV013';
  END IF;
END;
$function$;
