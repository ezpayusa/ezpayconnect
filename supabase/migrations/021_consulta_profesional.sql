-- ============================================================
-- MIGRACION: Panel Medico Profesional - Consulta Unificada
-- Fecha: 2026-06-06
-- ============================================================

-- 1. Extender expediente_notas con estructura SOAP y signos vitales
ALTER TABLE expediente_notas
  ADD COLUMN IF NOT EXISTS motivo_consulta TEXT,
  ADD COLUMN IF NOT EXISTS subjetivo TEXT,
  ADD COLUMN IF NOT EXISTS objetivo TEXT,
  ADD COLUMN IF NOT EXISTS analisis TEXT,
  ADD COLUMN IF NOT EXISTS plan TEXT,
  ADD COLUMN IF NOT EXISTS presion_arterial TEXT,
  ADD COLUMN IF NOT EXISTS frecuencia_cardiaca INTEGER,
  ADD COLUMN IF NOT EXISTS frecuencia_respiratoria INTEGER,
  ADD COLUMN IF NOT EXISTS temperatura NUMERIC(4,2),
  ADD COLUMN IF NOT EXISTS peso_kg NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS talla_cm NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS imc NUMERIC(4,2),
  ADD COLUMN IF NOT EXISTS saturacion_o2 INTEGER,
  ADD COLUMN IF NOT EXISTS glucosa INTEGER;

-- Comentarios para documentar los nuevos campos
COMMENT ON COLUMN expediente_notas.motivo_consulta IS 'Razon principal de la visita del paciente';
COMMENT ON COLUMN expediente_notas.subjetivo IS 'Lo que el paciente refiere: sintomas, molestias, historia';
COMMENT ON COLUMN expediente_notas.objetivo IS 'Hallazgos de la exploracion fisica';
COMMENT ON COLUMN expediente_notas.analisis IS 'Diagnostico e interpretacion del medico';
COMMENT ON COLUMN expediente_notas.plan IS 'Tratamiento, estudios, referencias, indicaciones';

-- 2. Crear tabla de signos vitales para historial temporal
CREATE TABLE IF NOT EXISTS signos_vitales (
  id SERIAL PRIMARY KEY,
  paciente_id INTEGER NOT NULL REFERENCES pacientes(id) ON DELETE CASCADE,
  medico_id UUID REFERENCES perfiles(id),
  consulta_id INTEGER REFERENCES expediente_notas(id) ON DELETE CASCADE,
  presion_arterial TEXT,
  frecuencia_cardiaca INTEGER,
  frecuencia_respiratoria INTEGER,
  temperatura NUMERIC(4,2),
  peso_kg NUMERIC(5,2),
  talla_cm NUMERIC(5,2),
  imc NUMERIC(4,2),
  saturacion_o2 INTEGER,
  glucosa INTEGER,
  notas TEXT,
  fecha_toma TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indice para buscar signos vitales por paciente rapidamente
CREATE INDEX IF NOT EXISTS idx_signos_vitales_paciente ON signos_vitales(paciente_id);
CREATE INDEX IF NOT EXISTS idx_signos_vitales_consulta ON signos_vitales(consulta_id);

-- 3. Extender pacientes con campos clinicos estructurados
ALTER TABLE pacientes
  ADD COLUMN IF NOT EXISTS tipo_sangre TEXT,
  ADD COLUMN IF NOT EXISTS antecedentes_personales TEXT,
  ADD COLUMN IF NOT EXISTS antecedentes_familiares TEXT,
  ADD COLUMN IF NOT EXISTS medicamentos_en_uso TEXT;

-- Comentarios
COMMENT ON COLUMN pacientes.tipo_sangre IS 'Ej: A+, O-, B+';
COMMENT ON COLUMN pacientes.antecedentes_personales IS 'Enfermedades previas, cirugias, hospitalizaciones';
COMMENT ON COLUMN pacientes.antecedentes_familiares IS 'Historial medico familiar relevante';
COMMENT ON COLUMN pacientes.medicamentos_en_uso IS 'Medicamentos que toma de forma cronica';

-- 4. Crear tabla de auditoria para sugerencias de IA
CREATE TABLE IF NOT EXISTS auditoria_ia (
  id SERIAL PRIMARY KEY,
  medico_id UUID REFERENCES perfiles(id),
  paciente_id INTEGER REFERENCES pacientes(id),
  consulta_id INTEGER REFERENCES expediente_notas(id),
  prompt TEXT NOT NULL,
  respuesta_ia TEXT NOT NULL,
  accion_medico TEXT,
  modelo_ia TEXT DEFAULT 'gpt-4o-mini',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auditoria_ia_medico ON auditoria_ia(medico_id);
CREATE INDEX IF NOT EXISTS idx_auditoria_ia_consulta ON auditoria_ia(consulta_id);

-- 5. Crear tabla de cache para biblioteca medica (evitar saturar APIs gratuitas)
CREATE TABLE IF NOT EXISTS cache_biblioteca (
  id SERIAL PRIMARY KEY,
  query_hash TEXT NOT NULL UNIQUE,
  query_original TEXT NOT NULL,
  fuente TEXT NOT NULL, -- 'pubmed', 'wikipedia', 'fda'
  resultados JSONB NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cache_biblioteca_hash ON cache_biblioteca(query_hash);

-- 6. Limpiar cache expirada automaticamente (funcion utilitaria)
CREATE OR REPLACE FUNCTION limpiar_cache_biblioteca_expirada()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM cache_biblioteca WHERE expires_at < NOW();
END;
$$;

-- Trigger opcional: calcular IMC automaticamente al insertar signos vitales
CREATE OR REPLACE FUNCTION calcular_imc_signos_vitales()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.peso_kg IS NOT NULL AND NEW.talla_cm IS NOT NULL AND NEW.talla_cm > 0 THEN
    NEW.imc := ROUND((NEW.peso_kg / ((NEW.talla_cm / 100) * (NEW.talla_cm / 100)))::numeric, 2);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_calcular_imc ON signos_vitales;
CREATE TRIGGER trg_calcular_imc
  BEFORE INSERT OR UPDATE ON signos_vitales
  FOR EACH ROW
  EXECUTE FUNCTION calcular_imc_signos_vitales();

-- Mismo trigger para expediente_notas (para guardar el IMC de la consulta actual)
DROP TRIGGER IF EXISTS trg_calcular_imc_expediente ON expediente_notas;
CREATE TRIGGER trg_calcular_imc_expediente
  BEFORE INSERT OR UPDATE ON expediente_notas
  FOR EACH ROW
  EXECUTE FUNCTION calcular_imc_signos_vitales();

-- 7. Vista para resumen de consultas por paciente (util para el detalle del paciente)
CREATE OR REPLACE VIEW v_consultas_paciente AS
SELECT
  en.id,
  en.paciente_id,
  en.medico_id,
  en.cita_id,
  en.motivo_consulta,
  en.subjetivo,
  en.objetivo,
  en.analisis,
  en.plan,
  en.diagnostico,
  en.presion_arterial,
  en.frecuencia_cardiaca,
  en.temperatura,
  en.peso_kg,
  en.talla_cm,
  en.imc,
  en.saturacion_o2,
  en.glucosa,
  en.created_at,
  p.nombre AS paciente_nombre,
  p.apellido AS paciente_apellido,
  pr.nombre_completo AS medico_nombre
FROM expediente_notas en
JOIN pacientes p ON p.id = en.paciente_id
LEFT JOIN perfiles pr ON pr.id = en.medico_id;

-- 8. RLS policies para las nuevas tablas
ALTER TABLE signos_vitales ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditoria_ia ENABLE ROW LEVEL SECURITY;
ALTER TABLE cache_biblioteca ENABLE ROW LEVEL SECURITY;

-- Signos vitales: medico ve los de sus pacientes
CREATE POLICY IF NOT EXISTS "Medico ve signos vitales de sus pacientes"
  ON signos_vitales FOR SELECT
  USING (medico_id = auth.uid() OR paciente_id IN (
    SELECT id FROM pacientes WHERE medico_id = auth.uid()
  ));

-- Auditoria IA: medico ve solo sus propias consultas
CREATE POLICY IF NOT EXISTS "Medico ve su propia auditoria IA"
  ON auditoria_ia FOR SELECT
  USING (medico_id = auth.uid());

-- Admin ve todo
CREATE POLICY IF NOT EXISTS "Admin ve todo signos vitales"
  ON signos_vitales FOR SELECT
  USING (auth.uid() IN (SELECT id FROM perfiles WHERE rol IN ('admin', 'super_admin')));
