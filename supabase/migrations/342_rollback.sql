-- ############################################################################################
-- 342 ROLLBACK - devuelve TRUNCATE/TRIGGER/REFERENCES a authenticated en las 83 relaciones de la 342
-- ############################################################################################
-- Lista generada del inventario PRE (2-oct-2026), no "ON ALL TABLES": 76 relaciones con los tres y 7 con
-- TRIGGER y REFERENCES. anon y PUBLIC no tenian ninguno: no se les devuelve nada. Precondicion = estado POST
-- de la 342 (0 de los tres; resto de la ACL = PRE); autochequeo = huella completa PRE 1df9d1b3777fbf51d472bd015c4e26e4.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado POST)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- cantidad y duenio de las relaciones de public (todas de postgres: su REVOKE alcanza a todos los grants)
  v := (SELECT count(*)::text||' '||string_agg(DISTINCT pg_get_userbyid(c.relowner), ',') FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f'));
  IF v IS DISTINCT FROM '132 postgres' THEN bad := bad||'relaciones '||COALESCE(v, '-')||'; '; END IF;
  -- TRUNCATE/TRIGGER/REFERENCES de anon, authenticated y PUBLIC (aclexplode, no information_schema)
  v := (SELECT COALESCE(string_agg(k||'='||n, ',' ORDER BY k COLLATE "C"), '-') FROM (
      SELECT CASE x.ge WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.ge) END||':'||x.pv AS k, count(*) AS n FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE x.pv IN ('TRUNCATE','TRIGGER','REFERENCES') AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid) GROUP BY 1) z);
  IF v IS DISTINCT FROM '-' THEN bad := bad||'conteos '||COALESCE(v, '-')||'; '; END IF;
  -- el resto de la ACL (todo menos esos tres privilegios para esos tres roles)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE NOT (x.pv IN ('TRUNCATE','TRIGGER','REFERENCES') AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid)));
  IF v IS DISTINCT FROM 'c57c024fec00ca4819a97bf020cfae6b' THEN bad := bad||'resto de la ACL '||COALESCE(v, '-')||'; '; END IF;
  -- grants por columna y default privileges (la 342 no los toca; los defaults son la 344)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '1f07b802bdb4ee70eb46bd21f46a8d3d' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK342 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------- los GRANT
GRANT TRUNCATE, TRIGGER, REFERENCES ON TABLE
  public.acciones_techo,
  public.auditoria_ia,
  public.auditoria_logs,
  public.cache_biblioteca,
  public.campanas_publicitarias,
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
  public.contratos_comision,
  public.cuentas_bancarias_pais,
  public.cuentas_proveedor,
  public.disponibilidad_medico,
  public.empresa_paises_operacion,
  public.empresas_proveedoras,
  public.equipos_visitadores,
  public.facturas,
  public.invitaciones_clinica,
  public.invitaciones_laboratorio,
  public.invitaciones_medico,
  public.invitaciones_visitador,
  public.laboratorio_clinicas,
  public.liquidacion_dispensaciones,
  public.liquidaciones_comision,
  public.medicamentos_categorias,
  public.medico_clinicas,
  public.medico_correlativos,
  public.medicos,
  public.notificaciones,
  public.notificaciones_email,
  public.notificaciones_pacientes,
  public.pacientes,
  public.pagos_proveedor,
  public.permisos_empresa_rol,
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
  public.productos_empresa,
  public.push_subscriptions,
  public.push_tokens,
  public.receta_items,
  public.recetas,
  public.recordatorios,
  public.recordatorios_citas,
  public.recordatorios_programados,
  public.reportes_guardados,
  public.resumen_comisiones,
  public.roles,
  public.roles_catalogo,
  public.roles_empresa_catalogo,
  public.signos_vitales,
  public.solicitudes_campana,
  public.transacciones,
  public.ubicaciones_medico_proveedor,
  public.usuario_roles,
  public.v_citas_hoy,
  public.v_consultas_paciente,
  public.v_estadisticas_medico,
  public.v_pacientes_actividad,
  public.v_resumen_mensual,
  public.visitas_agendadas,
  public.whatsapp_mensajes
TO authenticated;

GRANT TRIGGER, REFERENCES ON TABLE
  public.canjes,
  public.dispensaciones,
  public.especialidades_propuestas,
  public.farmacia_medicamentos,
  public.farmacias,
  public.historial_medico,
  public.recetas_avanzadas
TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (huella = PRE)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- cantidad y duenio de las relaciones de public (todas de postgres: su REVOKE alcanza a todos los grants)
  v := (SELECT count(*)::text||' '||string_agg(DISTINCT pg_get_userbyid(c.relowner), ',') FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f'));
  IF v IS DISTINCT FROM '132 postgres' THEN bad := bad||'relaciones '||COALESCE(v, '-')||'; '; END IF;
  -- huella completa de la ACL de las 132 relaciones
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '1df9d1b3777fbf51d472bd015c4e26e4' THEN bad := bad||'huella completa '||COALESCE(v, '-')||'; '; END IF;
  -- TRUNCATE/TRIGGER/REFERENCES de anon, authenticated y PUBLIC (aclexplode, no information_schema)
  v := (SELECT COALESCE(string_agg(k||'='||n, ',' ORDER BY k COLLATE "C"), '-') FROM (
      SELECT CASE x.ge WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.ge) END||':'||x.pv AS k, count(*) AS n FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE x.pv IN ('TRUNCATE','TRIGGER','REFERENCES') AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid) GROUP BY 1) z);
  IF v IS DISTINCT FROM 'authenticated:REFERENCES=83,authenticated:TRIGGER=83,authenticated:TRUNCATE=76' THEN bad := bad||'conteos '||COALESCE(v, '-')||'; '; END IF;
  -- el resto de la ACL (todo menos esos tres privilegios para esos tres roles)
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s,
           a.grantee AS ge, a.privilege_type AS pv
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x WHERE NOT (x.pv IN ('TRUNCATE','TRIGGER','REFERENCES') AND x.ge IN (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid)));
  IF v IS DISTINCT FROM 'c57c024fec00ca4819a97bf020cfae6b' THEN bad := bad||'resto de la ACL '||COALESCE(v, '-')||'; '; END IF;
  -- grants por columna y default privileges (la 342 no los toca; los defaults son la 344)
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '1f07b802bdb4ee70eb46bd21f46a8d3d' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK342 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
