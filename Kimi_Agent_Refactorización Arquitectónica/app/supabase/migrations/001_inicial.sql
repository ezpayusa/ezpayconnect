-- ============================================
-- EzPayConnect - Migracion Inicial
-- Tablas core + RLS + Datos seed
-- ============================================

-- Tipos ENUM
CREATE TYPE user_role AS ENUM ('medico', 'secretaria', 'admin_clinica', 'paciente', 'ezpay_admin');
CREATE TYPE cita_estado AS ENUM ('agendada', 'confirmada', 'en_curso', 'completada', 'cancelada', 'no_show');
CREATE TYPE receta_estado AS ENUM ('activa', 'completada', 'vencida', 'cancelada');
CREATE TYPE suscripcion_plan AS ENUM ('basico', 'profesional', 'premium');
CREATE TYPE suscripcion_estado AS ENUM ('activa', 'pendiente_pago', 'suspendida', 'cancelada');

-- Tabla: Paises
CREATE TABLE paises (
  id SERIAL PRIMARY KEY,
  nombre TEXT NOT NULL,
  codigo_iso TEXT NOT NULL UNIQUE,
  codigo_telefono TEXT,
  moneda TEXT NOT NULL DEFAULT 'GTQ',
  activo BOOLEAN NOT NULL DEFAULT true
);

-- Insertar paises
INSERT INTO paises (nombre, codigo_iso, codigo_telefono, moneda) VALUES
('Guatemala', 'GT', '+502', 'GTQ'),
('Mexico', 'MX', '+52', 'MXN'),
('El Salvador', 'SV', '+503', 'USD'),
('Honduras', 'HN', '+504', 'HNL'),
('Costa Rica', 'CR', '+506', 'CRC'),
('Nicaragua', 'NI', '+505', 'NIO'),
('Panama', 'PA', '+507', 'USD'),
('Colombia', 'CO', '+57', 'COP');

-- Tabla: Perfiles de usuario (extiende auth.users)
CREATE TABLE perfiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  rol user_role NOT NULL DEFAULT 'medico',
  nombre_completo TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL,
  telefono TEXT,
  avatar_url TEXT,
  pais_id INTEGER REFERENCES paises(id),
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Clinicas
CREATE TABLE clinicas (
  id SERIAL PRIMARY KEY,
  pais_id INTEGER NOT NULL REFERENCES paises(id),
  nombre TEXT NOT NULL,
  direccion TEXT,
  telefono TEXT,
  email TEXT,
  logo_url TEXT,
  color_primario TEXT DEFAULT '#1E5C8E',
  color_secundario TEXT DEFAULT '#3A8ABF',
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Relacion medico-clinica
CREATE TABLE medico_clinicas (
  id SERIAL PRIMARY KEY,
  medico_id UUID NOT NULL REFERENCES perfiles(id),
  clinica_id INTEGER NOT NULL REFERENCES clinicas(id),
  es_principal BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(medico_id, clinica_id)
);

-- Tabla: Secretarias asignadas a clinicas
CREATE TABLE secretaria_clinicas (
  id SERIAL PRIMARY KEY,
  secretaria_id UUID NOT NULL REFERENCES perfiles(id),
  clinica_id INTEGER NOT NULL REFERENCES clinicas(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(secretaria_id, clinica_id)
);

-- Tabla: Pacientes (aislados por medico - RLS)
CREATE TABLE pacientes (
  id SERIAL PRIMARY KEY,
  medico_id UUID NOT NULL REFERENCES perfiles(id),
  clinica_id INTEGER REFERENCES clinicas(id),
  nombre TEXT NOT NULL,
  apellido TEXT NOT NULL,
  fecha_nacimiento DATE,
  genero TEXT,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  emergencia_nombre TEXT,
  emergencia_telefono TEXT,
  alergias TEXT,
  notas TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Citas medicas
CREATE TABLE citas (
  id SERIAL PRIMARY KEY,
  medico_id UUID NOT NULL REFERENCES perfiles(id),
  paciente_id INTEGER NOT NULL REFERENCES pacientes(id),
  clinica_id INTEGER REFERENCES clinicas(id),
  fecha DATE NOT NULL,
  hora_inicio TIME NOT NULL,
  hora_fin TIME,
  motivo TEXT,
  estado cita_estado NOT NULL DEFAULT 'agendada',
  notas TEXT,
  created_by UUID REFERENCES perfiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Notas de expediente
CREATE TABLE expediente_notas (
  id SERIAL PRIMARY KEY,
  cita_id INTEGER REFERENCES citas(id),
  paciente_id INTEGER NOT NULL REFERENCES pacientes(id),
  medico_id UUID NOT NULL REFERENCES perfiles(id),
  nota TEXT NOT NULL,
  diagnostico TEXT,
  signos_vitales JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Archivos adjuntos del expediente
CREATE TABLE expediente_archivos (
  id SERIAL PRIMARY KEY,
  nota_id INTEGER NOT NULL REFERENCES expediente_notas(id) ON DELETE CASCADE,
  nombre_original TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  mime_type TEXT,
  tamano_bytes INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Catalogo de medicamentos
CREATE TABLE medicamentos (
  id SERIAL PRIMARY KEY,
  nombre_generico TEXT NOT NULL,
  nombre_comercial TEXT,
  laboratorio TEXT,
  presentacion TEXT,
  concentracion TEXT,
  via_administracion TEXT,
  precio_referencia DECIMAL(10,2),
  requiere_receta BOOLEAN NOT NULL DEFAULT true,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Recetas medicas
CREATE TABLE recetas (
  id SERIAL PRIMARY KEY,
  medico_id UUID NOT NULL REFERENCES perfiles(id),
  paciente_id INTEGER NOT NULL REFERENCES pacientes(id),
  cita_id INTEGER REFERENCES citas(id),
  estado receta_estado NOT NULL DEFAULT 'activa',
  instrucciones_generales TEXT,
  pdf_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: Items de receta
CREATE TABLE receta_items (
  id SERIAL PRIMARY KEY,
  receta_id INTEGER NOT NULL REFERENCES recetas(id) ON DELETE CASCADE,
  medicamento_id INTEGER REFERENCES medicamentos(id),
  nombre_medicamento TEXT NOT NULL,
  dosis TEXT NOT NULL,
  frecuencia TEXT NOT NULL,
  duracion TEXT,
  instrucciones TEXT,
  cantidad INTEGER NOT NULL DEFAULT 1
);

-- Tabla: Memoria inteligente de prescripciones
CREATE TABLE medico_medicamento_stats (
  id SERIAL PRIMARY KEY,
  medico_id UUID NOT NULL REFERENCES perfiles(id),
  medicamento_id INTEGER NOT NULL REFERENCES medicamentos(id),
  veces_prescrito INTEGER NOT NULL DEFAULT 0,
  ultima_prescripcion TIMESTAMPTZ,
  es_favorito BOOLEAN NOT NULL DEFAULT false,
  UNIQUE(medico_id, medicamento_id)
);

-- ============================================
-- RLS - Row Level Security
-- ============================================

ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinicas ENABLE ROW LEVEL SECURITY;
ALTER TABLE medico_clinicas ENABLE ROW LEVEL SECURITY;
ALTER TABLE secretaria_clinicas ENABLE ROW LEVEL SECURITY;
ALTER TABLE pacientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE citas ENABLE ROW LEVEL SECURITY;
ALTER TABLE expediente_notas ENABLE ROW LEVEL SECURITY;
ALTER TABLE expediente_archivos ENABLE ROW LEVEL SECURITY;
ALTER TABLE recetas ENABLE ROW LEVEL SECURITY;
ALTER TABLE receta_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE medico_medicamento_stats ENABLE ROW LEVEL SECURITY;

-- Politicas para pacientes: solo el medico asignado
CREATE POLICY pacientes_select ON pacientes FOR SELECT USING (medico_id = auth.uid());
CREATE POLICY pacientes_insert ON pacientes FOR INSERT WITH CHECK (medico_id = auth.uid());
CREATE POLICY pacientes_update ON pacientes FOR UPDATE USING (medico_id = auth.uid());
CREATE POLICY pacientes_delete ON pacientes FOR DELETE USING (medico_id = auth.uid());

-- Politicas para citas
CREATE POLICY citas_select ON citas FOR SELECT USING (medico_id = auth.uid());
CREATE POLICY citas_insert ON citas FOR INSERT WITH CHECK (medico_id = auth.uid());
CREATE POLICY citas_update ON citas FOR UPDATE USING (medico_id = auth.uid());

-- Politicas para recetas
CREATE POLICY recetas_select ON recetas FOR SELECT USING (medico_id = auth.uid());
CREATE POLICY recetas_insert ON recetas FOR INSERT WITH CHECK (medico_id = auth.uid());

-- Politicas para expediente
CREATE POLICY expediente_select ON expediente_notas FOR SELECT USING (medico_id = auth.uid());
CREATE POLICY expediente_insert ON expediente_notas FOR INSERT WITH CHECK (medico_id = auth.uid());

-- Politicas para archivos
CREATE POLICY archivos_select ON expediente_archivos FOR SELECT USING (
  EXISTS (SELECT 1 FROM expediente_notas en WHERE en.id = expediente_archivos.nota_id AND en.medico_id = auth.uid())
);

-- Politicas para stats
CREATE POLICY stats_select ON medico_medicamento_stats FOR SELECT USING (medico_id = auth.uid());
CREATE POLICY stats_insert ON medico_medicamento_stats FOR INSERT WITH CHECK (medico_id = auth.uid());

-- Politicas para perfiles
CREATE POLICY perfiles_select ON perfiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY perfiles_insert ON perfiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Permitir lectura de medicamentos (catalogo publico)
ALTER TABLE medicamentos DISABLE ROW LEVEL SECURITY;

-- ============================================
-- Datos seed: Medicamentos
-- ============================================

INSERT INTO medicamentos (nombre_generico, nombre_comercial, presentacion, concentracion, via_administracion, precio_referencia) VALUES
('Paracetamol', 'Tylenol', 'Tableta', '500mg', 'Oral', 25.00),
('Ibuprofeno', 'Advil', 'Tableta', '400mg', 'Oral', 30.00),
('Amoxicilina', 'Amoxil', 'Capsula', '500mg', 'Oral', 45.00),
('Omeprazol', 'Prilosec', 'Capsula', '20mg', 'Oral', 55.00),
('Loratadina', 'Claritin', 'Tableta', '10mg', 'Oral', 35.00),
('Metformina', 'Glucophage', 'Tableta', '500mg', 'Oral', 60.00),
('Losartan', 'Cozaar', 'Tableta', '50mg', 'Oral', 75.00),
('Amlodipino', 'Norvasc', 'Tableta', '5mg', 'Oral', 80.00),
('Azitromicina', 'Zithromax', 'Tableta', '500mg', 'Oral', 90.00),
('Diclofenaco', 'Voltaren', 'Tableta', '50mg', 'Oral', 40.00),
('Salbutamol', 'Ventolin', 'Inhalador', '100mcg', 'Inhalacion', 120.00),
('Dexametasona', 'Decadron', 'Tableta', '4mg', 'Oral', 35.00),
('Cloranfenicol', 'Chloromycetin', 'Gotas', '0.5%', 'Oftalmica', 55.00),
('Hidrocortisona', 'Cortizone', 'Crema', '1%', 'Topica', 65.00),
('Ciprofloxacino', 'Cipro', 'Tableta', '500mg', 'Oral', 85.00),
('Metronidazol', 'Flagyl', 'Tableta', '500mg', 'Oral', 50.00),
('Albendazol', 'Albenza', 'Tableta', '400mg', 'Oral', 30.00),
('Acido Acetilsalicilico', 'Aspirina', 'Tableta', '100mg', 'Oral', 20.00),
('Lansoprazol', 'Prevacid', 'Capsula', '30mg', 'Oral', 70.00),
('Vitamina C', 'Redoxon', 'Tableta efervescente', '1000mg', 'Oral', 40.00);
