-- ============================================================
-- O1 (DDL) · Correlativo por medico + acuse de regulados + emitida_at + flag de cutover.
-- INERTE: no crea emitir_receta, no cambia comportamiento. Habilita la RPC (mig 242).
-- Ref: DISENO-REGULATORIO.md §B7 (correlativo), addendum §3 [CERRADO D-ACUSE] opcion b1,
--      §14 [CERRADO C1] (flag = backout), y las 3 correcciones acordadas (2026-07-10):
--        (1) emitir_receta crea la fila de recetas_avanzadas en la MISMA transaccion
--        (2) emitida_at es la primera piedra del libro regulatorio y de la metrica de fuga
--        (3) el estado 'anulada' debe respetarse server-side (O6, no aqui)
-- ============================================================

-- ---------- 1. Flag de cutover (backout sin redeploy) ----------
-- Patron: espejo de private.reveal_gate_flags (RLS on, sin policies, sin grants).
-- default FALSE: un flag de cutover NACE APAGADO.
CREATE TABLE IF NOT EXISTS private.emision_flags (
  clave      text PRIMARY KEY,
  habilitado boolean NOT NULL DEFAULT false
);
ALTER TABLE private.emision_flags ENABLE ROW LEVEL SECURITY;

INSERT INTO private.emision_flags (clave, habilitado)
VALUES ('emitir_receta_rpc', false)
ON CONFLICT (clave) DO NOTHING;

-- Lectura desde el navegador: private.* no es alcanzable por PostgREST.
-- DEFINER + search_path='' + fail-safe a false si la fila no existe.
CREATE OR REPLACE FUNCTION public.emision_flag(p_clave text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT COALESCE((SELECT habilitado FROM private.emision_flags WHERE clave = p_clave), false);
$$;

REVOKE EXECUTE ON FUNCTION public.emision_flag(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.emision_flag(text) TO authenticated;

-- ---------- 2. Correlativo gapless por medico (semantica talonario) ----------
CREATE TABLE IF NOT EXISTS public.medico_correlativos (
  medico_id     uuid PRIMARY KEY,
  ultimo_numero bigint NOT NULL DEFAULT 0,
  updated_at    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.medico_correlativos ENABLE ROW LEVEL SECURITY;
-- Sin policies: escritura y lectura SOLO por RPC DEFINER (emitir_receta / recetario_medico).

ALTER TABLE public.recetas
  ADD COLUMN IF NOT EXISTS numero_correlativo bigint;

-- Unicidad por medico. Las 19 historicas quedan NULL (pre-numeracion) y no chocan.
CREATE UNIQUE INDEX IF NOT EXISTS uq_recetas_corr_medico
  ON public.recetas (medico_id, numero_correlativo)
  WHERE numero_correlativo IS NOT NULL;

COMMENT ON COLUMN public.recetas.numero_correlativo IS
  'Talonario gapless por medico. NULL = pre-numeracion (recetas anteriores a O1). Lo asigna SOLO emitir_receta.';

-- ---------- 3. Acuse del medico al recetar un regulado (opcion b1) ----------
ALTER TABLE public.receta_items
  ADD COLUMN IF NOT EXISTS acuse_iniciales text,
  ADD COLUMN IF NOT EXISTS acuse_at        timestamptz,
  ADD COLUMN IF NOT EXISTS acuse_categoria text;

COMMENT ON COLUMN public.receta_items.acuse_iniciales IS
  'Iniciales del medico al recetar un medicamento regulado. Lo persiste emitir_receta; no evadible desde el cliente.';
COMMENT ON COLUMN public.receta_items.acuse_categoria IS
  'Snapshot de medicamentos.categoria_regulatoria al momento de emitir. El catalogo puede cambiar; la receta no.';

-- ---------- 4. Momento de emision (libro regulatorio + metrica de fuga) ----------
-- Distinto de created_at: hoy la fila nace cuando alguien clickea "generar PDF",
-- no cuando el medico emite. Tras O1 nacen juntos; la columna deja de mentir.
ALTER TABLE public.recetas_avanzadas
  ADD COLUMN IF NOT EXISTS emitida_at timestamptz;

COMMENT ON COLUMN public.recetas_avanzadas.emitida_at IS
  'Momento de emision de la receta (lo setea emitir_receta). NULL en las 3 filas historicas creadas por la edge.';
