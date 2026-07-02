-- 197 Canal laboratorios — RPC enrolar_medico: POBLA medicos.lab_enrolador_id con datos reales
-- Un visitador enrola a un médico (camino post-alta: el médico ya existe). El lab se deriva de la
-- SESIÓN del visitador (mi_empresa_proveedor()), NUNCA de un parámetro → un lab no puede reclamar
-- médicos para otro. La puerta comercial es el plan/país (visitador_ve_medico), no el rol.
-- Único canal de escritura: la RLS de medicos NO permite UPDATE por cuentas_proveedor → SECURITY DEFINER.
--
-- MURO ÉTICO: solo lee helpers de proveedor (mi_empresa_proveedor, private.visitador_ve_medico) y
-- escribe medicos.lab_enrolador_id/fecha. CERO relación con disponibilidad_medico contexto='paciente'
-- ni con la agenda de pacientes.
--
-- ERRCODEs (familia PV, capturables por el front): PV010 no-visitador, PV011 sin-plan, PV012 no-medico,
-- PV013 ya-enrolado-por-otro. (país=P0001, bolsa=PV001, head-start=PV002.)

CREATE OR REPLACE FUNCTION public.enrolar_medico(p_medico_id uuid)
RETURNS TABLE (
  estado              text,
  lab_enrolador_id    uuid,
  lab_enrolador_fecha timestamptz
)
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

  -- 2) Puerta comercial: MISMA que ver disponibilidad/agendar (plan activo que cubre el país del médico).
  --    NO se restringe por rol_en_empresa (decisión de producto).
  IF NOT private.visitador_ve_medico(p_medico_id) THEN
    RAISE EXCEPTION 'No tienes un plan activo que cubra a este médico en su país.' USING ERRCODE = 'PV011';
  END IF;

  -- 3) El médico debe existir. Lock de la fila → serializa enrolamientos concurrentes del mismo médico.
  SELECT m.lab_enrolador_id INTO v_actual
  FROM public.medicos m
  WHERE m.id = p_medico_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Médico no encontrado.' USING ERRCODE = 'PV012';
  END IF;

  -- 4) Enrolamiento según estado previo.
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

REVOKE ALL     ON FUNCTION public.enrolar_medico(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.enrolar_medico(uuid) TO authenticated;
