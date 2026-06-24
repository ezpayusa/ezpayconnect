-- ============================================================
-- 150 · DELIVERY Fase 1 — OLA F: despacho sin-QR (buscar_recetas_pendientes_paciente). ORTOGONAL al delivery.
-- ------------------------------------------------------------
-- Vía PICKUP para paciente sin móvil: el dependiente identifica por nombre+apellido+fecha_nac (match EXACTO,
-- anti-fishing), encuentra recetas con ítems PENDIENTES ruteados a SU sucursal, y despacha por el path vivo
-- registrar_dispensacion_dirigida. F NO despacha, NO crea entrega, NO marca modalidad. Retorno MINIMIZADO (sin
-- direccion/telefono/expediente). Homónimos (a1): ambos con paciente_ref OPACO (salt por-llamada). Log anti-fishing
-- best-effort → VOLATILE. Confinamiento empresa + sucursal_visible (espejo del despacho). Idempotente.
-- ============================================================

-- 1) Log de búsqueda (anti-fishing) — solo el RPC DEFINER escribe ----------
CREATE TABLE IF NOT EXISTS private.busqueda_paciente_log (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  caller        uuid,
  termino_nombre   text,
  termino_apellido text,
  termino_fecha    date,
  n_resultados  integer,
  ocurrido_at   timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON private.busqueda_paciente_log FROM PUBLIC, anon, authenticated;

-- 2) RPC buscar_recetas_pendientes_paciente (VOLATILE por el log best-effort) ----
CREATE OR REPLACE FUNCTION public.buscar_recetas_pendientes_paciente(
  p_nombre text, p_apellido text, p_fecha_nac date)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_salt text; v_result jsonb; v_n integer;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  IF p_nombre IS NULL OR p_apellido IS NULL OR p_fecha_nac IS NULL THEN
    RAISE EXCEPTION 'Identidad incompleta (nombre, apellido y fecha de nacimiento requeridos)';
  END IF;
  v_salt := md5(clock_timestamp()::text || random()::text);   -- salt POR LLAMADA → paciente_ref opaco, no-enumerable

  WITH matched_pac AS (
    SELECT p.id, p.nombre, p.apellido
    FROM public.pacientes p
    WHERE lower(btrim(p.nombre))   = lower(btrim(p_nombre))     -- match EXACTO (case/espacios), sin LIKE/fuzzy
      AND lower(btrim(p.apellido)) = lower(btrim(p_apellido))
      AND p.fecha_nacimiento       = p_fecha_nac
  ),
  vis_items AS (   -- ítems PENDIENTES ruteados a la empresa+sucursal del caller (espejo del despacho)
    SELECT r.paciente_id, ri.receta_id, ri.id AS item_id, ri.nombre_medicamento, ri.dosis,
           ri.frecuencia, ri.cantidad, ri.instrucciones, ri.farmacia_id
    FROM public.receta_items ri
    JOIN public.recetas  r ON r.id = ri.receta_id
    JOIN public.farmacias f ON f.id = ri.farmacia_id
    WHERE r.paciente_id IN (SELECT id FROM matched_pac)
      AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false)
      AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)
      AND ri.dispensado = false
  )
  SELECT COALESCE(jsonb_agg(pac), '[]'::jsonb) INTO v_result FROM (
    SELECT jsonb_build_object(
      'paciente_ref', md5(mp.id::text || v_salt),                 -- OPACO: no es el id, salt por-llamada
      'paciente_nombre', mp.nombre || ' ' || COALESCE(mp.apellido,''),
      'recetas', (
        SELECT jsonb_agg(rj) FROM (
          SELECT jsonb_build_object(
            'receta_base_id', vi.receta_id,
            'items', jsonb_agg(jsonb_build_object(
              'item_id', vi.item_id, 'nombre_medicamento', vi.nombre_medicamento, 'dosis', vi.dosis,
              'frecuencia', vi.frecuencia, 'cantidad', vi.cantidad, 'instrucciones', vi.instrucciones,
              'farmacia_id', vi.farmacia_id))
          ) AS rj
          FROM vis_items vi WHERE vi.paciente_id = mp.id
          GROUP BY vi.receta_id
        ) s
      )
    ) AS pac
    FROM matched_pac mp
    WHERE EXISTS (SELECT 1 FROM vis_items vi WHERE vi.paciente_id = mp.id)   -- solo pacientes con ítem visible
  ) t;

  v_n := jsonb_array_length(v_result);

  -- log anti-fishing — best-effort: JAMÁS rompe la búsqueda
  BEGIN
    INSERT INTO private.busqueda_paciente_log(caller, termino_nombre, termino_apellido, termino_fecha, n_resultados, ocurrido_at)
    VALUES (auth.uid(), p_nombre, p_apellido, p_fecha_nac, v_n, now());
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_result;
END $$;
REVOKE EXECUTE ON FUNCTION public.buscar_recetas_pendientes_paciente(text,text,date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.buscar_recetas_pendientes_paciente(text,text,date) TO authenticated;
