-- ============================================
-- Migración 019: Notificaciones email + Configuración del sistema
-- ============================================

-- 1. Tabla de log de notificaciones email enviadas
CREATE TABLE IF NOT EXISTS notificaciones_email (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  destinatario TEXT NOT NULL,
  asunto TEXT NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'general',
  estado TEXT NOT NULL DEFAULT 'enviado', -- enviado, fallido
  error TEXT,
  proveedor_id UUID REFERENCES empresas_proveedoras(id),
  visita_id UUID REFERENCES visitas_agendadas(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS
ALTER TABLE notificaciones_email ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin ezpay ve notificaciones" ON notificaciones_email;
CREATE POLICY "Admin ezpay ve notificaciones" ON notificaciones_email
  FOR SELECT USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin')
    )
  );

-- 2. Tabla de configuración del sistema (datos bancarios, etc.)
CREATE TABLE IF NOT EXISTS configuracion_sistema (
  clave TEXT PRIMARY KEY,
  valor TEXT NOT NULL,
  descripcion TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS: solo admin puede modificar, cualquiera puede leer
ALTER TABLE configuracion_sistema ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Cualquiera lee configuracion" ON configuracion_sistema;
CREATE POLICY "Cualquiera lee configuracion" ON configuracion_sistema
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admin ezpay actualiza configuracion" ON configuracion_sistema;
CREATE POLICY "Admin ezpay actualiza configuracion" ON configuracion_sistema
  FOR ALL USING (
    auth.uid() IN (
      SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_finanzas')
    )
  );

-- 3. Datos bancarios por defecto
INSERT INTO configuracion_sistema (clave, valor, descripcion)
VALUES
  ('banco', 'Banco Industrial', 'Nombre del banco para transferencias'),
  ('cuenta_bancaria', '123-456789-0', 'Número de cuenta para transferencias'),
  ('tipo_cuenta', 'Cuenta Monetaria', 'Tipo de cuenta bancaria'),
  ('titular_cuenta', 'EzPayConnect S.A.', 'Titular de la cuenta bancaria'),
  ('email_pagos', 'pagos@ezpayconnect.com', 'Email para enviar comprobantes')
ON CONFLICT (clave) DO NOTHING;
