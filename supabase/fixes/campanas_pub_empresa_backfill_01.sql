-- Da dueño real a la campaña publicada: empresa_id + solicitud_campana_id en campanas_publicitarias.
-- Hoy la tabla no guarda dueño (el link vive solo en solicitudes_campana) y el proveedor lo reconstruye
-- por titulo exacto (fragil). Aditivo y nullable. Backfill one-time por titulo, conservador ante ambiguedad.
-- Aplicar con -f.

ALTER TABLE public.campanas_publicitarias
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas_proveedoras(id),
  ADD COLUMN IF NOT EXISTS solicitud_campana_id uuid REFERENCES public.solicitudes_campana(id);

CREATE INDEX IF NOT EXISTS idx_campanas_pub_empresa ON public.campanas_publicitarias(empresa_id);

-- Backfill empresa_id: solo cuando el titulo mapea a UNA sola empresa (sin ambiguedad).
UPDATE public.campanas_publicitarias cp
SET empresa_id = sub.empresa_id
FROM (
  SELECT titulo, min(empresa_id::text)::uuid AS empresa_id
  FROM public.solicitudes_campana
  WHERE empresa_id IS NOT NULL
  GROUP BY titulo
  HAVING count(DISTINCT empresa_id) = 1
) sub
WHERE cp.titulo = sub.titulo AND cp.empresa_id IS NULL;

-- Backfill solicitud_campana_id: solo cuando hay UNA sola solicitud con ese titulo.
UPDATE public.campanas_publicitarias cp
SET solicitud_campana_id = sub.sid
FROM (
  SELECT titulo, min(id::text)::uuid AS sid
  FROM public.solicitudes_campana
  GROUP BY titulo
  HAVING count(*) = 1
) sub
WHERE cp.titulo = sub.titulo AND cp.solicitud_campana_id IS NULL;
