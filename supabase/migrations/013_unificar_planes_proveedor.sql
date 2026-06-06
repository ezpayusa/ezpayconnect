-- ============================================
-- Migración 013: Unificar sistema de planes con portal proveedor
-- ============================================

-- 1. AGREGAR COLUMNA atributos JSONB a planes_base
ALTER TABLE planes_base
  ADD COLUMN IF NOT EXISTS atributos JSONB DEFAULT '{}';

COMMENT ON COLUMN planes_base.atributos IS 'Atributos flexibles según tipo: visitador={visitas_incluidas,duracion_dias}, medico={limite_pacientes,limite_medicos}, publicidad={impresiones,duracion_dias}';

-- 2. AGREGAR empresa_id a planes_asignaciones + hacer plan_config_id nullable
ALTER TABLE planes_asignaciones
  ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES empresas_proveedoras(id) ON DELETE CASCADE;

ALTER TABLE planes_asignaciones ALTER COLUMN plan_config_id DROP NOT NULL;

DO $$
BEGIN
  ALTER TABLE planes_asignaciones ALTER COLUMN medico_id DROP NOT NULL;
EXCEPTION WHEN undefined_column THEN
  RAISE NOTICE 'medico_id no existe, omitiendo';
END $$;

CREATE INDEX IF NOT EXISTS idx_planes_asignaciones_empresa
  ON planes_asignaciones(empresa_id);

COMMENT ON COLUMN planes_asignaciones.empresa_id IS 'Empresa proveedora (para planes B2B: visitador, publicidad, farmacia, etc.)';

-- 3. RLS - Proveedores pueden ver planes_base y planes_configuracion
DROP POLICY IF EXISTS "Proveedores ven planes disponibles" ON planes_base;
CREATE POLICY "Proveedores ven planes disponibles" ON planes_base
  FOR SELECT USING (
    activo = true
    AND tipo IN ('visitador', 'publicidad', 'farmacia', 'farmaceutico', 'empresas_afines')
  );

DROP POLICY IF EXISTS "Proveedores ven configuraciones de planes" ON planes_configuracion;
CREATE POLICY "Proveedores ven configuraciones de planes" ON planes_configuracion
  FOR SELECT USING (
    activo = true
    AND plan_base_id IN (
      SELECT id FROM planes_base
      WHERE activo = true
        AND tipo IN ('visitador', 'publicidad', 'farmacia', 'farmaceutico', 'empresas_afines')
    )
  );

-- 4. RLS - Proveedores ven sus asignaciones
DROP POLICY IF EXISTS "Proveedor ve sus planes asignados" ON planes_asignaciones;
CREATE POLICY "Proveedor ve sus planes asignados" ON planes_asignaciones
  FOR SELECT USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid()
    )
  );

-- 5. MIGRAR datos existentes de planes_visitador_contratados a planes_asignaciones
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM planes_visitador_contratados;
  IF v_count > 0 THEN
    RAISE NOTICE 'Migrando % planes_visitador_contratados a planes_asignaciones...', v_count;

    INSERT INTO planes_asignaciones (
      empresa_id,
      estado,
      fecha_inicio,
      fecha_fin,
      precio_aplicado,
      moneda,
      tipo_ciclo,
      metodo_pago
    )
    SELECT
      pvc.empresa_id,
      CASE
        WHEN pvc.estado = 'activo' AND pvc.fecha_fin >= CURRENT_DATE AND pvc.visitas_usadas < pvc.cantidad_visitas_incluidas THEN 'activo'
        WHEN pvc.estado = 'expirado' OR pvc.fecha_fin < CURRENT_DATE THEN 'cancelado'
        WHEN pvc.visitas_usadas >= pvc.cantidad_visitas_incluidas THEN 'cancelado'
        ELSE pvc.estado
      END,
      pvc.fecha_inicio::timestamptz,
      pvc.fecha_fin::timestamptz,
      pvc.precio_pagado,
      'GTQ',
      'unico',
      'transferencia'
    FROM planes_visitador_contratados pvc
    WHERE NOT EXISTS (
      SELECT 1 FROM planes_asignaciones pa
      WHERE pa.empresa_id = pvc.empresa_id
        AND pa.fecha_inicio = pvc.fecha_inicio::timestamptz
        AND pa.precio_aplicado = pvc.precio_pagado
    );

    RAISE NOTICE 'Migracion completada.';
  ELSE
    RAISE NOTICE 'No hay datos en planes_visitador_contratados para migrar.';
  END IF;
END $$;
