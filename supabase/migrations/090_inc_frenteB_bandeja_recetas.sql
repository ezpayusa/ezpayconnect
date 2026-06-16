-- ============================================================
-- FRENTE B · Bandeja de recetas entrantes (portal farmacia) — SEGURIDAD / PHI
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — NO aplicar sin OK. Probes rojo-primero (P163–P174).
-- Decisiones (Oscar): despacho DIRECTO por receta_id (autz por dueño de los ítems,
-- farmacéutico requerido, un-solo-uso, auditoría con auth.uid()) · alcance = bandeja
-- dirigida + walk-in QR.
--
-- Modelo reusado (Inc.4 / 085): el médico dirige cada ítem a una farmacia
-- (receta_items.farmacia_id → farmacias.id). Aislamiento canónico:
--   receta_items.farmacia_id → farmacias.empresa_id = public.mi_empresa_proveedor().
-- Permiso: private.tiene_permiso('recetas_dispensar') (ya sembrado en 085).
-- RLS de recetas/receta_items/dispensaciones NO se afloja: la única puerta de la
-- farmacia son estas RPC SECURITY DEFINER con payload CURADO y PHI mínima
-- (paciente/médico nombre; NUNCA diagnóstico/teléfono/dirección/firma/expediente).
-- NUNCA se expone dispatch_token en listar/detalle (solo tiene_token boolean): el
-- token es el secreto del QR del paciente.
--
-- Walk-in QR (Inc.4) NO cambia de contrato; solo se le añade el actor de auditoría.
-- ============================================================

-- ------------------------------------------------------------
-- 0) Auditoría: el DESPACHADOR autenticado (no solo el texto libre farmaceutico_nombre).
--    Sin el actor real, la trazabilidad que sostiene el despacho sin-token es hueca.
-- ------------------------------------------------------------
ALTER TABLE public.dispensaciones
  ADD COLUMN IF NOT EXISTS despachado_por uuid;   -- = auth.uid() del que despacha
COMMENT ON COLUMN public.dispensaciones.despachado_por IS
  'auth.uid() del usuario que ejecutó el despacho (auditoría real; farmaceutico_nombre es texto libre).';

-- ------------------------------------------------------------
-- 1) RPC listar_recetas_entrantes() — bandeja: recetas con ítems PENDIENTES dirigidos
--    a la(s) farmacia(s) de mi empresa. Payload curado: por receta, paciente/médico
--    nombre + fecha + ítems pendientes (SOLO de mi empresa). tiene_token = boolean
--    (¿despachable?); JAMÁS el dispatch_token. PHI mínima.
-- ------------------------------------------------------------
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
             'tiene_token', (ra.id IS NOT NULL),       -- ¿despachable? (recetas_avanzadas presente); NO el token
             'items_pendientes', (
                SELECT jsonb_agg(jsonb_build_object(
                         'item_id', ri.id,
                         'nombre_medicamento', ri.nombre_medicamento,
                         'dosis', ri.dosis,
                         'frecuencia', ri.frecuencia,
                         'cantidad', ri.cantidad,
                         'instrucciones', ri.instrucciones))
                FROM public.receta_items ri
                JOIN public.farmacias f ON f.id = ri.farmacia_id
                WHERE ri.receta_id = r.id
                  AND COALESCE(f.empresa_id = v_emp, false)
                  AND ri.dispensado = false)
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
        AND ri2.dispensado = false)
  ) s;

  RETURN v_out;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.listar_recetas_entrantes() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_recetas_entrantes() TO authenticated, service_role;

-- ------------------------------------------------------------
-- 2) RPC detalle_receta_entrante(p_receta_id) — re-fetch tras despacho parcial. Mismo
--    gate + aislamiento. Ítems pendientes y ya dispensados de MI empresa. SIN token.
-- ------------------------------------------------------------
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
    AND COALESCE(f.empresa_id = v_emp, false);

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
    'tiene_token', v_token,   -- boolean; NUNCA el dispatch_token
    'items', v_items);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.detalle_receta_entrante(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.detalle_receta_entrante(bigint) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 3) RPC registrar_dispensacion_dirigida(p_receta_id, p_item_ids[], p_farmaceutico)
--    Despacho DIRECTO por receta_id (sin token): autoriza por DUEÑO de los ítems
--    (farmacias.empresa_id = mi empresa). El array de item_ids solo REDUCE (igual que
--    Inc.4): ítems ajenos en el array se ignoran por el filtro de empresa. Farmacéutico
--    REQUERIDO + auditoría despachado_por=auth.uid(). Un-solo-uso. Edge sin
--    recetas_avanzadas → RECHAZO con motivo claro (no revienta el FK; no minta token).
-- ------------------------------------------------------------
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

  -- recetas_avanzadas (UNIQUE por receta_base_id): necesaria para la fila de auditoría
  -- (FK) y el trigger de stock. Sin ella → no despachable (rechazo limpio, sin FK crudo).
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
      AND COALESCE(f.empresa_id = v_emp, false)            -- aislamiento: ignora ítems ajenos del array
      AND ri.id = ANY (COALESCE(p_item_ids, ARRAY[]::bigint[]))
      AND ri.dispensado = false                            -- un solo uso
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
    RAISE EXCEPTION 'Sin ítems despachables (ya dispensados, no asignados a tu farmacia, o ids inválidos)';
  END IF;
  RETURN jsonb_build_object('despachados', v_n);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.registrar_dispensacion_dirigida(bigint, bigint[], text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_dispensacion_dirigida(bigint, bigint[], text) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 4) Walk-in (Inc.4) registrar_dispensacion: mismo contrato; solo añade el actor de
--    auditoría despachado_por=auth.uid(). Cuerpo idéntico a 085 salvo esa columna.
-- ------------------------------------------------------------
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
    RAISE EXCEPTION 'Sin ítems despachables (ya dispensados, no asignados a tu farmacia, o ids inválidos)';
  END IF;
  RETURN jsonb_build_object('despachados', v_n);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.registrar_dispensacion(text, bigint[], text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_dispensacion(text, bigint[], text) TO authenticated, service_role;
