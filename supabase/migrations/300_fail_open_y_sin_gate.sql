-- ############################################################################################
-- 300 — cierra 8 funciones explotables HOY: 3 con gate fail-open y 5 sin gate ninguno
-- ############################################################################################
-- Todo lo de abajo esta MEDIDO contra prod (18-sep), ejercitando el rol, no leyendo el cuerpo.
-- Detalle completo en tmp/censo_failopen.md y tmp/censo_security_definer_anon.md.
--
-- CAPA 1 — EL PATRON FAIL-OPEN TRIVALUADO (3)
-- ------------------------------------------
-- Un gate armado con OR/AND sobre comparaciones sueltas. Si una puede valer NULL,
-- `NULL OR false = NULL` y `NOT NULL = NULL`, y un IF con condicion NULL **no entra al THEN**: el
-- RAISE/RETURN nunca ocurre. Es la misma clase que documenta PA-FAILOPEN (mig 222).
--
--   actualizar_estado_cita        anon Y paciente cambiaron el estado de una cita ajena (medido: el
--                                 hash de citas.estado se movio). Lo unico que frena hoy es, por
--                                 casualidad, el trigger PE001 de la mig 291, que solo tapa
--                                 'completada'. El id de cita es un entero secuencial.
--   obtener_contexto_visita       DEVUELVE la nota clinica y las sugerencias de IA. DOS caminos:
--                                 anon lee CUALQUIER cita; un authenticated sin rol lee las citas
--                                 SIN medico asignado (ahi `NULL = auth.uid()` envenena igual).
--                                 Hoy hay 5 de 37 citas con medico_id NULL.
--   get_planes_visitador_proveedor  anon Y paciente leyeron 1 fila de una empresa ajena.
--
-- CAPA 2 — SIN GATE (5)
-- ---------------------
-- Estas no fallan abiertas: directamente no tienen gate. Por eso el fix es otro — hay que
-- ponerselo, o sacarles el EXECUTE si nadie las llama desde afuera.
--
--   registrar_campana_metrica        anon INSERTO una fila en campana_metricas (medido). Es la base
--                                    de la facturacion de publicidad.
--   slots_ocupados_cita              anon leyo 11 filas: la agenda de citas de un medico.
--   get_slots_ocupados               anon leyo 2 filas: idem sobre visitas_agendadas.
--   obtener_admins_ezpay             anon enumero los 3 user_id con rol privilegiado. Sin parametros.
--   obtener_clinica_principal_medico anon resolvio la clinica de cualquier medico.
--
-- POR QUE `CREATE OR REPLACE` Y NO `DROP` + `CREATE`
-- --------------------------------------------------
-- Es una desviacion deliberada del plan, y la razon es concreta: el default privilege de FUNCIONES
-- sigue abierto. En pg_default_acl, `public/objtype=f` para el rol postgres da
-- `anon=X/postgres` — la mig 298 cerro el default de TABLAS, no el de funciones. Con DROP+CREATE
-- cada una de estas renaceria CON `anon=X`, o sea que la migracion reabriria justo lo que viene a
-- cerrar, y habria que revocar despues. `CREATE OR REPLACE` conserva el ACL exacto que ya tienen.
-- Es legal en las seis: ninguna cambia de firma ni pierde un DEFAULT de parametro (eso es lo unico
-- que Postgres no deja replazar, y fue lo que obligo al DROP en la mig 296).
--
-- `slots_ocupados_cita` SI cambia de lenguaje, de `sql` a `plpgsql`. No hay forma de poner un
-- `RAISE` en una funcion `LANGUAGE sql`, y la alternativa —colar `auth.uid() IS NOT NULL` en el
-- WHERE— devolveria 0 filas en vez de un error, que es un contrato distinto del que usa el resto
-- del repo para "no autenticado". El cuerpo, la firma y el resultado son identicos.
--
-- LAS DOS QUE PIERDEN EXECUTE, Y POR QUE NO ROMPE NADA (medido)
-- -------------------------------------------------------------
-- obtener_admins_ezpay y obtener_clinica_principal_medico no tienen un solo call-site en src/,
-- supabase/functions/, api/ ni scripts/. Las llaman OTRAS funciones: notificar_campana_enviada la
-- primera; laboratorios_para_medico y mi_clinica_medico la segunda. Las tres llamantes son
-- SECURITY DEFINER con dueno `postgres`, y `postgres` conserva EXECUTE — verificado en catalogo.
-- Una llamada interna corre con los privilegios del DEFINER, no con los del caller original, asi
-- que revocarle a PUBLIC/anon/authenticated no la toca. El autochequeo lo prueba EJECUTANDO la
-- cadena, no mirando el catalogo.
-- ############################################################################################


-- ============================================================================================
-- CAPA 1.1 — actualizar_estado_cita
-- ============================================================================================
-- El veneno es `v.medico_id = auth.uid()`: con anon auth.uid() es NULL, y con un paciente lo es
-- v.medico_id en las citas sin medico. Se envuelve la expresion ENTERA en COALESCE(..., false) en
-- vez de solo ese operando: asi cualquier termino que alguien agregue manana tambien cae del lado
-- cerrado, en lugar de depender de que se acuerde de envolverlo.
CREATE OR REPLACE FUNCTION public.actualizar_estado_cita(p_cita_id bigint, p_estado text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v public.citas%ROWTYPE;
BEGIN
  SELECT * INTO v FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada'; END IF;
  -- citas.estado es TEXT: validar contra el conjunto permitido antes de escribir.
  IF p_estado NOT IN ('solicitada','agendada','confirmada','en_curso','completada','cancelada','no_show') THEN
    RAISE EXCEPTION 'Estado de cita inválido: %', p_estado;
  END IF;
  IF NOT COALESCE(
       v.medico_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.pacientes p WHERE p.id = v.paciente_id AND p.auth_user_id = auth.uid())
    OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
    OR private.tiene_rol(ARRAY['super_admin'])
  , false) THEN
    RAISE EXCEPTION 'No autorizado para modificar esta cita';
  END IF;
  UPDATE public.citas SET estado = p_estado WHERE id = p_cita_id;
END;
$function$;

-- ============================================================================================
-- CAPA 1.2 — obtener_contexto_visita
-- ============================================================================================
-- Mismo veneno (`v_cita.medico_id = auth.uid()`), dentro del NOT(...). Los otros cuatro terminos ya
-- venian con COALESCE: estaba tapada la mitad del problema. Ahora el COALESCE envuelve todo.
CREATE OR REPLACE FUNCTION public.obtener_contexto_visita(p_cita_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_cita public.citas%ROWTYPE;
  v_nota_id integer;
  v_nota jsonb;
  v_ia jsonb;
BEGIN
  SELECT * INTO v_cita FROM public.citas WHERE id = p_cita_id;

  -- Cita inexistente y cita ajena responden IGUAL. Distinguirlas convierte a esta funcion en un
  -- oraculo de existencia de citas para cualquier authenticated. Mismo criterio que la mig 267.
  IF NOT FOUND
     OR NOT COALESCE(
          v_cita.medico_id = auth.uid()
          -- las tres mitades de exp_select_medico, copiadas de la policy viva
          OR COALESCE(private.es_medico_de(v_cita.paciente_id::bigint), false)
          OR COALESCE(private.medico_atiende_paciente(v_cita.paciente_id::bigint), false)
          -- "Admin clinica ve expediente de su clinica"
          OR COALESCE(private.medico_es_de_mi_clinica(v_cita.medico_id::uuid), false)
          -- exp_superadmin_all
          OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
     , false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT n.id, to_jsonb(n.*) INTO v_nota_id, v_nota
    FROM public.expediente_notas n WHERE n.cita_id = p_cita_id;

  -- Sin nota no hay consulta_id, y sin consulta_id no hay con que atar las filas de IA: el array
  -- sale vacio, no NULL, para que el consumidor no tenga que distinguir dos formas de "nada".
  SELECT COALESCE(
           jsonb_agg(jsonb_build_object(
             'prompt', a.prompt, 'respuesta_ia', a.respuesta_ia, 'created_at', a.created_at
           ) ORDER BY a.created_at),
           '[]'::jsonb)
    INTO v_ia
    FROM public.auditoria_ia a
   WHERE v_nota_id IS NOT NULL
     AND a.consulta_id = v_nota_id
     AND a.medico_id = auth.uid();

  RETURN jsonb_build_object(
    'cita_id',        p_cita_id,
    'nota',           v_nota,
    'sugerencias_ia', COALESCE(v_ia, '[]'::jsonb)
  );
END
$function$;

-- ============================================================================================
-- CAPA 1.3 — get_planes_visitador_proveedor
-- ============================================================================================
-- Variante con AND antes de un RETURN. `v_empresa <> mi_empresa_proveedor()` da NULL cuando el
-- caller no tiene cuenta de proveedor, y `NULL AND true` es NULL, asi que el RETURN no dispara y la
-- funcion sigue de largo. El COALESCE va con **true** (no false): si no se puede establecer que la
-- empresa es la propia, la respuesta correcta es RETORNAR (denegar), no continuar.
CREATE OR REPLACE FUNCTION public.get_planes_visitador_proveedor(p_empresa_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(pvc_id uuid, pais_id uuid, pais_nombre text, plan_visitador_id integer, incluidas integer, usadas integer, restante integer, ilimitado boolean, fecha_inicio date, fecha_fin date, estado text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_empresa uuid;
BEGIN
  v_empresa := COALESCE(p_empresa_id, mi_empresa_proveedor());
  -- autz: solo la propia empresa (o super_admin)
  IF v_empresa IS NULL THEN RETURN; END IF;
  IF COALESCE(v_empresa <> mi_empresa_proveedor(), true)
     AND NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT pvc.id, pvc.pais_id, cp.nombre::text, pvc.plan_visitador_id,
         pvc.cantidad_visitas_incluidas,
         private.pvc_usadas(pvc.empresa_id, pvc.pais_id, pvc.fecha_inicio, pvc.fecha_fin),
         CASE WHEN pvc.cantidad_visitas_incluidas IS NULL THEN NULL
              ELSE GREATEST(0, pvc.cantidad_visitas_incluidas - private.pvc_usadas(pvc.empresa_id, pvc.pais_id, pvc.fecha_inicio, pvc.fecha_fin)) END,
         (pvc.cantidad_visitas_incluidas IS NULL),
         pvc.fecha_inicio, pvc.fecha_fin, pvc.estado::text
  FROM planes_visitador_contratados pvc
  JOIN configuracion_pais cp ON cp.id = pvc.pais_id
  WHERE pvc.empresa_id = v_empresa AND pvc.estado = 'activo';
END;
$function$;

-- ============================================================================================
-- CAPA 2.1 — registrar_campana_metrica: exigir sesion
-- ============================================================================================
-- NO se toca el resto de su logica: sigue confiando en el p_perfil_id / p_paciente_id que le pasa
-- el caller, asi que un authenticated puede seguir atribuyendo una impresion a otro. Eso es otro
-- frente. Lo que esta linea cierra es la ESCRITURA ANONIMA, que hoy esta medida y abierta.
CREATE OR REPLACE FUNCTION public.registrar_campana_metrica(p_campana_id integer, p_perfil_id uuid DEFAULT NULL::uuid, p_paciente_id integer DEFAULT NULL::integer, p_tipo_perfil text DEFAULT 'desconocido'::text, p_sesion_id text DEFAULT NULL::text, p_clickeado boolean DEFAULT false, p_contexto text DEFAULT NULL::text, p_pais_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_pais_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;   -- MIG 300

  IF p_pais_id IS NULL THEN
    SELECT pais_id INTO v_pais_id FROM public.campanas_publicitarias WHERE id = p_campana_id;
  ELSE
    v_pais_id := p_pais_id;
  END IF;

  INSERT INTO public.campana_metricas (
    campana_id, perfil_id, paciente_id, tipo_perfil, sesion_id, clickeado, contexto, pais_id
  ) VALUES (
    p_campana_id, p_perfil_id, p_paciente_id, p_tipo_perfil, p_sesion_id, p_clickeado, p_contexto, v_pais_id
  );
END;
$function$;

-- ============================================================================================
-- CAPA 2.2 — get_slots_ocupados: exigir sesion
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.get_slots_ocupados(p_medico_id uuid, p_fecha_inicio date, p_fecha_fin date)
 RETURNS TABLE(fecha_visita date, hora_inicio time without time zone, hora_fin time without time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;   -- MIG 300

  RETURN QUERY
  SELECT v.fecha_visita, v.hora_inicio, v.hora_fin
  FROM visitas_agendadas v
  WHERE v.medico_id = p_medico_id
    AND v.fecha_visita BETWEEN p_fecha_inicio AND p_fecha_fin
    AND v.estado NOT IN ('cancelada', 'rechazada', 'no_asistio')
  ORDER BY v.fecha_visita, v.hora_inicio;
END;
$function$;

-- ============================================================================================
-- CAPA 2.3 — slots_ocupados_cita: exigir sesion (pasa de LANGUAGE sql a plpgsql, ver cabecera)
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.slots_ocupados_cita(p_medico_id uuid, p_desde date, p_hasta date)
 RETURNS TABLE(fecha date, hora_inicio time without time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;   -- MIG 300

  RETURN QUERY
  SELECT c.fecha, c.hora_inicio
  FROM citas c
  WHERE c.medico_id = p_medico_id
    AND c.fecha BETWEEN p_desde AND p_hasta
    AND c.estado NOT IN ('cancelada', 'rechazada');
END;
$function$;

-- ============================================================================================
-- CAPA 2.4 y 2.5 — las dos que nadie llama desde afuera pierden el EXECUTE
-- ============================================================================================
-- No se les agrega gate: no hace falta. Se les saca el acceso. PUBLIC y anon son entradas de ACL
-- distintas, y `authenticated` tambien: hay que nombrar a los tres.
REVOKE EXECUTE ON FUNCTION public.obtener_admins_ezpay()                    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obtener_clinica_principal_medico(uuid)    FROM PUBLIC, anon, authenticated;

-- ============================================================================================
-- AUTOCHEQUEO — aborta si algo no quedo como se pidio. Ejercita los roles, no mira el catalogo.
-- ============================================================================================
DO $$
DECLARE
  v_pac      constant uuid   := '0dd0c68c-026c-4ebc-9475-e6791cc54933';  -- paciente real, sin rol
  v_medico   constant uuid   := '09d243d5-b222-482a-9762-94a582e9e752';  -- medico real
  v_emp      constant uuid   := '411d6f8c-a405-49d6-9ed6-fbeb0db05133';  -- empresa CON planes activos
  v_mal      text := '';
  v_hash_ini text;
  v_cita_nul bigint;
  v_cita_med bigint;
  v_estado0  text;
  n          bigint;
  i          int;
  j          jsonb;
BEGIN
  v_hash_ini := (SELECT coalesce(md5(string_agg(id::text||estado, ',' ORDER BY id)),'') FROM public.citas);

  SELECT id INTO v_cita_nul FROM public.citas WHERE medico_id IS NULL ORDER BY id LIMIT 1;
  SELECT id, estado INTO v_cita_med, v_estado0 FROM public.citas WHERE medico_id = v_medico ORDER BY id LIMIT 1;
  IF v_cita_nul IS NULL OR v_cita_med IS NULL THEN
    RAISE EXCEPTION '300: faltan fixtures (cita sin medico=% / cita del medico=%)', v_cita_nul, v_cita_med;
  END IF;

  -- ---------- (a) CAPA 1 cerrada para los DOS actores ----------
  FOR i IN 1..2 LOOP
    IF i = 1 THEN
      PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    ELSE
      PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
    END IF;

    BEGIN
      PERFORM public.actualizar_estado_cita(v_cita_nul, 'cancelada');
      v_mal := v_mal || format('actualizar_estado_cita NO corto (actor %s); ', i);
    EXCEPTION WHEN OTHERS THEN NULL;   -- cualquier excepcion es el resultado buscado
    END;

    BEGIN
      SELECT public.obtener_contexto_visita(v_cita_nul) INTO j;
      v_mal := v_mal || format('obtener_contexto_visita DEVOLVIO datos (actor %s); ', i);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      SELECT count(*) INTO n FROM public.get_planes_visitador_proveedor(v_emp);
      IF n <> 0 THEN
        v_mal := v_mal || format('get_planes_visitador_proveedor devolvio %s filas a un ajeno (actor %s); ', n, i);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- ---------- (b) CONTROL POSITIVO: el medico sigue pudiendo con SUS citas ----------
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_medico, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.actualizar_estado_cita(v_cita_med, 'confirmada');
    IF (SELECT estado FROM public.citas WHERE id = v_cita_med) <> 'confirmada' THEN
      v_mal := v_mal || 'el medico no pudo cambiar el estado de SU cita; ';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('el medico recibio %s al tocar SU cita: la RPC quedo rota; ', SQLSTATE);
  END;
  -- se restaura de inmediato: esta migracion COMMITEA, no puede dejar datos movidos
  UPDATE public.citas SET estado = v_estado0 WHERE id = v_cita_med;

  BEGIN
    SELECT public.obtener_contexto_visita(v_cita_med) INTO j;
    IF j IS NULL THEN v_mal := v_mal || 'obtener_contexto_visita no devolvio nada al medico duenio; '; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('el medico recibio %s en SU cita: la RPC quedo rota; ', SQLSTATE);
  END;

  -- ---------- (c) CAPA 2 ----------
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);

  BEGIN
    PERFORM public.registrar_campana_metrica(
      (SELECT id FROM public.campanas_publicitarias LIMIT 1), NULL, NULL, 'm300', 'm300', true, 'M300', NULL);
    v_mal := v_mal || 'registrar_campana_metrica ESCRIBIO sin sesion; ';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.slots_ocupados_cita(v_medico, '2000-01-01', '2035-01-01');
    v_mal := v_mal || 'slots_ocupados_cita respondio sin sesion; ';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.get_slots_ocupados(v_medico, '2000-01-01', '2035-01-01');
    v_mal := v_mal || 'get_slots_ocupados respondio sin sesion; ';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- Las dos sin EXECUTE: se comprueba en el ACL para los TRES grantees nombrados.
  IF has_function_privilege('anon',          'public.obtener_admins_ezpay()', 'EXECUTE')
     OR has_function_privilege('authenticated','public.obtener_admins_ezpay()', 'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc pr, unnest(coalesce(pr.proacl,'{}'::aclitem[])) a
                 WHERE pr.oid = 'public.obtener_admins_ezpay()'::regprocedure AND a::text LIKE '=%') THEN
    v_mal := v_mal || 'obtener_admins_ezpay conserva EXECUTE para anon/authenticated/PUBLIC; ';
  END IF;
  IF has_function_privilege('anon',          'public.obtener_clinica_principal_medico(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated','public.obtener_clinica_principal_medico(uuid)', 'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc pr, unnest(coalesce(pr.proacl,'{}'::aclitem[])) a
                 WHERE pr.oid = 'public.obtener_clinica_principal_medico(uuid)'::regprocedure AND a::text LIKE '=%') THEN
    v_mal := v_mal || 'obtener_clinica_principal_medico conserva EXECUTE para anon/authenticated/PUBLIC; ';
  END IF;

  -- ---------- (d) CONTROL POSITIVO de Capa 2 ----------
  -- La llamada INTERNA no se rompe. Se prueba con una SECDEF propia en vez de invocar
  -- notificar_campana_enviada: esa manda notificaciones de verdad, y un autochequeo no puede
  -- tener efectos colaterales sobre datos de gente. La cadena que se ejercita es la misma:
  -- SECDEF dueno postgres -> obtener_admins_ezpay, llamada por un authenticated que NO tiene EXECUTE.
  EXECUTE $probe$
    CREATE FUNCTION public._m300_probe_interna() RETURNS bigint
    LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
    AS 'SELECT count(*) FROM public.obtener_admins_ezpay()'
  $probe$;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
  BEGIN
    SELECT public._m300_probe_interna() INTO n;
    IF coalesce(n,0) = 0 THEN
      v_mal := v_mal || 'la llamada INTERNA a obtener_admins_ezpay devolvio 0: se rompio la cadena; ';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('la llamada INTERNA a obtener_admins_ezpay fallo con %s; ', SQLSTATE);
  END;
  EXECUTE 'DROP FUNCTION public._m300_probe_interna()';

  -- Los dos consumidores autenticados reales de los slots siguen respondiendo.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
  BEGIN
    SELECT count(*) INTO n FROM public.slots_ocupados_cita(v_medico, '2000-01-01', '2035-01-01');
    IF n = 0 THEN v_mal := v_mal || 'slots_ocupados_cita devolvio 0 a un authenticated real; '; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('slots_ocupados_cita fallo con %s para un authenticated; ', SQLSTATE);
  END;
  BEGIN
    PERFORM count(*) FROM public.get_slots_ocupados(v_medico, '2000-01-01', '2035-01-01');
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('get_slots_ocupados fallo con %s para un authenticated; ', SQLSTATE);
  END;

  PERFORM set_config('request.jwt.claims', '', true);

  -- ---------- (e) ni una cita quedo movida ----------
  IF (SELECT coalesce(md5(string_agg(id::text||estado, ',' ORDER BY id)),'') FROM public.citas) <> v_hash_ini THEN
    v_mal := v_mal || 'QUEDARON CITAS CON EL ESTADO CAMBIADO por el autochequeo; ';
  END IF;

  IF v_mal <> '' THEN RAISE EXCEPTION '300: %', v_mal; END IF;
END $$;
