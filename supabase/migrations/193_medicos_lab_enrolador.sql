-- 193 Canal laboratorios — capa lab_enrolador_id (paso 2): enrolador en medicos + inmutabilidad
-- Agrega a medicos el lab que lo enroló (vía sus visitadores) y la fecha de enrolamiento
-- (marca desde cuándo cuentan las visitas para expiración de la ventana de prioridad).
-- Trigger BEFORE UPDATE: lab_enrolador_id es INMUTABLE una vez seteado (patrón referidos).
-- NO agrega RPCs; NO toca visitas_agendadas ni disponibilidad_medico (bloque separado).

-- 1) Columnas
ALTER TABLE public.medicos
  ADD COLUMN IF NOT EXISTS lab_enrolador_id    uuid REFERENCES public.empresas_proveedoras(id),
  ADD COLUMN IF NOT EXISTS lab_enrolador_fecha timestamptz;

COMMENT ON COLUMN public.medicos.lab_enrolador_id IS
  'Lab que enroló a este médico vía sus visitadores. NULL = no enrolado. Inmutable una vez seteado (trigger).';
COMMENT ON COLUMN public.medicos.lab_enrolador_fecha IS
  'Fecha de enrolamiento (se setea atómicamente con lab_enrolador_id); desde aquí cuentan las visitas para la ventana de prioridad.';

-- 2) Trigger de inmutabilidad (BEFORE UPDATE — no afecta el INSERT inicial de un médico)
CREATE OR REPLACE FUNCTION public.trg_medicos_lab_enrolador_inmutable()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.lab_enrolador_id IS NOT NULL AND NEW.lab_enrolador_id IS DISTINCT FROM OLD.lab_enrolador_id THEN
    RAISE EXCEPTION 'lab_enrolador_id es inmutable una vez seteado';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS trigger_medicos_lab_enrolador_inmutable ON public.medicos;
CREATE TRIGGER trigger_medicos_lab_enrolador_inmutable
BEFORE UPDATE ON public.medicos
FOR EACH ROW EXECUTE FUNCTION public.trg_medicos_lab_enrolador_inmutable();
