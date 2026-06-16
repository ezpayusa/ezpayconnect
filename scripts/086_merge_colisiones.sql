-- ============================================================
-- PASO INTERMEDIO de Inc.5 · Merge product-level de colisiones de seed
-- ------------------------------------------------------------
-- ⚠️ Correr DESPUÉS de 086 (que crea la columna generada `nombre_normalizado`) y
-- ANTES de 087 (que crea el UNIQUE). Agrupa por la COLUMNA `nombre_normalizado`
-- (NO una expresión inline) → byte-idéntico al UNIQUE por construcción.
-- Es SEED/QA (4 grupos). Decisión Oscar: product-level → suma stock + fecha más
-- próxima (min) + lote=NULL. NO automático: revisar PREVIEW, luego correr MERGE.
-- ============================================================

-- ---- PREVIEW (no muta) ----  (id es uuid → sobreviviente por created_at, no min(id))
SELECT farmacia_id, nombre_normalizado AS nn,
       count(*) AS filas,
       (array_agg(id ORDER BY created_at NULLS FIRST, id::text))[1] AS sobreviviente_id,
       sum(stock_actual) AS stock_sumado,
       min(fecha_vencimiento) AS fecha_mas_proxima,
       array_agg(id::text ORDER BY created_at NULLS FIRST, id::text) AS ids_grupo
FROM public.farmacia_medicamentos
GROUP BY farmacia_id, nombre_normalizado
HAVING count(*) > 1
ORDER BY farmacia_id, nombre_normalizado;

-- ---- MERGE (mutación; correr SOLO tras revisar el PREVIEW y con OK) ----
-- BEGIN;
-- WITH grupos AS (
--   SELECT farmacia_id, nombre_normalizado AS nn,
--          (array_agg(id ORDER BY created_at NULLS FIRST, id::text))[1] AS keep_id,
--          sum(stock_actual) AS stock_sum, min(fecha_vencimiento) AS fv_min
--   FROM public.farmacia_medicamentos
--   GROUP BY farmacia_id, nombre_normalizado HAVING count(*) > 1
-- ),
-- upd AS (
--   UPDATE public.farmacia_medicamentos fm
--   SET stock_actual = g.stock_sum, fecha_vencimiento = g.fv_min, lote = NULL, updated_at = now()
--   FROM grupos g WHERE fm.id = g.keep_id
--   RETURNING fm.id
-- )
-- DELETE FROM public.farmacia_medicamentos fm
-- USING grupos g
-- WHERE fm.farmacia_id = g.farmacia_id AND fm.nombre_normalizado = g.nn AND fm.id <> g.keep_id;
-- COMMIT;

-- ---- VERIFICACIÓN post-merge (debe dar 0) ----
-- SELECT count(*) AS grupos_restantes FROM (
--   SELECT 1 FROM public.farmacia_medicamentos
--   GROUP BY farmacia_id, nombre_normalizado HAVING count(*) > 1
-- ) x;
