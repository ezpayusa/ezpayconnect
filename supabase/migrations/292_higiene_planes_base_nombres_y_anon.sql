-- ############################################################################################
-- 292 — higiene de planes_base + anon fuera de los catalogos de planes
-- ############################################################################################
-- Pendiente #8, cabo 3. Recon y dry-run del 14-sep contra la base viva.
--
-- QUE SE ENCONTRO
-- ---------------
-- * planes_base es un catalogo GLOBAL (sin pais_id) y NO la crea ninguna migracion: es anterior al
--   historial (la 043 la omite a proposito). Sus constraints eran solo la PK.
-- * 8 filas con nombres propios. Oscar confirmo que son datos de PRUEBA, no clientes reales.
-- * 'Plan Bronce' (visitador, 29.99 USD) estaba DOS veces, y la visitador 'Dr. Oscar Gutierrez' tambien.
-- * PaisesPage.tsx copia a planes_configuracion TODA fila con activo=true. Hasta hoy el unico pais
--   creado desde esa pantalla es ZZ (DEMO); los paises reales no recibieron estas filas. El fix del
--   replicador va aparte, despues de verificar esta migracion.
-- * `anon` tenia los 7 privilegios de tabla sobre las 4 tablas de planes (el ACL default de
--   Supabase, igual que en la 284) y, por las policies {public}, LEIA sin sesion 15 filas de
--   planes_base — entre ellas dos de los nombres propios. Oscar confirmo que ninguna pantalla sin
--   sesion lo necesita.
--
-- QUE HACE
-- --------
--   (a) los 8 nombres propios pasan a 'Plan Demo 1'..'Plan Demo 8'
--   (b) la 'Plan Bronce' duplicada (d75955b5) se desactiva y se renombra
--   (c) UNIQUE (tipo, nombre) en planes_base
--   (e) se borra la config huerfana (pais_id NULL)
--   (f) las policies de proveedores pasan de {public} a {authenticated}; la de planes_base suma 'otros'
--   (g) anon pierde todo privilegio sobre las 4 tablas
--   (h) la migracion se ejercita a si misma con anon y authenticated y aborta si no quedo como dice
--
-- QUE **NO** HACE
-- ---------------
-- * No toca los PRECIOS ni los duplicados de planes_configuracion en paises reales. Es otro problema
--   —precios de produccion, no nombres ni seguridad— y va como un cabo nuevo aparte. Las letras no
--   se renumeraron para que cuadren con el dry-run.
-- * No retipa 'Empresas Afines Básico' / 'Empresas Afines Pro' (tipo 'otros'): se amplia la policy.
--
-- POR QUE ACA SI SE PUEDE REVOCAR EL SELECT DE anon (Y EN LA 284 NO)
-- ------------------------------------------------------------------
-- La 284 rompio prod porque 36 policies de 29 tablas consultaban `perfiles` en su USING: sin el
-- SELECT, anon recibia 42501 en tablas que si le correspondian. Aca se midio lo mismo el 14-sep:
--   * policies de OTRAS tablas que consulten estas 4 en USING/WITH CHECK: 0.
--   * la unica dependencia es interna: la policy de planes_configuracion consulta planes_base, y
--     anon pierde las dos a la vez.
--   * vistas que dependan de estas 4: 0.
--   * funciones que las leen: solo public.auto_configurar_planes_publicidad, SECURITY DEFINER (corre
--     como dueno; el revoke no la toca).
-- El JOIN a planes_base que citaban 061_limite_visitas_plan.sql y 116_visitas_bucket_pvc.sql YA NO
-- EXISTE en la base viva: trg_limite_visitas_mes fue dropeada, y estado_plan_visitas /
-- get_planes_visitador_proveedor fueron reescritas y hoy leen planes_visitador_contratados.
-- ############################################################################################


-- ------------------------------------------------------------------------------------------
-- (a) Los 8 nombres propios pasan a genericos. Solo cambia `nombre`: tipo, precio_base, moneda,
--     periodicidad y activo quedan como estan. El nombre viejo vive en este comentario, no en la base.
-- ------------------------------------------------------------------------------------------
-- Cada UPDATE exige el id COMPLETO y el nombre ACTUAL, y aborta si no toca exactamente 1 fila: si
-- alguien renombro la fila entre el recon y el apply, la migracion se detiene en vez de pisar.
DO $$
DECLARE r record; n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    -- id                                          nombre viejo                    nombre nuevo
    ('ce9e9fb2-77f9-4929-a472-422ffa097d2d'::uuid, 'Dr. Oscar Gutierrez',          'Plan Demo 1'), -- lab, 120.00 GTQ, activo
    ('591e272c-c8f2-42d5-9452-9cb19222e2b9'::uuid, 'Farmacia Ardavin',             'Plan Demo 2'), -- publicidad, 100.00 USD, inactivo
    ('48d23984-fdf4-4757-84e2-d6f7776387e0'::uuid, 'Farmacia Moderna',             'Plan Demo 3'), -- publicidad, 200.00 USD, activo
    ('a072e874-8f41-4a6c-8160-a749b6be82a9'::uuid, 'Vitacoco',                     'Plan Demo 4'), -- publicidad, 100.00 USD, activo
    ('7ad01fbb-e7f5-46fc-86b6-598306e43b8d'::uuid, 'Dr. Oscar Gutierrez',          'Plan Demo 5'), -- visitador, 100.00 USD, inactivo
    ('a79c543a-5d02-49aa-941e-474fac263fd3'::uuid, 'Dr. Oscar Gutierrez',          'Plan Demo 6'), -- visitador, 10.00 GTQ, inactivo
    ('72325040-8814-46c1-ac12-05f794ca7c91'::uuid, 'Plan QA Prueba (2 medicos)',   'Plan Demo 7'), -- visitador, 29.99 USD, inactivo
    ('ec092d7c-2df6-4479-abe8-56b764e8b07d'::uuid, 'Visitador Juan Solis',         'Plan Demo 8')  -- visitador, 100.00 USD, inactivo
  ) AS t(id, viejo, nuevo)
  LOOP
    UPDATE public.planes_base SET nombre = r.nuevo WHERE id = r.id AND nombre = r.viejo;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 1 THEN
      RAISE EXCEPTION '292(a): se esperaba renombrar 1 fila % (%), se tocaron %', r.id, r.viejo, n;
    END IF;
  END LOOP;
END $$;


-- ------------------------------------------------------------------------------------------
-- (b) La 'Plan Bronce' duplicada: se desactiva d75955b5, queda activa d1a9917e
-- ------------------------------------------------------------------------------------------
-- Las dos tenian EXACTAMENTE las mismas dependencias (medido 14-sep): 1 config en ZZ cada una
-- (d1a9917e -> def05b0b, d75955b5 -> 09118ccc), y 0 planes_asignaciones, 0 planes_excepciones,
-- 0 planes_historial, 0 transacciones, 0 planes_features, 0 planes_limites. Se desactiva d75955b5
-- porque su descripcion es 'Solo para prueba' y se creo 25 minutos DESPUES (00:44:05 contra
-- 00:19:40 del 21-jul): es la copia.
--
-- TAMBIEN SE RENOMBRA, y no es opcional: desactivar no libera el nombre. Con las dos filas en
-- ('visitador', 'Plan Bronce'), el UNIQUE (tipo, nombre) de la letra (c) no se puede crear aunque
-- una este inactiva.
--
-- NO se toca su config 09118ccc de ZZ, que queda activo=true apuntando a una base inactiva.
DO $$
DECLARE n int;
BEGIN
  UPDATE public.planes_base
     SET activo = false, nombre = 'Plan Bronce (duplicado)'
   WHERE id = 'd75955b5-abe4-49f9-8b12-13a1cd3570b9' AND nombre = 'Plan Bronce' AND tipo = 'visitador';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION '292(b): se esperaba desactivar 1 Plan Bronce (d75955b5), se tocaron %', n;
  END IF;
END $$;


-- ------------------------------------------------------------------------------------------
-- (c) UNIQUE (tipo, nombre) en planes_base
-- ------------------------------------------------------------------------------------------
-- Antes de crearlo se verifica que no quede ningun duplicado. Si queda alguno, el mensaje lo NOMBRA:
-- un "could not create unique index" a secas no dice que fila sobra.
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(format('(%s, %s) x%s', tipo, nombre, c), '; ') INTO v
    FROM (SELECT tipo, nombre, count(*) c FROM public.planes_base GROUP BY tipo, nombre HAVING count(*) > 1) d;
  IF v IS NOT NULL THEN
    RAISE EXCEPTION '292(c): quedan duplicados de (tipo, nombre) que rompen el UNIQUE: %', v;
  END IF;
END $$;

ALTER TABLE public.planes_base
  ADD CONSTRAINT planes_base_tipo_nombre_key UNIQUE (tipo, nombre);


-- ------------------------------------------------------------------------------------------
-- (e) La config huerfana (pais_id NULL) de 'Plan QA Prueba (2 medicos)', ahora 'Plan Demo 7'
-- ------------------------------------------------------------------------------------------
-- Medido: 0 planes_asignaciones (la unica FK con ON DELETE RESTRICT), 0 excepciones, 0 historial.
DO $$
DECLARE n int;
BEGIN
  DELETE FROM public.planes_configuracion
   WHERE id = 'fcca1183-b7cc-493b-8d8a-91a9d8e98410'
     AND pais_id IS NULL
     AND plan_base_id = '72325040-8814-46c1-ac12-05f794ca7c91';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION '292(e): se esperaba borrar 1 config huerfana (fcca1183), se borraron %', n;
  END IF;
END $$;


-- ------------------------------------------------------------------------------------------
-- (f) Las policies de proveedores: de {public} a {authenticated}; planes_base suma 'otros'
-- ------------------------------------------------------------------------------------------
-- ALTER POLICY y no DROP + CREATE: cambia el TO y el USING en una sola sentencia, conserva nombre,
-- PERMISSIVE y cmd SELECT, y no deja un instante sin policy. Mismo DDL que la 228.
--
-- 'otros' SE SUMA, no reemplaza a 'empresas_afines'. No era un typo: PlanesEmpresasAfinesConfigPage.tsx
-- CREA planes con tipo 'empresas_afines', y src/types/planes.ts declara los dos valores. Lo que se
-- desvio son los datos ('Empresas Afines Básico/Pro' tienen tipo 'otros'), y Oscar decidio no
-- retiparlos. La lista queda con los siete.
--
-- USING de planes_base ANTES (medido 14-sep, pg_policies.qual, literal):
--   ((activo = true) AND ((tipo)::text = ANY ((ARRAY['visitador'::character varying,
--   'publicidad'::character varying, 'farmacia'::character varying, 'farmaceutico'::character varying,
--   'empresas_afines'::character varying, 'medico'::character varying])::text[])))
ALTER POLICY "Proveedores ven planes disponibles" ON public.planes_base
  TO authenticated
  USING (
    activo = true
    AND tipo IN ('visitador', 'publicidad', 'farmacia', 'farmaceutico', 'empresas_afines', 'medico', 'otros')
  );

-- planes_configuracion: SOLO cambia el TO. Su USING no se toca.
-- OJO, medido: esta policy TAMBIEN filtra por la lista de tipos — la consulta sobre planes_base con
-- la misma lista de seis, sin 'otros'. Despues de esta migracion las dos listas DIFIEREN. Hoy no
-- cambia nada para nadie: authenticated ademas tiene "Allow read planes_configuracion" USING true, y
-- las permisivas se combinan con OR. Pasa a importar el dia que esa policy se ajuste.
ALTER POLICY "Proveedores ven configuraciones de planes" ON public.planes_configuracion
  TO authenticated;


-- ------------------------------------------------------------------------------------------
-- (g) anon sin ningun privilegio sobre las 4 tablas de planes
-- ------------------------------------------------------------------------------------------
-- A authenticated no se le toca nada. planes_publicidad y planes_publicidad_config conservan sus
-- policies {public}; sin el grant, anon ya no llega a evaluarlas.
REVOKE ALL ON public.planes_base              FROM anon;
REVOKE ALL ON public.planes_configuracion     FROM anon;
REVOKE ALL ON public.planes_publicidad        FROM anon;
REVOKE ALL ON public.planes_publicidad_config FROM anon;


-- ------------------------------------------------------------------------------------------
-- (h) La migracion se EJERCITA a si misma y ABORTA si no quedo como dice
-- ------------------------------------------------------------------------------------------
-- Leccion de la 284: el catalogo dice quien tiene que, no que pasa cuando se usa. Por eso, ademas
-- del censo de privilegios y de policies, se hace el SELECT de verdad con cada rol.
--   anon          -> las 4 tablas tienen que responder 42501. Cualquier otra cosa, incluido "0 filas
--                    sin error", significa que todavia tiene acceso y la RLS lo estaba tapando.
--   authenticated -> las 4 tablas responden sin error y con filas, y el JOIN
--                    planes_configuracion <-> planes_base sigue andando. Ese JOIN es la dependencia
--                    real: la policy de planes_configuracion consulta planes_base en su USING.
-- Contraprobado en el dry-run del 14-sep: sin el REVOKE de planes_base, este bloque aborta con
-- "292(h): anon conserva privilegios: planes_base:SELECT, ...".
-- El detalle queda en `mig292.h`, un setting local a la transaccion que muere con el COMMIT.
DO $$
DECLARE t text; n bigint; v_res text := ''; v_err text; v_priv text;
BEGIN
  -- Censo de privilegios (lo que la 284 hace a secas).
  SELECT string_agg(format('%s:%s', tb, p), ', ') INTO v_priv
    FROM unnest(ARRAY['planes_base','planes_configuracion','planes_publicidad','planes_publicidad_config']) tb,
         unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
   WHERE has_table_privilege('anon', 'public.'||tb, p);
  IF v_priv IS NOT NULL THEN
    RAISE EXCEPTION '292(h): anon conserva privilegios: %', v_priv;
  END IF;

  SELECT string_agg(tb, ', ') INTO v_priv
    FROM unnest(ARRAY['planes_base','planes_configuracion','planes_publicidad','planes_publicidad_config']) tb
   WHERE NOT has_table_privilege('authenticated', 'public.'||tb, 'SELECT');
  IF v_priv IS NOT NULL THEN
    RAISE EXCEPTION '292(h): la 292 se paso — authenticated perdio SELECT sobre: %', v_priv;
  END IF;

  -- Censo de la letra (f): roles y la lista ampliada.
  IF (SELECT roles::text FROM pg_policies WHERE schemaname='public' AND tablename='planes_base'
        AND policyname='Proveedores ven planes disponibles') IS DISTINCT FROM '{authenticated}'
  OR (SELECT roles::text FROM pg_policies WHERE schemaname='public' AND tablename='planes_configuracion'
        AND policyname='Proveedores ven configuraciones de planes') IS DISTINCT FROM '{authenticated}' THEN
    RAISE EXCEPTION '292(h): alguna policy de proveedores no quedo en {authenticated}';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='planes_base'
                  AND policyname='Proveedores ven planes disponibles'
                  AND qual LIKE '%''otros''%' AND qual LIKE '%''empresas_afines''%' AND qual LIKE '%''medico''%') THEN
    RAISE EXCEPTION '292(h): la policy de planes_base no quedo con la lista ampliada (otros + las seis previas)';
  END IF;

  -- Ejercicio real: anon.
  FOREACH t IN ARRAY ARRAY['planes_base','planes_configuracion','planes_publicidad','planes_publicidad_config'] LOOP
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
      PERFORM set_config('role', 'anon', true);
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
      PERFORM set_config('role', 'none', true);
      RAISE EXCEPTION '292(h): anon LEE public.% (% filas) — el revoke no corto el acceso', t, n;
    EXCEPTION
      WHEN insufficient_privilege THEN
        PERFORM set_config('role', 'none', true);
        v_res := v_res || format('anon %s: 42501; ', t);
    END;
  END LOOP;

  -- Ejercicio real: authenticated.
  FOREACH t IN ARRAY ARRAY['planes_base','planes_configuracion','planes_publicidad','planes_publicidad_config'] LOOP
    v_err := NULL;
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
      PERFORM set_config('role', 'authenticated', true);
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
      PERFORM set_config('role', 'none', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('role', 'none', true);
      v_err := SQLSTATE || ' ' || SQLERRM;
    END;
    IF v_err IS NOT NULL THEN
      RAISE EXCEPTION '292(h): authenticated ya no puede leer public.%: %', t, v_err;
    END IF;
    IF n = 0 THEN
      RAISE EXCEPTION '292(h): authenticated lee public.% sin error pero con 0 filas — la RLS se cerro de mas', t;
    END IF;
    v_res := v_res || format('authenticated %s: %s filas; ', t, n);
  END LOOP;

  -- La dependencia: la policy de planes_configuracion consulta planes_base.
  v_err := NULL;
  BEGIN
    PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
    PERFORM set_config('role', 'authenticated', true);
    SELECT count(*) INTO n FROM public.planes_configuracion pc JOIN public.planes_base pb ON pb.id = pc.plan_base_id;
    PERFORM set_config('role', 'none', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    v_err := SQLSTATE || ' ' || SQLERRM;
  END;
  IF v_err IS NOT NULL OR n = 0 THEN
    RAISE EXCEPTION '292(h): authenticated rompio el JOIN planes_configuracion<->planes_base: %', coalesce(v_err, '0 filas');
  END IF;
  v_res := v_res || format('authenticated JOIN config<->base: %s filas', n);

  PERFORM set_config('mig292.h', 'OK — ' || v_res, true);
END $$;
