-- ============================================================
-- 143 · Cerrar gap de LECTURA del preview QR — espejo de 141 en verificar_receta_despacho (RPC VIVO)
-- ------------------------------------------------------------
-- 141 confinó por sucursal listar_recetas_entrantes / detalle_receta_entrante / registrar_dispensacion(_dirigida),
-- pero NO verificar_receta_despacho (el preview del QR walk-in) → un confinable, al escanear, veía en el preview
-- los ítems de OTRAS sucursales de su MISMA empresa (lectura; cross-empresa ya estaba cerrado; despacho ya gateado
-- por 141). Este espejo ANDea el MISMO término sobre el filtro de empresa EXACTO ya presente, reusando el helper.
--   admin/gerente_farmacia/finanzas/pagador (EXENTOS) → siguen viendo TODO el preview de su empresa (rama exento
--   de sucursal_visible gana; su sucursal_id NO confina). Confinable → solo ítems de su sucursal. Grandfather
--   (mi_sucursal() NULL) → todo (no-regresión). 0 confinados en prod → grandfather-inerte al apply.
-- Gate cross-empresa (f.empresa_id = mi_empresa_proveedor()) + recetas_dispensar INTACTOS; el término sucursal es
-- ADITIVO conjuntivo. DEFINER + search_path='' (igual que la versión viva). Única selección de ítems (v_items).
-- ============================================================
CREATE OR REPLACE FUNCTION public.verificar_receta_despacho(p_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_ra RECORD; v_receta_id bigint; v_pac_nombre text; v_items jsonb;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN RAISE EXCEPTION 'Token requerido'; END IF;

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

  RETURN jsonb_build_object(
    'receta_id', v_receta_id,
    'dispatch_token', v_ra.dispatch_token,
    'estado_dispensacion', v_ra.estado_dispensacion,
    'paciente_nombre', v_pac_nombre,   -- a lo sumo; sin teléfono/dirección
    'items', v_items                   -- solo los del actor (empresa + sucursal)
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.verificar_receta_despacho(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.verificar_receta_despacho(text) TO authenticated, service_role;
