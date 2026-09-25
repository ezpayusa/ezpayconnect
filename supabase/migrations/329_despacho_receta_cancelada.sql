-- ############################################################################################
-- Migracion 329 - el despacho rechaza recetas canceladas (lado servidor)
-- ############################################################################################
-- Antes (medido 25-sep contra la base viva): las funciones que verifican, revelan, despachan o
-- preparan la entrega de una receta validaban el token (igualdad + expira_at > now()) o el
-- receta_id y la farmacia del item, pero NO recetas.estado. Una receta 'cancelada' con token
-- vigente se podia verificar, revelar y despachar.
-- recetas.estado: text NOT NULL DEFAULT 'activa', sin CHECK. Hoy todas las recetas estan
-- 'activa' y ninguna funcion ni policy la pasa a 'cancelada' (solo service_role/postgres
-- podrian): el hueco es latente. Unico estado terminal confirmado: 'cancelada'.
-- Cambio: en 6 funciones, despues de resolver la receta y ANTES de cualquier escritura,
--   IF COALESCE(estado de la receta, 'cancelada') = 'cancelada' -> PR010
--   'Receta cancelada: no se puede despachar'. Fail-closed: sin fila o estado NULL tambien rechaza.
-- PR010 = proximo libre de la familia PR (recetas; PR001-PR009 = emitir_receta).
-- NO se toca confirmar_recepcion_receta: confirma la recepcion de algo ya entregado.
-- CREATE OR REPLACE con la misma firma, SECURITY DEFINER, owner, search_path y ACL (CREATE OR
-- REPLACE conserva owner y privilegios). Diff minimo: solo el bloque (mig 329).
-- ############################################################################################

BEGIN;

-- verificar_receta_despacho(text): tras resolver la receta por token (el token es el secreto: sin oraculo)
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
  -- (mig 329) receta cancelada: no se despacha. Fail-closed: sin fila o estado NULL tambien rechaza.
  IF COALESCE((SELECT rc329.estado FROM public.recetas rc329 WHERE rc329.id = v_receta_id), 'cancelada') = 'cancelada' THEN
    RAISE EXCEPTION 'Receta cancelada: no se puede despachar' USING ERRCODE = 'PR010';
  END IF;

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

-- registrar_dispensacion(text,bigint[],text): tras resolver la receta por token y antes del loop que escribe
CREATE OR REPLACE FUNCTION public.registrar_dispensacion(p_token text, p_item_ids bigint[], p_farmaceutico text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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
  -- (mig 329) receta cancelada: no se despacha. Fail-closed: sin fila o estado NULL tambien rechaza.
  IF COALESCE((SELECT rc329.estado FROM public.recetas rc329 WHERE rc329.id = v_receta_id), 'cancelada') = 'cancelada' THEN
    RAISE EXCEPTION 'Receta cancelada: no se puede despachar' USING ERRCODE = 'PR010';
  END IF;

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

-- registrar_dispensacion_dirigida(bigint,bigint[],text): tras resolver la avanzada por receta_id y antes del loop que escribe
CREATE OR REPLACE FUNCTION public.registrar_dispensacion_dirigida(p_receta_id bigint, p_item_ids bigint[], p_farmaceutico text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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
  -- (mig 329) receta cancelada: no se despacha. Fail-closed: sin fila o estado NULL tambien rechaza.
  IF COALESCE((SELECT rc329.estado FROM public.recetas rc329 WHERE rc329.id = p_receta_id), 'cancelada') = 'cancelada' THEN
    RAISE EXCEPTION 'Receta cancelada: no se puede despachar' USING ERRCODE = 'PR010';
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

-- revelar_items_receta(bigint,text): tras el confinamiento (sin oraculo para otras farmacias) y antes del INSERT en reveal_log
CREATE OR REPLACE FUNCTION public.revelar_items_receta(p_receta_base_id bigint, p_puerta text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_emp uuid; v_items jsonb;
BEGIN
  -- gate de permiso (mismo que listar_recetas_entrantes / verificar_receta_despacho / buscar_recetas_pendientes_paciente)
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  -- p_puerta validado contra el MISMO enum del CHECK de la tabla
  IF p_puerta NOT IN ('bandeja','walkin_qr','sinqr') THEN
    RAISE EXCEPTION 'Puerta inválida';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;

  -- confinamiento: ítems de la receta cuya farmacia ∈ empresa del caller Y sucursal_visible Y dispensado=false
  -- (mismo confinamiento que listar/verificar/buscar). Misma forma de ítems que devuelven hoy las puertas.
  SELECT jsonb_agg(jsonb_build_object(
           'item_id', ri.id,
           'nombre_medicamento', ri.nombre_medicamento,
           'dosis', ri.dosis,
           'frecuencia', ri.frecuencia,
           'cantidad', ri.cantidad,
           'instrucciones', ri.instrucciones,
           'farmacia_id', ri.farmacia_id) ORDER BY ri.id)
    INTO v_items
  FROM public.receta_items ri
  JOIN public.farmacias f ON f.id = ri.farmacia_id
  WHERE ri.receta_id = p_receta_base_id
    AND COALESCE(f.empresa_id = v_emp, false)
    AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)
    AND ri.dispensado = false;

  -- DECISIÓN confinamiento (no-leak): sin ítems visibles → RAISE ANTES de loguear. No es un reveal real → NO deja
  -- fila en reveal_log, y NUNCA expone ítems ajenos. (Espeja el `IF v_items IS NULL THEN RAISE` de listar/verificar.)
  IF v_items IS NULL THEN
    RAISE EXCEPTION 'No autorizado: la receta no tiene ítems asignados a tu farmacia';
  END IF;
  -- (mig 329) receta cancelada: no se despacha. Fail-closed: sin fila o estado NULL tambien rechaza.
  IF COALESCE((SELECT rc329.estado FROM public.recetas rc329 WHERE rc329.id = p_receta_base_id), 'cancelada') = 'cancelada' THEN
    RAISE EXCEPTION 'Receta cancelada: no se puede despachar' USING ERRCODE = 'PR010';
  END IF;

  -- REGISTRO BLOQUEANTE (Q-R1): el reveal es CONDICIÓN de mostrar. INSERT antes del RETURN; si el INSERT falla,
  -- la función falla (sin EXCEPTION-swallow, sin best-effort). No hay forma de ver el med sin dejar el registro.
  -- Q-R1 BLOQUEANTE: NO envolver este INSERT en BEGIN/EXCEPTION. El registro del reveal es condición de mostrar;
  -- si se traga el error del log, se reabre la ventana "vio sin registro". El RETURN debe ser inalcanzable sin este INSERT.
  INSERT INTO private.reveal_log (actor, receta_base_id, puerta, empresa_id)
  VALUES (auth.uid(), p_receta_base_id, p_puerta, v_emp);

  RETURN v_items;
END;
$function$;

-- crear_entrega(bigint,integer): tras resolver la receta y antes del INSERT en entregas
CREATE OR REPLACE FUNCTION public.crear_entrega(p_receta_base_id bigint, p_farmacia_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- (mig 329) receta cancelada: no se despacha. Fail-closed: sin fila o estado NULL tambien rechaza.
  IF COALESCE((SELECT rc329.estado FROM public.recetas rc329 WHERE rc329.id = p_receta_base_id), 'cancelada') = 'cancelada' THEN
    RAISE EXCEPTION 'Receta cancelada: no se puede despachar' USING ERRCODE = 'PR010';
  END IF;
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
END $function$;

-- fijar_modalidad_grupo(bigint,integer,text): tras el gate medico/paciente y antes del UPDATE de modalidad
CREATE OR REPLACE FUNCTION public.fijar_modalidad_grupo(p_receta_id bigint, p_farmacia_id integer, p_modalidad text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_es_medico boolean; v_es_paciente boolean; v_n integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF p_modalidad NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'Modalidad inválida'; END IF;

  SELECT EXISTS (SELECT 1 FROM public.recetas r WHERE r.id = p_receta_id AND r.medico_id = v_uid)
    INTO v_es_medico;
  SELECT EXISTS (SELECT 1 FROM public.recetas r
                 WHERE r.id = p_receta_id AND COALESCE(private.paciente_es_mio(r.paciente_id), false))
    INTO v_es_paciente;
  IF NOT (v_es_medico OR v_es_paciente) THEN
    RAISE EXCEPTION 'No autorizado para esta receta';
  END IF;
  -- (mig 329) receta cancelada: no se despacha. Fail-closed: sin fila o estado NULL tambien rechaza.
  IF COALESCE((SELECT rc329.estado FROM public.recetas rc329 WHERE rc329.id = p_receta_id), 'cancelada') = 'cancelada' THEN
    RAISE EXCEPTION 'Receta cancelada: no se puede despachar' USING ERRCODE = 'PR010';
  END IF;

  -- freeze: editable solo hasta que la sucursal despache el grupo (gate ANTES del efecto)
  IF EXISTS (SELECT 1 FROM public.receta_items
             WHERE receta_id = p_receta_id AND farmacia_id = p_farmacia_id AND dispensado = true) THEN
    RAISE EXCEPTION 'Modalidad congelada: la sucursal ya despachó este grupo';
  END IF;

  UPDATE public.receta_items SET modalidad = p_modalidad
    WHERE receta_id = p_receta_id AND farmacia_id = p_farmacia_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('receta_id', p_receta_id, 'farmacia_id', p_farmacia_id,
                            'modalidad', p_modalidad, 'items', v_n);
END $function$;

-- AUTOCHEQUEO -------------------------------------------------------------------------------------
DO $ac$
DECLARE v text := ''; e record; r record;
BEGIN
  FOR e IN SELECT * FROM (VALUES
    ('public.verificar_receta_despacho(text)', 'a258edce0ffe1ffdb2850f789497a6a4', true, 'postgres', '{"search_path=\"\""}', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
    ('public.registrar_dispensacion(text,bigint[],text)', 'c53336c3d8038da66133036f4fbec1ee', true, 'postgres', '{"search_path=\"\""}', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
    ('public.registrar_dispensacion_dirigida(bigint,bigint[],text)', '5801cdac37b1c42d94dd9258d71ab17f', true, 'postgres', '{"search_path=\"\""}', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
    ('public.revelar_items_receta(bigint,text)', 'e15ee147776aaab278b6b5dadc226592', true, 'postgres', '{"search_path=\"\""}', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
    ('public.crear_entrega(bigint,integer)', '6f469e33cb1ab11057d848c6b0de26c6', true, 'postgres', '{"search_path=\"\""}', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
    ('public.fijar_modalidad_grupo(bigint,integer,text)', '3984810fac815d1625c8732d2484cfac', true, 'postgres', '{"search_path=\"\""}', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}')
  ) x(f, md5, secdef, owner, cfg, acl) LOOP
    SELECT md5(p.prosrc) AS md5, p.prosrc, p.prosecdef, pg_get_userbyid(p.proowner) AS owner, p.proconfig::text AS cfg,
           ARRAY(SELECT a::text FROM unnest(p.proacl) a ORDER BY 1)::text AS acl
      INTO r FROM pg_proc p WHERE p.oid = e.f::regprocedure;
    IF r.md5 IS DISTINCT FROM e.md5 THEN v := v||E'\n '||e.f||' md5='||r.md5||' (esperado '||e.md5||')'; END IF;
    IF r.prosecdef IS DISTINCT FROM e.secdef OR r.owner IS DISTINCT FROM e.owner OR r.cfg IS DISTINCT FROM e.cfg OR r.acl IS DISTINCT FROM e.acl THEN
      v := v||E'\n '||e.f||' metadata distinta: secdef='||r.prosecdef||' owner='||r.owner||' cfg='||COALESCE(r.cfg,'NULL')||' acl='||r.acl; END IF;
    IF position('Receta cancelada: no se puede despachar' in r.prosrc) = 0 OR position('PR010' in r.prosrc) = 0 THEN
      v := v||E'\n '||e.f||' sin el chequeo de receta cancelada'; END IF;
  END LOOP;
  -- confirmar_recepcion_receta NO se toca (confirma algo ya entregado)
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.confirmar_recepcion_receta(text,inet,text)'::regprocedure)
     IS DISTINCT FROM 'b94e4d21e567ceeb38fb83ebf9a83b03' THEN v := v||E'\n confirmar_recepcion_receta cambio'; END IF;
  IF v <> '' THEN RAISE EXCEPTION 'MIG329 AUTOCHEQUEO FALLA:%', v; END IF;
END $ac$;

COMMIT;
