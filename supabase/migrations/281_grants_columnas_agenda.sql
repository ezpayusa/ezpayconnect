-- ############################################################################################
-- 281 — GRANT de las 3 columnas que agrego la 280 y se quedaron sin privilegio
-- ############################################################################################
-- EL BUG
-- ------
-- Desde la mig 277, `authenticated` NO tiene SELECT de tabla entera sobre visitas_comerciales:
-- tiene SELECT columna por columna, para dejar afuera las de coordenada. La 280 agrego tres
-- columnas nuevas (hora_planificada, planificada_por, cancelacion_motivo) y no las incluyo en
-- ningun GRANT.
--
-- Consecuencia: cualquier SELECT que las pida devuelve 403 / 42501. Y como el front pide una lista
-- EXPLICITA de columnas que ahora las incluye, se rompio TODA la lectura de visitas — no solo la
-- agenda. Un ALTER TABLE ADD COLUMN sobre una tabla con grants por columna es un cambio de
-- privilegios disfrazado de cambio de esquema.
--
-- Medido antes de escribir esto: 26 columnas, 4 de coordenada, 19 con grant, y exactamente estas
-- 3 sin grant. Ninguna otra falta, y las 4 de coordenada siguen revocadas (la 277, intacta).
-- `jornadas_comerciales` no tiene el problema: la 280 no le agrego columnas.
--
-- El censo P599 que acompana a esta migracion existe para que el proximo ALTER TABLE se ponga
-- rojo solo, en vez de descubrirse en el navegador como este.
-- ############################################################################################

-- Idempotente: un GRANT repetido no falla ni duplica.
GRANT SELECT (hora_planificada, planificada_por, cancelacion_motivo)
  ON public.visitas_comerciales TO authenticated;

-- Re-verificacion: las 3 quedaron legibles Y ninguna de coordenada se colo.
DO $$
DECLARE v_faltan text; v_coord text;
BEGIN
  SELECT string_agg(c, ', ') INTO v_faltan
    FROM unnest(ARRAY['hora_planificada','planificada_por','cancelacion_motivo']) c
   WHERE NOT EXISTS (
     SELECT 1 FROM information_schema.column_privileges
      WHERE table_schema='public' AND table_name='visitas_comerciales'
        AND grantee='authenticated' AND privilege_type='SELECT' AND column_name = c);
  IF v_faltan IS NOT NULL THEN
    RAISE EXCEPTION 'el GRANT no quedo en: %', v_faltan;
  END IF;

  SELECT string_agg(column_name, ', ') INTO v_coord
    FROM information_schema.column_privileges
   WHERE table_schema='public' AND table_name='visitas_comerciales'
     AND grantee='authenticated' AND privilege_type='SELECT'
     AND (column_name LIKE '%\_lat' OR column_name LIKE '%\_lng');
  IF v_coord IS NOT NULL THEN
    RAISE EXCEPTION 'esta migracion abrio columnas de coordenada: %', v_coord;
  END IF;
END $$;
