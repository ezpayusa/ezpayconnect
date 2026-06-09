-- ============================================
-- Migración 029: Suscripciones Push (Web Push API)
-- ============================================

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  pais_id UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices útiles
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user ON push_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_pais ON push_subscriptions(pais_id);

-- RLS
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Usuario ve sus push subscriptions" ON push_subscriptions;
CREATE POLICY "Usuario ve sus push subscriptions" ON push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Usuario crea sus push subscriptions" ON push_subscriptions;
CREATE POLICY "Usuario crea sus push subscriptions" ON push_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Usuario elimina sus push subscriptions" ON push_subscriptions;
CREATE POLICY "Usuario elimina sus push subscriptions" ON push_subscriptions
  FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role all push subscriptions" ON push_subscriptions;
CREATE POLICY "Service role all push subscriptions" ON push_subscriptions
  FOR ALL USING (true) WITH CHECK (true);
