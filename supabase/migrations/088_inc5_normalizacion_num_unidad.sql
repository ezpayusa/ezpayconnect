-- ============================================================
-- INCREMENTO 5 (Frente A) · Normalización (b): unificar espacio número↔unidad
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — NO aplicar sin OK.
-- Decisión Oscar (b): "500 mg" == "500MG". Una columna GENERATED no se altera en
-- sitio → DROP UNIQUE → DROP + re-ADD columna con la nueva expresión.
-- Orden de aplicación: 088 (esta) → MERGE (scripts/088, usa la COLUMNA nueva) → 089
-- (re-CREATE UNIQUE, SOLO post-merge). El UNIQUE NUNCA antes del merge (fallaría).
--
-- ANTI-DRIFT: la normalización vive en UNA función IMMUTABLE `private.norm_med_nombre`
-- usada por (1) la columna generada y (2) el pre-scan de dups del RPC. Una sola fuente.
-- Orden de la normalización (documentado):
--   translate(acentos→base, ñ→n) → colapsar espacios ('\s+'→' ', g) →
--   quitar espacio dígito→letra ('(\d)\s+([A-Za-z])'→'\1\2', g; varios pares por nombre) →
--   btrim (al final) → upper.
-- ============================================================

-- 1) Función única de normalización (IMMUTABLE → usable en columna GENERATED)
CREATE OR REPLACE FUNCTION private.norm_med_nombre(p_nombre text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
  SELECT upper(btrim(
    regexp_replace(
      regexp_replace(
        translate(p_nombre, 'áéíóúüÁÉÍÓÚÜñÑ', 'aeiouuAEIOUUnN'),
      '\s+', ' ', 'g'),                       -- colapsa espacios múltiples/líder/cola a uno
    '(\d)\s+([A-Za-z])', '\1\2', 'g')          -- "500 mg" -> "500mg" (todos los pares núm→unidad)
  ));
$function$;
REVOKE EXECUTE ON FUNCTION private.norm_med_nombre(text) FROM PUBLIC;
-- authenticated la necesita: la columna GENERATED se evalúa con privilegios del que
-- inserta/actualiza (altas/ediciones de farmacia). service_role para el RPC/owner.
GRANT EXECUTE ON FUNCTION private.norm_med_nombre(text) TO authenticated, service_role;

-- 2) Re-definir la columna generada (DROP UNIQUE → DROP CHECK → DROP COLUMN → re-ADD)
DROP INDEX IF EXISTS public.farmacia_medicamentos_farm_nombrenorm_uniq;
ALTER TABLE public.farmacia_medicamentos DROP CONSTRAINT IF EXISTS farmacia_medicamentos_nombrenorm_no_vacio;
ALTER TABLE public.farmacia_medicamentos DROP COLUMN IF EXISTS nombre_normalizado;
ALTER TABLE public.farmacia_medicamentos
  ADD COLUMN nombre_normalizado text GENERATED ALWAYS AS (private.norm_med_nombre(nombre_medicamento)) STORED;
ALTER TABLE public.farmacia_medicamentos
  ADD CONSTRAINT farmacia_medicamentos_nombrenorm_no_vacio CHECK (nombre_normalizado <> '');
-- (UNIQUE se re-crea en 089, SOLO después del MERGE.)

-- 3) RPC cargar_catalogo_farmacia: usar la MISMA función (no expresión inline) en el
--    pre-scan de dups intra-archivo → cero drift con la columna. Resto idéntico a 087.
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

  -- dups intra-archivo: clave normalizada (MISMA función que la columna) → última gana
  SELECT COALESCE(jsonb_object_agg(nn, last_ord), '{}'::jsonb) INTO v_lastmap FROM (
    SELECT private.norm_med_nombre(elem->>'nombre_medicamento') AS nn, max(ord) AS last_ord
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(elem, ord)
    WHERE btrim(COALESCE(elem->>'nombre_medicamento','')) <> ''
    GROUP BY 1
  ) m;

  FOR r, i IN SELECT value, ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(value, ordinality) LOOP
    v_nombre := btrim(COALESCE(r->>'nombre_medicamento',''));
    IF v_nombre = '' THEN
      v_rech := v_rech || jsonb_build_object('fila', i, 'motivo', 'nombre_medicamento vacío'); CONTINUE;
    END IF;
    v_nn := private.norm_med_nombre(v_nombre);
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
       COALESCE(v_stock, 0)::int, COALESCE(v_smin, 0),
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
