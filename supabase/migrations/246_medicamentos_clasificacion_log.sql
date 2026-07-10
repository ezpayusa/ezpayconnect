-- 246: log append-only de clasificacion regulatoria de medicamentos
-- Escrito SOLO por public.clasificar_medicamentos (mig 247, DEFINER).
-- RLS on + 0 policies = ningun cliente PostgREST lo toca.
-- El trigger es lo que lo hace append-only DE VERDAD: la RPC corre como
-- postgres (dueno de la tabla) y podria borrar su propia evidencia.
BEGIN;

CREATE TABLE public.medicamentos_clasificacion_log (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  medicamento_id  bigint NOT NULL REFERENCES public.medicamentos(id) ON DELETE RESTRICT,
  categoria_antes text,
  categoria_despues text NOT NULL,
  motivo          text NOT NULL,
  actor_id        uuid NOT NULL,
  actor_rol       text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_medclaslog_medicamento ON public.medicamentos_clasificacion_log (medicamento_id, created_at DESC);

ALTER TABLE public.medicamentos_clasificacion_log ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.medicamentos_clasificacion_log FROM PUBLIC;
REVOKE ALL ON public.medicamentos_clasificacion_log FROM anon;
REVOKE ALL ON public.medicamentos_clasificacion_log FROM authenticated;

CREATE OR REPLACE FUNCTION private.medclaslog_solo_append()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
BEGIN
  RAISE EXCEPTION 'PC009: medicamentos_clasificacion_log es append-only (intento de %)', TG_OP
    USING ERRCODE = 'PC009';
END;
$fn$;

CREATE TRIGGER trg_medclaslog_solo_append
  BEFORE UPDATE OR DELETE ON public.medicamentos_clasificacion_log
  FOR EACH ROW EXECUTE FUNCTION private.medclaslog_solo_append();

-- TRUNCATE no dispara triggers de fila. Este cierra esa puerta.
-- Contra el dueno de la base (postgres, que puede DISABLE TRIGGER) no hay
-- append-only posible: eso se resuelve con backups y control de acceso.
CREATE TRIGGER trg_medclaslog_no_truncate
  BEFORE TRUNCATE ON public.medicamentos_clasificacion_log
  FOR EACH STATEMENT EXECUTE FUNCTION private.medclaslog_solo_append();

COMMIT;
