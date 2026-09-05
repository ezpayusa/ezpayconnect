-- ############################################################################################
-- 282 — el UNIQUE de "una visita por prospecto y dia" deja de contar las CANCELADAS
-- ############################################################################################
-- EL BUG (reproducido en navegador)
-- --------------------------------
-- `visitas_com_una_por_dia` es UNIQUE (prospecto_id, asesor_id, fecha_planificada) TOTAL: cuenta
-- tambien las filas en estado 'cancelada'. Consecuencia: cancelar una visita NO libera el dia. El
-- par (prospecto, dia) queda quemado para siempre y re-agendar devuelve 23505 / 409.
-- Cancelar y re-agendar es el flujo NORMAL — es para lo que existe cancelar_visita_comercial, que
-- la 280 agrego sin notar que el UNIQUE la dejaba sin salida.
--
-- POR QUE ESTO NO ES UN `DROP INDEX`
-- ----------------------------------
-- Medido antes de escribir: `visitas_com_una_por_dia` NO es un indice suelto. La 273 lo declaro
-- inline dentro del CREATE TABLE como `CONSTRAINT ... UNIQUE`, asi que el indice CUELGA de una
-- constraint y `DROP INDEX` falla con 2BP01 ("cannot drop index ... because constraint ...
-- requires it"). Hay que soltar la CONSTRAINT.
-- Y no alcanza con hacerla parcial en el lugar: en Postgres una constraint UNIQUE **no puede ser
-- PARCIAL** — el WHERE solo existe en un indice unico suelto. El reemplazo es, necesariamente, un
-- indice y no una constraint. Se conserva el nombre para que el 23505 siga diciendo lo mismo.
--
-- QUE SE PIERDE AL DEJAR DE SER CONSTRAINT: `ON CONFLICT ON CONSTRAINT visitas_com_una_por_dia`
-- dejaria de resolver. Medido: NINGUNA funcion de public/private usa ON CONFLICT sobre
-- visitas_comerciales (planificar_visita nombra el indice solo en un comentario, a proposito, para
-- explicar que deja subir el 23505 tal cual). Nada que migrar.
--
-- SEGURIDAD DEL CAMBIO, medida contra la base viva antes de escribir esto:
--   - 4 filas en visitas_comerciales (1 cancelada, 2 en_curso, 1 planificada).
--   - 0 ternas (prospecto, asesor, fecha) quedarian DUPLICADAS al excluir canceladas -> el indice
--     nuevo se puede construir sin conflicto.
--   - 0 NULLs en las 3 columnas indexadas, y `estado` es NOT NULL DEFAULT 'planificada'. Eso
--     importa: si `estado` admitiera NULL, `NULL <> 'cancelada'` daria NULL y la fila se escaparia
--     del indice parcial — un NULL trivaluado abriendo la puerta, otra vez. No es el caso.
--
-- EL PREDICADO ES `<> 'cancelada'` Y NO UNA LISTA DE ESTADOS VIVOS: los estados terminales que NO
-- son cancelacion ('realizada', 'no_realizada') SIGUEN bloqueando el dia, porque son hechos que
-- ocurrieron. Solo la cancelacion borra la reserva. P604 fija esa distincion.
-- ############################################################################################

-- La constraint se va; el indice que la respaldaba se va con ella.
ALTER TABLE public.visitas_comerciales
  DROP CONSTRAINT IF EXISTS visitas_com_una_por_dia;

-- Idempotencia real: en un ambiente donde la 282 ya corrio, arriba no habia constraint que soltar
-- y aca ya existe el indice parcial. Este DROP cubre el caso intermedio (indice suelto TOTAL).
DROP INDEX IF EXISTS public.visitas_com_una_por_dia;

CREATE UNIQUE INDEX IF NOT EXISTS visitas_com_una_por_dia
  ON public.visitas_comerciales (prospecto_id, asesor_id, fecha_planificada)
  WHERE estado <> 'cancelada';

-- Re-verificacion: el indice quedo, es UNIQUE, es PARCIAL, y el predicado es el que dijimos.
DO $$
DECLARE v_def text; v_unico boolean; v_parcial boolean; v_es_constraint boolean;
BEGIN
  SELECT pg_get_indexdef(i.indexrelid), i.indisunique, i.indpred IS NOT NULL
    INTO v_def, v_unico, v_parcial
    FROM pg_index i
   WHERE i.indexrelid = 'public.visitas_com_una_por_dia'::regclass;

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'la 282 se quedo sin indice: visitas_com_una_por_dia no existe';
  END IF;
  IF NOT v_unico THEN
    RAISE EXCEPTION 'el indice quedo NO UNIQUE: %', v_def;
  END IF;
  IF NOT v_parcial OR v_def NOT ILIKE '%cancelada%' THEN
    RAISE EXCEPTION 'el indice quedo TOTAL o con otro predicado: %', v_def;
  END IF;

  SELECT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.visitas_comerciales'::regclass
                    AND conname='visitas_com_una_por_dia')
    INTO v_es_constraint;
  IF v_es_constraint THEN
    RAISE EXCEPTION 'sigue siendo una CONSTRAINT: una constraint UNIQUE no puede ser parcial, asi que el dia cancelado seguiria bloqueado';
  END IF;
END $$;
