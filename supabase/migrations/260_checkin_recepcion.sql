-- 260: check-in de recepción. El paciente llegó a recepción y espera al médico.
--   * Estado nuevo 'en_espera' (flujo: confirmada|agendada → en_espera → en_curso → completada).
--     NO se usa 'en_sala' (ese label ya lo usa el botón del médico que setea 'en_curso').
--   * Columna nueva citas.llegada_at timestamptz NULL (cuándo llegó).
--   * RPC NUEVA marcar_llegada_cita — NO se extiende actualizar_estado_cita (su whitelist de 7
--     estados con gate amplio le abriría a la secretaria cancelar/completar). Esta RPC solo hace
--     la transición de admisión, gateada al staff de recepción de la clínica de la cita.
-- Transición válida: SOLO desde 'confirmada'/'agendada'. Errcodes PT040-PT044.

-- Columna de llegada (idempotente).
ALTER TABLE public.citas ADD COLUMN IF NOT EXISTS llegada_at timestamptz;

CREATE OR REPLACE FUNCTION public.marcar_llegada_cita(p_cita_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid     uuid;
  v_estado  text;
  v_clinica uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicia sesión' USING ERRCODE = 'PT040';
  END IF;

  SELECT c.estado, c.clinica_id INTO v_estado, v_clinica
  FROM public.citas c WHERE c.id = p_cita_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cita inexistente' USING ERRCODE = 'PT043';
  END IF;

  -- Autorización (super_admin bypassa): rol de recepción PRIMERO, luego pertenencia a la clínica.
  IF NOT private.tiene_rol(ARRAY['super_admin']) THEN
    IF NOT private.tiene_rol(ARRAY['secretaria','admin_clinica','gerente','asistente_medico','enfermeria']) THEN
      RAISE EXCEPTION 'No autorizado: rol no habilitado para admisión' USING ERRCODE = 'PT042';
    END IF;
    -- NULL-safe (NOT EXISTS en vez de NOT IN): si el set de clínicas llegara a incluir un NULL,
    -- NOT IN evaluaría a NULL y el gate se pasaría por alto. clinicas_del_usuario() = SETOF uuid.
    IF v_clinica IS NULL
       OR NOT EXISTS (SELECT 1 FROM private.clinicas_del_usuario() AS x WHERE x = v_clinica) THEN
      RAISE EXCEPTION 'No autorizado: la cita no pertenece a tu clínica' USING ERRCODE = 'PT041';
    END IF;
  END IF;

  -- Transición válida SOLO desde confirmada/agendada (error explícito, no silencioso).
  IF v_estado NOT IN ('confirmada','agendada') THEN
    RAISE EXCEPTION 'Transición inválida: solo se marca llegada desde confirmada/agendada (estado actual: %)', v_estado
      USING ERRCODE = 'PT044';
  END IF;

  UPDATE public.citas
     SET estado = 'en_espera', llegada_at = now()
   WHERE id = p_cita_id;
END;
$function$;

REVOKE ALL     ON FUNCTION public.marcar_llegada_cita(bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.marcar_llegada_cita(bigint) FROM anon;
GRANT  EXECUTE ON FUNCTION public.marcar_llegada_cita(bigint) TO authenticated;
