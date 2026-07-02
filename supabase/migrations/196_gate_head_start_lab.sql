-- 196 Canal laboratorios — head-start por fecha (trigger BEFORE INSERT en visitas_agendadas)
-- Mientras un médico tiene prioridad activa de su lab enrolador, OTRO lab solo puede proponer visitas
-- con fecha_visita >= CURRENT_DATE + dias_ventaja_reserva (del lab prioritario). El lab prioritario y
-- los médicos no enrolados / con ventana expirada: sin restricción. Fuente de verdad en BASE (no front).
--
-- Orden en la cadena BEFORE INSERT (alfabético por nombre de trigger):
--   1) trg_gate_visita_pais           (país/plan; estampa pais_id)   ← corre ANTES
--   2) trigger_forzar_estado_propuesta (setea estado)
--   3) trigger_gate_head_start_lab     (ESTE; head-start por fecha)  ← solo lee medico_id/empresa_id/fecha_visita
--   4) trigger_set_limite_cancelacion  (setea fecha_limite_cancelacion)
-- Ninguno de los otros modifica las columnas que este lee → convive sin interferir, en cualquier orden.
--
-- MURO ÉTICO: opera EXCLUSIVAMENTE sobre visitas_agendadas (agenda de visitadores). Solo consulta
-- prioridad_activa (ya walled) y empresas_proveedoras. NO toca disponibilidad_medico ni contexto='paciente'.

CREATE OR REPLACE FUNCTION public.trg_gate_head_start_lab()
RETURNS trigger
LANGUAGE plpgsql SET search_path = public
AS $function$
DECLARE
  v_prio      record;
  v_ventaja   int;
  v_fecha_min date;
BEGIN
  SELECT * INTO v_prio FROM public.prioridad_activa(NEW.medico_id);

  -- Sin prioridad activa (no enrolado o ventana expirada): cualquier lab reserva libre.
  IF NOT v_prio.activa THEN
    RETURN NEW;
  END IF;

  -- El propio lab prioritario reserva cualquier fecha.
  IF NEW.empresa_id = v_prio.lab_prioritario_id THEN
    RETURN NEW;
  END IF;

  -- Otro lab: head-start por fecha del lab prioritario (default global 5 días).
  SELECT COALESCE(ep.dias_ventaja_reserva, 5) INTO v_ventaja
  FROM public.empresas_proveedoras ep
  WHERE ep.id = v_prio.lab_prioritario_id;
  v_ventaja := COALESCE(v_ventaja, 5);

  v_fecha_min := CURRENT_DATE + v_ventaja;   -- date + int = date

  IF NEW.fecha_visita < v_fecha_min THEN
    RAISE EXCEPTION 'Esta fecha está reservada para el laboratorio con prioridad hasta el %. Puedes agendar a partir de esa fecha.', to_char(v_fecha_min, 'YYYY-MM-DD')
      USING ERRCODE = 'PV002';   -- head-start (país=P0001, bolsa=PV001, head-start=PV002) → front lo captura por SQLSTATE
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_gate_head_start_lab ON public.visitas_agendadas;
CREATE TRIGGER trigger_gate_head_start_lab
BEFORE INSERT ON public.visitas_agendadas
FOR EACH ROW EXECUTE FUNCTION public.trg_gate_head_start_lab();
