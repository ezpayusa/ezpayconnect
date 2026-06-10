-- ============================================================
-- 042: Cancelación de cita por el paciente (con motivo)
-- ------------------------------------------------------------
-- Agrega la columna del motivo de cancelación y un RPC SECURITY DEFINER que
-- permite al paciente cancelar SOLO sus propias citas (no completadas/canceladas),
-- guardando el motivo. Devuelve medico_id y clinica_id para poder avisar a la
-- clínica/médico desde el frontend.
-- ============================================================

ALTER TABLE citas ADD COLUMN IF NOT EXISTS motivo_cancelacion TEXT;

CREATE OR REPLACE FUNCTION cancelar_cita_paciente(p_cita_id INTEGER, p_motivo TEXT)
RETURNS TABLE (medico_id UUID, clinica_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE citas c
  SET estado = 'cancelada',
      motivo_cancelacion = p_motivo
  WHERE c.id = p_cita_id
    AND c.paciente_id IN (SELECT pa.id FROM pacientes pa WHERE pa.auth_user_id = auth.uid())
    AND c.estado NOT IN ('completada', 'cancelada')
  RETURNING c.medico_id, c.clinica_id;
END;
$$;

GRANT EXECUTE ON FUNCTION cancelar_cita_paciente(INTEGER, TEXT) TO authenticated;
