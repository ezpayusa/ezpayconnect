-- ============================================================================
-- Migración 211: NUEVA RPC cancelar_visita — ownership + ventana + máquina de estados
-- ============================================================================
-- GAP QUE CIERRA:
-- La cancelación de visitas (cancelarVisita en useVisitasAgendadas.ts) hoy es un UPDATE
-- DIRECTO a visitas_agendadas SET estado='cancelada', sin validación server-side:
--   · Ownership: NINGUNA — cualquier authenticated podía cancelar cualquier visita.
--   · Estado: NINGUNA — el UPDATE pasa aunque la visita esté completada/cancelada/rechazada/
--     no_asistio; el front lo oculta con puedeCancelar, pero eso es solo un botón (UX).
--   · Ventana: solo el front aplica la regla de fecha_limite_cancelacion (client-side).
-- Esta RPC centraliza y valida las 3 cosas server-side (mismo patrón que administrar_visita,
-- migs 075+210). El front se reconecta en una pieza posterior.
--
-- NOTA (triggers): el único trigger BEFORE UPDATE de la tabla, trg_gate_visita_pais, está
-- acotado a UPDATE OF medico_id → un UPDATE de solo `estado` (el de esta RPC) NO lo dispara.
-- Ningún trigger reacciona a estado='cancelada' (no libera ni audita nada acá): la bolsa de
-- visitas se libera sola porque private.pvc_usadas no cuenta las canceladas.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cancelar_visita(p_visita_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_visita RECORD;
BEGIN
  -- 1) Cargar la visita. Inexistente → error en el jsonb (no RAISE), como administrar_visita.
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  -- 2) Ownership: super_admin o el visitador dueño de la visita. COALESCE evita el trivaluado
  --    (cuenta_proveedor_id NULL ⇒ 'false OR NULL' = NULL ⇒ RAISE saltado = fail-open).
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR COALESCE(v_visita.cuenta_proveedor_id = auth.uid(), false)
  ) THEN
    RAISE EXCEPTION 'No autorizado para cancelar esta visita';
  END IF;

  -- 3) Máquina de estados (misma regla de ventana que el front):
  IF v_visita.estado = 'propuesta' THEN
    NULL;  -- propuesta: se puede cancelar libremente, sin chequeo de ventana.
  ELSIF v_visita.estado IN ('confirmada', 'aprobada', 'pendiente') THEN
    -- Ventana: el día límite todavía se puede cancelar (<=). Sin límite fijado ⇒ permitido.
    IF NOT (v_visita.fecha_limite_cancelacion IS NULL
            OR CURRENT_DATE <= v_visita.fecha_limite_cancelacion) THEN
      RETURN jsonb_build_object('error', 'Ya pasó la fecha límite para cancelar esta visita');
    END IF;
  ELSE
    -- completada, cancelada, rechazada, no_asistio, o cualquier estado no contemplado.
    RETURN jsonb_build_object('error', 'Esta visita no se puede cancelar en su estado actual');
  END IF;

  -- 4) Aplicar la cancelación.
  UPDATE public.visitas_agendadas SET estado = 'cancelada' WHERE id = p_visita_id;
  RETURN jsonb_build_object('success', true, 'estado', 'cancelada');
END;
$function$;

REVOKE ALL     ON FUNCTION public.cancelar_visita(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cancelar_visita(uuid) TO authenticated, service_role;
