-- ============================================================
-- INCREMENTO 5 (Frente A) · Catálogo de farmacia — Parte 2: UNIQUE + RPC de carga
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — aplicar SOLO tras 086 + MERGE (sin colisiones).
-- ============================================================

-- ------------------------------------------------------------
-- 1) UNIQUE product-level (post-merge: 0 colisiones). Usa la columna generada de 086.
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS farmacia_medicamentos_farm_nombrenorm_uniq
  ON public.farmacia_medicamentos (farmacia_id, nombre_normalizado);

-- ------------------------------------------------------------
-- 2) RPC cargar_catalogo_farmacia(p_farmacia_id, p_rows jsonb) — carga masiva CSV.
--    SECURITY DEFINER + SET search_path = '' + TODAS las refs schema-calificadas
--    (anti-secuestro de search_path). Gate: tiene_permiso('inventario_editar') +
--    p_farmacia_id ∈ farmacias de mi empresa. UNA farmacia por llamada: el farmacia_id
--    sale del PARÁMETRO, NUNCA de las filas (las filas solo traen campos de producto;
--    un 'farmacia_id' en una fila se IGNORA). Upsert idempotente por la columna
--    generada. Reporte por fila. Semántica: stock/precio/fecha reemplazan solo si la
--    celda trae valor (blanco conserva); activo conserva si la fila no lo indica
--    (alta=true); presentacion/descripcion/laboratorio conservan si vienen vacías.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cargar_catalogo_farmacia(p_farmacia_id integer, p_rows jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_ins int := 0; v_upd int := 0; v_rech jsonb := '[]'::jsonb;
  r jsonb; i bigint := 0; v_nombre text; v_stock numeric; v_precio numeric; v_inserted boolean;
  v_activo boolean; v_fv date; v_smin int; v_nn text; v_lastmap jsonb;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('inventario_editar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede editar inventario';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.farmacias f
                 WHERE f.id = p_farmacia_id
                   AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false)) THEN
    RAISE EXCEPTION 'No autorizado: la farmacia no pertenece a tu empresa';
  END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'p_rows debe ser un arreglo JSON';
  END IF;

  -- DUPS INTRA-ARCHIVO: mapa clave_normalizada -> última posición (1-based). El upsert
  -- fila-por-fila colapsaría en silencio (última gana); en su lugar reportamos las
  -- ocurrencias previas y solo upsertamos la ÚLTIMA. Misma normalización que la columna.
  SELECT COALESCE(jsonb_object_agg(nn, last_ord), '{}'::jsonb) INTO v_lastmap FROM (
    SELECT upper(btrim(regexp_replace(translate(btrim(elem->>'nombre_medicamento'),
             'áéíóúüÁÉÍÓÚÜñÑ','aeiouuAEIOUUnN'), '\s+', ' ', 'g'))) AS nn,
           max(ord) AS last_ord
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(elem, ord)
    WHERE btrim(COALESCE(elem->>'nombre_medicamento','')) <> ''
    GROUP BY 1
  ) m;

  FOR r, i IN SELECT value, ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(value, ordinality) LOOP
    -- NOTA: NUNCA se lee r->>'farmacia_id'; el destino es SIEMPRE p_farmacia_id.
    v_nombre := btrim(COALESCE(r->>'nombre_medicamento',''));
    IF v_nombre = '' THEN
      v_rech := v_rech || jsonb_build_object('fila', i, 'motivo', 'nombre_medicamento vacío'); CONTINUE;
    END IF;
    v_nn := upper(btrim(regexp_replace(translate(v_nombre,'áéíóúüÁÉÍÓÚÜñÑ','aeiouuAEIOUUnN'),'\s+',' ','g')));
    IF (v_lastmap->>v_nn) IS NOT NULL AND i <> (v_lastmap->>v_nn)::bigint THEN
      v_rech := v_rech || jsonb_build_object('fila', i, 'motivo', 'duplica clave del archivo; se usó la fila '||(v_lastmap->>v_nn));
      CONTINUE;
    END IF;
    BEGIN
      v_stock  := CASE WHEN COALESCE(btrim(r->>'stock_actual'),'') = '' THEN NULL ELSE (r->>'stock_actual')::numeric END;
      v_precio := CASE WHEN COALESCE(btrim(r->>'precio_unitario'),'') = '' THEN NULL ELSE (r->>'precio_unitario')::numeric END;
      v_fv     := CASE WHEN COALESCE(btrim(r->>'fecha_vencimiento'),'') = '' THEN NULL ELSE (r->>'fecha_vencimiento')::date END;
      v_smin   := CASE WHEN COALESCE(btrim(r->>'stock_minimo'),'') = '' THEN 0 ELSE (r->>'stock_minimo')::int END;
    EXCEPTION WHEN others THEN
      v_rech := v_rech || jsonb_build_object('fila', i, 'motivo', 'valor numérico/fecha inválido'); CONTINUE;
    END;
    v_activo := CASE
      WHEN NOT (r ? 'activo') OR COALESCE(btrim(r->>'activo'),'') = '' THEN NULL
      WHEN lower(btrim(r->>'activo')) IN ('true','1','si','sí','activo') THEN true
      WHEN lower(btrim(r->>'activo')) IN ('false','0','no','inactivo') THEN false
      ELSE NULL END;

    INSERT INTO public.farmacia_medicamentos
      (farmacia_id, nombre_medicamento, presentacion, descripcion, laboratorio,
       stock_actual, stock_minimo, precio_unitario, fecha_vencimiento, activo)
    VALUES
      (p_farmacia_id, v_nombre,
       NULLIF(btrim(COALESCE(r->>'presentacion','')),''),
       NULLIF(btrim(COALESCE(r->>'descripcion','')),''),
       NULLIF(btrim(COALESCE(r->>'laboratorio','')),''),
       COALESCE(v_stock, 0)::int,
       COALESCE(v_smin, 0),
       v_precio, v_fv, COALESCE(v_activo, true))
    ON CONFLICT (farmacia_id, nombre_normalizado) DO UPDATE SET
       stock_actual      = COALESCE(v_stock::int, public.farmacia_medicamentos.stock_actual),
       precio_unitario   = COALESCE(v_precio, public.farmacia_medicamentos.precio_unitario),
       fecha_vencimiento = COALESCE(v_fv, public.farmacia_medicamentos.fecha_vencimiento),
       presentacion      = COALESCE(EXCLUDED.presentacion, public.farmacia_medicamentos.presentacion),
       descripcion       = COALESCE(EXCLUDED.descripcion, public.farmacia_medicamentos.descripcion),
       laboratorio       = COALESCE(EXCLUDED.laboratorio, public.farmacia_medicamentos.laboratorio),
       activo            = COALESCE(v_activo, public.farmacia_medicamentos.activo),
       nombre_medicamento = EXCLUDED.nombre_medicamento,
       updated_at        = now()
    RETURNING (xmax = 0) INTO v_inserted;

    IF v_inserted THEN v_ins := v_ins + 1; ELSE v_upd := v_upd + 1; END IF;
  END LOOP;

  RETURN jsonb_build_object('insertadas', v_ins, 'actualizadas', v_upd,
                            'rechazadas', v_rech, 'total_rechazadas', jsonb_array_length(v_rech));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.cargar_catalogo_farmacia(integer, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cargar_catalogo_farmacia(integer, jsonb) TO authenticated, service_role;
