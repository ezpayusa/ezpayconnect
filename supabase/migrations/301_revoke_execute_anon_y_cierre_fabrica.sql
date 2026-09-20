-- ############################################################################################
-- 301 — anon pierde EXECUTE en 49 funciones, y se cierra la fabrica que se lo regalaba
-- ############################################################################################
-- Cierra el frente que abrieron las migs 294-300. Scoping completo en
-- docs/CENSO_MIG301_2026-09-18.md (vivio en tmp/censo_mig301.md hasta que se trackeo), todo
-- medido contra prod el 18-sep, DESPUES de la 300 (el censo original de 62 quedo viejo: hoy son 60,
-- porque la 300 le revoco el EXECUTE a obtener_admins_ezpay y obtener_clinica_principal_medico).
--
-- QUE SE REVOCA Y QUE NO
-- ----------------------
-- De las 60 con EXECUTE a anon hoy, se revocan **49**. Quedan 11 afuera: `registrar_proveedor` y
-- las 10 que se usan DENTRO de policies de RLS.
--
-- LAS 10 DE LAS POLICIES: EL DRY-RUN DE LA PRIMERA VERSION LAS ENCONTRO ROMPIENDO PROD
-- ------------------------------------------------------------------------------------
-- Esta migracion se escribio primero con 59 y aborto con:
--     ERROR: 42501: permission denied for function get_auth_user_pais_id
-- Es la leccion de la mig 284 aplicada a FUNCIONES: **una policy se evalua con los privilegios del
-- LLAMANTE**. Diez de las 59 aparecen dentro de expresiones USING/WITH CHECK, sobre **30 tablas
-- donde anon tiene SELECT**. Sacarle el EXECUTE no hace que esas tablas devuelvan 0 filas: hace que
-- lancen 42501 y queden ROTAS para ese rol. Entre ellas estan `perfiles`, `citas`, `pacientes`,
-- `recetas` y `clinicas`.
--
--   get_auth_user_rol         -> campanas_publicitarias, citas, clinicas, facturas, notificaciones,
--                                pacientes, perfiles, recetas, solicitudes_campana, visitas_agendadas
--   get_auth_user_pais_id     -> las mismas, menos notificaciones
--   mi_empresa_proveedor      -> 18 tablas (contratos_comision, examenes, ordenes_examen, ...)
--   mi_rol_proveedor          -> cuentas_proveedor, equipos_visitadores, invitaciones_visitador,
--                                pagos_proveedor, productos_empresa, ubicaciones_medico_proveedor,
--                                visitas_agendadas
--   mi_clinica_id             -> invitaciones_laboratorio, laboratorio_clinicas
--   puede_ver_conversacion    -> chat_conversaciones, chat_mensajes_internos, chat_participantes
--   supervisa_cuenta_proveedor-> cuentas_proveedor, visitas_agendadas
--   get_empresa_id_proveedor  -> cuentas_proveedor
--   get_empresa_id_session    -> empresas_proveedoras
--   admin_clinica_de_medico   -> disponibilidad_medico
--
-- Dejarlas ejecutables por anon NO filtra nada: las 10 son helpers de identidad que sin sesion
-- devuelven NULL o false. Lo que filtraria es el 42501, que ademas es un sintoma dificil de
-- diagnosticar porque aparece lejos del cambio.
--
-- BACKLOG, NO ESTE BLOQUE: reescribir esas 10 policies para que no dependan del EXECUTE de anon
-- sobre funciones de `public` (moverlas a `private`, que es el patron que el proyecto ya usa) es un
-- frente propio y mas grande — toca 30 tablas. Queda anotado, no se hace aca.
--
-- `registrar_proveedor`: es el unico flujo pre-login del sistema. Vale aclarar por que se la deja
-- aunque su cuerpo empiece con `IF v_user_id IS NULL THEN RAISE 'Usuario no autenticado'` — o sea,
-- aunque anon no pueda hacer nada util con ella. Se la deja porque el alta de proveedor llama
-- `supabase.auth.signUp()` y despues la RPC, y si alguna vez ese signUp dejara de devolver sesion
-- inmediata (confirmacion por email), el fallo tiene que seguir siendo el P0001 explicito de la
-- funcion y no un 42501 de ACL, que es mucho mas dificil de diagnosticar. Es la unica excepcion.
--
-- NINGUNA DE LAS 49 TIENE UN CALL-SITE ALCANZABLE SIN SESION. Se verifico subiendo por la cadena de
-- imports desde cada `supabase.rpc('...')` de src/ hasta ver si el archivo cuelga de alguno de los
-- 10 componentes montados en rutas SIN guard (LoginPage, RegistroMedicoPage, RegistroClinicaPage,
-- SetPasswordPage, ConfirmarRecetaPage, WebAppLoginPage, WebAppRegistroPage, ProveedorLogin,
-- ProveedorRegistro, ProveedorRegistroVisitador). De las 60, 34 tienen call-site y 26 no tienen
-- ninguno; una sola resulto alcanzable desde una pantalla publica, y es `registrar_proveedor`.
--
-- SE REVOCA POR CATALOGO, NO POR LISTA DE 49 NOMBRES. Una lista copiada se desactualiza el dia que
-- aparece la 50; el `DO` recorre pg_proc con la regla ("toda SECDEF de public con EXECUTE a anon,
-- salvo registrar_proveedor y salvo las 10 de las policies") y el autochequeo ABORTA si el conteo
-- no da exactamente 49. Asi la
-- regla queda escrita y al mismo tiempo el alcance queda fijado: si entre hoy y el apply apareciera
-- una funcion nueva, la migracion no la revoca en silencio — se niega a correr.
--
-- NO SE TOCA `authenticated` EN NINGUNA. Este barrido es sobre anon y PUBLIC. De las 60, 26 no
-- tienen call-site en src/ y podrian no necesitar authenticated tampoco, pero eso es otro frente:
-- algunas las llaman otras funciones, y distinguir "muerta" de "esperando consumidor" necesita su
-- propia medicion.
--
-- liberar_examen_al_paciente: ADEMAS DEL REVOKE, SE LE ARREGLA EL GATE
-- --------------------------------------------------------------------
-- Su gate tiene el MISMO patron que cerro la mig 300 en actualizar_estado_cita y
-- obtener_contexto_visita: `v.medico_id = auth.uid()` suelto dentro de un OR. Con `v.medico_id`
-- NULL la cadena entera vale NULL, `NOT NULL` es NULL y el RAISE no dispara.
-- HOY NO ES EXPLOTABLE: medido, hay **0 examenes con medico_id NULL**, y por eso da PT002 a anon y
-- a un authenticated sin relacion. Pero es exactamente la bomba que exploto en obtener_contexto_visita
-- cuando apareciron las 5 citas sin medico. El REVOKE la tapa para anon; el COALESCE la tapa para
-- cualquier `authenticated`, que es el actor que el REVOKE no alcanza.
-- `liberar_orden_al_paciente` comparte el patron pero sus condiciones de autoria viven en el WHERE
-- del UPDATE, que es fail-closed por construccion (medido: 0 filas para los dos actores). Solo REVOKE.
--
-- LA FABRICA (capas 3 y 4)
-- ------------------------
-- Estado medido hoy en pg_default_acl, schema public, rol postgres:
--   objtype='f' (funciones): postgres=X  anon=X  authenticated=X  service_role=X
--   objtype='S' (secuencias): postgres=rwU  anon=rwU  authenticated=rwU  service_role=rwU
-- O sea que cada funcion nueva nace ejecutable por anon, y cada secuencia nueva le da USAGE — que es
-- lo que habilita `nextval()`. Es la fabrica que produjo las 62 del censo original, y la razon por
-- la que la mig 300 tuvo que usar CREATE OR REPLACE en vez de DROP+CREATE.
--
-- LAS SECUENCIAS: SE MIDIO QUE anon NO LAS NECESITA, no se asumio.
--   * 32 secuencias en public, las 32 con USAGE para anon.
--   * **0** tablas de public con INSERT para anon (la mig 298 se lo quito).
--   * **0** secuencias cuya tabla duena deje INSERT a anon — o sea, ni una sola por la que anon
--     pudiera llegar a un `nextval()` via el DEFAULT de una columna.
--   * **0** funciones en public/private con un `nextval` explicito en el cuerpo.
--   No hay camino. Cerrar el default no le saca nada a nadie.
--   FUERA DE ALCANCE: las 32 secuencias que YA existen conservan el USAGE de anon. Esta migracion
--   cierra la fabrica, no limpia el stock. Queda como decision aparte.
--
-- LA ENTRADA DE `supabase_admin` NO SE PUEDE TOCAR, y no importa. `ALTER DEFAULT PRIVILEGES FOR
-- ROLE supabase_admin` da 42501 desde esta conexion (postgres no es superuser ni miembro de ese
-- rol) — medido en la mig 298. No importa porque un default privilege aplica segun QUIEN CREA el
-- objeto, y las 266 funciones de public las crea `postgres`. Queda inerte. Lo vigila P724 para
-- tablas; las probes P739-P744 de este bloque hacen lo propio para funciones.
-- ############################################################################################

-- Foto del estado previo: el autochequeo la necesita para comprobar contra que se reviso.
CREATE TEMP TABLE _m301_antes AS
SELECT p.oid,
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS firma,
       p.proname AS nombre
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
  AND p.proname NOT IN (
    -- el unico flujo pre-login
    'registrar_proveedor',
    -- y las 10 que viven dentro de policies de RLS: revocarlas lanza 42501 sobre 30 tablas
    -- (medido por el dry-run de la primera version de esta migracion)
    'get_auth_user_rol', 'get_auth_user_pais_id', 'mi_empresa_proveedor', 'mi_rol_proveedor',
    'mi_clinica_id', 'puede_ver_conversacion', 'supervisa_cuenta_proveedor',
    'get_empresa_id_proveedor', 'get_empresa_id_session', 'admin_clinica_de_medico'
  );

-- ============================================================================================
-- CAPA 1 — REVOKE EXECUTE de PUBLIC y de anon en las 49
-- ============================================================================================
-- PUBLIC y anon son entradas de ACL distintas: revocar una no toca la otra. Hay que nombrar a las
-- dos, igual que en las migs 295 y 298.
DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT firma FROM _m301_antes ORDER BY firma LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s FROM PUBLIC, anon', r.firma);
    n := n + 1;
  END LOOP;
  PERFORM set_config('m301.revocadas', n::text, false);
  RAISE NOTICE '301 capa 1: % funciones revocadas', n;
END $$;

-- ============================================================================================
-- CAPA 2 — liberar_examen_al_paciente: el COALESCE que le falta al gate
-- ============================================================================================
-- CREATE OR REPLACE y no DROP+CREATE: con la fabrica todavia abierta en el momento en que corre
-- esta sentencia, un DROP+CREATE la haria renacer con anon=X y desharia la capa 1. El orden de las
-- capas importa por eso mismo — la 3 va despues, pero aunque fuera antes, REPLACE es lo correcto.
CREATE OR REPLACE FUNCTION public.liberar_examen_al_paciente(p_examen_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_pid integer;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Examen inexistente' USING ERRCODE='PT002'; END IF;
  -- MIG 301: el COALESCE envuelve la cadena ENTERA. `v.medico_id = auth.uid()` vale NULL cuando el
  -- examen no tiene medico asignado (o cuando el caller es anon), y `NULL OR false` es NULL, que en
  -- un IF no entra al THEN. Mismo arreglo que la mig 300 aplico a actualizar_estado_cita.
  IF NOT COALESCE( v.medico_id = auth.uid()
        OR private.medico_atiende_paciente((v.paciente_id)::bigint)
        OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
        OR private.tiene_rol(ARRAY['super_admin'::text]) , false) THEN
    RAISE EXCEPTION 'No autorizado para liberar este examen' USING ERRCODE='PT002'; END IF;
  IF v.estado::text <> 'completado' THEN
    RAISE EXCEPTION 'El examen aun no tiene resultado cargado' USING ERRCODE='PT002'; END IF;
  IF v.liberado_al_paciente THEN
    RETURN jsonb_build_object('examen', v.id, 'ya_liberado', true); END IF;
  UPDATE public.examenes SET liberado_al_paciente=true, fecha_liberacion=now(), liberado_por=auth.uid()
   WHERE id = v.id;
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen disponible',
              'Tu medico libero un resultado de examen. Ya puedes verlo.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    IF v_pid IS NOT NULL THEN PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text); END IF;
  END IF;
  RETURN jsonb_build_object('examen', v.id, 'liberado', true);
END; $function$;

-- El CREATE OR REPLACE conserva el ACL, y el ACL que conserva es el que dejo la CAPA 1 (esta
-- funcion esta entre las 59). Se re-revoca igual, explicito, para que la migracion sea legible sin
-- tener que razonar sobre el orden de las capas.
REVOKE EXECUTE ON FUNCTION public.liberar_examen_al_paciente(integer) FROM PUBLIC, anon;

-- ============================================================================================
-- CAPA 3 — la fabrica de FUNCIONES
-- ============================================================================================
-- OJO CON EL `IN SCHEMA`: el primero va SIN el, y no es un descuido.
--
-- Para FUNCIONES el `EXECUTE TO PUBLIC` es el default INTERNO de Postgres, y es GLOBAL. Una entrada
-- de pg_default_acl acotada a un esquema NO puede suprimirlo: `ALTER DEFAULT PRIVILEGES ... IN
-- SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` es un NO-OP — la entrada de public ni
-- siquiera lista a PUBLIC, asi que no hay nada que quitar, y la funcion nueva igual nace con
-- `=X/postgres`. Medido paso a paso el 18-sep; el autochequeo de la primera version de esta
-- migracion lo atrapo y aborto con "una FUNCION nueva sigue naciendo ejecutable por anon".
--
-- Hacen falta LAS DOS, y en estos alcances:
--   1. GLOBAL (sin IN SCHEMA) para sacar a PUBLIC.
--   2. POR ESQUEMA para sacar a anon, que tiene su propia entrada en el ACL de public.
-- Con solo la 1: anon sigue en true (por su entrada propia). Con solo la 2: PUBLIC sigue, y anon es
-- miembro de PUBLIC, asi que tambien sigue en true. Las dos juntas dan anon=false, authenticated=true.
--
-- ALCANCE DE LA GLOBAL, dicho para que sea decision y no efecto colateral: aplica a las funciones
-- que cree `postgres` en CUALQUIER esquema, no solo en public — `private` incluido. Es mas ancho
-- que lo pedido. Se considera correcto (un helper de `private` no deberia nacer ejecutable por todo
-- el mundo) y es el unico alcance en el que Postgres deja suprimir ese default, pero no es acotable.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres                 REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;

-- ============================================================================================
-- CAPA 4 — la fabrica de SECUENCIAS
-- ============================================================================================
-- Las secuencias NO tienen el problema de arriba: su default interno no le da nada a PUBLIC, asi
-- que alcanza con la entrada por esquema. Verificado: despues de esto una secuencia nueva da
-- anon=false y authenticated=true.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC, anon;

-- ============================================================================================
-- AUTOCHEQUEO — aborta si algo no quedo como se pidio. Ejercita roles, no mira solo el catalogo.
-- ============================================================================================
DO $$
DECLARE
  v_pac  constant uuid := '0dd0c68c-026c-4ebc-9475-e6791cc54933';  -- paciente real, sin rol
  v_med  constant uuid := '09d243d5-b222-482a-9762-94a582e9e752';  -- medico real
  v_mal  text := '';
  v_n    int;
  v_t    text;
  v_lista text;
  v_ex   integer;
  j      jsonb;
BEGIN
  -- (0) el alcance fue exactamente el esperado: ni una de mas, ni una de menos.
  IF coalesce(current_setting('m301.revocadas', true), '0')::int <> 49 THEN
    v_mal := v_mal || format('la capa 1 revoco %s funciones, se esperaban 49; ',
                             coalesce(current_setting('m301.revocadas', true), '?'));
  END IF;

  -- (a) NINGUNA de las revocadas conserva EXECUTE para anon ni para PUBLIC.
  SELECT count(*), string_agg(a.firma, ', ') INTO v_n, v_lista
    FROM _m301_antes a
   WHERE has_function_privilege('anon', a.oid, 'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc pr, unnest(coalesce(pr.proacl, '{}'::aclitem[])) x
                  WHERE pr.oid = a.oid AND x::text LIKE '=%');
  IF v_n <> 0 THEN
    v_mal := v_mal || format('%s funcion(es) conservan anon/PUBLIC: %s; ', v_n, left(v_lista, 250));
  END IF;

  -- (a-bis) y se EJERCITA una muestra como anon, no solo se mira el catalogo: la leccion de la
  -- mig 284 es que el ACL dice quien tiene que, no que pasa cuando se usa.
  -- La muestra usa funciones que SI estan entre las 49. Usar una de las 10 excluidas seria un
  -- chequeo que pasa siempre y no mide nada.
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('role', 'anon', true);
  FOREACH v_t IN ARRAY ARRAY['paciente_examenes', 'mis_conversaciones', 'contactos_chat',
                             'afiliaciones_de_clinica', 'estado_plan_visitas'] LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I()', v_t);
      v_mal := v_mal || format('anon todavia ejecuta %s(); ', v_t);
    EXCEPTION WHEN insufficient_privilege THEN NULL;
      WHEN OTHERS THEN v_mal := v_mal || format('%s fallo con %s (se esperaba 42501); ', v_t, SQLSTATE);
    END;
  END LOOP;
  PERFORM set_config('role', 'none', true);

  -- CONTROL NEGATIVO NUEVO (ajuste de alcance de la 2a version): las 10 de las policies TIENEN que
  -- conservar el EXECUTE. Si el barrido las alcanzara por accidente, el sintoma no seria esta
  -- funcion fallando: serian 30 tablas devolviendo 42501 a anon.
  FOREACH v_t IN ARRAY ARRAY['get_auth_user_rol', 'get_auth_user_pais_id', 'mi_empresa_proveedor',
                             'mi_rol_proveedor', 'mi_clinica_id', 'puede_ver_conversacion',
                             'supervisa_cuenta_proveedor', 'get_empresa_id_proveedor',
                             'get_empresa_id_session', 'admin_clinica_de_medico'] LOOP
    SELECT count(*) INTO v_n FROM pg_proc pr JOIN pg_namespace ns ON ns.oid = pr.pronamespace
     WHERE ns.nspname = 'public' AND pr.proname = v_t
       AND has_function_privilege('anon', pr.oid, 'EXECUTE');
    IF v_n = 0 THEN
      v_mal := v_mal || format('%s PERDIO el EXECUTE de anon: rompe las policies que la usan; ', v_t);
    END IF;
  END LOOP;

  -- ...y se comprueba el EFECTO, no solo el ACL: las tablas cuyas policies las llaman siguen
  -- respondiendo a anon con 0 filas y SIN 42501. Es la unica forma de ver lo que el dry-run de la
  -- 1a version vio (la leccion de la mig 284: el catalogo no dice que pasa cuando se usa).
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('role', 'anon', true);
  FOREACH v_t IN ARRAY ARRAY['perfiles', 'citas', 'cuentas_proveedor', 'pacientes', 'clinicas'] LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', v_t) INTO v_n;
    EXCEPTION WHEN insufficient_privilege THEN
      v_mal := v_mal || format('la tabla %s lanza 42501 a anon: se rompio una policy; ', v_t);
      WHEN OTHERS THEN
        v_mal := v_mal || format('la tabla %s fallo con %s para anon; ', v_t, SQLSTATE);
    END;
  END LOOP;
  PERFORM set_config('role', 'none', true);

  -- (d) CONTROL NEGATIVO: registrar_proveedor NO fue alcanzada por el barrido.
  IF NOT has_function_privilege('anon', 'public.registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)', 'EXECUTE') THEN
    v_mal := v_mal || 'registrar_proveedor PERDIO el EXECUTE de anon: el barrido se paso de alcance; ';
  END IF;

  -- (c) liberar_examen_al_paciente rechaza a los DOS actores.
  SELECT id INTO v_ex FROM public.examenes ORDER BY id LIMIT 1;
  IF v_ex IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    PERFORM set_config('role', 'anon', true);
    BEGIN
      SELECT public.liberar_examen_al_paciente(v_ex) INTO j;
      v_mal := v_mal || 'anon libero un examen; ';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM set_config('role', 'none', true);

    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    BEGIN
      SELECT public.liberar_examen_al_paciente(v_ex) INTO j;
      v_mal := v_mal || 'un authenticated sin relacion libero un examen; ';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM set_config('role', 'none', true);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  -- (b) CONTROL POSITIVO: la cadena interna no se rompe. Las funciones revocadas las siguen
  -- llamando otras SECDEF de dueno postgres, que corren con los privilegios del DEFINER. Se
  -- ejercita de verdad con una SECDEF propia, invocada por un `authenticated` que ya no tiene
  -- EXECUTE sobre la funcion de adentro.
  BEGIN
    -- La de adentro tiene que ser una de las REVOCADAS, si no la prueba no prueba nada.
    EXECUTE 'CREATE FUNCTION public._m301_probe() RETURNS bigint LANGUAGE sql SECURITY DEFINER '
         || 'SET search_path TO ''public'' AS ''SELECT count(*) FROM public.contactos_chat()''';
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    PERFORM public._m301_probe();     -- que no lance es el resultado buscado
    PERFORM set_config('role', 'none', true);
    PERFORM set_config('request.jwt.claims', '', true);
    EXECUTE 'DROP FUNCTION public._m301_probe()';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    v_mal := v_mal || format('la cadena interna se rompio (%s %s); ', SQLSTATE, SQLERRM);
  END;

  -- (e) las dos fabricas quedaron cerradas en el catalogo...
  IF EXISTS (
    SELECT 1 FROM pg_default_acl d LEFT JOIN pg_namespace ns ON ns.oid = d.defaclnamespace
     WHERE (ns.nspname = 'public' OR d.defaclnamespace = 0)
       AND d.defaclobjtype IN ('f', 'S')
       AND pg_get_userbyid(d.defaclrole) = 'postgres'
       AND (array_to_string(d.defaclacl, ',') LIKE '%anon=%'
            OR EXISTS (SELECT 1 FROM unnest(d.defaclacl) y WHERE y::text LIKE '=%'))
  ) THEN
    v_mal := v_mal || 'el default privilege de postgres sigue dando a anon/PUBLIC en funciones o secuencias; ';
  END IF;

  -- ...y se comprueba EJERCITANDOLAS: una funcion y una secuencia nuevas, creadas aca, no le dan
  -- nada a anon. Se crean y se borran dentro de este mismo bloque, que es una sola sentencia.
  BEGIN
    EXECUTE 'CREATE FUNCTION public._m301_nueva() RETURNS int LANGUAGE sql AS ''SELECT 1''';
    EXECUTE 'CREATE SEQUENCE public._m301_seq';
    IF has_function_privilege('anon', 'public._m301_nueva()', 'EXECUTE') THEN
      v_mal := v_mal || 'una FUNCION nueva sigue naciendo ejecutable por anon; ';
    END IF;
    IF has_sequence_privilege('anon', 'public._m301_seq', 'USAGE') THEN
      v_mal := v_mal || 'una SECUENCIA nueva sigue naciendo con USAGE para anon; ';
    END IF;
    EXECUTE 'DROP SEQUENCE public._m301_seq';
    EXECUTE 'DROP FUNCTION public._m301_nueva()';
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('no se pudo probar la fabrica (%s %s); ', SQLSTATE, SQLERRM);
  END;

  IF v_mal <> '' THEN RAISE EXCEPTION '301: %', v_mal; END IF;
END $$;

DROP TABLE IF EXISTS _m301_antes;
