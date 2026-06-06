-- ============================================
-- Migración 012: Portal B2B de Proveedores
-- ============================================

-- ============================================
-- 1. TABLAS DEL PORTAL PROVEEDOR
-- ============================================

-- Empresas proveedoras (farmacias, labs, labs clínicos, empresas afines)
CREATE TABLE IF NOT EXISTS empresas_proveedoras (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre_empresa TEXT NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'farmacia', -- farmacia, laboratorio_farmaceutico, laboratorio_clinico, empresa_afin
  ruc_nit TEXT,
  pais_id INTEGER, -- FK a paises(id) si existe
  ciudad TEXT,
  direccion TEXT,
  email_contacto TEXT NOT NULL,
  telefono TEXT,
  logo_url TEXT,
  estado TEXT NOT NULL DEFAULT 'pendiente', -- pendiente, activa, suspendida, rechazada
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Cuentas de usuarios proveedor (vinculadas a auth.users)
CREATE TABLE IF NOT EXISTS cuentas_proveedor (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  nombre_completo TEXT NOT NULL,
  email TEXT NOT NULL,
  rol_en_empresa TEXT NOT NULL DEFAULT 'admin', -- admin, editor, viewer
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Productos de la empresa
CREATE TABLE IF NOT EXISTS productos_empresa (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  nombre_producto TEXT NOT NULL,
  principio_activo TEXT,
  presentacion TEXT,
  concentracion TEXT,
  categoria TEXT,
  precio_unitario NUMERIC(12,2) NOT NULL DEFAULT 0,
  moneda TEXT NOT NULL DEFAULT 'GTQ',
  stock_disponible INTEGER NOT NULL DEFAULT 0,
  requiere_receta BOOLEAN NOT NULL DEFAULT false,
  imagen_url TEXT,
  estado TEXT NOT NULL DEFAULT 'activo', -- activo, agotado, descontinuado
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Disponibilidad de médicos para visitas
CREATE TABLE IF NOT EXISTS disponibilidad_medico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  medico_id UUID NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  dia_semana INTEGER NOT NULL CHECK (dia_semana BETWEEN 0 AND 6), -- 0=domingo, 6=sábado
  hora_inicio TIME NOT NULL,
  hora_fin TIME NOT NULL,
  duracion_slot INTEGER NOT NULL DEFAULT 30, -- minutos
  clinica_id UUID REFERENCES clinicas(id),
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Visitas agendadas por empresas a médicos
CREATE TABLE IF NOT EXISTS visitas_agendadas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  medico_id UUID NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  cuenta_proveedor_id UUID NOT NULL REFERENCES cuentas_proveedor(id) ON DELETE CASCADE,
  fecha_visita DATE NOT NULL,
  hora_inicio TIME NOT NULL,
  hora_fin TIME NOT NULL,
  tipo_visita TEXT NOT NULL DEFAULT 'presentacion_producto', -- presentacion_producto, capacitacion, muestra_gratis, pedido, otro
  productos_a_presentar UUID[] DEFAULT '{}',
  estado TEXT NOT NULL DEFAULT 'pendiente', -- pendiente, confirmada, completada, cancelada, no_asistio
  notas_empresa TEXT,
  notas_medico TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Planes de visitador contratados por empresa
CREATE TABLE IF NOT EXISTS planes_visitador_contratados (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  plan_visitador_id INTEGER NOT NULL, -- referencia lógica a planes_visitador (tabla de planes)
  pais_id INTEGER, -- FK a paises(id) si existe
  cantidad_visitas_incluidas INTEGER NOT NULL DEFAULT 0,
  visitas_usadas INTEGER NOT NULL DEFAULT 0,
  precio_pagado NUMERIC(12,2) NOT NULL DEFAULT 0,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  estado TEXT NOT NULL DEFAULT 'activo', -- activo, expirado, agotado
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Solicitudes de campaña publicitaria desde proveedores
CREATE TABLE IF NOT EXISTS solicitudes_campana (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  cuenta_proveedor_id UUID NOT NULL REFERENCES cuentas_proveedor(id) ON DELETE CASCADE,
  titulo TEXT NOT NULL,
  descripcion TEXT,
  tipo TEXT NOT NULL DEFAULT 'general', -- farmacia, equipo_medico, laboratorio, general
  imagen_url TEXT,
  link_url TEXT,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  condicion_filtro TEXT,
  genero_filtro TEXT,
  edad_min INTEGER,
  edad_max INTEGER,
  plan_publicidad_id INTEGER, -- referencia lógica
  estado TEXT NOT NULL DEFAULT 'borrador', -- borrador, enviada, en_revision, aprobada, rechazada, publicada
  monto_pagado NUMERIC(12,2) DEFAULT 0,
  comprobante_pago_url TEXT,
  notas_admin TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Pagos de proveedores
CREATE TABLE IF NOT EXISTS pagos_proveedor (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL, -- plan_publicidad, plan_visitador, campana, suscripcion
  referencia_id UUID, -- ID de la solicitud/plan relacionado
  monto NUMERIC(12,2) NOT NULL DEFAULT 0,
  moneda TEXT NOT NULL DEFAULT 'GTQ',
  metodo_pago TEXT,
  comprobante_url TEXT,
  estado TEXT NOT NULL DEFAULT 'pendiente', -- pendiente, verificado, rechazado
  verificado_por UUID REFERENCES perfiles(id),
  fecha_pago DATE,
  fecha_verificacion TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 2. RLS - EMPRESAS PROVEEDORAS
-- ============================================
ALTER TABLE empresas_proveedoras ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Proveedor ve su propia empresa" ON empresas_proveedoras;
CREATE POLICY "Proveedor ve su propia empresa" ON empresas_proveedoras
  FOR SELECT USING (
    id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Proveedor actualiza su propia empresa" ON empresas_proveedoras;
CREATE POLICY "Proveedor actualiza su propia empresa" ON empresas_proveedoras
  FOR UPDATE USING (
    id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa IN ('admin', 'editor')
    )
  );

DROP POLICY IF EXISTS "Admin ezpay ve todas las empresas" ON empresas_proveedoras;
CREATE POLICY "Admin ezpay ve todas las empresas" ON empresas_proveedoras
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_ventas')
    )
  );

DROP POLICY IF EXISTS "Admin ezpay actualiza empresas" ON empresas_proveedoras;
CREATE POLICY "Admin ezpay actualiza empresas" ON empresas_proveedoras
  FOR UPDATE USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_ventas')
    )
  );

-- Política INSERT pública para registro de nuevas empresas (protegida por lógica de negocio)
DROP POLICY IF EXISTS "Cualquiera inserta empresas" ON empresas_proveedoras;
CREATE POLICY "Cualquiera inserta empresas" ON empresas_proveedoras
  FOR INSERT WITH CHECK (true);

-- ============================================
-- 3. RLS - CUENTAS PROVEEDOR
-- ============================================
ALTER TABLE cuentas_proveedor ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Proveedor ve su propia cuenta" ON cuentas_proveedor;
CREATE POLICY "Proveedor ve su propia cuenta" ON cuentas_proveedor
  FOR SELECT USING (id = auth.uid());

DROP POLICY IF EXISTS "Proveedor admin ve cuentas de su empresa" ON cuentas_proveedor;
CREATE POLICY "Proveedor admin ve cuentas de su empresa" ON cuentas_proveedor
  FOR SELECT USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admin ezpay ve cuentas proveedor" ON cuentas_proveedor;
CREATE POLICY "Admin ezpay ve cuentas proveedor" ON cuentas_proveedor
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_ventas')
    )
  );

DROP POLICY IF EXISTS "Cuenta proveedor se inserta publicamente" ON cuentas_proveedor;
CREATE POLICY "Cuenta proveedor se inserta publicamente" ON cuentas_proveedor
  FOR INSERT WITH CHECK (true);

-- ============================================
-- 4. RLS - PRODUCTOS EMPRESA
-- ============================================
ALTER TABLE productos_empresa ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Proveedor ve productos de su empresa" ON productos_empresa;
CREATE POLICY "Proveedor ve productos de su empresa" ON productos_empresa
  FOR SELECT USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Médico ve productos activos" ON productos_empresa;
CREATE POLICY "Médico ve productos activos" ON productos_empresa
  FOR SELECT USING (estado = 'activo');

DROP POLICY IF EXISTS "Proveedor admin/editor gestiona productos" ON productos_empresa;
CREATE POLICY "Proveedor admin/editor gestiona productos" ON productos_empresa
  FOR ALL USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa IN ('admin', 'editor')
    )
  );

DROP POLICY IF EXISTS "Admin ezpay ve todos los productos" ON productos_empresa;
CREATE POLICY "Admin ezpay ve todos los productos" ON productos_empresa
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin')
    )
  );

-- ============================================
-- 5. RLS - DISPONIBILIDAD MEDICO
-- ============================================
ALTER TABLE disponibilidad_medico ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Médico gestiona su disponibilidad" ON disponibilidad_medico;
CREATE POLICY "Médico gestiona su disponibilidad" ON disponibilidad_medico
  FOR ALL USING (medico_id = auth.uid());

DROP POLICY IF EXISTS "Proveedor ve disponibilidad activa" ON disponibilidad_medico;
CREATE POLICY "Proveedor ve disponibilidad activa" ON disponibilidad_medico
  FOR SELECT USING (activo = true);

DROP POLICY IF EXISTS "Admin ezpay ve toda disponibilidad" ON disponibilidad_medico;
CREATE POLICY "Admin ezpay ve toda disponibilidad" ON disponibilidad_medico
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin')
    )
  );

-- ============================================
-- 6. RLS - VISITAS AGENDADAS
-- ============================================
ALTER TABLE visitas_agendadas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Proveedor ve visitas de su empresa" ON visitas_agendadas;
CREATE POLICY "Proveedor ve visitas de su empresa" ON visitas_agendadas
  FOR SELECT USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Médico ve sus visitas" ON visitas_agendadas;
CREATE POLICY "Médico ve sus visitas" ON visitas_agendadas
  FOR SELECT USING (medico_id = auth.uid());

DROP POLICY IF EXISTS "Proveedor crea visitas de su empresa" ON visitas_agendadas;
CREATE POLICY "Proveedor crea visitas de su empresa" ON visitas_agendadas
  FOR INSERT WITH CHECK (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa IN ('admin', 'editor')
    )
  );

DROP POLICY IF EXISTS "Médico actualiza sus visitas" ON visitas_agendadas;
CREATE POLICY "Médico actualiza sus visitas" ON visitas_agendadas
  FOR UPDATE USING (medico_id = auth.uid());

DROP POLICY IF EXISTS "Admin ezpay ve todas las visitas" ON visitas_agendadas;
CREATE POLICY "Admin ezpay ve todas las visitas" ON visitas_agendadas
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin')
    )
  );

-- ============================================
-- 7. RLS - PLANES VISITADOR CONTRATADOS
-- ============================================
ALTER TABLE planes_visitador_contratados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Proveedor ve sus planes visitador" ON planes_visitador_contratados;
CREATE POLICY "Proveedor ve sus planes visitador" ON planes_visitador_contratados
  FOR SELECT USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admin ezpay gestiona planes visitador" ON planes_visitador_contratados;
CREATE POLICY "Admin ezpay gestiona planes visitador" ON planes_visitador_contratados
  FOR ALL USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_ventas')
    )
  );

-- ============================================
-- 8. RLS - SOLICITUDES CAMPAÑA
-- ============================================
ALTER TABLE solicitudes_campana ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Proveedor ve sus campañas" ON solicitudes_campana;
CREATE POLICY "Proveedor ve sus campañas" ON solicitudes_campana
  FOR SELECT USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Proveedor crea campañas" ON solicitudes_campana;
CREATE POLICY "Proveedor crea campañas" ON solicitudes_campana
  FOR INSERT WITH CHECK (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa IN ('admin', 'editor')
    )
  );

DROP POLICY IF EXISTS "Proveedor actualiza sus campañas borrador" ON solicitudes_campana;
CREATE POLICY "Proveedor actualiza sus campañas borrador" ON solicitudes_campana
  FOR UPDATE USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa IN ('admin', 'editor')
    )
    AND estado IN ('borrador', 'enviada', 'rechazada')
  );

DROP POLICY IF EXISTS "Admin ezpay ve todas las campañas" ON solicitudes_campana;
CREATE POLICY "Admin ezpay ve todas las campañas" ON solicitudes_campana
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_publicidad')
    )
  );

DROP POLICY IF EXISTS "Admin ezpay actualiza campañas" ON solicitudes_campana;
CREATE POLICY "Admin ezpay actualiza campañas" ON solicitudes_campana
  FOR UPDATE USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_publicidad')
    )
  );

-- ============================================
-- 9. RLS - PAGOS PROVEEDOR
-- ============================================
ALTER TABLE pagos_proveedor ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Proveedor ve pagos de su empresa" ON pagos_proveedor;
CREATE POLICY "Proveedor ve pagos de su empresa" ON pagos_proveedor
  FOR SELECT USING (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Proveedor crea pagos" ON pagos_proveedor;
CREATE POLICY "Proveedor crea pagos" ON pagos_proveedor
  FOR INSERT WITH CHECK (
    empresa_id IN (
      SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND rol_en_empresa IN ('admin', 'editor')
    )
  );

DROP POLICY IF EXISTS "Admin ezpay gestiona pagos" ON pagos_proveedor;
CREATE POLICY "Admin ezpay gestiona pagos" ON pagos_proveedor
  FOR ALL USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_finanzas')
    )
  );

-- ============================================
-- 10. BUCKETS STORAGE
-- ============================================

-- Bucket público para imágenes de productos
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES (
  'productos',
  'productos',
  true,
  false,
  2097152,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- Bucket privado para comprobantes de pago
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES (
  'comprobantes',
  'comprobantes',
  false,
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

-- Políticas bucket productos
DROP POLICY IF EXISTS "Autenticados suben productos" ON storage.objects;
CREATE POLICY "Autenticados suben productos"
  ON storage.objects
  FOR INSERT
  WITH CHECK (bucket_id = 'productos' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Autenticados eliminan productos" ON storage.objects;
CREATE POLICY "Autenticados eliminan productos"
  ON storage.objects
  FOR DELETE
  USING (bucket_id = 'productos' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Lectura pública productos" ON storage.objects;
CREATE POLICY "Lectura pública productos"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'productos');

-- Políticas bucket comprobantes
DROP POLICY IF EXISTS "Autenticados suben comprobantes" ON storage.objects;
CREATE POLICY "Autenticados suben comprobantes"
  ON storage.objects
  FOR INSERT
  WITH CHECK (bucket_id = 'comprobantes' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admin ve comprobantes" ON storage.objects;
CREATE POLICY "Admin ve comprobantes"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'comprobantes'
    AND auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_finanzas')
    )
  );

DROP POLICY IF EXISTS "Autenticados ven sus comprobantes" ON storage.objects;
CREATE POLICY "Autenticados ven sus comprobantes"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'comprobantes'
    AND auth.role() = 'authenticated'
  );

-- ============================================
-- 11. DATOS DE PRUEBA (opcional, descomentar si se desea)
-- ============================================
/*
INSERT INTO empresas_proveedoras (nombre_empresa, tipo, ruc_nit, email_contacto, telefono, estado)
VALUES
  ('Farmacia Moderna', 'farmacia', '123456789', 'contacto@farmaciamoderna.com', '5555-1111', 'activa'),
  ('LabPharma Centroamérica', 'laboratorio_farmaceutico', '987654321', 'ventas@labpharma.com', '5555-2222', 'activa'),
  ('LabClinico Regional', 'laboratorio_clinico', '456789123', 'info@labclinico.com', '5555-3333', 'activa');
*/
