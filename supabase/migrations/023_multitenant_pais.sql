-- ============================================
-- Migración 023: Fundación Multitenant por País
-- EzPayConnect
-- ============================================

-- ============================================
-- 1. Agregar pais_id a tablas principales
-- ============================================

-- clinicas
ALTER TABLE clinicas ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_clinicas_pais ON clinicas(pais_id);

-- medicos
ALTER TABLE medicos ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_medicos_pais ON medicos(pais_id);

-- perfiles
ALTER TABLE perfiles ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_perfiles_pais ON perfiles(pais_id);

-- pacientes
ALTER TABLE pacientes ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_pacientes_pais ON pacientes(pais_id);

-- citas
ALTER TABLE citas ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_citas_pais ON citas(pais_id);

-- recetas
ALTER TABLE recetas ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_recetas_pais ON recetas(pais_id);

-- campanas_publicitarias
ALTER TABLE campanas_publicitarias ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_campanas_pais ON campanas_publicitarias(pais_id);

-- cuentas_proveedor
ALTER TABLE cuentas_proveedor ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_cuentas_proveedor_pais ON cuentas_proveedor(pais_id);

-- visitas_agendadas
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_visitas_pais ON visitas_agendadas(pais_id);

-- solicitudes_campana
ALTER TABLE solicitudes_campana ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_solicitudes_campana_pais ON solicitudes_campana(pais_id);

-- facturas
ALTER TABLE facturas ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_facturas_pais ON facturas(pais_id);

-- notificaciones
ALTER TABLE notificaciones ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_notificaciones_pais ON notificaciones(pais_id);

-- ============================================
-- 2. Corregir empresas_proveedoras.pais_id (INTEGER → UUID)
-- ============================================

-- La columna existe como INTEGER sin FK. La reemplazamos por UUID.
ALTER TABLE empresas_proveedoras DROP COLUMN IF EXISTS pais_id;
ALTER TABLE empresas_proveedoras ADD COLUMN pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_empresas_proveedoras_pais ON empresas_proveedoras(pais_id);

-- ============================================
-- 3. Asignar Guatemala (GT) como país default a registros existentes
-- ============================================

DO $$
DECLARE
  v_guatemala_id UUID := 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909';
BEGIN
  UPDATE clinicas SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE medicos SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE perfiles SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE pacientes SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE citas SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE recetas SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE campanas_publicitarias SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE cuentas_proveedor SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE visitas_agendadas SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE solicitudes_campana SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE facturas SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE notificaciones SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
  UPDATE empresas_proveedoras SET pais_id = v_guatemala_id WHERE pais_id IS NULL;
END $$;

-- ============================================
-- 4. Tablas adicionales identificadas por el explorador
-- ============================================

-- farmacias (si existe)
DO $$
BEGIN
  ALTER TABLE farmacias ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
  CREATE INDEX IF NOT EXISTS idx_farmacias_pais ON farmacias(pais_id);
  UPDATE farmacias SET pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' WHERE pais_id IS NULL;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'Tabla farmacias no existe, ignorando';
END $$;

-- productos_empresa (si existe)
DO $$
BEGIN
  ALTER TABLE productos_empresa ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
  CREATE INDEX IF NOT EXISTS idx_productos_empresa_pais ON productos_empresa(pais_id);
  UPDATE productos_empresa SET pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' WHERE pais_id IS NULL;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'Tabla productos_empresa no existe, ignorando';
END $$;

-- disponibilidad_medico (si existe)
DO $$
BEGIN
  ALTER TABLE disponibilidad_medico ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
  CREATE INDEX IF NOT EXISTS idx_disponibilidad_medico_pais ON disponibilidad_medico(pais_id);
  UPDATE disponibilidad_medico SET pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' WHERE pais_id IS NULL;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'Tabla disponibilidad_medico no existe, ignorando';
END $$;

-- expediente_notas (si existe)
DO $$
BEGIN
  ALTER TABLE expediente_notas ADD COLUMN IF NOT EXISTS pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL;
  CREATE INDEX IF NOT EXISTS idx_expediente_notas_pais ON expediente_notas(pais_id);
  UPDATE expediente_notas SET pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909' WHERE pais_id IS NULL;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'Tabla expediente_notas no existe, ignorando';
END $$;

-- ============================================
-- 5. Corregir bug en perfiles: pais_id vs rol_id
-- ============================================
-- Nota: El explorador detectó que useAdminAuth.ts lee pais_id de rol_id.
-- Esto es un bug de frontend, no de base de datos. Se corregirá en Fase 2.

-- ============================================
-- 6. Comentarios para documentación
-- ============================================

COMMENT ON COLUMN clinicas.pais_id IS 'País donde opera la clínica';
COMMENT ON COLUMN medicos.pais_id IS 'País donde ejerce el médico';
COMMENT ON COLUMN perfiles.pais_id IS 'País de residencia/operación del usuario';
COMMENT ON COLUMN pacientes.pais_id IS 'País del paciente';
COMMENT ON COLUMN citas.pais_id IS 'País donde se agenda la cita';
COMMENT ON COLUMN recetas.pais_id IS 'País donde se emite la receta';
COMMENT ON COLUMN campanas_publicitarias.pais_id IS 'País objetivo de la campaña';
COMMENT ON COLUMN empresas_proveedoras.pais_id IS 'País donde opera la empresa proveedora';
COMMENT ON COLUMN cuentas_proveedor.pais_id IS 'País del representante de la empresa';
COMMENT ON COLUMN visitas_agendadas.pais_id IS 'País donde se realiza la visita';
COMMENT ON COLUMN solicitudes_campana.pais_id IS 'País objetivo de la solicitud de campaña';
COMMENT ON COLUMN facturas.pais_id IS 'País de emisión de la factura';
COMMENT ON COLUMN notificaciones.pais_id IS 'País relacionado con la notificación';
