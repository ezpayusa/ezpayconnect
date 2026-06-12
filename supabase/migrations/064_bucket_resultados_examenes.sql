-- ============================================================
-- 064 · Bucket para archivos de resultados de examen (PDF/imagen)
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('resultados-examenes', 'resultados-examenes', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Autenticados suben resultados" ON storage.objects;
CREATE POLICY "Autenticados suben resultados" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'resultados-examenes');

DROP POLICY IF EXISTS "Lectura publica resultados" ON storage.objects;
CREATE POLICY "Lectura publica resultados" ON storage.objects
  FOR SELECT USING (bucket_id = 'resultados-examenes');

DROP POLICY IF EXISTS "Autenticados actualizan resultados" ON storage.objects;
CREATE POLICY "Autenticados actualizan resultados" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'resultados-examenes');
