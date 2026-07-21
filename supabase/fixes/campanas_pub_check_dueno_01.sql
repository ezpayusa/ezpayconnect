-- Guardarrail: una campana nacida de una solicitud DEBE llevar su empresa_id (dueno). Una house-ad del admin
-- (ambos NULL) sigue valida. Blinda contra regresiones futuras (metricas del proveedor dependen de empresa_id).
-- Pre-check: 0 filas con solicitud_campana_id NOT NULL y empresa_id NULL. Idempotente por el guard.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_campana_dueno'
      AND conrelid = 'public.campanas_publicitarias'::regclass
  ) THEN
    ALTER TABLE public.campanas_publicitarias
      ADD CONSTRAINT chk_campana_dueno
      CHECK (solicitud_campana_id IS NULL OR empresa_id IS NOT NULL);
  END IF;
END $$;
