-- ============================================================
-- INCREMENTO 5 (Frente A) · Re-CREATE UNIQUE tras normalización (b)
-- ------------------------------------------------------------
-- ⚠️ APLICAR SOLO DESPUÉS de 088 + MERGE (scripts/088_merge_colisiones.sql).
-- El UNIQUE NUNCA antes del merge: si quedara una colisión bajo la nueva norma, fallaría.
-- Re-análisis (no-mutante) previo al MERGE: 0 colisiones → el merge fue no-op y este
-- índice se crea limpio. Mismo nombre/forma que 087 (sobre la columna re-definida).
-- ============================================================
CREATE UNIQUE INDEX IF NOT EXISTS farmacia_medicamentos_farm_nombrenorm_uniq
  ON public.farmacia_medicamentos (farmacia_id, nombre_normalizado);
