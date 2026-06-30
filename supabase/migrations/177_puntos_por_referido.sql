-- 177 Ola 1 backend "puntos por referido"
-- 10 puntos al REFERIDOR cuando su amigo referido completa su PRIMERA cita ('completada').
-- Ledger append-only (saldo = SUM). Otorgamiento por TRIGGER AFTER UPDATE OF estado ON citas
-- → cubre las 3 vías de completar cita (UPDATE directo médico, UPDATE directo ConsultaPage, RPC actualizar_estado_cita).
-- Best-effort: el otorgamiento NUNCA tumba el UPDATE de la cita.

-- ============================================================
-- 1) TABLA puntos_movimientos — ledger append-only
-- ============================================================
CREATE TABLE IF NOT EXISTS public.puntos_movimientos (
  id                     bigserial PRIMARY KEY,
  paciente_id            bigint NOT NULL REFERENCES public.pacientes(id),  -- DUEÑO de los puntos (el referidor cuando gana)
  puntos                 int    NOT NULL,                                   -- + gana, - canje (Ola 3)
  tipo                   text   NOT NULL,                                   -- 'referido_completado' (Ola 1); 'canje' (Ola 3)
  motivo                 text,
  referido_atribucion_id bigint REFERENCES public.referidos_atribucion(id),-- de qué atribución vino (nullable para otros tipos)
  cita_id                bigint,                                            -- cita que disparó el otorgamiento (auditoría/idempotencia)
  created_at             timestamptz NOT NULL DEFAULT now()
);

-- IDEMPOTENCIA: una misma atribución otorga puntos UNA sola vez.
CREATE UNIQUE INDEX IF NOT EXISTS uq_puntos_referido
  ON public.puntos_movimientos (referido_atribucion_id)
  WHERE tipo = 'referido_completado';

-- Escritura SOLO por el trigger DEFINER. authenticated conserva SELECT (gobernado por RLS); anon nada.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.puntos_movimientos FROM authenticated;
REVOKE ALL ON public.puntos_movimientos FROM anon;

ALTER TABLE public.puntos_movimientos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Paciente ve sus movimientos de puntos" ON public.puntos_movimientos;
CREATE POLICY "Paciente ve sus movimientos de puntos" ON public.puntos_movimientos
  FOR SELECT TO authenticated
  USING (private.paciente_es_mio(paciente_id));

-- ============================================================
-- 2) FUNCIÓN trigger otorgar_puntos_referido()
-- ============================================================
CREATE OR REPLACE FUNCTION public.otorgar_puntos_referido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_atrib  RECORD;
  v_puntos constant int := 10;  -- monto por referido completado (ajustable a futuro)
BEGIN
  -- Solo en transición REAL a 'completada' (evita re-saves del mismo estado).
  IF NEW.estado <> 'completada' OR COALESCE(OLD.estado, '') = 'completada' THEN
    RETURN NEW;
  END IF;

  -- BEST-EFFORT: cualquier error del otorgamiento se traga; nunca rompe la transición de la cita.
  BEGIN
    -- Solo la PRIMERA cita completada de este paciente.
    IF EXISTS (
      SELECT 1 FROM public.citas c
      WHERE c.paciente_id = NEW.paciente_id
        AND c.estado = 'completada'
        AND c.id <> NEW.id
    ) THEN
      RETURN NEW;  -- ya tenía otra completada → no es la primera
    END IF;

    -- ¿El paciente vino por referido?
    SELECT a.id AS atrib_id, rp.referidor_paciente_id AS referidor
      INTO v_atrib
    FROM public.referidos_atribucion a
    JOIN public.referidos_paciente rp ON rp.codigo = a.codigo
    WHERE a.referido_nuevo_paciente_id = NEW.paciente_id;

    IF NOT FOUND THEN
      RETURN NEW;  -- no vino por referido → nada que otorgar
    END IF;

    -- Otorgar al REFERIDOR. Idempotente por el índice único parcial.
    INSERT INTO public.puntos_movimientos
      (paciente_id, puntos, tipo, motivo, referido_atribucion_id, cita_id)
    VALUES
      (v_atrib.referidor, v_puntos, 'referido_completado',
       'Tu referido completó su primera cita', v_atrib.atrib_id, NEW.id)
    ON CONFLICT (referido_atribucion_id) WHERE tipo = 'referido_completado' DO NOTHING;

  EXCEPTION WHEN OTHERS THEN
    NULL;  -- best-effort: no propagar (no tumbar el UPDATE de la cita)
  END;

  RETURN NEW;
END;
$function$;

-- ============================================================
-- 3) TRIGGER sobre citas (AFTER UPDATE OF estado → cubre las 3 vías de completar)
-- ============================================================
DROP TRIGGER IF EXISTS trg_otorgar_puntos_referido ON public.citas;
CREATE TRIGGER trg_otorgar_puntos_referido
  AFTER UPDATE OF estado ON public.citas
  FOR EACH ROW EXECUTE FUNCTION public.otorgar_puntos_referido();
