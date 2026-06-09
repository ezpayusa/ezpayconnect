-- Migration 037: RPC functions to assign medico and update cita estado (bypass RLS)

CREATE OR REPLACE FUNCTION asignar_medico_cita(
  p_cita_id INTEGER,
  p_medico_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE citas
  SET medico_id = p_medico_id, estado = 'agendada'
  WHERE id = p_cita_id;
END;
$$;

CREATE OR REPLACE FUNCTION actualizar_estado_cita(
  p_cita_id INTEGER,
  p_estado TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE citas
  SET estado = p_estado
  WHERE id = p_cita_id;
END;
$$;
