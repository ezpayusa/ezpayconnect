-- 189 Auto-registro clínica FASE 1 — función canónica de creación (aditiva, no rompe nada)
-- Modelo: clinicas.doctor_id = DUEÑO (1 por clínica); medico_clinicas = MEMBRESÍA (es_principal).
-- Integridad: un dueño SIEMPRE es también miembro (es_principal) de su propia clínica.
-- Esta RPC crea AMBAS filas atómicamente. NO toca medicos.clinica_id (se elimina en fase posterior).
--
-- Criterio es_principal: TRUE si el médico no tiene ya otra membresía es_principal=true; si ya tiene
-- una principal, la nueva entra es_principal=false (no le pisa su principal existente).

CREATE OR REPLACE FUNCTION public.crear_clinica_con_dueno(
  p_doctor_id uuid,
  p_nombre    text,
  p_pais_id   uuid,
  p_direccion text DEFAULT NULL,
  p_telefono  text DEFAULT NULL,
  p_email     text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_clinica_id   uuid;
  v_es_principal boolean;
BEGIN
  -- ¿el médico ya tiene una clínica principal? Si no, esta es su principal.
  v_es_principal := NOT EXISTS (
    SELECT 1 FROM public.medico_clinicas
    WHERE medico_id = p_doctor_id AND es_principal = true
  );

  -- a) clínica con el médico como dueño
  INSERT INTO public.clinicas (doctor_id, nombre, pais_id, direccion, telefono, email, activa)
  VALUES (p_doctor_id, p_nombre, p_pais_id, p_direccion, p_telefono, p_email, true)
  RETURNING id INTO v_clinica_id;

  -- b) membresía del dueño en su propia clínica
  INSERT INTO public.medico_clinicas (medico_id, clinica_id, es_principal)
  VALUES (p_doctor_id, v_clinica_id, v_es_principal);

  RETURN v_clinica_id;
  -- Cualquier fallo en a) o b) revierte toda la transacción de la función (atomicidad).
END;
$function$;

REVOKE ALL     ON FUNCTION public.crear_clinica_con_dueno(uuid, text, uuid, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_clinica_con_dueno(uuid, text, uuid, text, text, text) TO authenticated;
