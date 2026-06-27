-- 162 · Ola 1 (fix) — la captura de vitales pasa de RLS-INSERT-policy a RPC SECURITY DEFINER.
-- Diagnóstico (PRUEBA 1/2, dry-run Ola 1): la RLS-INSERT-policy sv_insert_captura denegaba al staff
-- no-médico de forma intermitente AUNQUE los 3 predicados evaluaban true en la sesión real del caller
-- (auth.uid() correcto, rol correcto, pertenencia true). Causa: PostgREST evalúa el WITH CHECK
-- multi-expresión con 2 funciones STABLE SECURITY DEFINER bajo un plan genérico de prepared statement
-- que folda mal el resultado de esas funciones. El MISMO gate, ejecutado dentro de un RPC SECURITY
-- DEFINER, funciona 3/3 estable. No es bug de la lógica ni de las funciones: es la evaluación en el
-- WITH CHECK. Solución alineada al patrón del proyecto (verificar_receta_despacho, registrar_dispensacion,
-- revelar_items_receta): escritura multi-rol por RPC DEFINER con gate explícito adentro.

-- ============================================================
-- 1) RPC de captura. VOLATILE (hace INSERT). Gate explícito fail-closed. capturado_por/estado server-side.
--    paciente_en_clinica_de y tiene_rol se siguen usando, pero AHORA dentro del DEFINER (evaluación
--    normal en plpgsql, sin el plan de PostgREST sobre el WITH CHECK) → sin la flakiness.
-- ============================================================
CREATE OR REPLACE FUNCTION public.capturar_signo_vital(
  p_paciente_id             int,
  p_cita_id                 bigint  DEFAULT NULL,
  p_presion_arterial        text    DEFAULT NULL,
  p_frecuencia_cardiaca     int     DEFAULT NULL,
  p_frecuencia_respiratoria int     DEFAULT NULL,
  p_temperatura             numeric DEFAULT NULL,
  p_peso_kg                 numeric DEFAULT NULL,
  p_talla_cm                numeric DEFAULT NULL,
  p_saturacion_o2           int     DEFAULT NULL,
  p_glucosa                 int     DEFAULT NULL,
  p_notas                   text    DEFAULT NULL,
  p_medico_id               uuid    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_row public.signos_vitales%ROWTYPE;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  -- Gate explícito fail-closed (mismo que la ex-policy): rol de captura + pertenencia del paciente.
  IF NOT (
       private.tiene_rol(ARRAY['medico','asistente_medico','enfermeria'])
   AND private.paciente_en_clinica_de(p_paciente_id)
  ) THEN
    RAISE EXCEPTION 'No autorizado: rol o pertenencia';
  END IF;

  -- capturado_por = auth.uid() y estado='capturado' FORZADOS server-side (no params → no suplantables).
  -- imc lo calcula el trigger BEFORE INSERT trg_calcular_imc a partir de peso_kg/talla_cm.
  INSERT INTO public.signos_vitales (
    paciente_id, cita_id, medico_id, capturado_por, estado,
    presion_arterial, frecuencia_cardiaca, frecuencia_respiratoria, temperatura,
    peso_kg, talla_cm, saturacion_o2, glucosa, notas
  ) VALUES (
    p_paciente_id, p_cita_id, p_medico_id, v_uid, 'capturado',
    p_presion_arterial, p_frecuencia_cardiaca, p_frecuencia_respiratoria, p_temperatura,
    p_peso_kg, p_talla_cm, p_saturacion_o2, p_glucosa, p_notas
  )
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);
END;
$function$;
REVOKE ALL    ON FUNCTION public.capturar_signo_vital(int,bigint,text,int,int,numeric,numeric,numeric,int,int,text,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.capturar_signo_vital(int,bigint,text,int,int,numeric,numeric,numeric,int,int,text,uuid) TO authenticated, service_role;

-- ============================================================
-- 2) Retirar la captura por INSERT directo: la escritura solo pasa por el RPC DEFINER.
--    Tras el DROP, la única policy aplicable a INSERT es sv_superadmin_all (FOR ALL) → SOLO super_admin
--    puede INSERT directo (patrón estándar del proyecto); authenticated normal queda default-deny y
--    DEBE usar public.capturar_signo_vital. (sv_insert_medico ya había sido reemplazada por mig 160.)
-- ============================================================
DROP POLICY IF EXISTS sv_insert_captura ON public.signos_vitales;

-- NOTA Ola 3 (NO se construye aquí): sv_update_valida_medico (UPDATE) llama private.paciente_en_clinica_de
-- en USING/WITH CHECK. Si la validación de Ola 3 se hace por UPDATE directo, HEREDARÁ la misma flakiness
-- de plan de PostgREST. La validación probablemente deba ser también un RPC DEFINER (p.ej.
-- validar_signo_vital(p_id, ...) que setee estado='validado'/'corregido' + validado_por=auth.uid() +
-- validado_at=now() con gate de rol médico + pertenencia adentro). Se deja la policy inerte por ahora.
