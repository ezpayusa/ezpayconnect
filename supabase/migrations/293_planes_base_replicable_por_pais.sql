-- ############################################################################################
-- 293 — planes_base.replicable_por_pais: que filas copia PaisesPage a un pais nuevo
-- ############################################################################################
-- Pendiente #8, cabo 3, ultimo tramo. Recon del 14-sep contra la base viva.
--
-- EL PROBLEMA
-- -----------
-- PaisesPage.tsx (handleCrearPais) copia a planes_configuracion TODA fila de planes_base con
-- activo=true. Asi llegaron a ZZ (DEMO) planes de prueba con nombres propios y un plan duplicado.
--
-- POR QUE UN FLAG POR FILA Y NO UNA LISTA DE TIPOS
-- ------------------------------------------------
-- Medido: los 8 tipos que existen (clinica, farmaceutico, farmacia, lab, medico, otros, publicidad,
-- visitador) tienen configs en paises reales Y transacciones. Ninguno es un catalogo transversal.
-- Los planes que contaminaron ZZ eran de tipo lab, publicidad y visitador — tipos legitimamente por
-- pais —, asi que una lista de tipos o no filtraba nada o dejaba afuera planes que si se venden.
-- El problema es de FILA: el catalogo mezcla planes comerciales estandar con planes puntuales.
--
-- DEFAULT false, A PROPOSITO: un plan nuevo no se replica solo. Hay que marcarlo. Hoy es al reves y
-- eso es exactamente lo que fallo.
--
-- EL BACKFILL: los 19 planes activos de hoy
-- -----------------------------------------
-- 22 activos despues de la 292, menos los 3 'Plan Demo' desactivados el mismo 14-sep
-- (scripts/sql/desactivar-plan-demo-2026-09-14.sql) = 19. Oscar los confirmo uno por uno como planes
-- estandar, incluidos Plan Bronce/Plata/Oro (visitador) y Plan Premium (publicidad), que hoy solo
-- tienen config en ZZ. Con este backfill todo lo activo queda replicable; el flag muerde con los
-- planes que se creen de aca en adelante.
--
-- QUE **NO** HACE
-- ---------------
-- No toca planes_configuracion, ni precios, ni moneda_local, ni tasas, ni descuento_porcentaje: eso
-- es el cabo de precios, aparte.
-- ############################################################################################

ALTER TABLE public.planes_base
  ADD COLUMN replicable_por_pais boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.planes_base.replicable_por_pais IS
  'true = PaisesPage lo copia a planes_configuracion al crear un pais. Nace false: un plan nuevo no se replica hasta que alguien lo marque (mig 293).';


-- ------------------------------------------------------------------------------------------
-- Backfill: 19 filas, una por una
-- ------------------------------------------------------------------------------------------
-- Cada UPDATE exige id COMPLETO + tipo + nombre + activo=true, y aborta si no toca exactamente 1
-- fila. Ids resueltos por (tipo, nombre) contra la base el 14-sep, no asumidos.
DO $$
DECLARE r record; n int; total int := 0;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('2a693a62-60ef-4e1e-91b3-677f44e14b25'::uuid, 'clinica',      'Clínica Enterprise'),
    ('7df7cc00-a3ef-4640-b417-2a272c989a2f'::uuid, 'clinica',      'Clínica Starter'),
    ('a8002674-2ab2-489b-9b28-771d16e369e1'::uuid, 'farmaceutico', 'Farmacéutico Básico'),
    ('5cbcff6d-4795-4e90-9605-81c9b89243a8'::uuid, 'farmaceutico', 'Farmacéutico Pro'),
    ('6f4d0c56-e9db-40ae-bb76-685aa1e97c84'::uuid, 'farmacia',     'Farmacia Básico'),
    ('216d151f-c07a-49ff-8eec-7acfb417f3fe'::uuid, 'farmacia',     'Farmacia Pro'),
    ('b104c8e2-5160-4a1a-bca3-fd3a784a76cf'::uuid, 'lab',          'Lab Básico'),
    ('3d8780e4-d4aa-4047-890d-b9655024ebe2'::uuid, 'lab',          'Lab Pro'),
    ('29cb9481-b849-4b52-9fdb-cc4fb493bbe3'::uuid, 'lab',          'Laboratorio/Farmacia'),
    ('eb55e5be-6526-45bc-9edc-6458be78d60c'::uuid, 'medico',       'Médico Básico'),
    ('ca3fd826-854d-4b20-a42c-3f73fff69ec7'::uuid, 'medico',       'Médico Pro'),
    ('e4daa046-7e17-421a-9be9-1c8fa4b84a33'::uuid, 'otros',        'Empresas Afines Básico'),
    ('3f0cd9e6-f409-4f57-9cc6-7abd53adb6c7'::uuid, 'otros',        'Empresas Afines Pro'),
    ('f8ac36ea-de76-4f43-826e-cfbc5763cc93'::uuid, 'publicidad',   'Publicidad Básico'),
    ('1e27d883-9f53-425f-928f-db93878ed25f'::uuid, 'publicidad',   'Publicidad Pro'),
    ('78deb78e-6eb6-44c2-ab1a-0d1520559470'::uuid, 'publicidad',   'Plan Premium'),
    ('d1a9917e-31d5-4002-959e-5c0d3d12b5cd'::uuid, 'visitador',    'Plan Bronce'),
    ('838d9e7d-9fbd-49a6-a2ae-5bf3431efb4b'::uuid, 'visitador',    'Plan Plata'),
    ('0af89fd9-ee3d-411d-84f6-dcd716ba1bac'::uuid, 'visitador',    'Plan Oro')
  ) AS t(id, tipo, nombre)
  LOOP
    UPDATE public.planes_base
       SET replicable_por_pais = true
     WHERE id = r.id AND tipo = r.tipo AND nombre = r.nombre AND activo = true;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 1 THEN
      RAISE EXCEPTION '293: se esperaba marcar 1 fila % (%, %), se tocaron % — o cambio el nombre, o ya no esta activa',
        r.id, r.tipo, r.nombre, n;
    END IF;
    total := total + n;
  END LOOP;
  IF total <> 19 THEN
    RAISE EXCEPTION '293: el backfill toco % filas, se esperaban 19', total;
  END IF;
END $$;


-- ------------------------------------------------------------------------------------------
-- Verificacion: la migracion comprueba lo que dejo, no lo asume
-- ------------------------------------------------------------------------------------------
DO $$
DECLARE n int; v text;
BEGIN
  SELECT count(*) INTO n FROM public.planes_base WHERE replicable_por_pais;
  IF n <> 19 THEN
    RAISE EXCEPTION '293(verif): quedaron % filas con replicable_por_pais=true, se esperaban 19', n;
  END IF;

  SELECT string_agg(nombre, ', ') INTO v FROM public.planes_base
   WHERE nombre IN ('Plan Demo 1', 'Plan Demo 3', 'Plan Demo 4') AND (activo OR replicable_por_pais);
  IF v IS NOT NULL THEN
    RAISE EXCEPTION '293(verif): hay Plan Demo activos o replicables: %', v;
  END IF;
  SELECT count(*) INTO n FROM public.planes_base WHERE nombre IN ('Plan Demo 1', 'Plan Demo 3', 'Plan Demo 4');
  IF n <> 3 THEN
    RAISE EXCEPTION '293(verif): se esperaban 3 Plan Demo (1, 3, 4), hay %', n;
  END IF;

  -- Un plan replicable pero inactivo no rompe nada hoy (PaisesPage filtra por los dos), pero no
  -- deberia existir recien hecho el backfill: si aparece, el backfill marco algo que no correspondia.
  SELECT string_agg(nombre, ', ') INTO v FROM public.planes_base WHERE replicable_por_pais AND NOT activo;
  IF v IS NOT NULL THEN
    RAISE EXCEPTION '293(verif): planes replicables pero inactivos: %', v;
  END IF;

  -- El otro lado: todo lo activo tiene que haber quedado replicable (hoy son el mismo conjunto).
  SELECT string_agg(nombre, ', ') INTO v FROM public.planes_base WHERE activo AND NOT replicable_por_pais;
  IF v IS NOT NULL THEN
    RAISE EXCEPTION '293(verif): planes activos que quedaron fuera del backfill: %', v;
  END IF;
END $$;
