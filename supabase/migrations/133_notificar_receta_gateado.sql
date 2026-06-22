-- ============================================================
-- Fix push transaccional · EVENTO RECETA — notificar_receta gateado (in-app + push). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P419–P423. RPC nuevo → DORMANT hasta su hook (useRecetas:95).
-- Reemplaza el caller genérico notificar_paciente (titulo/mensaje crudos del cliente) por un RPC firma
-- bigint-only: cero vector de contenido del caller (l.56). Tras migrar este (último caller de citas/examen ya
-- cubiertos por el batch evt1-hook), notificar_paciente queda con 0 callers → REVOKE EXECUTE en CIERRE FINAL.
--
-- Gate = relación médico↔paciente derivada de auth.uid (private.medico_atiende_paciente, el MISMO helper que ya
-- gatea notificar_paciente) → evita el id-space frágil de recetas.medico_id (sin FK). Recipient derivado del ref.
-- PHI: cuerpo GENÉRICO (sin medicamento/dosis/diagnóstico); detalle tras accion_url (precedente evt4/130).
-- recetas.paciente_id NOT NULL + FK→pacientes → guard recipient-huérfano innecesario (l.49).
-- ============================================================

ALTER TABLE public.recetas ADD COLUMN IF NOT EXISTS notificado boolean NOT NULL DEFAULT false;  -- idempotencia (metadata-only)

CREATE OR REPLACE FUNCTION public.notificar_receta(p_receta_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_pac bigint; v_estado text; v_count int; v_nid integer;
BEGIN
  -- (1) cargar
  SELECT paciente_id, estado INTO v_pac, v_estado FROM public.recetas WHERE id = p_receta_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receta no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- (2) GATE: médico que atiende al paciente (derivado de auth.uid; evita id-space de medico_id) + super_admin. fail-closed.
  IF NOT (COALESCE(private.medico_atiende_paciente(v_pac), false) OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)) THEN
    RAISE EXCEPTION 'No autorizado para notificar esta receta' USING ERRCODE = 'PT002';
  END IF;
  -- (3) CLAIM idempotencia (tras el gate; receta no re-entra → sin trigger-reset). Predicado booleano (col NOT NULL).
  UPDATE public.recetas SET notificado = true WHERE id = p_receta_id AND NOT notificado;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN RETURN; END IF;   -- ya notificado (retry/doble) → no-op
  -- (4) recipient = paciente del ref; contenido GENÉRICO (sin medicamento/dosis/diagnóstico)
  INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
    VALUES (v_pac, 'receta', 'Nueva receta', 'Tu médico te emitió una nueva receta.', '/paciente/recetas', false)
    RETURNING id INTO v_nid;
  -- (5) push (in-app + push; el edge re-deriva de la fila → cuerpo genérico al lock screen)
  PERFORM private.push_notificar('notificaciones_pacientes', v_nid::text);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_receta(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_receta(bigint) TO authenticated;   -- lo llama el médico; gate interno
