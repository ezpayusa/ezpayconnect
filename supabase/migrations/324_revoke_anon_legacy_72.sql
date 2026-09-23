-- ############################################################################################
-- Migracion 324 - REVOKE anon sobre 72 relaciones legacy de WL_ANON_LEGACY   (23-sep-2026)
-- ############################################################################################
-- CONTEXTO: Supabase deja de auto-otorgar GRANTs del Data API el 30-oct-2026. El recon del 23-sep
-- midio las 80 relaciones con SELECT de anon: casi todas devuelven 0 filas o 42501 a anon y no
-- tienen caller sin sesion (las 8 vistas son security_invoker -> heredan la RLS del invocador).
--
-- SE REVOCAN 72. Se DEJAN 8 con SELECT de anon, a proposito:
--   * configuracion_pais / configuracion_sistema - uso sin sesion (dropdown de registro) y policy
--     anon explicita (config no-bancaria). configuracion_sistema pendiente de revision.
--   * perfiles, pacientes, cuentas_proveedor, empresas_proveedoras, liquidaciones_comision, recetas
--     - DEPENDENCIAS INLINE de policies de OTRAS tablas (perfiles en 28, pacientes 12,
--     cuentas_proveedor 3, empresas_proveedoras 2, liquidaciones_comision 1, recetas 1). Una policy
--     se evalua con los privilegios del LLAMANTE: si anon pierde SELECT sobre estas tablas, TODA
--     policy que las consulta inline lanza 42501 a anon en vez de negar en silencio (leccion mig 284).
--     Medido: revocar perfiles rompe la lectura anonima de configuracion_sistema. Su cierre requiere
--     reescribir esas policies a helpers SECURITY DEFINER (get_auth_user_rol, mi_empresa_proveedor,
--     etc.) - FRENTE APARTE, no en esta migracion.
-- Sin ALTER DEFAULT PRIVILEGES. Autochequeo (a)-(d) con RAISE al final. Aplicar con: db query --linked -f.

-- 0) SNAPSHOT ANTES: firma de privilegios de authenticated y service_role sobre las 80 (72+8).
CREATE TEMP TABLE _snap_324 (rel text, rol text, sig text) ON COMMIT DROP;
INSERT INTO _snap_324
SELECT c.relname, v.rol,
       has_table_privilege(v.rol,c.oid,'SELECT')::int::text||has_table_privilege(v.rol,c.oid,'INSERT')::int::text
     ||has_table_privilege(v.rol,c.oid,'UPDATE')::int::text||has_table_privilege(v.rol,c.oid,'DELETE')::int::text
     ||has_table_privilege(v.rol,c.oid,'TRUNCATE')::int::text||has_table_privilege(v.rol,c.oid,'REFERENCES')::int::text
     ||has_table_privilege(v.rol,c.oid,'TRIGGER')::int::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN (VALUES ('authenticated'),('service_role')) v(rol)
 WHERE n.nspname='public' AND c.relname = ANY(ARRAY['auditoria_ia','auditoria_logs','cache_biblioteca','campana_metricas','campana_vistas','campanas_publicitarias','chat_conversaciones','chat_lecturas','chat_mensajes','chat_mensajes_internos','chat_participantes','citas','clinicas','configuracion','confirmaciones_receta','contratos_comision','cuentas_bancarias_pais','disponibilidad_medico','empresa_paises_operacion','entrega_evidencias','equipos_visitadores','examenes','examenes_catalogo','expediente_notas','facturas','invitaciones_clinica','invitaciones_laboratorio','invitaciones_medico','invitaciones_visitador','laboratorio_clinicas','liquidacion_dispensaciones','medico_clinicas','medico_correlativos','notificaciones','notificaciones_email','notificaciones_pacientes','ordenes_examen','pagos_proveedor','permisos_empresa_rol','planes_asignaciones','planes_excepciones','planes_features','planes_historial','planes_limites','planes_visitador_contratados','productos_empresa','push_subscriptions','push_tokens','receta_items','recordatorios','recordatorios_citas','recordatorios_programados','reportes_guardados','resumen_comisiones','roles','roles_catalogo','roles_empresa_catalogo','signos_vitales','solicitudes_campana','transacciones','ubicaciones_medico_proveedor','usuario_roles','v_citas_hoy','v_consultas_paciente','v_estadisticas_medico','v_medicamentos_bajo_stock','v_metricas_campana_pais','v_metricas_campana_resumen','v_pacientes_actividad','v_resumen_mensual','visitas_agendadas','whatsapp_mensajes','configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas']);

-- 1) REVOKE ALL de anon sobre las 72 (alfabetico, una por linea).
REVOKE ALL ON public.auditoria_ia FROM anon;
REVOKE ALL ON public.auditoria_logs FROM anon;
REVOKE ALL ON public.cache_biblioteca FROM anon;
REVOKE ALL ON public.campana_metricas FROM anon;
REVOKE ALL ON public.campana_vistas FROM anon;
REVOKE ALL ON public.campanas_publicitarias FROM anon;
REVOKE ALL ON public.chat_conversaciones FROM anon;
REVOKE ALL ON public.chat_lecturas FROM anon;
REVOKE ALL ON public.chat_mensajes FROM anon;
REVOKE ALL ON public.chat_mensajes_internos FROM anon;
REVOKE ALL ON public.chat_participantes FROM anon;
REVOKE ALL ON public.citas FROM anon;
REVOKE ALL ON public.clinicas FROM anon;
REVOKE ALL ON public.configuracion FROM anon;
REVOKE ALL ON public.confirmaciones_receta FROM anon;
REVOKE ALL ON public.contratos_comision FROM anon;
REVOKE ALL ON public.cuentas_bancarias_pais FROM anon;
REVOKE ALL ON public.disponibilidad_medico FROM anon;
REVOKE ALL ON public.empresa_paises_operacion FROM anon;
REVOKE ALL ON public.entrega_evidencias FROM anon;
REVOKE ALL ON public.equipos_visitadores FROM anon;
REVOKE ALL ON public.examenes FROM anon;
REVOKE ALL ON public.examenes_catalogo FROM anon;
REVOKE ALL ON public.expediente_notas FROM anon;
REVOKE ALL ON public.facturas FROM anon;
REVOKE ALL ON public.invitaciones_clinica FROM anon;
REVOKE ALL ON public.invitaciones_laboratorio FROM anon;
REVOKE ALL ON public.invitaciones_medico FROM anon;
REVOKE ALL ON public.invitaciones_visitador FROM anon;
REVOKE ALL ON public.laboratorio_clinicas FROM anon;
REVOKE ALL ON public.liquidacion_dispensaciones FROM anon;
REVOKE ALL ON public.medico_clinicas FROM anon;
REVOKE ALL ON public.medico_correlativos FROM anon;
REVOKE ALL ON public.notificaciones FROM anon;
REVOKE ALL ON public.notificaciones_email FROM anon;
REVOKE ALL ON public.notificaciones_pacientes FROM anon;
REVOKE ALL ON public.ordenes_examen FROM anon;
REVOKE ALL ON public.pagos_proveedor FROM anon;
REVOKE ALL ON public.permisos_empresa_rol FROM anon;
REVOKE ALL ON public.planes_asignaciones FROM anon;
REVOKE ALL ON public.planes_excepciones FROM anon;
REVOKE ALL ON public.planes_features FROM anon;
REVOKE ALL ON public.planes_historial FROM anon;
REVOKE ALL ON public.planes_limites FROM anon;
REVOKE ALL ON public.planes_visitador_contratados FROM anon;
REVOKE ALL ON public.productos_empresa FROM anon;
REVOKE ALL ON public.push_subscriptions FROM anon;
REVOKE ALL ON public.push_tokens FROM anon;
REVOKE ALL ON public.receta_items FROM anon;
REVOKE ALL ON public.recordatorios FROM anon;
REVOKE ALL ON public.recordatorios_citas FROM anon;
REVOKE ALL ON public.recordatorios_programados FROM anon;
REVOKE ALL ON public.reportes_guardados FROM anon;
REVOKE ALL ON public.resumen_comisiones FROM anon;
REVOKE ALL ON public.roles FROM anon;
REVOKE ALL ON public.roles_catalogo FROM anon;
REVOKE ALL ON public.roles_empresa_catalogo FROM anon;
REVOKE ALL ON public.signos_vitales FROM anon;
REVOKE ALL ON public.solicitudes_campana FROM anon;
REVOKE ALL ON public.transacciones FROM anon;
REVOKE ALL ON public.ubicaciones_medico_proveedor FROM anon;
REVOKE ALL ON public.usuario_roles FROM anon;
REVOKE ALL ON public.v_citas_hoy FROM anon;
REVOKE ALL ON public.v_consultas_paciente FROM anon;
REVOKE ALL ON public.v_estadisticas_medico FROM anon;
REVOKE ALL ON public.v_medicamentos_bajo_stock FROM anon;
REVOKE ALL ON public.v_metricas_campana_pais FROM anon;
REVOKE ALL ON public.v_metricas_campana_resumen FROM anon;
REVOKE ALL ON public.v_pacientes_actividad FROM anon;
REVOKE ALL ON public.v_resumen_mensual FROM anon;
REVOKE ALL ON public.visitas_agendadas FROM anon;
REVOKE ALL ON public.whatsapp_mensajes FROM anon;

-- 2) AUTOCHEQUEO (a)-(d)
DO $ac$
DECLARE nom text; v_viol text := ''; oidx oid; v_sig text; n bigint;
  arr72 text[] := ARRAY['auditoria_ia','auditoria_logs','cache_biblioteca','campana_metricas','campana_vistas','campanas_publicitarias','chat_conversaciones','chat_lecturas','chat_mensajes','chat_mensajes_internos','chat_participantes','citas','clinicas','configuracion','confirmaciones_receta','contratos_comision','cuentas_bancarias_pais','disponibilidad_medico','empresa_paises_operacion','entrega_evidencias','equipos_visitadores','examenes','examenes_catalogo','expediente_notas','facturas','invitaciones_clinica','invitaciones_laboratorio','invitaciones_medico','invitaciones_visitador','laboratorio_clinicas','liquidacion_dispensaciones','medico_clinicas','medico_correlativos','notificaciones','notificaciones_email','notificaciones_pacientes','ordenes_examen','pagos_proveedor','permisos_empresa_rol','planes_asignaciones','planes_excepciones','planes_features','planes_historial','planes_limites','planes_visitador_contratados','productos_empresa','push_subscriptions','push_tokens','receta_items','recordatorios','recordatorios_citas','recordatorios_programados','reportes_guardados','resumen_comisiones','roles','roles_catalogo','roles_empresa_catalogo','signos_vitales','solicitudes_campana','transacciones','ubicaciones_medico_proveedor','usuario_roles','v_citas_hoy','v_consultas_paciente','v_estadisticas_medico','v_medicamentos_bajo_stock','v_metricas_campana_pais','v_metricas_campana_resumen','v_pacientes_actividad','v_resumen_mensual','visitas_agendadas','whatsapp_mensajes'];
  keep8 text[] := ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas'];
BEGIN
  -- (a) anon NO conserva ningun privilegio (tabla o columna) sobre las 72
  FOREACH nom IN ARRAY arr72 LOOP
    SELECT c.oid INTO oidx FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=nom;
    IF oidx IS NULL THEN v_viol := v_viol||E'\n(a) no existe public.'||nom; CONTINUE; END IF;
    IF has_table_privilege('anon',oidx,'SELECT') OR has_table_privilege('anon',oidx,'INSERT')
       OR has_table_privilege('anon',oidx,'UPDATE') OR has_table_privilege('anon',oidx,'DELETE')
       OR has_table_privilege('anon',oidx,'TRUNCATE') OR has_table_privilege('anon',oidx,'REFERENCES')
       OR has_table_privilege('anon',oidx,'TRIGGER')
       OR has_any_column_privilege('anon',oidx,'SELECT,INSERT,UPDATE,REFERENCES') THEN
      v_viol := v_viol||E'\n(a) anon CONSERVA privilegio en '||nom;
    END IF;
  END LOOP;
  -- (b) anon SIGUE con SELECT en las 8 que quedan
  FOREACH nom IN ARRAY keep8 LOOP
    IF NOT has_table_privilege('anon',('public.'||nom)::regclass,'SELECT') THEN v_viol := v_viol||E'\n(b) anon perdio SELECT en '||nom; END IF;
  END LOOP;
  -- (c) authenticated / service_role SIN cambios respecto del snapshot
  FOR nom, v_sig IN
    SELECT s.rel||'/'||s.rol, s.sig FROM _snap_324 s
     JOIN pg_class c ON c.relname=s.rel JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
    WHERE s.sig IS DISTINCT FROM (
       has_table_privilege(s.rol,c.oid,'SELECT')::int::text||has_table_privilege(s.rol,c.oid,'INSERT')::int::text
     ||has_table_privilege(s.rol,c.oid,'UPDATE')::int::text||has_table_privilege(s.rol,c.oid,'DELETE')::int::text
     ||has_table_privilege(s.rol,c.oid,'TRUNCATE')::int::text||has_table_privilege(s.rol,c.oid,'REFERENCES')::int::text
     ||has_table_privilege(s.rol,c.oid,'TRIGGER')::int::text)
  LOOP
    v_viol := v_viol||E'\n(c) cambio priv de '||nom||' (antes '||v_sig||')';
  END LOOP;
  -- (d) EJERCICIO REAL: toda relacion de public donde anon CONSERVE algun privilegio debe
  --     responderle un SELECT sin error (si no, alguna policy la rompe con 42501).
  FOR nom IN
    SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind IN ('r','v','m','p')
       AND (has_table_privilege('anon',c.oid,'SELECT') OR has_any_column_privilege('anon',c.oid,'SELECT'))
     ORDER BY c.relname
  LOOP
    BEGIN
      PERFORM set_config('role','anon',true);
      EXECUTE format('SELECT count(*) FROM public.%I', nom) INTO n;
      PERFORM set_config('role','none',true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('role','none',true);
      v_viol := v_viol||E'\n(d) anon con grant pero la lectura falla: '||nom||' '||SQLSTATE;
    END;
  END LOOP;

  IF v_viol <> '' THEN RAISE EXCEPTION 'MIG324 AUTOCHEQUEO FALLA:%', v_viol; END IF;
  RAISE NOTICE 'MIG324 OK: anon revocado en 72, conserva SELECT en las 8, authenticated/service_role intactos, ejercicio (d) sin errores.';
END $ac$;
