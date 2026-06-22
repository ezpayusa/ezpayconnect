-- ============================================================
-- Hardening INSERT (opción-2) · chat_mensajes — relación paciente↔médico + remitente. SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ POLICY VIVA (no dormant): el ALTER cambia prod de inmediato (l.20). Espejo del hardening de visitas (134).
-- El WITH CHECK actual gatea paciente_id (self) pero NO medico_id (col caller-libre) ni remitente → un paciente
-- podía (a) crear un mensaje atribuido a CUALQUIER médico (la opción-1 notificar_chat ya skipea el NOTIFY a médico
-- ajeno, pero la FILA se creaba) y (b) spoofear remitente='medico' en su propio hilo. Esto lo cierra el INSERT.
--
-- Términos CONJUNTIVOS (AND sobre el self-check EXACTO, l.33):
--   remitente='paciente' (el insert legítimo SIEMPRE lo usa — hardcoded en useWebAppChat; cierra el spoof).
--   medico_id IS NULL OR private.paciente_relacion_medico(paciente_id, medico_id) (grandfather NULL l.45: sin
--   médico resuelto el hook deja NULL → legítimo, NULL no targetea a nadie ≠ fail-open).
-- Helper DEFINER OBLIGATORIO (l.12): el EXISTS cruza a citas/pacientes; bajo la RLS del caller daría falso-negativo
-- y rompería el POSITIVO de no-regresión. Relación byte-a-byte con notificar_chat (evt6, mig 126). id-space uuid
-- consistente (chat.medico_id ∈ mismo espacio que citas.medico_id / pacientes.medico_*). NO toca el lado médico (dormant).
-- Mantiene TO public (anon ya inerte por el self-check; cambiar el TO es scope no pedido).
-- ============================================================

CREATE OR REPLACE FUNCTION private.paciente_relacion_medico(p_paciente_id integer, p_medico_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.citas c WHERE c.paciente_id = p_paciente_id AND c.medico_id = p_medico_id)
      OR EXISTS (SELECT 1 FROM public.pacientes p WHERE p.id = p_paciente_id AND (p.medico_primario_id = p_medico_id OR p.medico_id = p_medico_id));
$function$;
REVOKE EXECUTE ON FUNCTION private.paciente_relacion_medico(integer, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.paciente_relacion_medico(integer, uuid) TO authenticated;

-- Reproduce el self-check EXACTO y SOLO AND-ea los términos nuevos.
ALTER POLICY "Paciente envía mensajes" ON public.chat_mensajes
  WITH CHECK (
    (paciente_id IN ( SELECT pacientes.id
       FROM pacientes
      WHERE (pacientes.auth_user_id = auth.uid())))
    AND remitente = 'paciente'
    AND (medico_id IS NULL OR private.paciente_relacion_medico(paciente_id, medico_id))
  );
