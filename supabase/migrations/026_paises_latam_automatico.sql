-- ============================================
-- Migración 026: Países de América Latina + Auto-configuración
-- ============================================
-- 1. Insertar todos los países de América Latina
-- 2. Trigger: al crear país nuevo, auto-insertar planes_publicidad_config
-- 3. Insertar precios base para países existentes que no los tengan

-- ============================================
-- 0. ASEGURAR QUE codigo SEA ÚNICO
-- ============================================
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_configuracion_pais_codigo'
  ) THEN
    ALTER TABLE configuracion_pais ADD CONSTRAINT uq_configuracion_pais_codigo UNIQUE (codigo);
  END IF;
END $$;

-- ============================================
-- 1. INSERTAR PAÍSES DE AMÉRICA LATINA
-- ============================================
INSERT INTO configuracion_pais (id, codigo, nombre, moneda, comisiones_activas, porcentaje_comision_default, activo)
VALUES
  (gen_random_uuid(), 'AR', 'Argentina', 'ARS', false, 5.0, true),
  (gen_random_uuid(), 'BO', 'Bolivia', 'BOB', false, 5.0, true),
  (gen_random_uuid(), 'BR', 'Brasil', 'BRL', false, 5.0, true),
  (gen_random_uuid(), 'CL', 'Chile', 'CLP', false, 5.0, true),
  (gen_random_uuid(), 'CO', 'Colombia', 'COP', false, 5.0, true),
  (gen_random_uuid(), 'CU', 'Cuba', 'CUP', false, 5.0, true),
  (gen_random_uuid(), 'EC', 'Ecuador', 'USD', false, 5.0, true),
  (gen_random_uuid(), 'MX', 'México', 'MXN', false, 5.0, true),
  (gen_random_uuid(), 'NI', 'Nicaragua', 'NIO', false, 5.0, true),
  (gen_random_uuid(), 'PA', 'Panamá', 'USD', false, 5.0, true),
  (gen_random_uuid(), 'PY', 'Paraguay', 'PYG', false, 5.0, true),
  (gen_random_uuid(), 'PE', 'Perú', 'PEN', false, 5.0, true),
  (gen_random_uuid(), 'DO', 'República Dominicana', 'DOP', false, 5.0, true),
  (gen_random_uuid(), 'UY', 'Uruguay', 'UYU', false, 5.0, true),
  (gen_random_uuid(), 'VE', 'Venezuela', 'VES', false, 5.0, true)
ON CONFLICT (codigo) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  moneda = EXCLUDED.moneda,
  activo = EXCLUDED.activo;

-- ============================================
-- 2. TRIGGER: Auto-configurar planes al crear país
-- ============================================
CREATE OR REPLACE FUNCTION auto_configurar_planes_publicidad()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Insertar configuración de planes para el nuevo país
  INSERT INTO planes_publicidad_config (pais_id, plan_publicidad_id, precio_local, moneda_local, activo)
  SELECT
    NEW.id,
    pp.id,
    pp.precio,        -- Precio base como placeholder (admin debe ajustar)
    NEW.moneda,       -- Moneda del país
    true
  FROM planes_publicidad pp
  WHERE pp.activo = true
  ON CONFLICT (pais_id, plan_publicidad_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Crear el trigger
DROP TRIGGER IF EXISTS trigger_auto_planes_publicidad ON configuracion_pais;
CREATE TRIGGER trigger_auto_planes_publicidad
  AFTER INSERT ON configuracion_pais
  FOR EACH ROW
  EXECUTE FUNCTION auto_configurar_planes_publicidad();

-- ============================================
-- 3. INSERTAR PRECIOS BASE PARA PAÍSES EXISTENTES SIN CONFIG
-- ============================================
INSERT INTO planes_publicidad_config (pais_id, plan_publicidad_id, precio_local, moneda_local, activo)
SELECT
  cp.id,
  pp.id,
  pp.precio,
  cp.moneda,
  true
FROM configuracion_pais cp
CROSS JOIN planes_publicidad pp
WHERE pp.activo = true
  AND NOT EXISTS (
    SELECT 1 FROM planes_publicidad_config pc
    WHERE pc.pais_id = cp.id AND pc.plan_publicidad_id = pp.id
  )
ON CONFLICT (pais_id, plan_publicidad_id) DO NOTHING;
