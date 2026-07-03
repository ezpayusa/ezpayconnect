-- ============================================================================
-- Migración 213: NUEVAS RPCs checkin_visita / checkout_visita — ownership + estado
--                + máquina de estados server-side
-- ============================================================================
-- GAP QUE CIERRA:
-- checkin/checkout de visitas (checkinVisita/checkoutVisita en useVisitasAgendadas.ts) hoy son
-- UPDATEs DIRECTOS a visitas_agendadas sin validación server-side:
--   · Ownership: NINGUNA — cualquier authenticated podía marcar checkin/checkout de cualquier visita.
--   · Estado / máquina de estados: NINGUNA — no se valida estado previo, ni fecha, ni que el checkin
--     preceda al checkout, ni doble checkin/checkout (el upsert:true del upload agravaba esto).
--   · Además checkinVisita hacía getPublicUrl sobre evidencias-visitas → ROTO desde mig 212 (bucket
--     privado). Estas RPCs guardan el PATH en checkin_evidencia_url (no una URL pública); el front lo
--     resuelve con createSignedUrl (openSignedUrl) en la pieza siguiente.
--
-- Molde: registrar_evidencia_entrega (mig 152) — la RPC recibe un PATH YA subido (NO sube ella el
-- archivo; el front sigue subiendo directo, con el INSERT ya acotado por mig 209) y valida ownership +
-- path scoping. A DIFERENCIA del molde, acá SÍ validamos la máquina de estados (decisión explícita,
-- más estricto que el flujo del repartidor).
--
-- Ownership: el visitador dueño (cuenta_proveedor_id = auth.uid()) O super_admin, igual que
-- cancelar_visita (mig 211) / administrar_visita (mig 210). El super_admin no hace check-in de
-- campo por rutina, pero se admite como excepción para soporte/corrección de un registro de campo.
-- ============================================================================


-- ============================================================================
-- 1) checkin_visita — registra el check-in (con evidencia y geo opcionales)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.checkin_visita(
  p_visita_id      uuid,
  p_evidencia_path text    DEFAULT NULL,
  p_lat            numeric DEFAULT NULL,
  p_lng            numeric DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_visita RECORD;
BEGIN
  -- a) Cargar la visita.
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  -- b) Ownership: el visitador dueño o super_admin (soporte/corrección de un registro de campo).
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR COALESCE(v_visita.cuenta_proveedor_id = auth.uid(), false)
  ) THEN
    RAISE EXCEPTION 'No autorizado para hacer check-in de esta visita';
  END IF;

  -- c) Estado valido para check-in.
  IF v_visita.estado NOT IN ('confirmada', 'aprobada') THEN
    RETURN jsonb_build_object('error', 'Esta visita no está en un estado válido para check-in');
  END IF;

  -- d) Solo el dia de la visita (mismo criterio que la UI).
  IF v_visita.fecha_visita <> CURRENT_DATE THEN
    RETURN jsonb_build_object('error', 'El check-in solo se puede hacer el día de la visita');
  END IF;

  -- e) Evitar doble check-in / upsert accidental.
  IF v_visita.checkin_fecha IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Ya se registró el check-in de esta visita');
  END IF;

  -- f) Si hay evidencia, el path debe pertenecer a ESTA visita (mismo scoping que mig 209/212:
  --    segmento 1 = empresa_id, segmento 2 = visita_id via private.safe_uuid).
  IF p_evidencia_path IS NOT NULL THEN
    IF NOT (
         split_part(p_evidencia_path, '/', 1) = v_visita.empresa_id::text
         AND private.safe_uuid(split_part(p_evidencia_path, '/', 2)) = v_visita.id
    ) THEN
      RETURN jsonb_build_object('error', 'La evidencia no corresponde a esta visita');
    END IF;
  END IF;

  -- g) Registrar el check-in. checkin_evidencia_url guarda el PATH (no URL publica; el front lo
  --    resuelve con signed URL). Normaliza estado a 'confirmada' (desde 'aprobada' si aplicaba).
  UPDATE public.visitas_agendadas
  SET checkin_fecha         = NOW(),
      checkin_lat           = p_lat,
      checkin_lng           = p_lng,
      checkin_evidencia_url = p_evidencia_path,
      estado                = 'confirmada'
  WHERE id = p_visita_id;

  RETURN jsonb_build_object('success', true, 'estado', 'confirmada');
END;
$function$;

REVOKE ALL     ON FUNCTION public.checkin_visita(uuid, text, numeric, numeric) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.checkin_visita(uuid, text, numeric, numeric) TO authenticated, service_role;


-- ============================================================================
-- 2) checkout_visita — cierra la visita (requiere check-in previo)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.checkout_visita(
  p_visita_id uuid,
  p_notas     text DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_visita RECORD;
BEGIN
  -- a) Cargar la visita.
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  -- b) Ownership: el visitador dueño o super_admin (mismo criterio que checkin).
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR COALESCE(v_visita.cuenta_proveedor_id = auth.uid(), false)
  ) THEN
    RAISE EXCEPTION 'No autorizado para hacer check-out de esta visita';
  END IF;

  -- c) Estado valido para check-out.
  IF v_visita.estado NOT IN ('confirmada', 'aprobada') THEN
    RETURN jsonb_build_object('error', 'Esta visita no está en un estado válido para check-out');
  END IF;

  -- d) Debe existir check-in previo.
  IF v_visita.checkin_fecha IS NULL THEN
    RETURN jsonb_build_object('error', 'No se puede hacer check-out sin haber hecho check-in primero');
  END IF;

  -- e) Evitar doble check-out.
  IF v_visita.checkout_fecha IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Ya se registró el check-out de esta visita');
  END IF;

  -- f) Cerrar la visita.
  UPDATE public.visitas_agendadas
  SET checkout_fecha    = NOW(),
      checkout_notas    = p_notas,
      visita_concretada = true,
      estado            = 'completada'
  WHERE id = p_visita_id;

  RETURN jsonb_build_object('success', true, 'estado', 'completada');
END;
$function$;

REVOKE ALL     ON FUNCTION public.checkout_visita(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.checkout_visita(uuid, text) TO authenticated, service_role;
