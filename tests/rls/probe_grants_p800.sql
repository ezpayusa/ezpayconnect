-- ############################################################################################
-- probe_grants_p800.sql — GATE GLOBAL DE GRANTS DEL DATA API en public. Correr AISLADO:
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
-- ============================================================================
DO $p800$
DECLARE
  -- WL_ANON_LEGACY — BASELINE LEGACY 23-sep-2026 — congelada, solo puede achicarse
  wl_anon text[] := ARRAY['auditoria_ia','auditoria_logs','cache_biblioteca','campana_metricas','campana_vistas','campanas_publicitarias','chat_conversaciones','chat_lecturas','chat_mensajes','chat_mensajes_internos','chat_participantes','citas','clinicas','configuracion','configuracion_pais','configuracion_sistema','confirmaciones_receta','contratos_comision','cuentas_bancarias_pais','cuentas_proveedor','disponibilidad_medico','empresa_paises_operacion','empresas_proveedoras','entrega_evidencias','equipos_visitadores','examenes','examenes_catalogo','expediente_notas','facturas','invitaciones_clinica','invitaciones_laboratorio','invitaciones_medico','invitaciones_visitador','laboratorio_clinicas','liquidacion_dispensaciones','liquidaciones_comision','medico_clinicas','medico_correlativos','notificaciones','notificaciones_email','notificaciones_pacientes','ordenes_examen','pacientes','pagos_proveedor','perfiles','permisos_empresa_rol','planes_asignaciones','planes_excepciones','planes_features','planes_historial','planes_limites','planes_visitador_contratados','productos_empresa','push_subscriptions','push_tokens','receta_items','recetas','recordatorios','recordatorios_citas','recordatorios_programados','reportes_guardados','resumen_comisiones','roles','roles_catalogo','roles_empresa_catalogo','signos_vitales','solicitudes_campana','transacciones','ubicaciones_medico_proveedor','usuario_roles','v_citas_hoy','v_consultas_paciente','v_estadisticas_medico','v_medicamentos_bajo_stock','v_metricas_campana_pais','v_metricas_campana_resumen','v_pacientes_actividad','v_resumen_mensual','visitas_agendadas','whatsapp_mensajes'];
  wl_auth text[] := ARRAY['empresa_capacidades','jornadas_comerciales','medicamentos_clasificacion_log','solicitudes_capacidad_pais','visitas_comerciales'];
  r record;
  v_viol text := '';
  auth_tiene boolean;
  anon_tiene boolean;
  anon_no_select boolean;
  anon_leyo boolean := false;
  f_err text := '';
  nom text;
BEGIN
  -- FIX 3: las listas blancas solo pueden ACHICARSE (nunca crecer sobre el baseline).
  IF array_length(wl_anon,1) > 80 THEN RAISE EXCEPTION 'P800: WL_ANON_LEGACY solo puede achicarse (baseline 80), tiene %', array_length(wl_anon,1); END IF;
  IF array_length(wl_auth,1) > 5  THEN RAISE EXCEPTION 'P800: WL_AUTH_SIN_GRANT solo puede achicarse (baseline 5), tiene %', array_length(wl_auth,1); END IF;
  -- (g) entradas huerfanas: nombre en la WL que ya no existe como relacion en public (limpiar la lista).
  FOREACH nom IN ARRAY wl_anon LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
                    WHERE ns.nspname='public' AND c.relname=nom AND c.relkind IN ('r','v','m','p')) THEN
      v_viol := v_viol || E'\n(g) entrada huerfana en WL: '||nom;
    END IF;
  END LOOP;
  FOREACH nom IN ARRAY wl_auth LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
                    WHERE ns.nspname='public' AND c.relname=nom AND c.relkind IN ('r','v','m','p')) THEN
      v_viol := v_viol || E'\n(g) entrada huerfana en WL: '||nom;
    END IF;
  END LOOP;

  FOR r IN
    SELECT c.oid, c.relname, c.relkind, c.relrowsecurity
      FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND c.relkind IN ('r','v','m','p')
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
      OR has_table_privilege('anon', r.oid,'TRUNCATE') OR has_any_column_privilege('anon', r.oid, 'SELECT,INSERT,UPDATE,REFERENCES');
    -- (c) anon con cualquier privilegio y fuera de WL_ANON_LEGACY
    IF anon_tiene AND NOT (r.relname = ANY(wl_anon)) THEN
      v_viol := v_viol || E'\n(c) anon CON privilegio y fuera de WL_ANON_LEGACY: '||r.relname;
    END IF;
    -- (d) en WL_ANON_LEGACY pero con algo != SELECT
    anon_no_select := has_table_privilege('anon', r.oid,'INSERT') OR has_table_privilege('anon', r.oid,'UPDATE')
      OR has_table_privilege('anon', r.oid,'DELETE') OR has_table_privilege('anon', r.oid,'REFERENCES') OR has_table_privilege('anon', r.oid,'TRIGGER')
      OR has_table_privilege('anon', r.oid,'TRUNCATE') OR has_any_column_privilege('anon', r.oid, 'INSERT,UPDATE,REFERENCES');
    IF (r.relname = ANY(wl_anon)) AND anon_no_select THEN
      v_viol := v_viol || E'\n(d) anon con privilegio != SELECT en WL_ANON_LEGACY: '||r.relname;
    END IF;

    -- (e) RLS deshabilitada en tabla
    IF r.relkind IN ('r','p') AND r.relrowsecurity = false THEN
      v_viol := v_viol || E'\n(e) RLS deshabilitada en tabla '||r.relname;
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

  IF v_viol <> '' THEN
    RAISE EXCEPTION 'P800 GATE DE GRANTS — VIOLACIONES:%', v_viol;
  END IF;
END $p800$;
SELECT 'P800 PASA (0 violaciones)' AS resultado;
ROLLBACK;
