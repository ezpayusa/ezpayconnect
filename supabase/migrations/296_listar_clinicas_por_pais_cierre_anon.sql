-- ############################################################################################
-- 296 — listar_clinicas_por_pais: gate de pais, parametro obligatorio, search_path y cierre de anon
-- ############################################################################################
-- MISMO CRITERIO QUE LAS MIGS 294/295 (medicos). La funcion es SECURITY DEFINER con dueno
-- `postgres`: corre con los privilegios del dueno y **no pasa por la RLS de public.clinicas**. Con
-- EXECUTE abierto a anon, el scoping que esa RLS si tiene ("Admin ve clinicas de su pais",
-- "Paciente ve clinicas de su pais", etc.) quedaba puenteado por completo.
--
-- ESTADO MEDIDO EN PROD EL 17-sep (definicion VIVA, no la del archivo 039 de migrations/):
--
--   CREATE OR REPLACE FUNCTION public.listar_clinicas_por_pais(p_pais_id uuid DEFAULT NULL::uuid)
--    RETURNS TABLE(id uuid, nombre text, pais_id uuid) LANGUAGE plpgsql SECURITY DEFINER
--   AS $function$ BEGIN RETURN QUERY
--     SELECT c.id, c.nombre, c.pais_id FROM clinicas c
--      WHERE p_pais_id IS NULL OR c.pais_id = p_pais_id ORDER BY c.nombre; END; $function$
--
--   proacl    = =X/postgres | postgres=X | anon=X | authenticated=X | service_role=X
--   proconfig = NULL  (SIN search_path)
--
-- EL `DEFAULT NULL` ERA LA MITAD GRAVE DEL HALLAZGO, no el EXECUTE de anon por si solo. El WHERE
-- decia `p_pais_id IS NULL OR ...`, asi que llamarla SIN argumento no devolvia vacio: devolvia la
-- tabla entera, todos los paises. Un POST a /rest/v1/rpc/listar_clinicas_por_pais con body `{}` y
-- la anon key volcaba el padron completo de clinicas sin sesion. Por eso el parametro pasa a ser
-- OBLIGATORIO y la rama `IS NULL OR` desaparece: aunque alguien reabra el EXECUTE por error mas
-- adelante, ya no existe la forma "sin filtro = todo".
--
-- POR QUE SE PUEDE REVOCAR SIN ROMPER NADA (medido, no asumido)
-- -------------------------------------------------------------
-- Barrido de todo el repo (src/, supabase/functions/, api/, scripts/, tests/ y la raiz): la RPC
-- tiene UN solo consumidor, AgendarCitaModal.tsx:198, y siempre pasa `p_pais_id`. Ese modal se
-- monta en WebAppCitas.tsx:189 y WebAppDashboard.tsx:255, las dos bajo /paciente detras de
-- WebAppPrivateRoute, que exige sesion Y fila de paciente. Ninguna pantalla publica, ninguna edge
-- function y ninguna llamada de servidor dependen del EXECUTE de anon.
--
-- POR QUE HAY QUE CALIFICAR `public.clinicas`: el `SET search_path = ''` deja el search_path vacio,
-- asi que el `FROM clinicas` sin esquema del cuerpo actual reventaria con 42P01. Las dos cosas van
-- juntas en la misma sentencia o no van.
--
-- NO se toca service_role: lo usan las edges y el tooling de Supabase, y revocarlo no cierra nada
-- que anon/PUBLIC no cierren ya.
--
-- EL GATE INTERNO: POR QUE TRES RAMAS Y NO UNA
-- --------------------------------------------
-- Sacar a anon no alcanzaba. Al ser SECURITY DEFINER la funcion NO pasa por la RLS de
-- public.clinicas, asi que cualquier `authenticated` podia pasar el pais_id que quisiera y leer las
-- clinicas de otro pais. El gate replica la RLS que la funcion se saltea, con las MISMAS funciones y
-- las MISMAS tablas — no inventa una fuente de verdad nueva:
--
--   a) super_admin                                  <- policy "Admin ve clinicas de su pais", 1a rama
--   b) admin_pais con get_auth_user_pais_id() = p_pais_id   <- misma policy, 2a rama
--   c) EXISTS en public.pacientes por auth_user_id   <- policy "Paciente ve clinicas de su pais", 1a rama
--      OR EXISTS en public.perfiles por id           <- misma policy, 2a rama
--
-- LA RAMA DE `pacientes` NO ES OPCIONAL, Y ESO SE MIDIO. En prod hay 11 pacientes con auth_user_id
-- y los 11 tienen CERO filas en `perfiles`. O sea que para un paciente `get_auth_user_rol()` y
-- `get_auth_user_pais_id()` devuelven NULL: un gate armado solo sobre `perfiles` le cerraria la
-- puerta a TODOS los pacientes y rompería el agendado de citas, que es el unico consumidor real de
-- esta RPC (AgendarCitaModal). Las dos ramas de esa policy hacen falta y por eso van las dos.
-- (Medido tambien: 0 pacientes con perfil de pais_id distinto y 0 con pais_id NULL en perfiles, asi
-- que hoy las ramas no se contradicen entre si.)
--
-- LA (b) ESTA CONTENIDA EN LA (c)-perfiles y se escribe igual, a proposito: un admin_pais tiene fila
-- en `perfiles`, asi que la rama de perfiles ya lo dejaria pasar. Se deja explicita para que el gate
-- se lea contra la policy que replica, linea por linea, y no haya que deducir que un caso esta
-- cubierto de rebote.
--
-- EL `COALESCE(..., false)` ES EL GATE, NO DECORACION. Para un paciente `get_auth_user_rol()` es
-- NULL, asi que `NULL = 'super_admin'` es NULL y toda la expresion puede dar NULL en vez de false.
-- Un `IF NOT <expr> THEN RETURN` con <expr> NULL NO entra al THEN: la funcion seguiria de largo y
-- devolveria las filas. Es exactamente la clase de fallo que documenta PA-FAILOPEN (mig 222, gate de
-- pais trivaluado). Con el COALESCE el caso indeterminado cae del lado cerrado.
--
-- DEVUELVE 0 FILAS, NO 42501, por pedido explicito: es el mismo comportamiento que tiene hoy la RLS
-- cuando no matchea ninguna policy, y cambiar el contrato a "tira excepcion" obligaria al front a
-- manejar un error que hoy no maneja. Efecto colateral a saber: el censo de gates fail-open del
-- centinela P480 solo mira gates que terminan en RAISE, asi que este gate le es invisible — no lo
-- va a marcar, pero tampoco lo vigila. Lo vigilan las probes P704-P710.
-- ############################################################################################

-- 0. HACE FALTA DROP, no alcanza CREATE OR REPLACE. Medido contra prod el 17-sep:
--
--      ERROR:  42P13: cannot remove parameter defaults from existing function
--      HINT:   Use DROP FUNCTION listar_clinicas_por_pais(uuid) first.
--
--    Postgres deja AGREGAR o CAMBIAR un default con REPLACE, pero no QUITARLO. Sin DROP, la firma
--    de 0 argumentos sobreviviria y el volcado sin filtro seguiria vivo.
--
--    Va SIN CASCADE a proposito: si algun dia alguien cuelga una vista o una funcion de esta RPC,
--    el DROP tiene que ABORTAR la migracion, no llevarse el dependiente por delante. Hoy no hay
--    ninguno: medido el 17-sep contra prod, pg_depend = 0 dependientes, 0 funciones que la nombren
--    en su prosrc y 0 vistas que la nombren en su definicion.
DROP FUNCTION IF EXISTS public.listar_clinicas_por_pais(uuid);

-- 1 + 2. Parametro obligatorio (sin DEFAULT), rama `IS NULL OR` eliminada, gate de pais, tabla
--        calificada y search_path fijo. Se mantiene plpgsql/RETURN QUERY: ademas de ser el delta
--        minimo, el gate con `RETURN` temprano necesita un cuerpo procedural.
CREATE FUNCTION public.listar_clinicas_por_pais(p_pais_id uuid)
RETURNS TABLE(id uuid, nombre text, pais_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  -- GATE (ver la cabecera). Sin autoridad sobre p_pais_id: 0 filas, no excepcion.
  -- El COALESCE es obligatorio: para un paciente los dos helpers devuelven NULL y la expresion
  -- entera puede valer NULL, que en un IF no entra al THEN y dejaria el gate ABIERTO.
  IF NOT COALESCE(
         public.get_auth_user_rol() = 'super_admin'
      OR (public.get_auth_user_rol() = 'admin_pais'
          AND public.get_auth_user_pais_id() = p_pais_id)
      OR EXISTS (SELECT 1 FROM public.pacientes pa
                  WHERE pa.auth_user_id = auth.uid() AND pa.pais_id = p_pais_id)
      OR EXISTS (SELECT 1 FROM public.perfiles pe
                  WHERE pe.id = auth.uid() AND pe.pais_id = p_pais_id)
    , false) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT c.id, c.nombre, c.pais_id
  FROM public.clinicas c
  WHERE c.pais_id = p_pais_id
  ORDER BY c.nombre;
END;
$function$;

-- 3 + 4. Cierre del ACL. Aca los REVOKE no son prolijidad: como la funcion se DROPEA y se vuelve a
--        crear, NACE con el ACL por defecto —PUBLIC con EXECUTE, mas lo que agreguen los default
--        privileges de Supabase para anon/authenticated—, o sea que sin estas dos lineas la
--        migracion REABRIRIA el agujero que vino a cerrar. PUBLIC y anon son entradas distintas del
--        ACL: revocar una no toca la otra.
REVOKE EXECUTE ON FUNCTION public.listar_clinicas_por_pais(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.listar_clinicas_por_pais(uuid) FROM anon;

-- 5. Explicito aunque ya lo tenga: el consumidor real es una pantalla con sesion, y dejarlo
--    declarado hace que la migracion sola alcance para reconstruir el estado correcto.
GRANT EXECUTE ON FUNCTION public.listar_clinicas_por_pais(uuid) TO authenticated;

-- Re-verificacion: la migracion comprueba lo que dejo y ABORTA si no quedo asi. Las mitades
-- importan lo mismo. Que anon/PUBLIC quedaron afuera es la mitad obvia; que authenticated NO se
-- cayo de paso es la que evita romper el agendado de citas del paciente, y que el search_path
-- quedo puesto es la que evita "cerre el ACL y deje la funcion inyectable".
DO $$
DECLARE oid_f oid := 'public.listar_clinicas_por_pais(uuid)'::regprocedure::oid;
        v_mal text := '';
        v_cfg text;
        v_def int;
        v_own text;
        v_n   int;
BEGIN
  -- Quedo UNA sola firma. Si el DROP no hubiera corrido y el CREATE hubiera hecho un overload,
  -- habria dos y la llamada sin argumento seguiria resolviendo contra la vieja.
  SELECT count(*) INTO v_n FROM pg_proc pr JOIN pg_namespace ns ON ns.oid = pr.pronamespace
   WHERE ns.nspname = 'public' AND pr.proname = 'listar_clinicas_por_pais';
  IF v_n <> 1 THEN
    v_mal := v_mal || format('hay %s firmas de listar_clinicas_por_pais, se esperaba 1; ', v_n);
  END IF;

  -- La funcion se DROPEO y se recreo: el dueno lo define quien corre la migracion. Es SECURITY
  -- DEFINER, asi que el dueno ES el privilegio con el que corre — no puede quedar al azar.
  SELECT r.rolname INTO v_own FROM pg_proc pr JOIN pg_roles r ON r.oid = pr.proowner WHERE pr.oid = oid_f;
  IF v_own <> 'postgres' THEN
    v_mal := v_mal || format('el dueno quedo en %L, se esperaba postgres; ', v_own);
  END IF;

  IF has_function_privilege('anon', oid_f, 'EXECUTE') THEN
    v_mal := v_mal || 'anon conserva EXECUTE; ';
  END IF;

  -- PUBLIC se mira DIRECTO en el ACL: su entrada es la que no tiene rol a la izquierda ('=X/...').
  -- Preguntarlo con has_function_privilege() de un rol cualquiera obligaria a elegir un rol sin
  -- grant propio, y eso ata la verificacion a que ese rol exista.
  IF EXISTS (SELECT 1 FROM pg_proc pr, unnest(coalesce(pr.proacl, '{}'::aclitem[])) a
              WHERE pr.oid = oid_f AND a::text LIKE '=%') THEN
    v_mal := v_mal || 'PUBLIC conserva EXECUTE; ';
  END IF;

  IF NOT has_function_privilege('authenticated', oid_f, 'EXECUTE') THEN
    v_mal := v_mal || 'authenticated PERDIO EXECUTE; ';
  END IF;

  IF NOT has_function_privilege('service_role', oid_f, 'EXECUTE') THEN
    v_mal := v_mal || 'service_role PERDIO EXECUTE; ';
  END IF;

  SELECT coalesce(array_to_string(pr.proconfig, ','), '') INTO v_cfg FROM pg_proc pr WHERE pr.oid = oid_f;
  IF v_cfg NOT LIKE '%search_path=%' THEN
    v_mal := v_mal || format('search_path NO quedo fijado (proconfig=%L); ', v_cfg);
  END IF;

  -- pronargdefaults > 0 significa que el DEFAULT sobrevivio y la llamada sin argumento seguiria
  -- existiendo. Es la comprobacion de la mitad grave del hallazgo.
  SELECT pr.pronargdefaults INTO v_def FROM pg_proc pr WHERE pr.oid = oid_f;
  IF v_def <> 0 THEN
    v_mal := v_mal || format('el parametro conserva DEFAULT (pronargdefaults=%s); ', v_def);
  END IF;

  IF v_mal <> '' THEN RAISE EXCEPTION '296: %', v_mal; END IF;
END $$;
