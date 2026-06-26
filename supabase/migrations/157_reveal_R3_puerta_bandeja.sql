-- 157 · Ola R3 — enciende la PUERTA 1 (bandeja entrantes) del gate reveal-registrado (patrón de 2 pasos).
-- listar_recetas_entrantes y detalle_receta_entrante pasan a leer el flag 'bandeja':
--   · flag activo=true  → CABECERA sin med (n_pendientes + sucursales por receta). El med se obtiene en el PASO 2
--     vía revelar_items_receta(receta_id,'bandeja') que registra el reveal (mig 154, bloqueante).
--   · flag false/ausente → comportamiento VIEJO EXACTO (items con med). FAIL-SAFE: backout sin redeploy.
-- Intacto: confinamiento (empresa+sucursal_visible+dispensado=false), EXISTS exterior, validaciones de permiso/empresa,
-- revelar_items_receta, y el valor del flag (NO se activa acá; queda en false — activación manual posterior, Opción A).

-- ===== (A) listar_recetas_entrantes =====
CREATE OR REPLACE FUNCTION public.listar_recetas_entrantes()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_out jsonb; v_gate boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;

  -- R3: gate de la puerta bandeja. Fail-safe: ausente/false → comportamiento viejo (con items_pendientes/med).
  v_gate := COALESCE((SELECT activo FROM private.reveal_gate_flags WHERE puerta='bandeja'), false);

  SELECT COALESCE(jsonb_agg(rec ORDER BY (rec->>'created_at') DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT jsonb_build_object(
             'receta_id', r.id,
             'created_at', r.created_at,
             'estado', r.estado,
             'paciente_nombre', btrim(COALESCE(p.nombre,'') || ' ' || COALESCE(p.apellido,'')),
             'medico_nombre', COALESCE(pm.nombre_completo, pm.nombre),
             'tiene_token', (ra.id IS NOT NULL))
           || CASE WHEN v_gate THEN
                -- R3 CABECERA: conteo + sucursales (sin med), derivados del MISMO subquery confinado.
                jsonb_build_object(
                  'n_pendientes', (
                     SELECT count(*)
                     FROM public.receta_items ri
                     JOIN public.farmacias f ON f.id = ri.farmacia_id
                     WHERE ri.receta_id = r.id
                       AND COALESCE(f.empresa_id = v_emp, false)
                       AND ri.dispensado = false
                       AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)),
                  'sucursales', (
                     SELECT jsonb_agg(DISTINCT jsonb_build_object(
                              'farmacia_id', f.id, 'sucursal_nombre', f.nombre, 'sucursal_direccion', f.direccion))
                     FROM public.receta_items ri
                     JOIN public.farmacias f ON f.id = ri.farmacia_id
                     WHERE ri.receta_id = r.id
                       AND COALESCE(f.empresa_id = v_emp, false)
                       AND ri.dispensado = false
                       AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)))
              ELSE
                -- VIEJO exacto: items_pendientes con med inline.
                jsonb_build_object(
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
                       AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)))   -- 3.4: confinamiento por sucursal
              END
           AS rec
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

-- ===== (B) detalle_receta_entrante =====
CREATE OR REPLACE FUNCTION public.detalle_receta_entrante(p_receta_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_items jsonb; v_pac text; v_med text; v_estado text; v_created timestamptz; v_token boolean; v_gate boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;

  -- R3: gate de la puerta bandeja. Fail-safe: ausente/false → comportamiento viejo (items con med).
  v_gate := COALESCE((SELECT activo FROM private.reveal_gate_flags WHERE puerta='bandeja'), false);

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

  -- R3: con el gate activo, devolver CABECERA (sin med). n_pendientes deriva de v_items; sucursales del confinado pendiente.
  IF v_gate THEN
    RETURN jsonb_build_object(
      'receta_id', p_receta_id, 'created_at', v_created, 'estado', v_estado,
      'paciente_nombre', v_pac, 'medico_nombre', v_med, 'tiene_token', v_token,
      'n_pendientes', (SELECT count(*) FROM jsonb_array_elements(v_items) e WHERE (e->>'dispensado')::boolean = false),
      'sucursales', (
         SELECT jsonb_agg(DISTINCT jsonb_build_object(
                  'farmacia_id', f.id, 'sucursal_nombre', f.nombre, 'sucursal_direccion', f.direccion))
         FROM public.receta_items ri
         JOIN public.farmacias f ON f.id = ri.farmacia_id
         WHERE ri.receta_id = p_receta_id
           AND COALESCE(f.empresa_id = v_emp, false)
           AND ri.dispensado = false
           AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)));
  END IF;

  RETURN jsonb_build_object(
    'receta_id', p_receta_id, 'created_at', v_created, 'estado', v_estado,
    'paciente_nombre', v_pac, 'medico_nombre', v_med,
    'tiene_token', v_token,
    'items', v_items);
END;
$function$;

-- NO se activa el flag bandeja acá: queda en false (Opción A: front primero, activación manual posterior).
