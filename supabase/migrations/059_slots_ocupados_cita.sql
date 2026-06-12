-- ============================================================
-- 059: slots_ocupados_cita — qué slots de un médico ya están tomados por citas.
-- El paciente no puede leer las citas de otros (RLS), pero sí necesita saber
-- qué horarios están ocupados para no elegirlos. Devuelve solo fecha+hora
-- (sin datos del otro paciente).
-- ============================================================
CREATE OR REPLACE FUNCTION slots_ocupados_cita(p_medico_id uuid, p_desde date, p_hasta date)
RETURNS TABLE (fecha date, hora_inicio time)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT c.fecha, c.hora_inicio
  FROM citas c
  WHERE c.medico_id = p_medico_id
    AND c.fecha BETWEEN p_desde AND p_hasta
    AND c.estado NOT IN ('cancelada', 'rechazada');
$$;
GRANT EXECUTE ON FUNCTION slots_ocupados_cita(uuid, date, date) TO authenticated;
