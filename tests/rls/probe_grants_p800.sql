-- ############################################################################################
-- probe_grants_p800.sql — GATE GLOBAL DE GRANTS DEL DATA API en public (relaciones) y public/private (funciones). AISLADO:
--   npm run harness:grants   (= npx supabase db query --linked -f tests/rls/probe_grants_p800.sql)
-- Autocontenido: BEGIN ... ROLLBACK. RAISE ante cualquier violacion (junta todas).
-- ############################################################################################
BEGIN;
-- ============================================================================
-- P800 — GATE GLOBAL DE GRANTS DEL DATA API (public). CORRE AISLADO.
-- No es parte de la corrida transaccional del harness (RAISE ante violacion).
-- Listas blancas LITERALES (no derivadas de la DB). Un solo DO: junta TODAS las
-- violaciones y RAISE con el detalle. La parte (f) trae su EXCEPTION handler
-- (satisface b2_guard: el bloque "tiene handler"); el RAISE final es top-level y
-- por eso propaga. Baseline anon = 80 relaciones SELECT (23-sep-2026).
-- 343 (2-oct-2026): (c)/(d) miran tambien MAINTAIN de anon, y la regla nueva (i) exige 0 TRUNCATE/TRIGGER/
-- REFERENCES/MAINTAIN para authenticated y PUBLIC (antes P800 no veia MAINTAIN). Con 343_rollback sale ROJO.
-- 370 (6-oct-2026): P800 mira tambien FUNCIONES (pg_proc de public y private, sin las de extensiones):
--   (j) ninguna funcion con EXECUTE para PUBLIC (aclexplode de COALESCE(proacl, acldefault): proacl NULL = PUBLIC);
--   (k) anon con EXECUTE solo en WL_ANON_FN (literal, solo puede achicarse; huerfanas y entradas sin uso = violacion);
--   (l) toda policy y toda funcion de la que depende (pg_depend): cada rol de la policy (public -> anon y
--       authenticated) la puede ejecutar (leccion 284 aplicada a funciones);
--   (m) EJERCICIO como anon: catalogo_planes_visitador_publico() responde y get_auth_user_rol() da 42501.
--   Hasta el apply de la 370, (j)/(k)/(m-42501) salen PENDIENTE solo si el estado previo esta INTACTO Y EXACTO (ver el
--   bloque de funciones); cualquier otro estado es violacion. relkind alineado con la 343 y P925: incluye 'f'.
-- ============================================================================
DO $p800$
DECLARE
  -- WL_ANON_LEGACY — BASELINE 8 (achicada de 80 a 8 por mig 324 (23-sep-2026)) — solo puede achicarse.
  -- Las 72 se revocaron; quedan 8: configuracion_pais/configuracion_sistema (uso sin sesion / policy
  -- anon) y las 6 dependencias inline de policies ajenas (perfiles, pacientes, cuentas_proveedor,
  -- empresas_proveedoras, liquidaciones_comision, recetas): sin su SELECT anon, esas policies lanzan
  -- 42501 en vez de negar en silencio (leccion mig 284). Su cierre = reescribir policies a DEFINER.
  wl_anon text[] := ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas'];
  wl_auth text[] := ARRAY['empresa_capacidades','jornadas_comerciales','medicamentos_clasificacion_log','solicitudes_capacidad_pais','visitas_comerciales'];
  r record;
  v_viol text := '';
  auth_tiene boolean;
  anon_tiene boolean;
  anon_no_select boolean;
  anon_leyo boolean := false;
  f_err text := '';
  nom text;
  -- WL_ANON_FN — BASELINE 1 (mig 370, 6-oct-2026) — solo puede achicarse. Catalogo publico de precios de la landing
  -- /planes-visitador sin sesion (mig 362; excepcion de producto, P739).
  wl_anon_fn text[] := ARRAY['public.catalogo_planes_visitador_publico()'];
  -- Estado previo a la 370 (censo de prod del 6-oct-2026). Solo para distinguir PENDIENTE de violacion: borrar con la 370 aplicada.
  pre38 text[] := ARRAY[
    'private.es_staff_calendario_clinica(uuid)','private.guard_jornada_pais()','private.guard_pais_prospecto()',
    'private.guard_pais_visita_comercial()','private.guard_reporte_exige_checkin()','private.guard_supervisor_asesor()',
    'private.medclaslog_solo_append()','private.puede_aprobar_visitas()','private.receta_items_modalidad_uniforme()',
    'private.reset_notificado_cancelacion()','private.reset_notificado_envio()','private.resolver_medicamento_id(text)',
    'private.safe_uuid(text)','private.trg_farmed_resolver_medid()','private.trg_gate_capacidad_productos()',
    'private.trg_gate_capacidad_publicidad()','private.trg_guard_tema_columns()',
    'public.actualizar_stock_dispensacion()','public.admin_clinica_de_medico(uuid)','public.calcular_imc_signos_vitales()',
    'public.calcular_limite_cancelacion(date)','public.get_auth_user_pais_id()','public.get_auth_user_rol()',
    'public.get_empresa_id_proveedor()','public.get_empresa_id_session()','public.limpiar_cache_biblioteca_expirada()',
    'public.mi_clinica_id()','public.mi_empresa_proveedor()','public.mi_rol_proveedor()','public.perfiles_guard_rol_update()',
    'public.puede_ver_conversacion(uuid)','public.set_fecha_limite_cancelacion()','public.supervisa_cuenta_proveedor(uuid)',
    'public.trg_gate_head_start_lab()','public.trg_medicos_lab_enrolador_inmutable()','public.trigger_set_updated_at()',
    'public.update_config_timestamp()','public.update_updated_at_column()'];
  pre22 text[] := ARRAY[
    'public.actualizar_stock_dispensacion()','public.admin_clinica_de_medico(uuid)','public.calcular_imc_signos_vitales()',
    'public.calcular_limite_cancelacion(date)','public.get_auth_user_pais_id()','public.get_auth_user_rol()',
    'public.get_empresa_id_proveedor()','public.get_empresa_id_session()','public.limpiar_cache_biblioteca_expirada()',
    'public.mi_clinica_id()','public.mi_empresa_proveedor()','public.mi_rol_proveedor()','public.perfiles_guard_rol_update()',
    'public.puede_ver_conversacion(uuid)','public.set_fecha_limite_cancelacion()','public.supervisa_cuenta_proveedor(uuid)',
    'public.trg_gate_head_start_lab()','public.trg_medicos_lab_enrolador_inmutable()','public.trigger_set_updated_at()',
    'public.update_config_timestamp()','public.update_updated_at_column()','public.catalogo_planes_visitador_publico()'];
  fn_pre boolean;
  n_pend_j int := 0;
  n_pend_k int := 0;
  n_pend_m int := 0;
  m_st text;
BEGIN
  PERFORM set_config('p800.pendiente', '', true);
  -- FIX 3: las listas blancas solo pueden ACHICARSE (nunca crecer sobre el baseline).
  IF array_length(wl_anon,1) > 8 THEN RAISE EXCEPTION 'P800: WL_ANON_LEGACY solo puede achicarse (baseline 8 tras mig 324), tiene %', array_length(wl_anon,1); END IF;
  IF array_length(wl_auth,1) > 5  THEN RAISE EXCEPTION 'P800: WL_AUTH_SIN_GRANT solo puede achicarse (baseline 5), tiene %', array_length(wl_auth,1); END IF;
  -- (g) entradas huerfanas: nombre en la WL que ya no existe como relacion en public (limpiar la lista).
  FOREACH nom IN ARRAY wl_anon LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
                    WHERE ns.nspname='public' AND c.relname=nom AND c.relkind IN ('r','v','m','p','f')) THEN
      v_viol := v_viol || E'\n(g) entrada huerfana en WL: '||nom;
    END IF;
  END LOOP;
  FOREACH nom IN ARRAY wl_auth LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
                    WHERE ns.nspname='public' AND c.relname=nom AND c.relkind IN ('r','v','m','p','f')) THEN
      v_viol := v_viol || E'\n(g) entrada huerfana en WL: '||nom;
    END IF;
  END LOOP;

  FOR r IN
    SELECT c.oid, c.relname, c.relkind, c.relrowsecurity
      FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND c.relkind IN ('r','v','m','p','f')
     ORDER BY c.relname
  LOOP
    -- (a) service_role: tablas S/I/U/D ; vistas solo S
    IF r.relkind IN ('v','m') THEN
      IF NOT has_table_privilege('service_role', r.oid, 'SELECT') THEN
        v_viol := v_viol || E'\n(a) service_role SIN SELECT en vista '||r.relname;
      END IF;
    ELSE
      IF NOT (has_table_privilege('service_role', r.oid,'SELECT') AND has_table_privilege('service_role', r.oid,'INSERT')
              AND has_table_privilege('service_role', r.oid,'UPDATE') AND has_table_privilege('service_role', r.oid,'DELETE')) THEN
        v_viol := v_viol || E'\n(a) service_role SIN S/I/U/D en '||r.relname;
      END IF;
    END IF;

    auth_tiene := has_table_privilege('authenticated', r.oid,'SELECT') OR has_table_privilege('authenticated', r.oid,'INSERT')
      OR has_table_privilege('authenticated', r.oid,'UPDATE') OR has_table_privilege('authenticated', r.oid,'DELETE')
      OR has_table_privilege('authenticated', r.oid,'REFERENCES') OR has_table_privilege('authenticated', r.oid,'TRIGGER')
      OR has_any_column_privilege('authenticated', r.oid, 'SELECT,INSERT,UPDATE,REFERENCES');
    -- (b) authenticated sin ningun privilegio y fuera de WL_AUTH_SIN_GRANT
    IF NOT auth_tiene AND NOT (r.relname = ANY(wl_auth)) THEN
      v_viol := v_viol || E'\n(b) authenticated SIN privilegio y fuera de WL_AUTH: '||r.relname;
    END IF;

    anon_tiene := has_table_privilege('anon', r.oid,'SELECT') OR has_table_privilege('anon', r.oid,'INSERT')
      OR has_table_privilege('anon', r.oid,'UPDATE') OR has_table_privilege('anon', r.oid,'DELETE')
      OR has_table_privilege('anon', r.oid,'REFERENCES') OR has_table_privilege('anon', r.oid,'TRIGGER')
      OR has_table_privilege('anon', r.oid,'TRUNCATE') OR has_table_privilege('anon', r.oid,'MAINTAIN')
      OR has_any_column_privilege('anon', r.oid, 'SELECT,INSERT,UPDATE,REFERENCES');
    -- (c) anon con cualquier privilegio y fuera de WL_ANON_LEGACY
    IF anon_tiene AND NOT (r.relname = ANY(wl_anon)) THEN
      v_viol := v_viol || E'\n(c) anon CON privilegio y fuera de WL_ANON_LEGACY: '||r.relname;
    END IF;
    -- (d) en WL_ANON_LEGACY pero con algo != SELECT
    anon_no_select := has_table_privilege('anon', r.oid,'INSERT') OR has_table_privilege('anon', r.oid,'UPDATE')
      OR has_table_privilege('anon', r.oid,'DELETE') OR has_table_privilege('anon', r.oid,'REFERENCES') OR has_table_privilege('anon', r.oid,'TRIGGER')
      OR has_table_privilege('anon', r.oid,'TRUNCATE') OR has_table_privilege('anon', r.oid,'MAINTAIN')
      OR has_any_column_privilege('anon', r.oid, 'INSERT,UPDATE,REFERENCES');
    IF (r.relname = ANY(wl_anon)) AND anon_no_select THEN
      v_viol := v_viol || E'\n(d) anon con privilegio != SELECT en WL_ANON_LEGACY: '||r.relname;
    END IF;

    -- (i) privilegios que ningun cliente usa y que saltan la RLS o toman locks (migs 342/343): ni authenticated
    --     ni PUBLIC tienen TRUNCATE, TRIGGER, REFERENCES ni MAINTAIN en ninguna relacion de public, sin allowlist
    --     (anon ya lo cubren (c) y (d)). Una tabla nueva nace con los cuatro hasta la 344: hay que revocarlos.
    IF has_table_privilege('authenticated', r.oid,'TRUNCATE') OR has_table_privilege('authenticated', r.oid,'TRIGGER')
       OR has_table_privilege('authenticated', r.oid,'REFERENCES') OR has_table_privilege('authenticated', r.oid,'MAINTAIN')
       OR has_table_privilege('public', r.oid,'TRUNCATE') OR has_table_privilege('public', r.oid,'TRIGGER')
       OR has_table_privilege('public', r.oid,'REFERENCES') OR has_table_privilege('public', r.oid,'MAINTAIN') THEN
      v_viol := v_viol || E'\n(i) authenticated o PUBLIC con TRUNCATE/TRIGGER/REFERENCES/MAINTAIN: '||r.relname;
    END IF;

    -- (e) RLS deshabilitada en tabla
    IF r.relkind IN ('r','p') AND r.relrowsecurity = false THEN
      v_viol := v_viol || E'\n(e) RLS deshabilitada en tabla '||r.relname;
    END IF;

    -- (h) EJERCICIO: si anon conserva grant, un SELECT como anon debe responder SIN error
    --     (si una policy inline-a una tabla que anon ya no lee, lanza 42501 en vez de 0 filas).
    IF anon_tiene THEN
      BEGIN
        PERFORM set_config('role','anon', true);
        EXECUTE format('SELECT count(*) FROM public.%I', r.relname);
        PERFORM set_config('role','none', true);
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('role','none', true);
        v_viol := v_viol || E'\n(h) anon con grant pero la lectura falla: '||r.relname||' '||SQLSTATE;
      END;
    END IF;
  END LOOP;

  -- (f) ejercicio del rol anon sobre una tabla de public NO listada (una de las 49)
  BEGIN
    PERFORM set_config('role','anon', true);
    PERFORM 1 FROM public.empresa_capacidades LIMIT 1;
    anon_leyo := true;  -- si no fallo -> violacion
  EXCEPTION
    WHEN insufficient_privilege THEN anon_leyo := false;  -- comportamiento esperado (no leyo)
    WHEN OTHERS THEN f_err := '(f) error inesperado ejercitando anon: SQLSTATE=' || SQLSTATE || ' ' || SQLERRM;
  END;
  PERFORM set_config('role','none', true);  -- reset del role SIEMPRE, pase lo que pase
  IF anon_leyo THEN
    v_viol := v_viol || E'\n(f) anon PUDO leer public.empresa_capacidades (no esta en WL y deberia fallar)';
  END IF;
  IF f_err <> '' THEN
    v_viol := v_viol || E'\n' || f_err;
  END IF;


  -- =========================== FUNCIONES (pg_proc) — mig 370 ===========================
  -- Alcance: public y private, sin funciones de extensiones (pg_depend deptype 'e').
  -- ESTADO: 'post' = 0 con PUBLIC y anon solo en WL_ANON_FN; 'pre' = el estado previo a la 370 INTACTO Y EXACTO (las
  -- 38 con PUBLIC y anon explicito en las 21 legacy + la del catalogo, censo del 6-oct-2026); cualquier otra cosa se juzga
  -- estricto. Con 'pre', (j)/(k) y la mitad 42501 de (m) se reportan como PENDIENTE (no como PASA limpio); con cualquier
  -- otro estado, incluida una regresion despues del apply, son violacion. (l), la integridad de WL_ANON_FN y la mitad
  -- "el catalogo responde" de (m) se exigen SIEMPRE. Las listas pre38/pre22 se borran cuando la 370 este aplicada.
  IF array_length(wl_anon_fn, 1) > 1 THEN RAISE EXCEPTION 'P800: WL_ANON_FN solo puede achicarse (baseline 1 tras mig 370), tiene %', array_length(wl_anon_fn, 1); END IF;
  FOREACH nom IN ARRAY wl_anon_fn LOOP
    IF to_regprocedure(nom) IS NULL THEN
      v_viol := v_viol || E'\n(k) entrada huerfana en WL_ANON_FN: '||nom;
    ELSIF NOT has_function_privilege('anon', to_regprocedure(nom), 'EXECUTE') THEN
      v_viol := v_viol || E'\n(k) entrada de WL_ANON_FN sin EXECUTE de anon (sacarla de la lista): '||nom;
    END IF;
  END LOOP;

  WITH f AS (
    SELECT p.oid, n.nspname||'.'||p.proname||'('||COALESCE((SELECT string_agg(format_type(t, NULL), ', ' ORDER BY o)
             FROM unnest(p.proargtypes::oid[]) WITH ORDINALITY u(t, o)), '')||')' AS sig,
           EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') AS pub,
           EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 'anon'::regrole AND a.privilege_type = 'EXECUTE') AS anon_x
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'private')
       AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'))
  SELECT NOT EXISTS (SELECT f.sig FROM f WHERE f.pub EXCEPT SELECT unnest(pre38))
     AND NOT EXISTS (SELECT unnest(pre38) EXCEPT SELECT f.sig FROM f WHERE f.pub)
     AND NOT EXISTS (SELECT f.sig FROM f WHERE f.anon_x EXCEPT SELECT unnest(pre22))
     AND NOT EXISTS (SELECT unnest(pre22) EXCEPT SELECT f.sig FROM f WHERE f.anon_x)
    INTO fn_pre;

  FOR r IN
    SELECT p.oid, p.oid::regprocedure::text AS f,
           EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') AS pub,
           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_e
      FROM pg_proc p
     WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
       AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
     ORDER BY 2
  LOOP
    -- (j) ninguna funcion con EXECUTE para PUBLIC (proacl NULL = acldefault = PUBLIC incluido)
    IF r.pub THEN
      IF fn_pre THEN n_pend_j := n_pend_j + 1; ELSE v_viol := v_viol || E'\n(j) funcion con EXECUTE para PUBLIC: '||r.f; END IF;
    END IF;
    -- (k) anon solo en WL_ANON_FN
    IF r.anon_e AND NOT (r.oid = ANY (SELECT to_regprocedure(x)::oid FROM unnest(wl_anon_fn) x)) THEN
      IF fn_pre THEN n_pend_k := n_pend_k + 1; ELSE v_viol := v_viol || E'\n(k) anon con EXECUTE y fuera de WL_ANON_FN: '||r.f; END IF;
    END IF;
  END LOOP;

  -- (l) toda policy y toda funcion de la que depende (pg_depend): cada rol de la policy la puede ejecutar
  --     (public -> anon y authenticated). Una policy se evalua con los privilegios del LLAMANTE (leccion 284): sin
  --     EXECUTE, la tabla le lanza 42501 a ese rol en vez de negarle filas.
  FOR r IN
    SELECT DISTINCT pl.polname, pl.polrelid::regclass::text AS tabla, d.refobjid::regprocedure::text AS f, rr.rl
      FROM pg_policy pl
      JOIN pg_depend d ON d.classid = 'pg_policy'::regclass AND d.objid = pl.oid AND d.refclassid = 'pg_proc'::regclass
      CROSS JOIN LATERAL (SELECT CASE WHEN x = 0 THEN 'anon' ELSE pg_get_userbyid(x) END AS rl FROM unnest(pl.polroles) x
                          UNION SELECT 'authenticated' WHERE 0 = ANY (pl.polroles)) rr
     WHERE NOT has_function_privilege(rr.rl, d.refobjid, 'EXECUTE')
     ORDER BY 2, 1
  LOOP
    v_viol := v_viol || E'\n(l) la policy '||r.polname||' de '||r.tabla||' usa '||r.f||' y '||r.rl||' no la puede ejecutar';
  END LOOP;

  -- (m) EJERCICIO como anon: la funcion de la WL responde; una helper de policy da 42501
  BEGIN
    PERFORM set_config('role', 'anon', true);
    PERFORM count(*) FROM public.catalogo_planes_visitador_publico();
    PERFORM set_config('role', 'none', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    v_viol := v_viol || E'\n(m) anon no pudo ejecutar catalogo_planes_visitador_publico(): '||SQLSTATE||' '||SQLERRM;
  END;
  m_st := '00000';
  BEGIN
    PERFORM set_config('role', 'anon', true);
    PERFORM public.get_auth_user_rol();
    PERFORM set_config('role', 'none', true);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM set_config('role', 'none', true); m_st := '42501';
  WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true); m_st := SQLSTATE;
  END;
  IF m_st <> '42501' THEN
    IF fn_pre AND m_st = '00000' THEN n_pend_m := 1;
    ELSE v_viol := v_viol || E'\n(m) anon ejecuto public.get_auth_user_rol() (SQLSTATE '||m_st||'; se esperaba 42501)'; END IF;
  END IF;
  IF fn_pre THEN
    PERFORM set_config('p800.pendiente', ' — (j)/(k)/(m) PENDIENTE mig 370: estado previo intacto ('||n_pend_j||' con PUBLIC, '
                       ||n_pend_k||' ejecutables por anon fuera de WL_ANON_FN, get_auth_user_rol ejecutable por anon='||n_pend_m||')', true);
  END IF;

  IF v_viol <> '' THEN
    RAISE EXCEPTION 'P800 GATE DE GRANTS — VIOLACIONES:%', v_viol;
  END IF;
END $p800$;
SELECT 'P800 PASA (0 violaciones)'||COALESCE(current_setting('p800.pendiente', true), '') AS resultado;
ROLLBACK;
