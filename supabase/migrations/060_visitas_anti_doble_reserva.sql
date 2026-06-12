-- ============================================================
-- 060: Evitar doble-reserva de un slot del médico entre laboratorios.
--  (1) Una visita 'rechazada' por el supervisor LIBERA el slot.
--  (2) Índice único: no puede haber dos visitas ACTIVAS en el mismo
--      médico+fecha+hora (aunque sean de empresas distintas). El segundo
--      INSERT simultáneo falla con 23505 y el frontend avisa.
-- ============================================================

-- (1) get_slots_ocupados ya no cuenta las rechazadas como ocupadas.
CREATE OR REPLACE FUNCTION get_slots_ocupados(p_medico_id uuid, p_fecha_inicio date, p_fecha_fin date)
RETURNS TABLE (fecha_visita date, hora_inicio time without time zone, hora_fin time without time zone)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT v.fecha_visita, v.hora_inicio, v.hora_fin
  FROM visitas_agendadas v
  WHERE v.medico_id = p_medico_id
    AND v.fecha_visita BETWEEN p_fecha_inicio AND p_fecha_fin
    AND v.estado NOT IN ('cancelada', 'rechazada', 'no_asistio')
  ORDER BY v.fecha_visita, v.hora_inicio;
END;
$$;

-- (2) Candado atómico: un solo slot activo por médico+fecha+hora.
CREATE UNIQUE INDEX IF NOT EXISTS ux_visita_medico_slot
ON visitas_agendadas (medico_id, fecha_visita, hora_inicio)
WHERE estado NOT IN ('cancelada', 'rechazada', 'no_asistio');
