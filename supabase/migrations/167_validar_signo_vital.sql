-- 167 · Ola 3 — validar_signo_vital: el médico de la cita valida una toma (estado capturado→validado).
-- Patrón DEFINER idéntico a capturar_signo_vital (NO UPDATE-directo+RLS, que es la trampa de plan de
-- PostgREST de Ola 1). signos_vitales es APPEND-ONLY: la validación NO toca columnas de medida; solo
-- estado/validado_por/validado_at. La corrección (Ola futura) será fila nueva estado='corregido', no edición.

-- ============================================================
-- 1) RPC de validación. Gate fail-closed: solo el MÉDICO de la cita. Transición estricta capturado→validado.
-- ============================================================
CREATE OR REPLACE FUNCTION public.validar_signo_vital(p_signo_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid    uuid;
  v_cita   bigint;
  v_estado text;
  v_medico uuid;
  v_row    public.signos_vitales%ROWTYPE;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  -- Localizar la toma.
  SELECT cita_id, estado INTO v_cita, v_estado
  FROM public.signos_vitales WHERE id = p_signo_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Toma inexistente'; END IF;

  -- Una toma walk-in (sin cita) no tiene médico que la gatee.
  IF v_cita IS NULL THEN RAISE EXCEPTION 'Toma sin cita: no validable'; END IF;

  -- Médico responsable = el de la cita.
  SELECT medico_id INTO v_medico FROM public.citas WHERE id = v_cita;
  IF v_medico IS NULL THEN RAISE EXCEPTION 'La cita no tiene médico asignado'; END IF;

  -- Gate fail-closed: rol médico Y ser el médico responsable de la cita.
  IF NOT (private.tiene_rol(ARRAY['medico']) AND v_uid = v_medico) THEN
    RAISE EXCEPTION 'No autorizado: solo el médico de la cita valida';
  END IF;

  -- Transición estricta: solo desde 'capturado'.
  IF v_estado <> 'capturado' THEN
    RAISE EXCEPTION 'Solo se valida una toma en estado capturado';
  END IF;

  -- UPDATE acotado con guard de carrera (AND estado='capturado'). NO toca columnas de medida (append-only):
  -- solo estado/validado_por/validado_at.
  UPDATE public.signos_vitales
     SET estado = 'validado', validado_por = v_uid, validado_at = now()
   WHERE id = p_signo_id AND estado = 'capturado'
   RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'No se pudo validar (estado cambió)'; END IF;

  RETURN to_jsonb(v_row);
END;
$function$;
REVOKE ALL    ON FUNCTION public.validar_signo_vital(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.validar_signo_vital(bigint) TO authenticated;

-- ============================================================
-- 2) Retirar la superficie de UPDATE directo: la validación pasa a ser SOLO por la RPC DEFINER (mismo
--    criterio con que Ola 1 dropeó sv_insert_captura). Tras el drop NO queda policy de UPDATE para
--    authenticated → no puede UPDATE directo aunque tenga el grant de tabla (RLS deniega). super_admin
--    conserva UPDATE vía sv_superadmin_all (FOR ALL). SELECT y captura por RPC: sin cambios.
-- ============================================================
DROP POLICY IF EXISTS sv_update_valida_medico ON public.signos_vitales;

-- DEUDA ANOTADA (NO se toca aquí): los grants de tabla anon/authenticated (UPDATE/DELETE/INSERT/TRUNCATE)
-- son ruido del REVOKE masivo pendiente; el acceso real lo restringe la RLS (sin policy de INSERT/UPDATE
-- para authenticated tras Ola 1+3). Limpieza de esos grants = fuera de alcance de esta migración.
