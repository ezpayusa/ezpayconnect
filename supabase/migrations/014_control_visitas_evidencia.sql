-- ============================================
-- Migración 014: Control de visitas + checkin/checkout + evidencia
-- ============================================

-- 1. Agregar contador de visitas usadas a planes_asignaciones
ALTER TABLE planes_asignaciones ADD COLUMN IF NOT EXISTS visitas_usadas INTEGER NOT NULL DEFAULT 0;

-- 2. Agregar campos de control a visitas_agendadas
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS fecha_limite_cancelacion DATE;
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS checkin_fecha TIMESTAMPTZ;
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS checkin_lat NUMERIC(10, 8);
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS checkin_lng NUMERIC(11, 8);
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS checkin_evidencia_url TEXT;
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS checkout_fecha TIMESTAMPTZ;
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS checkout_notas TEXT;
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS visita_concretada BOOLEAN DEFAULT false;
ALTER TABLE visitas_agendadas ADD COLUMN IF NOT EXISTS verificada_por_sistema BOOLEAN DEFAULT false;

-- 3. Función para calcular 3 días hábiles antes de una fecha
CREATE OR REPLACE FUNCTION calcular_limite_cancelacion(fecha_visita DATE)
RETURNS DATE AS $$
DECLARE
  dias_restantes INT := 3;
  fecha_actual DATE := fecha_visita;
BEGIN
  WHILE dias_restantes > 0 LOOP
    fecha_actual := fecha_actual - INTERVAL '1 day';
    IF EXTRACT(DOW FROM fecha_actual) NOT IN (0, 6) THEN
      dias_restantes := dias_restantes - 1;
    END IF;
  END LOOP;
  RETURN fecha_actual;
END;
$$ LANGUAGE plpgsql;

-- 4. Trigger para auto-calcular fecha_limite_cancelacion al insertar visita
CREATE OR REPLACE FUNCTION set_fecha_limite_cancelacion()
RETURNS TRIGGER AS $$
BEGIN
  NEW.fecha_limite_cancelacion := calcular_limite_cancelacion(NEW.fecha_visita);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_limite_cancelacion ON visitas_agendadas;
CREATE TRIGGER trigger_set_limite_cancelacion
  BEFORE INSERT ON visitas_agendadas
  FOR EACH ROW
  EXECUTE FUNCTION set_fecha_limite_cancelacion();

-- 5. Bucket para evidencias de visitas (público para que admin y empresa vean)
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES (
  'evidencias-visitas',
  'evidencias-visitas',
  true,
  false,
  2097152,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- Políticas storage
DROP POLICY IF EXISTS "Autenticados suben evidencias" ON storage.objects;
CREATE POLICY "Autenticados suben evidencias"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'evidencias-visitas' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Todos ven evidencias" ON storage.objects;
CREATE POLICY "Todos ven evidencias"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'evidencias-visitas');
