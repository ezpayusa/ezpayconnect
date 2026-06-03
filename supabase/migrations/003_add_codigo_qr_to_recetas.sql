-- Agregar codigo_qr a recetas para el sistema de QR de dispensacion

ALTER TABLE IF EXISTS recetas
ADD COLUMN IF NOT EXISTS codigo_qr TEXT UNIQUE;

-- Actualizar recetas existentes con un codigo generado
UPDATE recetas
SET codigo_qr = 'EZP-' || id || '-' || substr(md5(random()::text), 1, 6)
WHERE codigo_qr IS NULL;
