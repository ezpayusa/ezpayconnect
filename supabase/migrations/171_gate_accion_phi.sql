-- 171 · gate_accion_phi — gate server-side para acciones sobre PHI (lo invoca un edge con el JWT del caller).
-- Valida en orden: (1) caller autenticado, (2) staff (medico/asistente) + pertenencia a la clínica del paciente,
-- (3) consentimiento del permiso con regla GRANDFATHER (bloquea SOLO si hay estado vigente concedido=false;
-- sin fila o concedido=true = permite). Distingue los 3 motivos por el mensaje de RAISE para que el edge
-- mapee a 403 con el texto correcto: 'no_auth' | 'no_pertenencia' | 'consentimiento_revocado'.
-- NO depende del RAISE de estado_consentimiento_paciente: valida pertenencia él mismo y consulta consentimientos
-- directo (la fila vigente = ORDER BY created_at DESC, id DESC LIMIT 1, mismo criterio que mig 170).
CREATE OR REPLACE FUNCTION public.gate_accion_phi(p_paciente_id bigint, p_permiso_codigo text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid       uuid;
  v_concedido boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;

  -- Gate pertenencia (staff + clínica del paciente). NO depende del consentimiento.
  IF NOT ( private.tiene_rol(ARRAY['medico','asistente_medico'])
       AND private.paciente_en_clinica_de(p_paciente_id::integer) )
  THEN RAISE EXCEPTION 'no_pertenencia'; END IF;

  -- Gate consentimiento grandfather: fila VIGENTE del permiso; bloquear solo si existe y concedido=false.
  SELECT c.concedido INTO v_concedido
  FROM public.consentimientos c
  WHERE c.paciente_id = p_paciente_id
    AND c.permiso_codigo = p_permiso_codigo
  ORDER BY c.created_at DESC, c.id DESC
  LIMIT 1;

  IF v_concedido IS NOT NULL AND v_concedido = false THEN
    RAISE EXCEPTION 'consentimiento_revocado';
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$function$;
REVOKE ALL     ON FUNCTION public.gate_accion_phi(bigint, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.gate_accion_phi(bigint, text) TO authenticated;
