-- 250: Pieza 1 (DDL) — confirmación de recepción de receta por el paciente.
-- (1) token de confirmación dedicado por receta (molde dispatch_token, mig 085) para el link del email.
--     NO se reusa dispatch_token (credencial de despacho): credenciales y blast-radius separados.
-- (2) tabla de eventos confirmaciones_receta con pais_id snapshot + RLS cerrada (0 policies).

-- ── (1) token de confirmación en recetas_avanzadas (por DEFAULT de columna) ─────
-- ADD COLUMN NOT NULL con default volátil (gen_random_bytes) => reescritura de tabla y
-- cada fila existente recibe su propio token único (mismo comportamiento que mig 085).
ALTER TABLE public.recetas_avanzadas
  ADD COLUMN IF NOT EXISTS confirmacion_token text NOT NULL
    DEFAULT encode(extensions.gen_random_bytes(32), 'hex'),
  ADD COLUMN IF NOT EXISTS confirmacion_token_expira_at timestamptz NOT NULL
    DEFAULT (now() + interval '90 days');

-- ── (2) tabla de eventos de confirmación (pais_id snapshot para reporte país/tiempo) ──
CREATE TABLE IF NOT EXISTS public.confirmaciones_receta (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receta_avanzada_id    uuid NOT NULL REFERENCES public.recetas_avanzadas(id) ON DELETE CASCADE,
  pais_id               uuid NOT NULL REFERENCES public.configuracion_pais(id),
  confirmada_at         timestamptz NOT NULL DEFAULT now(),
  confirmada_ip         inet,
  confirmada_user_agent text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT confirmaciones_receta_avanzada_uniq UNIQUE (receta_avanzada_id)  -- idempotencia: 1 confirmación por receta
);

CREATE INDEX IF NOT EXISTS idx_confirmaciones_receta_pais_fecha
  ON public.confirmaciones_receta (pais_id, confirmada_at);

-- RLS ON, 0 policies: la escribe la edge pública (service_role/DEFINER, Pieza 2) y la lee
-- el admin por RPC país-scoped (pieza futura). Nadie la toca por PostgREST directo.
ALTER TABLE public.confirmaciones_receta ENABLE ROW LEVEL SECURITY;
