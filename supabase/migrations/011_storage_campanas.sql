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
  5242880, -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml'];

-- 2. Políticas RLS para el bucket
-- Permitir a usuarios autenticados subir imágenes
CREATE POLICY IF NOT EXISTS "Usuarios autenticados pueden subir campanas"
  ON storage.objects
  FOR INSERT
  WITH CHECK (bucket_id = 'campanas' AND auth.role() = 'authenticated');

-- Permitir a usuarios autenticados eliminar imágenes
CREATE POLICY IF NOT EXISTS "Usuarios autenticados pueden eliminar campanas"
  ON storage.objects
  FOR DELETE
  USING (bucket_id = 'campanas' AND auth.role() = 'authenticated');

-- Permitir lectura pública de imágenes
CREATE POLICY IF NOT EXISTS "Lectura pública de campanas"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'campanas');
