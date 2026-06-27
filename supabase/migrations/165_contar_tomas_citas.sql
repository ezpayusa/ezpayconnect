-- 165 · contar_tomas_citas — conteo de tomas de signos_vitales por cita, para el ✓ "ya tiene tomas"
-- en la cola de Admisión SIN N+1. Patrón DEFINER idéntico a listar_signos_vitales_cita (mig 164):
-- gate de rol al tope + confinamiento por pertenencia. Aquí el confinamiento es PER CITA (cada toma se
-- filtra por private.paciente_en_clinica_de(sv.paciente_id)).
-- Rol = MISMA audiencia que listar_signos_vitales_cita (captura-only): medico/asistente_medico/enfermeria.
--   No incluye gestión: el ✓ (conteo visible) sigue exactamente a quién puede ver la serie → sin la
--   incoherencia "conteo visible / serie denegada".
-- Confinamiento (decisión): una cita_id ajena (su paciente no está en clínica del caller) NO aparece en
--   el resultado (no se devuelve n=0) → no sirve para sondear existencia de citas de otras clínicas.
-- Citas con CERO tomas: tampoco aparecen (no hay filas en signos_vitales) → la UI las trata como
--   "sin tomas" por ausencia.
-- Escala: una sola query (cita_id = ANY(...) + GROUP BY), usa el índice idx_signos_vitales_cita. Sin N+1.
CREATE OR REPLACE FUNCTION public.contar_tomas_citas(p_cita_ids bigint[])
RETURNS TABLE(cita_id bigint, n bigint)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- Gate fail-closed (mismo que listar_signos_vitales_cita): rol de captura.
  IF NOT COALESCE(private.tiene_rol(ARRAY['medico','asistente_medico','enfermeria']), false) THEN
    RAISE EXCEPTION 'No autorizado: rol';
  END IF;

  -- Una sola query, confinamiento per-cita por pertenencia del paciente de cada toma.
  RETURN QUERY
  SELECT sv.cita_id, count(*)::bigint AS n
  FROM public.signos_vitales sv
  WHERE sv.cita_id = ANY (p_cita_ids)
    AND COALESCE(private.paciente_en_clinica_de(sv.paciente_id), false)
  GROUP BY sv.cita_id;
END;
$function$;
REVOKE ALL    ON FUNCTION public.contar_tomas_citas(bigint[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.contar_tomas_citas(bigint[]) TO authenticated;
