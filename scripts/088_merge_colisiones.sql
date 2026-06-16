-- ============================================================
-- INCREMENTO 5 (Frente A) · MERGE de colisiones tras normalización (b)
-- ------------------------------------------------------------
-- ⚠️ Correr SOLO con OK, ENTRE 088 (columna re-definida, SIN UNIQUE) y 089 (re-CREATE
-- UNIQUE). Usa la COLUMNA nombre_normalizado (ya con la nueva regla) → byte-idéntico al
-- futuro UNIQUE. Sobreviviente determinista (created_at NULLS FIRST, id::text). Suma
-- stock, fecha más próxima, lote a NULL. Mismo patrón que scripts/086_merge.
--
-- Re-análisis no-mutante (normalización b) sobre los datos actuales: 0 grupos de
-- colisión → este MERGE es NO-OP (0 filas tocadas). Se conserva por completitud de la
-- secuencia; si en el futuro entran datos que colisionen, este script los resuelve.
-- ============================================================
WITH grupos AS (
  SELECT farmacia_id, nombre_normalizado,
         (array_agg(id ORDER BY created_at NULLS FIRST, id::text))[1] AS sobreviviente,
         sum(COALESCE(stock_actual,0))::int AS stock_sumado,
         min(fecha_vencimiento) AS fecha_min
  FROM public.farmacia_medicamentos
  GROUP BY farmacia_id, nombre_normalizado
  HAVING count(*) > 1
),
upd AS (
  UPDATE public.farmacia_medicamentos m
     SET stock_actual = g.stock_sumado,
         fecha_vencimiento = g.fecha_min,
         lote = NULL,
         updated_at = now()
  FROM grupos g
  WHERE m.id = g.sobreviviente
  RETURNING m.id
)
DELETE FROM public.farmacia_medicamentos d
USING grupos g
WHERE d.farmacia_id = g.farmacia_id
  AND d.nombre_normalizado = g.nombre_normalizado
  AND d.id <> g.sobreviviente;
