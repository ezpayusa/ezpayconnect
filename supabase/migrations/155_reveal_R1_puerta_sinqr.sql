-- 155 · Ola R1 — enciende la PUERTA 3 (sin-QR) del gate reveal-registrado (patrón de 2 pasos).
-- buscar_recetas_pendientes_paciente pasa a leer el flag 'sinqr':
--   · flag activo=true  → devuelve CABECERA (paciente_ref, paciente_nombre, recetas:[{receta_base_id, n_items_pendientes}]).
--     SIN datos clínicos (nada de nombre_medicamento/dosis/frecuencia/cantidad/instrucciones/item_id). El med se obtiene
--     recién en el PASO 2 vía revelar_items_receta('sinqr'), que registra el reveal (Q-R1, R0).
--   · flag false/ausente → comportamiento VIEJO EXACTO (payload completo con med). FAIL-SAFE: backout sin redeploy.
-- Intacto: match exacto 3 campos, confinamiento empresa+sucursal_visible+dispensado=false, busqueda_paciente_log
-- best-effort, paciente_ref opaco (md5+salt). La cabecera deriva del MISMO query confinado; solo proyecta menos.

CREATE OR REPLACE FUNCTION public.buscar_recetas_pendientes_paciente(p_nombre text, p_apellido text, p_fecha_nac date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_salt text; v_result jsonb; v_n integer; v_gate boolean;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  IF p_nombre IS NULL OR p_apellido IS NULL OR p_fecha_nac IS NULL THEN
    RAISE EXCEPTION 'Identidad incompleta (nombre, apellido y fecha de nacimiento requeridos)';
  END IF;
  v_salt := md5(clock_timestamp()::text || random()::text);   -- salt POR LLAMADA → paciente_ref opaco, no-enumerable

  -- R1: gate de la puerta sin-QR. Fail-safe: ausente/false → comportamiento viejo (con med).
  v_gate := COALESCE((SELECT activo FROM private.reveal_gate_flags WHERE puerta='sinqr'), false);

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
        SELECT jsonb_agg(
          CASE WHEN v_gate
            THEN jsonb_build_object('receta_base_id', x.receta_id, 'n_items_pendientes', x.n)   -- R1: CABECERA, sin clínico
            ELSE jsonb_build_object('receta_base_id', x.receta_id, 'items', x.items)             -- VIEJO exacto (con med)
          END
        )
        FROM (
          SELECT vi.receta_id, count(*) AS n,
                 jsonb_agg(jsonb_build_object(
                   'item_id', vi.item_id, 'nombre_medicamento', vi.nombre_medicamento, 'dosis', vi.dosis,
                   'frecuencia', vi.frecuencia, 'cantidad', vi.cantidad, 'instrucciones', vi.instrucciones,
                   'farmacia_id', vi.farmacia_id)) AS items
          FROM vis_items vi WHERE vi.paciente_id = mp.id
          GROUP BY vi.receta_id
        ) x
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
END $function$;

-- Activación de la puerta sin-QR. Nace en true: F4 no está en prod (no hay front viejo que romper); el front de R1
-- consume la cabecera. Backout = UPDATE ... SET activo=false (vuelve al payload viejo sin redeploy).
UPDATE private.reveal_gate_flags SET activo = true WHERE puerta = 'sinqr';
