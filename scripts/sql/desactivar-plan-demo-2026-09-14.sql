-- Pendiente #8, cabo 3 — medida de seguridad: desactivar los 3 'Plan Demo' que quedaron activos.
--
-- La mig 292 renombro los planes de prueba pero tres seguian con activo=true, y PaisesPage.tsx copia
-- a planes_configuracion TODA fila activa de planes_base. Sin esto, el proximo pais creado desde esa
-- pantalla los recibe, igual que los recibio ZZ. Va aparte de la mig 293 (flag replicable_por_pais)
-- porque es urgente y no depende de ella.
--
-- No es una migracion de esquema: es un cambio de datos puntual. No toca planes_configuracion — las
-- configs de ZZ de estos tres planes quedan como estan.
--
-- Ids medidos el 14-sep:
--   ce9e9fb2-77f9-4929-a472-422ffa097d2d  Plan Demo 1  lab         120.00 GTQ  (ex 'Dr. Oscar Gutierrez')
--   48d23984-fdf4-4757-84e2-d6f7776387e0  Plan Demo 3  publicidad  200.00 USD  (ex 'Farmacia Moderna')
--   a072e874-8f41-4a6c-8160-a749b6be82a9  Plan Demo 4  publicidad  100.00 USD  (ex 'Vitacoco')
DO $$
DECLARE n int;
BEGIN
  UPDATE public.planes_base
     SET activo = false
   WHERE id IN ('ce9e9fb2-77f9-4929-a472-422ffa097d2d',
                '48d23984-fdf4-4757-84e2-d6f7776387e0',
                'a072e874-8f41-4a6c-8160-a749b6be82a9')
     AND nombre IN ('Plan Demo 1', 'Plan Demo 3', 'Plan Demo 4')
     AND activo = true;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 3 THEN
    RAISE EXCEPTION 'desactivar Plan Demo: se esperaban 3 filas, se tocaron %', n;
  END IF;
END $$;
