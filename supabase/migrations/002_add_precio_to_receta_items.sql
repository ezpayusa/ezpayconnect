-- Agregar precio_unitario y stock_actual a receta_items
-- para guardar la información del proveedor seleccionado

ALTER TABLE IF EXISTS receta_items
ADD COLUMN IF NOT EXISTS precio_unitario NUMERIC(10,2),
ADD COLUMN IF NOT EXISTS stock_actual INTEGER;
