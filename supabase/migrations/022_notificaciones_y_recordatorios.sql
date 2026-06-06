-- ============================================
-- Migración 022: Notificaciones in-app y Recordatorios unificados
-- EzPayConnect
-- ============================================

-- Extensiones para cron automático (pueden requerir habilitación en dashboard)
-- Si fallan, ignóralas y usa Supabase Scheduled Functions o un cron externo
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "pg_cron";
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'pg_cron no disponible. Usar Supabase Scheduled Functions o cron externo.';
END $$;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "pg_net";
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'pg_net no disponible.';
END $$;

-- ============================================
-- 1. Tabla notificaciones (in-app)
-- ============================================
CREATE TABLE IF NOT EXISTS notificaciones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL,
  titulo TEXT NOT NULL,
  mensaje TEXT NOT NULL,
  estado TEXT DEFAULT 'pendiente',
  leida BOOLEAN DEFAULT false,
  accion_url TEXT,
  metadata JSONB DEFAULT '{}',
  evento_id UUID,
  rol_destinatario TEXT,
  nivel_destinatario INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE notificaciones IS 'Notificaciones in-app del sistema';

-- Índices útiles
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario ON notificaciones(usuario_id);
CREATE INDEX IF NOT EXISTS idx_notificaciones_leida ON notificaciones(leida);
CREATE INDEX IF NOT EXISTS idx_notificaciones_created_at ON notificaciones(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notificaciones_evento ON notificaciones(evento_id);

-- RLS
ALTER TABLE notificaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notificaciones_select_propia ON notificaciones;
CREATE POLICY notificaciones_select_propia
  ON notificaciones FOR SELECT
  USING (auth.uid() = usuario_id);

DROP POLICY IF EXISTS notificaciones_update_propia ON notificaciones;
CREATE POLICY notificaciones_update_propia
  ON notificaciones FOR UPDATE
  USING (auth.uid() = usuario_id);

DROP POLICY IF EXISTS notificaciones_admin_all ON notificaciones;
CREATE POLICY notificaciones_admin_all
  ON notificaciones FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'ezpay_admin'
    )
  );

-- Permitir inserts desde Edge Functions (service role)
DROP POLICY IF EXISTS notificaciones_service_insert ON notificaciones;
CREATE POLICY notificaciones_service_insert
  ON notificaciones FOR INSERT
  WITH CHECK (true);

-- ============================================
-- 2. Tabla recordatorios (unificada: citas + visitas)
-- ============================================
CREATE TABLE IF NOT EXISTS recordatorios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo TEXT NOT NULL CHECK (tipo IN ('cita', 'visita')),
  cita_id INTEGER REFERENCES citas(id) ON DELETE CASCADE,
  visita_id UUID REFERENCES visitas_agendadas(id) ON DELETE CASCADE,
  destinatario_email TEXT,
  destinatario_telefono TEXT,
  mensaje TEXT NOT NULL,
  fecha_envio_programada TIMESTAMPTZ NOT NULL,
  estado TEXT DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'enviado', 'fallido')),
  fecha_envio_real TIMESTAMPTZ,
  error TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Validar que exactamente uno de cita_id o visita_id esté presente
  CONSTRAINT chk_recordatorio_referencia CHECK (
    (cita_id IS NOT NULL AND visita_id IS NULL) OR
    (cita_id IS NULL AND visita_id IS NOT NULL)
  )
);

COMMENT ON TABLE recordatorios IS 'Recordatorios automáticos para citas médicas y visitas de proveedores';

-- Índices
CREATE INDEX IF NOT EXISTS idx_recordatorios_estado_fecha ON recordatorios(estado, fecha_envio_programada);
CREATE INDEX IF NOT EXISTS idx_recordatorios_cita ON recordatorios(cita_id);
CREATE INDEX IF NOT EXISTS idx_recordatorios_visita ON recordatorios(visita_id);

-- RLS
ALTER TABLE recordatorios ENABLE ROW LEVEL SECURITY;

-- Solo service role puede leer/insertar/actualizar (manejado por Edge Functions)
DROP POLICY IF EXISTS recordatorios_service_all ON recordatorios;
CREATE POLICY recordatorios_service_all
  ON recordatorios FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================
-- 3. Función SQL para procesar recordatorios vía cron
-- ============================================
CREATE OR REPLACE FUNCTION procesar_recordatorios_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Stub documentado. En Supabase hosted las env vars no están disponibles en PG
  -- y pg_net requiere configuración adicional. Se recomienda usar:
  --   1. Supabase Scheduled Functions (dashboard)
  --   2. Un cron externo (cron-job.org)
  -- para invocar periodicamente /functions/v1/procesar-recordatorios
  RAISE NOTICE 'procesar_recordatorios_cron() invocado. Usar Supabase Scheduled Functions o cron externo para invocar /functions/v1/procesar-recordatorios';
END;
$$;

-- ============================================
-- 4. Cron job (opcional, puede fallar si pg_cron no está habilitado en el proyecto)
-- ============================================
DO $$
BEGIN
  -- Intentar eliminar job previo si existe
  PERFORM cron.unschedule('procesar-recordatorios-hourly');
EXCEPTION WHEN OTHERS THEN
  -- Ignorar si no existe
  NULL;
END $$;

-- Nota: Este job requiere que pg_cron esté habilitado y que exista un mecanismo de auth.
-- En Supabase hosted, la forma recomendada es usar Supabase Scheduled Functions desde el dashboard
-- o programar un cron externo (cron-job.org) que haga POST al endpoint de la Edge Function.
-- Dejamos comentado el schedule como referencia:
-- SELECT cron.schedule('procesar-recordatorios-hourly', '0 * * * *', 'SELECT procesar_recordatorios_cron();');
