-- ============================================================
-- 066 · Realtime para la bandeja del laboratorio: que las nuevas
--       órdenes (examenes/ordenes_examen) lleguen sin refrescar.
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'examenes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE examenes;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ordenes_examen'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE ordenes_examen;
  END IF;
END $$;
