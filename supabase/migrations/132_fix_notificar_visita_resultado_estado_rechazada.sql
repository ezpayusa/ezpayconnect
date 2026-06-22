-- ============================================================
-- Fix · notificar_visita_resultado — alinear rama de rechazo al estado REAL 'rechazada'. SEGURIDAD.
-- ------------------------------------------------------------
-- mig 131 ramificaba el rechazo sobre 'cancelada', pero useVisitasAgendadas.rechazar() deja estado='rechazada'
-- (aprobar→'confirmada'). Con 'rechazada' el RPC caía al guard de estado-notificable y RETORNABA (skip) → la
-- notif de rechazo se perdía. El probe P418 sembró 'cancelada' (falso-verde, nunca ejerció la rama real).
-- 'cancelada' es cancelación (cancelarVisita, NO notifica) → fuera de scope; el guard la salta a propósito.
--
-- 132 SOLO toca la rama de estado + re-declara la envoltura (l.50: CREATE OR REPLACE NO preserva DEFINER/sp'').
-- Gate admin de empresa, GATE RELACIÓN (cuenta∈empresa), firma uuid-only e in-app-only quedan INTACTOS.
-- Rama fail-closed (ELSIF explícito, no ELSE): un estado nuevo agregado al guard no caería en 'rechazada'.
-- DORMANT (callers #5/#6 viven en la rama de hooks sin mergear) → apply = cero runtime.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notificar_visita_resultado(p_visita_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; v_titulo text; v_msg text; v_tipo text;
BEGIN
  SELECT empresa_id, cuenta_proveedor_id, estado INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller = admin/editor de la empresa de la visita. COALESCE fail-closed.
  IF NOT COALESCE((SELECT true FROM public.cuentas_proveedor WHERE id = auth.uid() AND empresa_id = v.empresa_id
                   AND activo = true AND rol_en_empresa IN ('admin','editor') LIMIT 1), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  IF v.estado NOT IN ('confirmada','rechazada') THEN RETURN; END IF;  -- estado notificable (resultado real); 'cancelada'/etc → skip
  -- GATE RELACIÓN: cuenta_proveedor_id es caller-libre en el INSERT de visitas (l.52) → exigir que pertenezca
  -- a la empresa de la visita; si no → SKIP sin abortar (espejo evt6/P394).
  IF v.cuenta_proveedor_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.cuentas_proveedor WHERE id = v.cuenta_proveedor_id AND empresa_id = v.empresa_id AND activo = true) THEN
    RETURN; END IF;
  -- rama fail-closed por estado del ref (no ELSE genérico)
  IF v.estado = 'confirmada' THEN
    v_tipo := 'visita_aprobada';  v_titulo := 'Visita aprobada';  v_msg := 'Tu visita propuesta fue confirmada.';
  ELSIF v.estado = 'rechazada' THEN
    v_tipo := 'visita_rechazada'; v_titulo := 'Visita rechazada'; v_msg := 'Tu visita propuesta no fue aprobada.';
  END IF;
  INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.cuenta_proveedor_id, v_tipo, v_titulo, v_msg, '/proveedor/visitador');
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_visita_resultado(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_visita_resultado(uuid) TO authenticated;
