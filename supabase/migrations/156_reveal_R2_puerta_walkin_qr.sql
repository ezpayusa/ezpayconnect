-- 156 · Ola R2 — enciende la PUERTA 2 (walk-in QR) del gate reveal-registrado (patrón de 2 pasos).
-- verificar_receta_despacho pasa a leer el flag 'walkin_qr':
--   · flag activo=true  → devuelve CABECERA: { receta_id, dispatch_token, estado_dispensacion, paciente_nombre,
--     n_pendientes }. SIN array 'items', SIN ningún campo clínico. n_pendientes = count de ítems dispensado=false
--     dentro del MISMO confinamiento (empresa+sucursal_visible). El med se obtiene en el PASO 2 vía
--     revelar_items_receta(receta_id,'walkin_qr') que registra el reveal (mig 154, bloqueante).
--   · flag false/ausente → comportamiento VIEJO EXACTO (jsonb con items[] completo + flag dispensado por ítem).
--     FAIL-SAFE: el walk-in viejo en prod sigue funcionando; backout sin redeploy.
-- Intacto: validación del token (existe + no expirado), confinamiento empresa+sucursal_visible, el RAISE no-leak.
-- NO se activa el flag acá (queda en false). El UPDATE a true es un paso MANUAL posterior, tras mergear el front (Opción A).

CREATE OR REPLACE FUNCTION public.verificar_receta_despacho(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_ra RECORD; v_receta_id bigint; v_pac_nombre text; v_items jsonb; v_gate boolean; v_n_pend integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN RAISE EXCEPTION 'Token requerido'; END IF;

  -- R2: gate de la puerta walk-in QR. Fail-safe: ausente/false → comportamiento viejo (con items[]).
  v_gate := COALESCE((SELECT activo FROM private.reveal_gate_flags WHERE puerta='walkin_qr'), false);

  SELECT ra.id, ra.receta_base_id, ra.estado_dispensacion, ra.dispatch_token
    INTO v_ra
  FROM public.recetas_avanzadas ra
  WHERE ra.dispatch_token = p_token
    AND COALESCE(ra.dispatch_token_expira_at > now(), false);   -- token NO expirado
  IF NOT FOUND THEN RAISE EXCEPTION 'Token inválido o expirado'; END IF;

  v_receta_id := v_ra.receta_base_id;

  SELECT p.nombre INTO v_pac_nombre
  FROM public.recetas r JOIN public.pacientes p ON p.id = r.paciente_id
  WHERE r.id = v_receta_id;

  -- Ítems SOLO de la(s) farmacia(s) de la empresa del actor (cross-empresa) Y de su sucursal (3.4: confinamiento).
  SELECT jsonb_agg(jsonb_build_object(
           'item_id', ri.id,
           'nombre_medicamento', ri.nombre_medicamento,
           'dosis', ri.dosis,
           'frecuencia', ri.frecuencia,
           'cantidad', ri.cantidad,
           'instrucciones', ri.instrucciones,
           'dispensado', ri.dispensado))
    INTO v_items
  FROM public.receta_items ri
  JOIN public.farmacias f ON f.id = ri.farmacia_id
  WHERE ri.receta_id = v_receta_id
    AND COALESCE(f.empresa_id = v_emp, false)
    AND COALESCE(private.sucursal_visible(ri.farmacia_id), false);   -- 143: confinamiento por sucursal (espejo 141)

  IF v_items IS NULL THEN
    RAISE EXCEPTION 'No autorizado: la receta no tiene ítems asignados a tu farmacia';
  END IF;

  -- R2: con el gate activo, devolver CABECERA (sin clínico). n_pendientes deriva del MISMO query confinado.
  IF v_gate THEN
    v_n_pend := (SELECT count(*) FROM jsonb_array_elements(v_items) e WHERE (e->>'dispensado')::boolean = false);
    RETURN jsonb_build_object(
      'receta_id', v_receta_id,
      'dispatch_token', v_ra.dispatch_token,
      'estado_dispensacion', v_ra.estado_dispensacion,
      'paciente_nombre', v_pac_nombre,
      'n_pendientes', v_n_pend);
  END IF;

  RETURN jsonb_build_object(
    'receta_id', v_receta_id,
    'dispatch_token', v_ra.dispatch_token,
    'estado_dispensacion', v_ra.estado_dispensacion,
    'paciente_nombre', v_pac_nombre,   -- a lo sumo; sin teléfono/dirección
    'items', v_items                   -- solo los del actor (empresa + sucursal)
  );
END;
$function$;

-- NO se activa el flag walkin_qr acá: queda en false (Opción A: front primero, activación manual posterior).
