-- 181 Migración A — Catálogo de especialidades + backfill medicos.especialidad_id
-- Introduce catálogo normalizado de especialidades. medicos.especialidad (texto) se MANTIENE
-- en paralelo como respaldo por un ciclo (NO se toca aquí).
-- Semilla: Cardiología, Pediatría, Medicina General. "Administración" NO se siembra
-- (error de carga confirmado por Oscar, no es especialidad médica).
-- Backfill: 'General' ⇒ 'Medicina General'; 'Administración' y NULL ⇒ especialidad_id NULL.

-- ============================================================
-- 1) TABLA especialidades (catálogo público de lectura)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.especialidades (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre     text NOT NULL UNIQUE,
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Catálogo de solo-lectura para authenticated (patrón del proyecto:
-- toda tabla nace con ALL a authenticated por default privileges → REVOKE explícito de escritura).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.especialidades FROM authenticated;
REVOKE ALL ON public.especialidades FROM anon;
GRANT  SELECT ON public.especialidades TO authenticated;

ALTER TABLE public.especialidades ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated ve especialidades" ON public.especialidades;
CREATE POLICY "Authenticated ve especialidades" ON public.especialidades
  FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 2) COLUMNA medicos.especialidad_id (FK) — en paralelo al texto, sin tocar medicos.especialidad
-- ============================================================
ALTER TABLE public.medicos
  ADD COLUMN IF NOT EXISTS especialidad_id uuid REFERENCES public.especialidades(id);

-- ============================================================
-- 3) SEMILLA (sin "Administración")
-- ============================================================
INSERT INTO public.especialidades (nombre) VALUES
  ('Cardiología'),
  ('Pediatría'),
  ('Medicina General')
ON CONFLICT (nombre) DO NOTHING;

-- ============================================================
-- 4) BACKFILL medicos.especialidad_id
--    'General' ⇒ 'Medicina General'; 'Administración' y NULL ⇒ quedan NULL (sin match).
-- ============================================================
UPDATE public.medicos m
SET especialidad_id = e.id
FROM public.especialidades e
WHERE m.especialidad IS NOT NULL
  AND m.especialidad <> 'Administración'
  AND e.nombre = CASE WHEN m.especialidad = 'General' THEN 'Medicina General'
                      ELSE m.especialidad END;
