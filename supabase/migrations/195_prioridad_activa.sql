-- 195 Canal laboratorios — RPC prioridad_activa(medico) SOLO LECTURA
-- Calcula EN VIVO (sin contador guardado) si la ventana de prioridad del lab enrolador sobre un médico
-- sigue activa. Lee visitas cumplidas reales (estado='completada' AND checkout_fecha IS NOT NULL AND
-- checkout_fecha >= lab_enrolador_fecha) contra el lab enrolador, y compara con el límite
-- (empresas_proveedoras.ventana_prioridad_visitas, default global 8) + techo anti-gaming de 18 meses.
--
-- MURO ÉTICO: NO toca disponibilidad_medico ni nada de contexto='paciente'. Solo lee
-- medicos, empresas_proveedoras y visitas_agendadas (agenda de visitadores). No modifica ninguna tabla.

CREATE OR REPLACE FUNCTION public.prioridad_activa(p_medico_id uuid)
RETURNS TABLE (
  activa               boolean,
  lab_prioritario_id   uuid,
  visitas_completadas  int,
  visitas_limite       int
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_lab    uuid;
  v_fecha  timestamptz;
  v_count  int;
  v_limite int;
BEGIN
  SELECT m.lab_enrolador_id, m.lab_enrolador_fecha
    INTO v_lab, v_fecha
  FROM public.medicos m
  WHERE m.id = p_medico_id;

  -- Médico inexistente o sin enrolador → sin prioridad.
  IF v_lab IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, 0, 0;
    RETURN;
  END IF;

  -- Visitas CUMPLIDAS reales del lab enrolador desde el enrolamiento (checkout, no fecha agendada).
  SELECT count(*)::int INTO v_count
  FROM public.visitas_agendadas va
  WHERE va.medico_id      = p_medico_id
    AND va.empresa_id     = v_lab
    AND va.estado         = 'completada'
    AND va.checkout_fecha IS NOT NULL
    AND va.checkout_fecha >= v_fecha;

  -- Límite del lab enrolador; default global 8 si la columna es NULL (o el lab no existiera).
  SELECT COALESCE(ep.ventana_prioridad_visitas, 8) INTO v_limite
  FROM public.empresas_proveedoras ep
  WHERE ep.id = v_lab;
  v_limite := COALESCE(v_limite, 8);

  RETURN QUERY SELECT
    ( v_count < v_limite
      AND now() < v_fecha + INTERVAL '18 months' ),   -- techo anti-gaming (hardcodeado por ahora)
    v_lab,
    v_count,
    v_limite;
END;
$function$;

REVOKE ALL     ON FUNCTION public.prioridad_activa(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.prioridad_activa(uuid) TO authenticated;
