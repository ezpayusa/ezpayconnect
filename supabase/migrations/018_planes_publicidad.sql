-- ============================================
-- Migración 018: Planes de Publicidad desde BD
-- ============================================

-- 1. Tabla de planes de publicidad
CREATE TABLE IF NOT EXISTS planes_publicidad (
  id SERIAL PRIMARY KEY,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  dias INTEGER NOT NULL DEFAULT 7,
  precio NUMERIC(12,2) NOT NULL DEFAULT 0,
  moneda TEXT NOT NULL DEFAULT 'GTQ',
  activo BOOLEAN NOT NULL DEFAULT true,
  orden INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Datos iniciales (migrados desde el hardcode del frontend)
INSERT INTO planes_publicidad (id, nombre, descripcion, dias, precio, moneda, orden)
VALUES
  (1, 'Banner Básico', 'Aparece en banners del portal paciente y médico por 7 días', 7, 1500, 'GTQ', 1),
  (2, 'Banner Profesional', 'Aparece en banners + notificación push por 15 días', 15, 3500, 'GTQ', 2),
  (3, 'Campaña Premium', 'Banner destacado + segmentación por edad/género/condición por 30 días', 30, 8000, 'GTQ', 3)
ON CONFLICT (id) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  descripcion = EXCLUDED.descripcion,
  dias = EXCLUDED.dias,
  precio = EXCLUDED.precio,
  moneda = EXCLUDED.moneda,
  orden = EXCLUDED.orden;

-- 3. RLS
ALTER TABLE planes_publicidad ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Cualquiera ve planes publicidad activos" ON planes_publicidad;
CREATE POLICY "Cualquiera ve planes publicidad activos" ON planes_publicidad
  FOR SELECT USING (activo = true);

-- 4. Permite a proveedores guardar el plan elegido en solicitudes_campana
ALTER TABLE solicitudes_campana
  ADD COLUMN IF NOT EXISTS plan_publicidad_id INTEGER REFERENCES planes_publicidad(id);
