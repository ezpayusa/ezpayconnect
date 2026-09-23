-- ############################################################################################
-- ROLLBACK de la mig 324 - restaura SELECT de anon en las 72 relaciones.  (23-sep-2026)
-- Solo SELECT (era lo unico que anon tenia). Las 6 dependencias y las 2 de config no se tocaron.
-- ############################################################################################
GRANT SELECT ON public.auditoria_ia TO anon;
GRANT SELECT ON public.auditoria_logs TO anon;
GRANT SELECT ON public.cache_biblioteca TO anon;
GRANT SELECT ON public.campana_metricas TO anon;
GRANT SELECT ON public.campana_vistas TO anon;
GRANT SELECT ON public.campanas_publicitarias TO anon;
GRANT SELECT ON public.chat_conversaciones TO anon;
GRANT SELECT ON public.chat_lecturas TO anon;
GRANT SELECT ON public.chat_mensajes TO anon;
GRANT SELECT ON public.chat_mensajes_internos TO anon;
GRANT SELECT ON public.chat_participantes TO anon;
GRANT SELECT ON public.citas TO anon;
GRANT SELECT ON public.clinicas TO anon;
GRANT SELECT ON public.configuracion TO anon;
GRANT SELECT ON public.confirmaciones_receta TO anon;
GRANT SELECT ON public.contratos_comision TO anon;
GRANT SELECT ON public.cuentas_bancarias_pais TO anon;
GRANT SELECT ON public.disponibilidad_medico TO anon;
GRANT SELECT ON public.empresa_paises_operacion TO anon;
GRANT SELECT ON public.entrega_evidencias TO anon;
GRANT SELECT ON public.equipos_visitadores TO anon;
GRANT SELECT ON public.examenes TO anon;
GRANT SELECT ON public.examenes_catalogo TO anon;
GRANT SELECT ON public.expediente_notas TO anon;
GRANT SELECT ON public.facturas TO anon;
GRANT SELECT ON public.invitaciones_clinica TO anon;
GRANT SELECT ON public.invitaciones_laboratorio TO anon;
GRANT SELECT ON public.invitaciones_medico TO anon;
GRANT SELECT ON public.invitaciones_visitador TO anon;
GRANT SELECT ON public.laboratorio_clinicas TO anon;
GRANT SELECT ON public.liquidacion_dispensaciones TO anon;
GRANT SELECT ON public.medico_clinicas TO anon;
GRANT SELECT ON public.medico_correlativos TO anon;
GRANT SELECT ON public.notificaciones TO anon;
GRANT SELECT ON public.notificaciones_email TO anon;
GRANT SELECT ON public.notificaciones_pacientes TO anon;
GRANT SELECT ON public.ordenes_examen TO anon;
GRANT SELECT ON public.pagos_proveedor TO anon;
GRANT SELECT ON public.permisos_empresa_rol TO anon;
GRANT SELECT ON public.planes_asignaciones TO anon;
GRANT SELECT ON public.planes_excepciones TO anon;
GRANT SELECT ON public.planes_features TO anon;
GRANT SELECT ON public.planes_historial TO anon;
GRANT SELECT ON public.planes_limites TO anon;
GRANT SELECT ON public.planes_visitador_contratados TO anon;
GRANT SELECT ON public.productos_empresa TO anon;
GRANT SELECT ON public.push_subscriptions TO anon;
GRANT SELECT ON public.push_tokens TO anon;
GRANT SELECT ON public.receta_items TO anon;
GRANT SELECT ON public.recordatorios TO anon;
GRANT SELECT ON public.recordatorios_citas TO anon;
GRANT SELECT ON public.recordatorios_programados TO anon;
GRANT SELECT ON public.reportes_guardados TO anon;
GRANT SELECT ON public.resumen_comisiones TO anon;
GRANT SELECT ON public.roles TO anon;
GRANT SELECT ON public.roles_catalogo TO anon;
GRANT SELECT ON public.roles_empresa_catalogo TO anon;
GRANT SELECT ON public.signos_vitales TO anon;
GRANT SELECT ON public.solicitudes_campana TO anon;
GRANT SELECT ON public.transacciones TO anon;
GRANT SELECT ON public.ubicaciones_medico_proveedor TO anon;
GRANT SELECT ON public.usuario_roles TO anon;
GRANT SELECT ON public.v_citas_hoy TO anon;
GRANT SELECT ON public.v_consultas_paciente TO anon;
GRANT SELECT ON public.v_estadisticas_medico TO anon;
GRANT SELECT ON public.v_medicamentos_bajo_stock TO anon;
GRANT SELECT ON public.v_metricas_campana_pais TO anon;
GRANT SELECT ON public.v_metricas_campana_resumen TO anon;
GRANT SELECT ON public.v_pacientes_actividad TO anon;
GRANT SELECT ON public.v_resumen_mensual TO anon;
GRANT SELECT ON public.visitas_agendadas TO anon;
GRANT SELECT ON public.whatsapp_mensajes TO anon;

-- AUTOCHEQUEO: anon vuelve a tener SELECT en las 72.
DO $ac$
DECLARE nom text; v_viol text := ''; oidx oid; arr72 text[] := ARRAY['auditoria_ia','auditoria_logs','cache_biblioteca','campana_metricas','campana_vistas','campanas_publicitarias','chat_conversaciones','chat_lecturas','chat_mensajes','chat_mensajes_internos','chat_participantes','citas','clinicas','configuracion','confirmaciones_receta','contratos_comision','cuentas_bancarias_pais','disponibilidad_medico','empresa_paises_operacion','entrega_evidencias','equipos_visitadores','examenes','examenes_catalogo','expediente_notas','facturas','invitaciones_clinica','invitaciones_laboratorio','invitaciones_medico','invitaciones_visitador','laboratorio_clinicas','liquidacion_dispensaciones','medico_clinicas','medico_correlativos','notificaciones','notificaciones_email','notificaciones_pacientes','ordenes_examen','pagos_proveedor','permisos_empresa_rol','planes_asignaciones','planes_excepciones','planes_features','planes_historial','planes_limites','planes_visitador_contratados','productos_empresa','push_subscriptions','push_tokens','receta_items','recordatorios','recordatorios_citas','recordatorios_programados','reportes_guardados','resumen_comisiones','roles','roles_catalogo','roles_empresa_catalogo','signos_vitales','solicitudes_campana','transacciones','ubicaciones_medico_proveedor','usuario_roles','v_citas_hoy','v_consultas_paciente','v_estadisticas_medico','v_medicamentos_bajo_stock','v_metricas_campana_pais','v_metricas_campana_resumen','v_pacientes_actividad','v_resumen_mensual','visitas_agendadas','whatsapp_mensajes'];
BEGIN
  FOREACH nom IN ARRAY arr72 LOOP
    SELECT c.oid INTO oidx FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=nom;
    IF oidx IS NULL THEN v_viol := v_viol||E'\n no existe public.'||nom; CONTINUE; END IF;
    IF NOT has_table_privilege('anon',oidx,'SELECT') THEN v_viol := v_viol||E'\n anon SIN SELECT en '||nom; END IF;
  END LOOP;
  IF v_viol <> '' THEN RAISE EXCEPTION 'ROLLBACK324 FALLA:%', v_viol; END IF;
  RAISE NOTICE 'ROLLBACK324 OK: anon con SELECT en las 72.';
END $ac$;
