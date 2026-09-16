-- ############################################################################################
-- 294 — medicos: se cierra la lectura de `anon` y el cruce entre paises de `authenticated`
-- ############################################################################################
-- EL HALLAZGO (recon 16-sep-2026 contra prod)
-- -------------------------------------------
-- `public.medicos` tenia TRES policies de SELECT con `USING (true)` que NO estaban en ninguna
-- migracion del repo — nacieron fuera de git:
--     medicos_select                     TO PUBLIC
--     "Allow anon read medicos"          TO anon
--     "Allow authenticated read medicos" TO authenticated
-- Las policies PERMISSIVE se combinan con OR, asi que esas tres ANULABAN el scoping por pais de las
-- que si estan versionadas (`Medico ve su perfil` de la 027, `Paciente ve medicos de su pais` de la
-- 028, y la FOR ALL `Admin ve medicos de su pais`). Efecto medido: cualquier `authenticated` leia
-- TODAS las columnas de TODOS los medicos de TODOS los paises, y `anon` leia 7 columnas por el GRANT
-- de columna de la mig 073 (id, nombre_completo, especialidad, foto_url, clinica_id, pais_id, activo),
-- sin un solo consumidor en el repo.
--
-- Esta migracion es la PRIMERA fuente de verdad de esas tres policies: las versiona borrandolas.
--
-- QUE SE CONSERVA, Y POR QUE HAY UNA POLICY NUEVA
-- -----------------------------------------------
-- El unico consumidor real que quedaba cubierto SOLO por la policy abierta es
-- src/proveedor/pages/visitador/VisitadorDetallePage.tsx (ruta autenticada del portal de proveedor),
-- que hace select('id, nombre_completo').in('id', ids). Decision de negocio: el proveedor ve medicos
-- de SU MISMO PAIS, mismo espiritu que `Paciente ve medicos de su pais`. Fail-closed: si el pais no
-- matchea, no hay fila.
--
-- DE DONDE SALE EL PAIS DEL PROVEEDOR (medido, no asumido)
-- --------------------------------------------------------
-- NO se puede usar `cuentas_proveedor.pais_id` a secas: esta en NULL en 19 de 28 filas, y 18 cuentas
-- activas tienen un pais_id DISTINTO al de su empresa. Scopear por esa columna dejaria ciegos a casi
-- todos los proveedores. Se usa la misma precedencia que ya usa `private.mi_pais()` (COALESCE de la
-- cuenta y despues la empresa), que es la respuesta canonica del proyecto a "mi pais".
-- Control positivo medido: las 4 cuentas de proveedor que HOY tienen visitas resuelven a GT
-- (cbbbbe6d), incluida una con pais_id de cuenta NULL que cae al de la empresa, y los 2 medicos de
-- esas visitas tambien son de GT. O sea: VisitadorDetallePage sigue funcionando.
--
-- El helper es SECURITY DEFINER a proposito. Una policy se evalua con los privilegios del LLAMANTE
-- (leccion de la mig 284): un EXISTS inline contra cuentas_proveedor/empresas_proveedoras ataria esta
-- policy a los privilegios y a la RLS de esas dos tablas. Con DEFINER, la pregunta es el HECHO.
-- ############################################################################################

-- 1) Las tres policies abiertas. `IF EXISTS` porque nunca estuvieron en el repo: esta migracion tiene
--    que poder aplicarse sobre una base donde no existan.
DROP POLICY IF EXISTS "Allow anon read medicos" ON public.medicos;
DROP POLICY IF EXISTS medicos_select ON public.medicos;
DROP POLICY IF EXISTS "Allow authenticated read medicos" ON public.medicos;

-- 2) `anon` deja de tener columnas. El GRANT de columna de la 073 sobrevivia sin consumidor: con la
--    policy abierta era lectura real de un directorio de medicos sin sesion.
REVOKE SELECT (id, nombre_completo, especialidad, foto_url, clinica_id, pais_id, activo)
  ON public.medicos FROM anon;
REVOKE SELECT ON public.medicos FROM anon;

-- 3) El pais del proveedor autenticado. NULL si no es una cuenta de proveedor activa -> la policy
--    no matchea (comparar con NULL da NULL, no true) -> fail-closed.
CREATE OR REPLACE FUNCTION private.pais_de_proveedor()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $fn$
  SELECT COALESCE(cp.pais_id, e.pais_id)
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo IS TRUE
   LIMIT 1;
$fn$;

-- Supabase concede EXECUTE por default privileges: hay que revocar explicito y volver a conceder solo
-- lo que corresponde (mismo gotcha documentado en la mig 232).
REVOKE ALL ON FUNCTION private.pais_de_proveedor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.pais_de_proveedor() TO authenticated;

-- 4) La policy del proveedor. `pais_id IS NOT NULL` explicito: los 8 medicos que hoy tienen pais NULL
--    no son de nadie, y con la comparacion sola ya quedarian afuera — se escribe para que se lea.
DROP POLICY IF EXISTS "Proveedor ve medicos de su pais" ON public.medicos;
CREATE POLICY "Proveedor ve medicos de su pais" ON public.medicos
  FOR SELECT TO authenticated
  USING (
    pais_id IS NOT NULL
    AND pais_id = private.pais_de_proveedor()
  );

-- 5) Re-verificacion: la migracion comprueba lo que dejo y ABORTA si no quedo asi.
DO $$
DECLARE v text; n int;
BEGIN
  SELECT string_agg(polname, ', ') INTO v FROM pg_policy
   WHERE polrelid='public.medicos'::regclass
     AND polname IN ('Allow anon read medicos','medicos_select','Allow authenticated read medicos');
  IF v IS NOT NULL THEN RAISE EXCEPTION '294: sobreviven policies abiertas: %', v; END IF;

  SELECT count(*) INTO n FROM information_schema.column_privileges
   WHERE table_schema='public' AND table_name='medicos' AND grantee='anon' AND privilege_type='SELECT';
  IF n <> 0 THEN RAISE EXCEPTION '294: anon conserva SELECT sobre % columnas de medicos', n; END IF;
  IF has_table_privilege('anon','public.medicos','SELECT') THEN
    RAISE EXCEPTION '294: anon conserva SELECT a nivel tabla sobre medicos';
  END IF;

  -- Las cuatro que NO se tocan. Si alguna falta, el DROP se llevo algo que no debia.
  SELECT string_agg(p, ', ') INTO v FROM unnest(ARRAY['Medico ve su perfil','Paciente ve medicos de su pais',
        'Admin ve medicos de su pais','medicos_admin_clinica']) p
   WHERE NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.medicos'::regclass AND polname = p);
  IF v IS NOT NULL THEN RAISE EXCEPTION '294: falta una policy que NO se debia tocar: %', v; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='medicos'
                  AND policyname='Proveedor ve medicos de su pais' AND roles::text='{authenticated}') THEN
    RAISE EXCEPTION '294: la policy del proveedor no quedo, o no quedo en {authenticated}';
  END IF;

  IF has_function_privilege('anon','private.pais_de_proveedor()','EXECUTE')
     OR NOT has_function_privilege('authenticated','private.pais_de_proveedor()','EXECUTE') THEN
    RAISE EXCEPTION '294: privilegios mal en private.pais_de_proveedor()';
  END IF;
END $$;
