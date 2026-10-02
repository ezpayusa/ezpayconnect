-- ############################################################################################
-- 343 - familia 1 (privilegios), paso 2: REVOKE MAINTAIN en public
-- ############################################################################################
-- MAINTAIN (PG17) habilita VACUUM, ANALYZE, CLUSTER, REINDEX, REFRESH MATERIALIZED VIEW y LOCK TABLE. Medido
-- el 2-oct-2026 sobre c2d837e (tras la 342): authenticated lo tiene en 114 de las 132 relaciones de public y anon
-- en 8 (configuracion_pais, configuracion_sistema, cuentas_proveedor, empresas_proveedoras,
-- liquidaciones_comision, medicos, pacientes, recetas); PUBLIC en ninguna; private (7 tablas) en ninguna. Todas
-- de postgres, grantor postgres, sin grant option. Viene del default privilege de postgres en public. Ningun
-- cliente lo usa (PostgREST y pg_graphql no emiten VACUUM ni LOCK), pero con SQL directo un LOCK TABLE ... ACCESS
-- EXCLUSIVE deja fuera de servicio una tabla clinica (VACUUM FULL/CLUSTER/REINDEX tambien toman locks fuertes).
-- P800 no lo veia (miraba role_table_grants): se extiende en este mismo paso.
--
-- Cambio (unico): REVOKE MAINTAIN FROM anon, authenticated, PUBLIC sobre la lista EXPLICITA de las 114
-- relaciones de public que hoy lo tienen (las 8 de anon estan incluidas). NO se tocan SELECT/INSERT/UPDATE/DELETE,
-- grants por columna, service_role/postgres/supabase_admin ni pg_default_acl (los defaults = 344).
-- Huellas (aclexplode de las 132 relaciones de public, misma expresion que la 342):
--   completa PRE c57c024fec00ca4819a97bf020cfae6b (= POST de la 342); resto (sin MAINTAIN de esos 3 roles) 855f079761052808e9593a8911baaac2, igual PRE y POST;
--   grants por columna dab25af63754e06d699ac3bd454011a6; pg_default_acl 1f07b802bdb4ee70eb46bd21f46a8d3d.
-- Probe: P925 (censo global de MAINTAIN en public y private). Ajuste: P884 (examenes_catalogo sin MAINTAIN).
-- Rollback: 343_rollback.sql (independiente de 334-341; aplicar antes que 342_rollback si se revierten ambas).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
-- Estado PRE medido en prod el 2-oct-2026. Una segunda pasada aborta aca: los conteos ya no son los PRE.
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- cantidad y duenio de las relaciones de public y private (todas de postgres: su REVOKE alcanza a todos los grants)
  v := (SELECT string_agg(z.k, ',' ORDER BY z.k) FROM (SELECT n.nspname||'='||count(*)||':'||string_agg(DISTINCT pg_get_userbyid(c.relowner), '+') AS k
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m','f') GROUP BY n.nspname) z);
  IF v IS DISTINCT FROM 'private=7:postgres,public=132:postgres' THEN bad := bad||'relaciones '||COALESCE(v, '-')||'; '; END IF;
  -- huella completa de la ACL de las 132 relaciones de public (misma expresion que la 342)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'c57c024fec00ca4819a97bf020cfae6b' THEN bad := bad||'huella completa '||COALESCE(v, '-')||'; '; END IF;
  -- MAINTAIN de anon, authenticated y PUBLIC en public y private: ACL (aclexplode) y efectivo (has_table_privilege)
  v := (SELECT COALESCE(string_agg(k||'='||n, ',' ORDER BY k COLLATE "C"), '-') FROM (
      SELECT n.nspname||':'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS k, count(*) AS n
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m','f') AND a.privilege_type = 'MAINTAIN' AND a.grantee IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid)
       GROUP BY 1) z);
  IF v IS DISTINCT FROM 'public:anon=8,public:authenticated=114' THEN bad := bad||'MAINTAIN '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT count(*) FILTER (WHERE has_table_privilege('anon', c.oid, 'MAINTAIN'))||'/'||count(*) FILTER (WHERE has_table_privilege('authenticated', c.oid, 'MAINTAIN'))||'/'||count(*) FILTER (WHERE has_table_privilege('public', c.oid, 'MAINTAIN'))
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m','f'));
  IF v IS DISTINCT FROM '8/114/0' THEN bad := bad||'MAINTAIN efectivo anon/auth/PUBLIC '||COALESCE(v, '-')||'; '; END IF;
  -- TRUNCATE/TRIGGER/REFERENCES siguen en 0 (342)
  v := (SELECT count(*)::text FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE x.pv IN ('TRUNCATE','TRIGGER','REFERENCES') AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid));
  IF v IS DISTINCT FROM '0' THEN bad := bad||'TRUNCATE/TRIGGER/REFERENCES '||COALESCE(v, '-')||'; '; END IF;
  -- el resto de la ACL de public (todo menos MAINTAIN de esos tres roles)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE NOT (x.pv = 'MAINTAIN' AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid)));
  IF v IS DISTINCT FROM '855f079761052808e9593a8911baaac2' THEN bad := bad||'resto de la ACL '||COALESCE(v, '-')||'; '; END IF;
  -- grants por columna y default privileges (la 343 no los toca; los defaults son la 344)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '1f07b802bdb4ee70eb46bd21f46a8d3d' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG343 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------- el REVOKE
-- Las 114 relaciones de public con MAINTAIN de authenticated; las 8 de anon son un subconjunto. PUBLIC no lo
-- tiene en ninguna: se nombra igual para que el REVOKE cierre la clase entera.
REVOKE MAINTAIN ON TABLE
  public.acciones_techo,
  public.asesores_perfil,
  public.auditoria_ia,
  public.auditoria_logs,
  public.cache_biblioteca,
  public.campana_metricas,
  public.campana_vistas,
  public.campanas_publicitarias,
  public.canjes,
  public.capacidades_catalogo,
  public.catalogo_pipeline_estado,
  public.catalogo_prospecto_tipo,
  public.chat_conversaciones,
  public.chat_lecturas,
  public.chat_mensajes,
  public.chat_mensajes_internos,
  public.chat_participantes,
  public.citas,
  public.clinicas,
  public.configuracion,
  public.configuracion_pais,
  public.configuracion_sistema,
  public.confirmaciones_receta,
  public.consentimiento_permisos,
  public.consentimientos,
  public.contratos_comision,
  public.cuentas_bancarias_pais,
  public.cuentas_proveedor,
  public.dispensaciones,
  public.disponibilidad_medico,
  public.documentos_paciente,
  public.empresa_paises_operacion,
  public.empresas_proveedoras,
  public.entrega_evidencias,
  public.entregas,
  public.envios_push_cola,
  public.equipos_visitadores,
  public.especialidades,
  public.especialidades_propuestas,
  public.examenes_catalogo,
  public.facturas,
  public.farmacia_medicamentos,
  public.farmacias,
  public.historial_medico,
  public.invitaciones_clinica,
  public.invitaciones_laboratorio,
  public.invitaciones_medico,
  public.invitaciones_visitador,
  public.laboratorio_clinicas,
  public.liquidacion_dispensaciones,
  public.liquidaciones_comision,
  public.medicamentos,
  public.medicamentos_categorias,
  public.medico_clinicas,
  public.medico_correlativos,
  public.medicos,
  public.notificaciones,
  public.notificaciones_email,
  public.notificaciones_pacientes,
  public.pacientes,
  public.pagos_proveedor,
  public.perfiles,
  public.permisos_empresa_rol,
  public.permisos_empresa_rol_override,
  public.planes_asignaciones,
  public.planes_base,
  public.planes_configuracion,
  public.planes_excepciones,
  public.planes_features,
  public.planes_historial,
  public.planes_limites,
  public.planes_publicidad,
  public.planes_publicidad_config,
  public.planes_visitador_contratados,
  public.preferencias_notificacion,
  public.premios,
  public.productos_empresa,
  public.prospecto_contactos,
  public.prospectos,
  public.puntos_movimientos,
  public.push_subscriptions,
  public.push_tokens,
  public.receta_items,
  public.recetas,
  public.recetas_avanzadas,
  public.recordatorios,
  public.recordatorios_citas,
  public.recordatorios_programados,
  public.referidos_atribucion,
  public.referidos_paciente,
  public.reportes_guardados,
  public.resumen_comisiones,
  public.roles,
  public.roles_catalogo,
  public.roles_empresa_catalogo,
  public.signos_vitales,
  public.solicitudes_campana,
  public.solicitudes_personalizacion,
  public.solicitudes_push,
  public.tier_capacidades,
  public.tiers_catalogo,
  public.transacciones,
  public.ubicaciones_medico_proveedor,
  public.usuario_roles,
  public.v_citas_hoy,
  public.v_consultas_paciente,
  public.v_estadisticas_medico,
  public.v_medicamentos_bajo_stock,
  public.v_metricas_campana_pais,
  public.v_metricas_campana_resumen,
  public.v_pacientes_actividad,
  public.v_resumen_mensual,
  public.visitas_agendadas,
  public.whatsapp_mensajes
FROM anon, authenticated, PUBLIC;

-- ---------------------------------------------------------------------------- autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- cantidad y duenio de las relaciones de public y private (todas de postgres: su REVOKE alcanza a todos los grants)
  v := (SELECT string_agg(z.k, ',' ORDER BY z.k) FROM (SELECT n.nspname||'='||count(*)||':'||string_agg(DISTINCT pg_get_userbyid(c.relowner), '+') AS k
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m','f') GROUP BY n.nspname) z);
  IF v IS DISTINCT FROM 'private=7:postgres,public=132:postgres' THEN bad := bad||'relaciones '||COALESCE(v, '-')||'; '; END IF;
  -- MAINTAIN de anon, authenticated y PUBLIC en public y private: ACL (aclexplode) y efectivo (has_table_privilege)
  v := (SELECT COALESCE(string_agg(k||'='||n, ',' ORDER BY k COLLATE "C"), '-') FROM (
      SELECT n.nspname||':'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS k, count(*) AS n
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m','f') AND a.privilege_type = 'MAINTAIN' AND a.grantee IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid)
       GROUP BY 1) z);
  IF v IS DISTINCT FROM '-' THEN bad := bad||'MAINTAIN '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT count(*) FILTER (WHERE has_table_privilege('anon', c.oid, 'MAINTAIN'))||'/'||count(*) FILTER (WHERE has_table_privilege('authenticated', c.oid, 'MAINTAIN'))||'/'||count(*) FILTER (WHERE has_table_privilege('public', c.oid, 'MAINTAIN'))
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m','f'));
  IF v IS DISTINCT FROM '0/0/0' THEN bad := bad||'MAINTAIN efectivo anon/auth/PUBLIC '||COALESCE(v, '-')||'; '; END IF;
  -- TRUNCATE/TRIGGER/REFERENCES siguen en 0 (342)
  v := (SELECT count(*)::text FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE x.pv IN ('TRUNCATE','TRIGGER','REFERENCES') AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid));
  IF v IS DISTINCT FROM '0' THEN bad := bad||'TRUNCATE/TRIGGER/REFERENCES '||COALESCE(v, '-')||'; '; END IF;
  -- el resto de la ACL de public (todo menos MAINTAIN de esos tres roles)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE NOT (x.pv = 'MAINTAIN' AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid)));
  IF v IS DISTINCT FROM '855f079761052808e9593a8911baaac2' THEN bad := bad||'resto de la ACL '||COALESCE(v, '-')||'; '; END IF;
  -- grants por columna y default privileges (la 343 no los toca; los defaults son la 344)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '1f07b802bdb4ee70eb46bd21f46a8d3d' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG343 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
