-- ============================================
-- Migración 034: Agregar clinica_id a citas + actualizar función crear_cita
-- EzPayConnect
-- ============================================

-- 1. Agregar clinica_id a citas si no existe (UUID para coincidir con clinicas.id actual)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'citas' AND column_name = 'clinica_id'
  ) THEN
    ALTER TABLE citas ADD COLUMN clinica_id UUID REFERENCES clinicas(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 2. Eliminar versiones viejas de crear_cita (evita conflictos de overload)
DROP FUNCTION IF EXISTS crear_cita(integer, uuid, integer, date, time without time zone, time without time zone, text, text, text, uuid);
DROP FUNCTION IF EXISTS crear_cita(integer, uuid, uuid, date, time without time zone, time without time zone, text, text, text, uuid);
DROP FUNCTION IF EXISTS crear_cita;

-- 3. Crear función crear_cita con UUID en clinica_id
CREATE OR REPLACE FUNCTION crear_cita(
  p_paciente_id INTEGER,
  p_medico_id UUID DEFAULT NULL,
  p_clinica_id UUID DEFAULT NULL,
  p_fecha DATE DEFAULT NULL,
  p_hora_inicio TIME DEFAULT NULL,
  p_hora_fin TIME DEFAULT NULL,
  p_motivo TEXT DEFAULT NULL,
  p_notas TEXT DEFAULT NULL,
  p_estado TEXT DEFAULT 'agendada',
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

COMMENT ON FUNCTION crear_cita IS 'Crea una cita médica. Usa UUID para clinica_id para coincidir con clinicas.id.';
