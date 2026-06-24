-- ============================================================
-- 147 · DELIVERY Fase 1 — OLA C: auto-create (best-effort #4-B) + RPCs de ciclo. TOCA RPCs vivos 141/143.
-- ------------------------------------------------------------
-- Alcance: (1) private.delivery_flags (kill-switch, seed autocreate_entregas=true) + private.delivery_autocreate_fallos
-- (rastro best-effort); (2) RPCs nuevos crear/asignar/reasignar/actualizar_estado_entrega (DEFINER sp''); (3)
-- CREATE OR REPLACE de registrar_dispensacion + registrar_dispensacion_dirigida con el bloque auto-create
-- (doble savepoint, lectura fail-safe del flag). Grandfather-inerte (default pickup + 0 grupos delivery hoy).
-- NO toca front. Pickup byte-idéntico (la rama delivery + su EXCEPTION es el único código nuevo en caliente).
-- ============================================================

-- 1) Kill-switch + rastro de fallos (schema private; solo DEFINER/owner los toca) ----
CREATE TABLE IF NOT EXISTS private.delivery_flags (
  clave text PRIMARY KEY,
  habilitado boolean NOT NULL DEFAULT true
);
INSERT INTO private.delivery_flags (clave, habilitado) VALUES ('autocreate_entregas', true)
  ON CONFLICT (clave) DO NOTHING;
CREATE TABLE IF NOT EXISTS private.delivery_autocreate_fallos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receta_base_id bigint,
  empresa_id uuid,
  error text,
  ocurrido_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON private.delivery_flags             FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.delivery_autocreate_fallos FROM PUBLIC, anon, authenticated;

-- 2) RPCs de ciclo (DEFINER sp'') -------------------------------------------
-- crear_entrega: manual (gestor). UPSERT snapshot; exige grupo delivery + confinamiento.
CREATE OR REPLACE FUNCTION public.crear_entrega(p_receta_base_id bigint, p_farmacia_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_emp uuid; v_pac bigint; v_ra_id uuid; v_monto numeric; v_eid bigint;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Sin empresa'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.farmacias f WHERE f.id=p_farmacia_id AND f.empresa_id=v_emp) THEN
    RAISE EXCEPTION 'Farmacia no es de tu empresa'; END IF;
  IF NOT COALESCE(private.sucursal_visible(p_farmacia_id), false) THEN RAISE EXCEPTION 'Sucursal no visible'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.receta_items WHERE receta_id=p_receta_base_id AND farmacia_id=p_farmacia_id AND modalidad='delivery') THEN
    RAISE EXCEPTION 'El grupo (receta, farmacia) no es modalidad delivery'; END IF;
  SELECT r.paciente_id INTO v_pac FROM public.recetas r WHERE r.id=p_receta_base_id;
  IF v_pac IS NULL THEN RAISE EXCEPTION 'Receta inexistente'; END IF;
  SELECT ra.id INTO v_ra_id FROM public.recetas_avanzadas ra WHERE ra.receta_base_id=p_receta_base_id;
  SELECT SUM(d.total_dispensado) INTO v_monto FROM public.dispensaciones d
    WHERE d.receta_avanzada_id=v_ra_id AND d.farmacia_id=p_farmacia_id;
  INSERT INTO public.entregas (receta_base_id, farmacia_id, empresa_id, paciente_id,
                               direccion_entrega, telefono_contacto, monto, created_by)
  SELECT p_receta_base_id, p_farmacia_id, v_emp, v_pac, pac.direccion, pac.telefono, v_monto, auth.uid()
  FROM public.pacientes pac WHERE pac.id=v_pac
  ON CONFLICT (receta_base_id, farmacia_id) DO UPDATE
    SET monto = COALESCE(excluded.monto, entregas.monto), updated_at=now()
    WHERE entregas.estado='pendiente'
  RETURNING id INTO v_eid;
  IF v_eid IS NULL THEN SELECT id INTO v_eid FROM public.entregas WHERE receta_base_id=p_receta_base_id AND farmacia_id=p_farmacia_id; END IF;
  RETURN jsonb_build_object('entrega_id', v_eid, 'receta_base_id', p_receta_base_id, 'farmacia_id', p_farmacia_id, 'monto', v_monto);
END $$;
REVOKE EXECUTE ON FUNCTION public.crear_entrega(bigint,integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_entrega(bigint,integer) TO authenticated;

-- asignar_entrega: pendiente→asignada; valida delivery de la MISMA sucursal (#8)
CREATE OR REPLACE FUNCTION public.asignar_entrega(p_entrega_id bigint, p_delivery_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_del public.cuentas_proveedor;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  IF v_e.estado <> 'pendiente' THEN RAISE EXCEPTION 'Solo se asigna desde pendiente (estado=%)', v_e.estado; END IF;
  SELECT * INTO v_del FROM public.cuentas_proveedor
    WHERE id=p_delivery_id AND empresa_id=v_e.empresa_id AND rol_en_empresa='delivery' AND activo=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery inválido (no es delivery activo de la empresa)'; END IF;
  IF v_del.sucursal_id IS DISTINCT FROM v_e.farmacia_id THEN
    RAISE EXCEPTION 'El delivery no pertenece a la sucursal de la entrega'; END IF;
  UPDATE public.entregas SET estado='asignada', delivery_id=p_delivery_id,
    asignado_por=auth.uid(), asignado_at=now(), updated_at=now() WHERE id=p_entrega_id;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.asignar_entrega(bigint,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.asignar_entrega(bigint,uuid) TO authenticated;

-- reasignar_entrega: desde asignada/en_camino (reasignar) y fallida (reabrir). RAISE si cobrada. #8.
CREATE OR REPLACE FUNCTION public.reasignar_entrega(p_entrega_id bigint, p_delivery_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_del public.cuentas_proveedor; v_reabrir boolean;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  IF v_e.cobrado THEN RAISE EXCEPTION 'Entrega ya cobrada: no reasignable'; END IF;
  IF v_e.estado NOT IN ('asignada','en_camino','fallida') THEN
    RAISE EXCEPTION 'No reasignable desde estado %', v_e.estado; END IF;
  SELECT * INTO v_del FROM public.cuentas_proveedor
    WHERE id=p_delivery_id AND empresa_id=v_e.empresa_id AND rol_en_empresa='delivery' AND activo=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery inválido'; END IF;
  IF v_del.sucursal_id IS DISTINCT FROM v_e.farmacia_id THEN
    RAISE EXCEPTION 'El delivery no pertenece a la sucursal de la entrega'; END IF;
  v_reabrir := (v_e.estado='fallida');
  UPDATE public.entregas SET
    estado='asignada', delivery_id=p_delivery_id, asignado_por=auth.uid(), asignado_at=now(),
    motivo_fallo  = CASE WHEN v_reabrir THEN NULL          ELSE motivo_fallo  END,
    intentos      = CASE WHEN v_reabrir THEN intentos+1    ELSE intentos      END,
    reabierta_at  = CASE WHEN v_reabrir THEN now()         ELSE reabierta_at  END,
    reabierta_por = CASE WHEN v_reabrir THEN auth.uid()    ELSE reabierta_por END,
    updated_at=now()
  WHERE id=p_entrega_id;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.reasignar_entrega(bigint,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.reasignar_entrega(bigint,uuid) TO authenticated;

-- actualizar_estado_entrega: máquina de estados; delivery solo su entrega; idempotente.
CREATE OR REPLACE FUNCTION public.actualizar_estado_entrega(p_entrega_id bigint, p_nuevo_estado text, p_motivo_fallo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_es_delivery boolean;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_actualizar_estado'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  v_es_delivery := (v_e.delivery_id = auth.uid());
  IF private.mi_sucursal() IS NOT NULL AND NOT v_es_delivery
     AND NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado: no es tu entrega'; END IF;
  IF v_e.estado = p_nuevo_estado THEN RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id); END IF;
  IF NOT ( (v_e.estado='asignada'  AND p_nuevo_estado IN ('en_camino','fallida'))
        OR (v_e.estado='en_camino' AND p_nuevo_estado IN ('entregada','fallida')) ) THEN
    RAISE EXCEPTION 'Transición ilegal % → %', v_e.estado, p_nuevo_estado; END IF;
  IF p_nuevo_estado='fallida' AND p_motivo_fallo IS NULL THEN RAISE EXCEPTION 'Motivo requerido'; END IF;
  UPDATE public.entregas SET estado=p_nuevo_estado,
    motivo_fallo = CASE WHEN p_nuevo_estado='fallida' THEN p_motivo_fallo ELSE NULL END,
    entregado_at = CASE WHEN p_nuevo_estado='entregada' THEN now() ELSE entregado_at END,
    updated_at=now()
  WHERE id=p_entrega_id;
  -- HOOK push (Fase 4): en_camino / entregada → punto de notificación (stub).
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.actualizar_estado_entrega(bigint,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.actualizar_estado_entrega(bigint,text,text) TO authenticated;

-- 3) CREATE OR REPLACE de los 2 RPCs de dispensación + bloque auto-create -----
-- registrar_dispensacion (walk-in/QR, token) — reproducción EXACTA de la versión viva + bloque antes del RETURN.
CREATE OR REPLACE FUNCTION public.registrar_dispensacion(p_token text, p_item_ids bigint[], p_farmaceutico text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
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
      AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)
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

  -- ===== Ola C: AUTO-CREATE entregas (best-effort #4-B, kill-switch fail-safe). Pickup → 0 filas. =====
  IF COALESCE((SELECT habilitado FROM private.delivery_flags WHERE clave='autocreate_entregas'), false) THEN
    BEGIN
      INSERT INTO public.entregas (receta_base_id, farmacia_id, empresa_id, paciente_id,
                                   direccion_entrega, telefono_contacto, monto, created_by)
      SELECT v_ra.receta_base_id, ri.farmacia_id, v_emp, r2.paciente_id, pac.direccion, pac.telefono,
             (SELECT SUM(d.total_dispensado) FROM public.dispensaciones d
                WHERE d.receta_avanzada_id = v_ra.id AND d.farmacia_id = ri.farmacia_id),
             NULL
      FROM public.receta_items ri
      JOIN public.recetas   r2  ON r2.id  = v_ra.receta_base_id
      JOIN public.pacientes pac ON pac.id = r2.paciente_id
      WHERE ri.receta_id = v_ra.receta_base_id
        AND ri.farmacia_id IS NOT NULL
        AND ri.modalidad = 'delivery'
        AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)
        AND EXISTS (SELECT 1 FROM public.dispensaciones d
                     WHERE d.receta_avanzada_id = v_ra.id AND d.farmacia_id = ri.farmacia_id)
      GROUP BY ri.farmacia_id, r2.paciente_id, pac.direccion, pac.telefono
      ON CONFLICT (receta_base_id, farmacia_id) DO UPDATE
        SET monto = excluded.monto, updated_at = now()
        WHERE entregas.estado = 'pendiente';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto-create entrega falló (receta %, empresa %): %', v_ra.receta_base_id, v_emp, SQLERRM;
      BEGIN
        INSERT INTO private.delivery_autocreate_fallos (receta_base_id, empresa_id, error, ocurrido_at)
        VALUES (v_ra.receta_base_id, v_emp, SQLERRM, now());
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END;
  END IF;

  RETURN jsonb_build_object('despachados', v_n);
END;
$function$;

-- registrar_dispensacion_dirigida (bandeja, sin token) — reproducción EXACTA + bloque.
CREATE OR REPLACE FUNCTION public.registrar_dispensacion_dirigida(p_receta_id bigint, p_item_ids bigint[], p_farmaceutico text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
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
      AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)
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

  -- ===== Ola C: AUTO-CREATE entregas (best-effort #4-B, kill-switch fail-safe). Pickup → 0 filas. =====
  IF COALESCE((SELECT habilitado FROM private.delivery_flags WHERE clave='autocreate_entregas'), false) THEN
    BEGIN
      INSERT INTO public.entregas (receta_base_id, farmacia_id, empresa_id, paciente_id,
                                   direccion_entrega, telefono_contacto, monto, created_by)
      SELECT v_ra.receta_base_id, ri.farmacia_id, v_emp, r2.paciente_id, pac.direccion, pac.telefono,
             (SELECT SUM(d.total_dispensado) FROM public.dispensaciones d
                WHERE d.receta_avanzada_id = v_ra.id AND d.farmacia_id = ri.farmacia_id),
             NULL
      FROM public.receta_items ri
      JOIN public.recetas   r2  ON r2.id  = v_ra.receta_base_id
      JOIN public.pacientes pac ON pac.id = r2.paciente_id
      WHERE ri.receta_id = v_ra.receta_base_id
        AND ri.farmacia_id IS NOT NULL
        AND ri.modalidad = 'delivery'
        AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)
        AND EXISTS (SELECT 1 FROM public.dispensaciones d
                     WHERE d.receta_avanzada_id = v_ra.id AND d.farmacia_id = ri.farmacia_id)
      GROUP BY ri.farmacia_id, r2.paciente_id, pac.direccion, pac.telefono
      ON CONFLICT (receta_base_id, farmacia_id) DO UPDATE
        SET monto = excluded.monto, updated_at = now()
        WHERE entregas.estado = 'pendiente';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto-create entrega falló (receta %, empresa %): %', v_ra.receta_base_id, v_emp, SQLERRM;
      BEGIN
        INSERT INTO private.delivery_autocreate_fallos (receta_base_id, empresa_id, error, ocurrido_at)
        VALUES (v_ra.receta_base_id, v_emp, SQLERRM, now());
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END;
  END IF;

  RETURN jsonb_build_object('despachados', v_n);
END;
$function$;
