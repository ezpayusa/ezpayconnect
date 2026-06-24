-- ============================================================
-- 141 · Spine sucursales 3.4 — Buzón confinado por sucursal (RPCs VIVOS, NO dormant)
-- ------------------------------------------------------------
-- ANDea COALESCE(private.sucursal_visible(ri.farmacia_id), false) CONJUNTIVO sobre el filtro de empresa
-- EXACTO existente (no relaja nada) en los 4 RPCs del buzón/despacho. REUSA el helper de mig 114:
--   sucursal_visible = EXENTO {admin,gerente_farmacia,finanzas,pagador} OR mi_sucursal() IS NULL (grandfather)
--                      OR p_farmacia_id = mi_sucursal().
-- → admin/gerente ven y despachan TODO el buzón de la empresa; confinable asignado a X solo lo ruteado a X;
--   grandfather (NULL) todo (no-regresión). Con 0 confinados en prod = GRANDFATHER-INERTE al apply.
--
-- CALLER REAL (precisión 2): sucursal_visible → private.mi_sucursal() = cuentas_proveedor.sucursal_id de
--   auth.uid(). En un DEFINER, auth.uid() es el JWT del CALLER (no cambia con el rol DEFINER) → confina por
--   la sucursal de QUIEN despacha. Igual patrón que el resto de RPCs gateados por auth.uid().
-- GATE ANTES DEL EFECTO (precisión 3): en los 2 RPCs de despacho el término va en el WHERE del FOR loop →
--   un ítem fuera de la sucursal del caller NUNCA entra al loop → JAMÁS se UPDATE/INSERT (dispensado intacto);
--   si 0 ítems pasan → RAISE existente, sin efecto. El rechazo precede a cualquier mutación.
-- Preserva firma + gates (empresa + recetas_dispensar); el término sucursal entra sin tocar lo demás.
-- + Columna informativa: listar_recetas_entrantes agrega sucursal_nombre/direccion por ítem (admin-central
--   ve a qué sucursal está ruteada cada receta). No cambia el gate.
-- ============================================================

-- 1) listar_recetas_entrantes — término en AMBOS lugares (items_pendientes + EXISTS exterior) + columna sucursal.
CREATE OR REPLACE FUNCTION public.listar_recetas_entrantes()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_out jsonb;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;

  SELECT COALESCE(jsonb_agg(rec ORDER BY (rec->>'created_at') DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT jsonb_build_object(
             'receta_id', r.id,
             'created_at', r.created_at,
             'estado', r.estado,
             'paciente_nombre', btrim(COALESCE(p.nombre,'') || ' ' || COALESCE(p.apellido,'')),
             'medico_nombre', COALESCE(pm.nombre_completo, pm.nombre),
             'tiene_token', (ra.id IS NOT NULL),
             'items_pendientes', (
                SELECT jsonb_agg(jsonb_build_object(
                         'item_id', ri.id,
                         'nombre_medicamento', ri.nombre_medicamento,
                         'dosis', ri.dosis,
                         'frecuencia', ri.frecuencia,
                         'cantidad', ri.cantidad,
                         'instrucciones', ri.instrucciones,
                         'sucursal_nombre', f.nombre,            -- informativo (admin-central)
                         'sucursal_direccion', f.direccion))
                FROM public.receta_items ri
                JOIN public.farmacias f ON f.id = ri.farmacia_id
                WHERE ri.receta_id = r.id
                  AND COALESCE(f.empresa_id = v_emp, false)
                  AND ri.dispensado = false
                  AND COALESCE(private.sucursal_visible(ri.farmacia_id), false))   -- 3.4: confinamiento por sucursal
           ) AS rec
    FROM public.recetas r
    JOIN public.pacientes p ON p.id = r.paciente_id
    LEFT JOIN public.perfiles pm ON pm.id = r.medico_id
    LEFT JOIN public.recetas_avanzadas ra ON ra.receta_base_id = r.id
    WHERE EXISTS (
      SELECT 1 FROM public.receta_items ri2
      JOIN public.farmacias f2 ON f2.id = ri2.farmacia_id
      WHERE ri2.receta_id = r.id
        AND COALESCE(f2.empresa_id = v_emp, false)
        AND ri2.dispensado = false
        AND COALESCE(private.sucursal_visible(ri2.farmacia_id), false))            -- 3.4: idem en el EXISTS exterior
  ) s;

  RETURN v_out;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.listar_recetas_entrantes() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_recetas_entrantes() TO authenticated, service_role;

-- 2) detalle_receta_entrante — mismo término (defensa; 0 callers vivos). Read-only: confina qué ítems ve.
CREATE OR REPLACE FUNCTION public.detalle_receta_entrante(p_receta_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_items jsonb; v_pac text; v_med text; v_estado text; v_created timestamptz; v_token boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;

  SELECT jsonb_agg(jsonb_build_object(
           'item_id', ri.id,
           'nombre_medicamento', ri.nombre_medicamento,
           'dosis', ri.dosis,
           'frecuencia', ri.frecuencia,
           'cantidad', ri.cantidad,
           'instrucciones', ri.instrucciones,
           'dispensado', ri.dispensado) ORDER BY ri.id)
    INTO v_items
  FROM public.receta_items ri
  JOIN public.farmacias f ON f.id = ri.farmacia_id
  WHERE ri.receta_id = p_receta_id
    AND COALESCE(f.empresa_id = v_emp, false)
    AND COALESCE(private.sucursal_visible(ri.farmacia_id), false);                 -- 3.4: confinamiento por sucursal

  IF v_items IS NULL THEN
    RAISE EXCEPTION 'No autorizado: la receta no tiene ítems asignados a tu farmacia';
  END IF;

  SELECT btrim(COALESCE(p.nombre,'') || ' ' || COALESCE(p.apellido,'')),
         COALESCE(pm.nombre_completo, pm.nombre), r.estado, r.created_at,
         EXISTS (SELECT 1 FROM public.recetas_avanzadas ra WHERE ra.receta_base_id = r.id)
    INTO v_pac, v_med, v_estado, v_created, v_token
  FROM public.recetas r
  JOIN public.pacientes p ON p.id = r.paciente_id
  LEFT JOIN public.perfiles pm ON pm.id = r.medico_id
  WHERE r.id = p_receta_id;

  RETURN jsonb_build_object(
    'receta_id', p_receta_id, 'created_at', v_created, 'estado', v_estado,
    'paciente_nombre', v_pac, 'medico_nombre', v_med,
    'tiene_token', v_token,
    'items', v_items);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.detalle_receta_entrante(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.detalle_receta_entrante(bigint) TO authenticated, service_role;

-- 3) registrar_dispensacion_dirigida — término en el WHERE del FOR loop (gate ANTES del efecto).
CREATE OR REPLACE FUNCTION public.registrar_dispensacion_dirigida(
  p_receta_id bigint, p_item_ids bigint[], p_farmaceutico text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_ra RECORD; v_n int := 0; r RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;
  IF p_farmaceutico IS NULL OR length(btrim(p_farmaceutico)) = 0 THEN
    RAISE EXCEPTION 'Farmacéutico requerido';
  END IF;

  SELECT ra.id, ra.receta_base_id, ra.paciente_id, ra.medico_id, ra.dispatch_token
    INTO v_ra
  FROM public.recetas_avanzadas ra
  WHERE ra.receta_base_id = p_receta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receta sin registro de despacho (PDF no generado): no despachable';
  END IF;

  FOR r IN
    SELECT ri.id, ri.farmacia_id, ri.nombre_medicamento, ri.cantidad, ri.precio_unitario
    FROM public.receta_items ri
    JOIN public.farmacias f ON f.id = ri.farmacia_id
    WHERE ri.receta_id = p_receta_id
      AND COALESCE(f.empresa_id = v_emp, false)
      AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)   -- 3.4: gate por sucursal ANTES del UPDATE/INSERT
      AND ri.id = ANY (COALESCE(p_item_ids, ARRAY[]::bigint[]))
      AND ri.dispensado = false
  LOOP
    UPDATE public.receta_items SET dispensado = true, dispensado_at = now() WHERE id = r.id;
    INSERT INTO public.dispensaciones
      (receta_avanzada_id, farmacia_id, paciente_id, medico_id, codigo_qr,
       medicamentos_dispensados, cantidad_items, total_dispensado, estado_dispensacion,
       farmaceutico_nombre, despachado_por, fecha_dispensacion)
    VALUES
      (v_ra.id, r.farmacia_id, v_ra.paciente_id, v_ra.medico_id, v_ra.dispatch_token,
       jsonb_build_array(jsonb_build_object('item_id', r.id, 'nombre', r.nombre_medicamento, 'cantidad', r.cantidad)),
       1, COALESCE(r.precio_unitario, 0) * r.cantidad, 'completada', btrim(p_farmaceutico), v_uid, now());
    v_n := v_n + 1;
  END LOOP;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Sin ítems despachables (ya dispensados, no asignados a tu farmacia/sucursal, o ids inválidos)';
  END IF;
  RETURN jsonb_build_object('despachados', v_n);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.registrar_dispensacion_dirigida(bigint, bigint[], text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_dispensacion_dirigida(bigint, bigint[], text) TO authenticated, service_role;

-- 4) registrar_dispensacion (walk-in/QR) — mismo término en el WHERE del FOR loop (gate ANTES del efecto).
CREATE OR REPLACE FUNCTION public.registrar_dispensacion(
  p_token text, p_item_ids bigint[], p_farmaceutico text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_ra RECORD; v_receta_id bigint; v_n int := 0; r RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN RAISE EXCEPTION 'Token requerido'; END IF;

  SELECT ra.id, ra.receta_base_id, ra.paciente_id, ra.medico_id, ra.dispatch_token
    INTO v_ra
  FROM public.recetas_avanzadas ra
  WHERE ra.dispatch_token = p_token
    AND COALESCE(ra.dispatch_token_expira_at > now(), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Token inválido o expirado'; END IF;
  v_receta_id := v_ra.receta_base_id;

  FOR r IN
    SELECT ri.id, ri.farmacia_id, ri.nombre_medicamento, ri.cantidad, ri.precio_unitario
    FROM public.receta_items ri
    JOIN public.farmacias f ON f.id = ri.farmacia_id
    WHERE ri.receta_id = v_receta_id
      AND COALESCE(f.empresa_id = v_emp, false)
      AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)   -- 3.4: gate por sucursal ANTES del UPDATE/INSERT
      AND ri.id = ANY (COALESCE(p_item_ids, ARRAY[]::bigint[]))
      AND ri.dispensado = false
  LOOP
    UPDATE public.receta_items SET dispensado = true, dispensado_at = now() WHERE id = r.id;
    INSERT INTO public.dispensaciones
      (receta_avanzada_id, farmacia_id, paciente_id, medico_id, codigo_qr,
       medicamentos_dispensados, cantidad_items, total_dispensado, estado_dispensacion,
       farmaceutico_nombre, despachado_por, fecha_dispensacion)
    VALUES
      (v_ra.id, r.farmacia_id, v_ra.paciente_id, v_ra.medico_id, v_ra.dispatch_token,
       jsonb_build_array(jsonb_build_object('item_id', r.id, 'nombre', r.nombre_medicamento, 'cantidad', r.cantidad)),
       1, COALESCE(r.precio_unitario, 0) * r.cantidad, 'completada', p_farmaceutico, v_uid, now());
    v_n := v_n + 1;
  END LOOP;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Sin ítems despachables (ya dispensados, no asignados a tu farmacia/sucursal, o ids inválidos)';
  END IF;
  RETURN jsonb_build_object('despachados', v_n);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.registrar_dispensacion(text, bigint[], text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_dispensacion(text, bigint[], text) TO authenticated, service_role;
