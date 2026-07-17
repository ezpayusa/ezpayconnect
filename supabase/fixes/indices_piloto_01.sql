-- Índices para el piloto (rutas calientes: dashboard médico, portal paciente, clínica, farmacia).
-- Plain CREATE INDEX IF NOT EXISTS (NO CONCURRENTLY): las tablas son diminutas hoy → instantáneo, sin lock real.
-- Idempotente. Aplicar con: supabase db query --linked -f supabase/fixes/indices_piloto_01.sql
-- Reversible: ver el bloque DROP al pie.

CREATE INDEX IF NOT EXISTS idx_citas_medico_fecha      ON public.citas (medico_id, fecha);
CREATE INDEX IF NOT EXISTS idx_citas_clinica_fecha     ON public.citas (clinica_id, fecha);
CREATE INDEX IF NOT EXISTS idx_citas_paciente_medico   ON public.citas (paciente_id, medico_id);
CREATE INDEX IF NOT EXISTS idx_recetas_paciente        ON public.recetas (paciente_id);
CREATE INDEX IF NOT EXISTS idx_receta_items_farmacia   ON public.receta_items (farmacia_id);
CREATE INDEX IF NOT EXISTS idx_pagos_prov_empresa      ON public.pagos_proveedor (empresa_id);
CREATE INDEX IF NOT EXISTS idx_medico_clinicas_clinica ON public.medico_clinicas (clinica_id);
CREATE INDEX IF NOT EXISTS idx_examenes_medico         ON public.examenes (medico_id);
CREATE INDEX IF NOT EXISTS idx_facturas_medico         ON public.facturas (medico_id);
CREATE INDEX IF NOT EXISTS idx_disponibilidad_medico   ON public.disponibilidad_medico (medico_id, clinica_id);

-- REVERSO (si hiciera falta):
-- DROP INDEX IF EXISTS public.idx_citas_medico_fecha, public.idx_citas_clinica_fecha,
--   public.idx_citas_paciente_medico, public.idx_recetas_paciente, public.idx_receta_items_farmacia,
--   public.idx_pagos_prov_empresa, public.idx_medico_clinicas_clinica, public.idx_examenes_medico,
--   public.idx_facturas_medico, public.idx_disponibilidad_medico;
