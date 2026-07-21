-- FK faltante: el embed PostgREST recetas(...,receta_items(...)) de la webapp del paciente fallaba
-- con "Could not find a relationship". La columna receta_items.receta_id (bigint) existia sin constraint.
-- ON DELETE CASCADE: al borrar una receta se borran sus items (modelo logico ya asumido por la app).
ALTER TABLE public.receta_items
  ADD CONSTRAINT receta_items_receta_id_fkey
  FOREIGN KEY (receta_id) REFERENCES public.recetas(id) ON DELETE CASCADE;
