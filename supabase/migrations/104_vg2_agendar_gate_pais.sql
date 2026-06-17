-- ============================================================
-- V-G2 · Visitas: AGENDAR gateado por plan de visitas activo + país (SEGURIDAD)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes red-first (P254–P260).
-- Recon write path: INSERT "Proveedor crea visitas de su empresa" (visitador); UPDATE
-- "Médico actualiza sus visitas" (médico aprueba/cancela vía estado) + "Proveedor cancela".
-- Triggers BEFORE INSERT: trg_limite_visitas (cuota, search_path=public — NO se toca),
-- set_default_estado_propuesta, set_fecha_limite_cancelacion.
--
-- Gate país = TRIGGER NUEVO BEFORE INSERT OR UPDATE OF medico_id (NO en todo UPDATE: el
-- UPDATE de estado del médico al aprobar/cancelar NO debe disparar el gate). DEFINER
-- search_path='' fail-closed. Reusa private.visitador_ve_medico (país del médico derivado
-- server-side de perfiles + plan activo/vigente de la empresa del visitador). NO param de país.
--
-- NOTA (dos sistemas de plan, pre-existente): la CUOTA (trg_limite_visitas_mes) usa
-- planes_asignaciones (genérico); el gate PAÍS usa planes_visitador_contratados (bespoke).
-- Una visita ahora requiere AMBOS. Reconciliarlos = deuda de monetización aparte.
--
-- NOTA (super_admin): el gate exige visitador_ve_medico → un INSERT por super_admin (sin
-- empresa proveedora/plan) quedaría BLOQ. No hay flujo de super_admin que cree visitas
-- (se crean en el portal del visitador). Si se necesitara, añadir exención explícita.
-- ============================================================

CREATE OR REPLACE FUNCTION private.gate_visita_pais()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF NOT COALESCE(private.visitador_ve_medico(NEW.medico_id), false) THEN
    RAISE EXCEPTION 'No autorizado: sin plan de visitas activo que cubra el país del médico'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION private.gate_visita_pais() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_gate_visita_pais ON public.visitas_agendadas;
CREATE TRIGGER trg_gate_visita_pais
  BEFORE INSERT OR UPDATE OF medico_id ON public.visitas_agendadas
  FOR EACH ROW EXECUTE FUNCTION private.gate_visita_pais();
