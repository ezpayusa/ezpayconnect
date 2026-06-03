-- ============================================
-- Migración 011: Bucket de Storage para campañas publicitarias
-- ============================================

-- 1. Crear bucket público para imágenes de campañas
INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
VALUES (
  'campanas',
  'campanas',
  true,
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml'];

-- 2. Políticas RLS para el bucket
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Usuarios autenticados pueden subir campanas' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "Usuarios autenticados pueden subir campanas"
      ON storage.objects
      FOR INSERT
      WITH CHECK (bucket_id = 'campanas' AND auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Usuarios autenticados pueden eliminar campanas' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "Usuarios autenticados pueden eliminar campanas"
      ON storage.objects
      FOR DELETE
      USING (bucket_id = 'campanas' AND auth.role() = 'authenticated');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Lectura pública de campanas' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "Lectura pública de campanas"
      ON storage.objects
      FOR SELECT
      USING (bucket_id = 'campanas');
  END IF;
END $$;
