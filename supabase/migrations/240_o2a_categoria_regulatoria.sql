-- ============================================================
-- O2a · Clasificacion regulatoria del catalogo global de medicamentos.
-- INERTE: agrega la columna, no clasifica ninguna fila (40 filas quedan NULL).
-- default NULL = sin_clasificar (fail-safe: "controlados" nunca incluye un NULL).
-- Los 5 valores son TENTATIVOS, pendientes de validacion contra la norma GT (MSPAS).
-- text+CHECK y no CREATE TYPE: el CHECK se ajusta con drop/add; el enum nativo no.
-- Ref: DISENO-REGULATORIO.md §A1, decision cerrada A1 (2026-06-24).
-- La clasificacion autoritativa vive SOLO en public.medicamentos (RLS write = super_admin).
-- Habilita el gate de acuse de emitir_receta (O1).
-- ============================================================

ALTER TABLE public.medicamentos
  ADD COLUMN IF NOT EXISTS categoria_regulatoria text;

ALTER TABLE public.medicamentos
  DROP CONSTRAINT IF EXISTS chk_categoria_regulatoria;

ALTER TABLE public.medicamentos
  ADD CONSTRAINT chk_categoria_regulatoria
  CHECK (categoria_regulatoria IS NULL OR categoria_regulatoria IN
    ('venta_libre','receta_simple','psicotropico','estupefaciente','recetario_especial'));

COMMENT ON COLUMN public.medicamentos.categoria_regulatoria IS
  'NULL = sin clasificar (fail-safe). Valores tentativos, pendiente validacion MSPAS. Write: solo super_admin.';
