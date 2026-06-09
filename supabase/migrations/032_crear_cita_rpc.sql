-- ============================================
-- Migración 032: Función RPC crear_cita para saltar PostgREST schema cache
-- EzPayConnect
-- ============================================

-- Función para crear citas con clinica_id (evita bug de PostgREST schema cache)
CREATE OR REPLACE FUNCTION crear_cita(
  p_paciente_id INTEGER,
  p_medico_id UUID DEFAULT NULL,
  p_clinica_id INTEGER DEFAULT NULL,
  p_fecha DATE DEFAULT NULL,
  p_hora_inicio TIME DEFAULT NULL,
  p_hora_fin TIME DEFAULT NULL,
  p_motivo TEXT DEFAULT NULL,
  p_notas TEXT DEFAULT NULL,
  p_estado TEXT DEFAULT 'pendiente',
  p_pais_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cita_id INTEGER;
BEGIN
  INSERT INTO citas (
    paciente_id,
    medico_id,
    clinica_id,
    fecha,
    hora_inicio,
    hora_fin,
    motivo,
    notas,
    estado,
    pais_id
  ) VALUES (
    p_paciente_id,
    p_medico_id,
    p_clinica_id,
    p_fecha,
    p_hora_inicio,
    p_hora_fin,
    p_motivo,
    p_notas,
    p_estado,
    p_pais_id
  )
  RETURNING id INTO v_cita_id;

  RETURN v_cita_id;
END;
$$;

COMMENT ON FUNCTION crear_cita IS 'Crea una cita médica saltando el schema cache de PostgREST. Usar cuando el INSERT directo falle por clinica_id.';
