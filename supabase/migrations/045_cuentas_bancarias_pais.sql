-- ============================================================
-- 045: Cuentas bancarias por país (para pagos por depósito/transferencia)
-- ------------------------------------------------------------
-- EzPay puede tener una cuenta bancaria por país. El checkout muestra la
-- cuenta del país del cliente y este sube su comprobante. Lectura pública
-- (el checkout la muestra); escritura solo admin.
-- ============================================================

CREATE TABLE IF NOT EXISTS cuentas_bancarias_pais (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pais_id UUID REFERENCES configuracion_pais(id) ON DELETE CASCADE,
  banco TEXT NOT NULL,
  tipo_cuenta TEXT,
  numero_cuenta TEXT NOT NULL,
  titular TEXT NOT NULL,
  nit TEXT,
  moneda TEXT,
  instrucciones TEXT,
  email_pagos TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cuentas_banco_pais ON cuentas_bancarias_pais(pais_id);

ALTER TABLE cuentas_bancarias_pais ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cuentas_banco_read ON cuentas_bancarias_pais;
CREATE POLICY cuentas_banco_read ON cuentas_bancarias_pais
  FOR SELECT USING (true);

DROP POLICY IF EXISTS cuentas_banco_admin ON cuentas_bancarias_pais;
CREATE POLICY cuentas_banco_admin ON cuentas_bancarias_pais
  FOR ALL USING (
    auth.uid() IN (SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_finanzas', 'admin'))
  ) WITH CHECK (
    auth.uid() IN (SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_finanzas', 'admin'))
  );
