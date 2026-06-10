-- ============================================================
-- 043: Baseline de tablas que existían en producción pero NO en las migraciones
-- ------------------------------------------------------------
-- Reconstruido desde el esquema real de producción (information_schema) el
-- 2026-06-10, para cerrar el "migration drift": el repo no podía recrear estas
-- tablas. Todas con CREATE TABLE IF NOT EXISTS -> no-op en prod (ya existen),
-- y recrea la estructura en una BD nueva.
--
-- ALCANCE: captura columnas, tipos, defaults, PK y FKs *internas* (hacia tablas
-- creadas en este mismo archivo). Las FKs hacia tablas externas con drift de
-- tipos conocido (clinicas, pacientes, planes_base, auth.users) se OMITEN aquí
-- a propósito para que la migración sea auto-consistente y aplique sin error.
-- NO incluye RLS ni CHECKs. Para fidelidad 100% usar `supabase db dump` (Docker).
-- ============================================================

-- 1. configuracion_pais (sin dependencias)
CREATE TABLE IF NOT EXISTS configuracion_pais (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo character varying NOT NULL,
  nombre character varying NOT NULL,
  moneda character varying NOT NULL,
  comisiones_activas boolean DEFAULT false,
  porcentaje_comision_default numeric DEFAULT 0.00,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- 2. roles
CREATE TABLE IF NOT EXISTS roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre character varying NOT NULL,
  descripcion text,
  created_at timestamp with time zone DEFAULT now(),
  permisos jsonb DEFAULT '[]'::jsonb,
  nivel integer DEFAULT 1
);

-- 3. recetas_avanzadas (ids de paciente/medico como text; sin FK)
CREATE TABLE IF NOT EXISTS recetas_avanzadas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receta_base_id text,
  paciente_id text NOT NULL,
  medico_id text NOT NULL,
  codigo_qr text,
  firma_digital text,
  estado_dispensacion text DEFAULT 'pendiente'::text,
  farmacia_id text,
  fecha_dispensacion timestamp with time zone,
  pdf_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- 4. farmacias (id serial; FK pais_id -> configuracion_pais)
CREATE TABLE IF NOT EXISTS farmacias (
  id serial PRIMARY KEY,
  nombre text NOT NULL,
  direccion text,
  telefono text,
  email text,
  encargado text,
  horario text,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  tipo character varying DEFAULT 'farmacia'::character varying,
  pais_id uuid REFERENCES configuracion_pais(id)
);

-- 5. medicos (FK clinica_id -> clinicas OMITIDA por drift de tipos; pais_id sí)
CREATE TABLE IF NOT EXISTS medicos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinica_id uuid NOT NULL,
  nombre_completo text NOT NULL,
  especialidad text,
  telefono text,
  email text,
  cedula_profesional text,
  horario_atencion jsonb DEFAULT '[]'::jsonb,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  pais_id uuid REFERENCES configuracion_pais(id),
  foto_url text
);

-- 6. farmacia_medicamentos (FK farmacia_id -> farmacias)
CREATE TABLE IF NOT EXISTS farmacia_medicamentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farmacia_id integer NOT NULL REFERENCES farmacias(id),
  nombre_medicamento text NOT NULL,
  descripcion text,
  presentacion text,
  stock_actual integer NOT NULL DEFAULT 0,
  stock_minimo integer NOT NULL DEFAULT 10,
  precio_unitario numeric,
  laboratorio text,
  lote text,
  fecha_vencimiento date,
  activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- 7. dispensaciones (FK farmacia_id -> farmacias, receta_avanzada_id -> recetas_avanzadas)
CREATE TABLE IF NOT EXISTS dispensaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receta_avanzada_id uuid NOT NULL REFERENCES recetas_avanzadas(id),
  farmacia_id integer NOT NULL REFERENCES farmacias(id),
  paciente_id text NOT NULL,
  medico_id text NOT NULL,
  codigo_qr text NOT NULL,
  medicamentos_dispensados jsonb DEFAULT '[]'::jsonb,
  cantidad_items integer DEFAULT 0,
  total_dispensado numeric,
  estado_dispensacion text DEFAULT 'completada'::text,
  motivo_rechazo text,
  farmaceutico_nombre text,
  fecha_dispensacion timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now()
);

-- 8. facturas (id serial; FK pais_id -> configuracion_pais; paciente_id/medico_id sin FK por drift)
CREATE TABLE IF NOT EXISTS facturas (
  id serial PRIMARY KEY,
  paciente_id integer,
  medico_id uuid,
  fecha_emision date NOT NULL DEFAULT CURRENT_DATE,
  concepto character varying NOT NULL,
  cantidad integer DEFAULT 1,
  precio_unitario numeric NOT NULL,
  subtotal numeric,
  descuento numeric DEFAULT 0,
  total numeric,
  metodo_pago character varying,
  estado character varying DEFAULT 'pendiente'::character varying,
  notas text,
  created_at timestamp without time zone DEFAULT now(),
  pais_id uuid REFERENCES configuracion_pais(id)
);

-- 9. transacciones (FK pais_id -> configuracion_pais; plan_id/usuario_id sin FK por drift)
CREATE TABLE IF NOT EXISTS transacciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id uuid,
  plan_id uuid,
  pais_id uuid REFERENCES configuracion_pais(id),
  monto numeric NOT NULL,
  moneda character varying NOT NULL,
  tipo_pago character varying DEFAULT 'suscripcion'::character varying,
  estado character varying DEFAULT 'pendiente'::character varying,
  metodo_pago character varying,
  referencia_externa character varying,
  comision_aplicada numeric DEFAULT 0,
  monto_comision numeric DEFAULT 0,
  fecha_pago timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
