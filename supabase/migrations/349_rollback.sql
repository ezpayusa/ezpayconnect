-- ############################################################################################
-- 349 ROLLBACK - devuelve las 88 policies a TO public (huella de policies 96a7fabd... 309)
-- ############################################################################################
-- Misma lista que la 349. Precondicion = estado POST de la 349; autochequeo = estado PRE.
-- Orden: correr ANTES que 348_rollback (que exige la huella 96a7fabd...) y que los de la familia 1.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado POST)
DO $precondicion$
DECLARE bad text := ''; v text; n_falta int; n_rol int;
BEGIN
  -- el conjunto (88 policies de la lista): existen, todas con roles = {authenticated}, y su contenido sin roles
  -- (tabla|nombre|cmd|permissive|USING|CHECK) es el medido
  SELECT count(*) FILTER (WHERE pl.oid IS NULL), count(*) FILTER (WHERE pl.polroles = ARRAY['authenticated'::regrole::oid]),
         md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n'
           ORDER BY c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') COLLATE "C"))||' '||count(pl.oid)
    INTO n_falta, n_rol, v
    FROM (VALUES
      ('auditoria_ia', 'Medico ve su propia auditoria IA'),
      ('auditoria_logs', 'auditoria_insert_authenticated'),
      ('auditoria_logs', 'auditoria_select_admin'),
      ('campana_metricas', 'campana_metricas admin select'),
      ('campana_vistas', 'Paciente crea sus vistas'),
      ('campana_vistas', 'Paciente ve sus vistas'),
      ('campanas_publicitarias', 'Admin ve campanas de su pais'),
      ('chat_conversaciones', 'chat_conv_select'),
      ('chat_lecturas', 'chat_lect_own'),
      ('chat_mensajes', 'Medico ve mensajes de sus pacientes'),
      ('chat_mensajes', 'Paciente envía mensajes'),
      ('chat_mensajes', 'Paciente ve sus mensajes'),
      ('chat_mensajes_internos', 'chat_msg_select'),
      ('chat_participantes', 'chat_part_select'),
      ('citas', 'Admin ve citas de su pais'),
      ('citas', 'Paciente ve sus citas'),
      ('clinicas', 'Admin ve clinicas de su pais'),
      ('clinicas', 'Paciente ve clinicas de su pais'),
      ('cuentas_bancarias_pais', 'cuentas_banco_admin'),
      ('disponibilidad_medico', 'Admin clinica gestiona disponibilidad de sus medicos'),
      ('disponibilidad_medico', 'Admin ezpay ve toda disponibilidad'),
      ('disponibilidad_medico', 'Médico gestiona su disponibilidad'),
      ('equipos_visitadores', 'Equipos: admin gestiona'),
      ('equipos_visitadores', 'Equipos: ver segun rol'),
      ('examenes', 'Paciente ve sus examenes'),
      ('examenes', 'examenes_laboratorio_select'),
      ('examenes', 'examenes_laboratorio_update'),
      ('examenes_catalogo', 'catalogo_lab_all'),
      ('facturas', 'Admin ve facturas de su pais'),
      ('facturas', 'Medico actualiza sus facturas'),
      ('facturas', 'Medico crea sus facturas'),
      ('facturas', 'Medico ve sus facturas'),
      ('facturas', 'medicos_actualizar_facturas'),
      ('facturas', 'medicos_crear_facturas'),
      ('facturas', 'medicos_ver_facturas'),
      ('invitaciones_clinica', 'invitaciones_clinica_admin_all'),
      ('invitaciones_clinica', 'invitaciones_clinica_adminpais_all'),
      ('invitaciones_laboratorio', 'inv_lab_clinica_all'),
      ('invitaciones_laboratorio', 'inv_lab_lab_select'),
      ('invitaciones_medico', 'invitaciones_medico_admin_all'),
      ('invitaciones_medico', 'invitaciones_medico_adminpais_all'),
      ('invitaciones_visitador', 'invitaciones_insert_admin'),
      ('laboratorio_clinicas', 'lab_clinicas_clinica_all'),
      ('laboratorio_clinicas', 'lab_clinicas_lab_select'),
      ('medicos', 'Admin ve medicos de su pais'),
      ('medicos', 'Medico ve su perfil'),
      ('medicos', 'Paciente ve medicos de su pais'),
      ('notificaciones', 'notificaciones_select_propia'),
      ('notificaciones', 'notificaciones_select_super_admin'),
      ('notificaciones', 'notificaciones_update_propia'),
      ('notificaciones', 'notificaciones_update_super_admin'),
      ('notificaciones_email', 'Admin ezpay ve notificaciones'),
      ('notificaciones_pacientes', 'notif_pac_select_propia'),
      ('notificaciones_pacientes', 'notif_pac_update_leida'),
      ('ordenes_examen', 'ordenes_lab_select'),
      ('pagos_proveedor', 'Admin ezpay gestiona pagos'),
      ('pagos_proveedor', 'Proveedor crea pagos'),
      ('pagos_proveedor', 'Proveedor ve pagos segun rol'),
      ('planes_publicidad', 'Cualquiera ve planes publicidad activos'),
      ('planes_publicidad_config', 'Admin gestiona config'),
      ('planes_publicidad_config', 'Cualquiera ve config activa'),
      ('planes_visitador_contratados', 'Proveedor ve sus planes visitador'),
      ('productos_empresa', 'Admin ezpay ve todos los productos'),
      ('productos_empresa', 'Proveedor ve productos de su empresa'),
      ('push_subscriptions', 'Usuario crea sus push subscriptions'),
      ('push_subscriptions', 'Usuario elimina sus push subscriptions'),
      ('push_subscriptions', 'Usuario ve sus push subscriptions'),
      ('push_tokens', 'Paciente gestiona sus tokens'),
      ('receta_items', 'Paciente ve items de sus recetas'),
      ('signos_vitales', 'Admin ve todo signos vitales'),
      ('solicitudes_campana', 'Admin ve solicitudes de su pais'),
      ('solicitudes_campana', 'Proveedor ve sus campañas'),
      ('solicitudes_campana', 'solicitudes_campana admin select'),
      ('solicitudes_campana', 'solicitudes_campana admin update'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_delete'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_insert'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_select'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_update'),
      ('usuario_roles', 'Admins pueden actualizar usuario_roles'),
      ('usuario_roles', 'Admins pueden insertar usuario_roles'),
      ('usuario_roles', 'Admins pueden leer usuario_roles'),
      ('visitas_agendadas', 'Admin ezpay ve todas las visitas'),
      ('visitas_agendadas', 'Admin ve visitas de su pais'),
      ('visitas_agendadas', 'Médico actualiza sus visitas'),
      ('visitas_agendadas', 'Médico ve sus visitas'),
      ('visitas_agendadas', 'Proveedor cancela sus visitas'),
      ('visitas_agendadas', 'Proveedor crea visitas de su empresa'),
      ('visitas_agendadas', 'Proveedor ve visitas segun rol')) s(tab, pol)
    LEFT JOIN pg_class c ON c.relnamespace = 'public'::regnamespace AND c.relname = s.tab
    LEFT JOIN pg_policy pl ON pl.polrelid = c.oid AND pl.polname = s.pol;
  IF n_falta <> 0 THEN bad := bad||n_falta||' policies de la lista no existen; '; END IF;
  IF n_rol <> 88 THEN bad := bad||'policies de la lista con roles {authenticated}: '||n_rol||' de 88; '; END IF;
  IF v IS DISTINCT FROM 'd0dfa2b9f7496778c5baabfcc1cca910 88' THEN bad := bad||'contenido del conjunto '||COALESCE(v, '-')||'; '; END IF;
  -- huella de TODAS las policies de public/private/storage: tabla|nombre|cmd|permissive|roles|USING|CHECK
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'fc06b02c0b09efd90f774e612e53d454 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- policies {public} de public fuera de la WL_ANON_LEGACY (la misma regla de P934)
  v := (SELECT count(*)::text FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE c.relnamespace = 'public'::regnamespace AND pl.polroles = '{0}'::oid[] AND NOT (c.relname = ANY (ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas'])));
  IF v IS DISTINCT FROM '0' THEN bad := bad||'policies {public} fuera de la WL '||COALESCE(v, '-')||'; '; END IF;
  -- anon sigue sin ningun privilegio (tabla ni columna) en las tablas del conjunto
  v := (SELECT string_agg(DISTINCT s.tab, ',') FROM (VALUES
      ('auditoria_ia', 'Medico ve su propia auditoria IA'),
      ('auditoria_logs', 'auditoria_insert_authenticated'),
      ('auditoria_logs', 'auditoria_select_admin'),
      ('campana_metricas', 'campana_metricas admin select'),
      ('campana_vistas', 'Paciente crea sus vistas'),
      ('campana_vistas', 'Paciente ve sus vistas'),
      ('campanas_publicitarias', 'Admin ve campanas de su pais'),
      ('chat_conversaciones', 'chat_conv_select'),
      ('chat_lecturas', 'chat_lect_own'),
      ('chat_mensajes', 'Medico ve mensajes de sus pacientes'),
      ('chat_mensajes', 'Paciente envía mensajes'),
      ('chat_mensajes', 'Paciente ve sus mensajes'),
      ('chat_mensajes_internos', 'chat_msg_select'),
      ('chat_participantes', 'chat_part_select'),
      ('citas', 'Admin ve citas de su pais'),
      ('citas', 'Paciente ve sus citas'),
      ('clinicas', 'Admin ve clinicas de su pais'),
      ('clinicas', 'Paciente ve clinicas de su pais'),
      ('cuentas_bancarias_pais', 'cuentas_banco_admin'),
      ('disponibilidad_medico', 'Admin clinica gestiona disponibilidad de sus medicos'),
      ('disponibilidad_medico', 'Admin ezpay ve toda disponibilidad'),
      ('disponibilidad_medico', 'Médico gestiona su disponibilidad'),
      ('equipos_visitadores', 'Equipos: admin gestiona'),
      ('equipos_visitadores', 'Equipos: ver segun rol'),
      ('examenes', 'Paciente ve sus examenes'),
      ('examenes', 'examenes_laboratorio_select'),
      ('examenes', 'examenes_laboratorio_update'),
      ('examenes_catalogo', 'catalogo_lab_all'),
      ('facturas', 'Admin ve facturas de su pais'),
      ('facturas', 'Medico actualiza sus facturas'),
      ('facturas', 'Medico crea sus facturas'),
      ('facturas', 'Medico ve sus facturas'),
      ('facturas', 'medicos_actualizar_facturas'),
      ('facturas', 'medicos_crear_facturas'),
      ('facturas', 'medicos_ver_facturas'),
      ('invitaciones_clinica', 'invitaciones_clinica_admin_all'),
      ('invitaciones_clinica', 'invitaciones_clinica_adminpais_all'),
      ('invitaciones_laboratorio', 'inv_lab_clinica_all'),
      ('invitaciones_laboratorio', 'inv_lab_lab_select'),
      ('invitaciones_medico', 'invitaciones_medico_admin_all'),
      ('invitaciones_medico', 'invitaciones_medico_adminpais_all'),
      ('invitaciones_visitador', 'invitaciones_insert_admin'),
      ('laboratorio_clinicas', 'lab_clinicas_clinica_all'),
      ('laboratorio_clinicas', 'lab_clinicas_lab_select'),
      ('medicos', 'Admin ve medicos de su pais'),
      ('medicos', 'Medico ve su perfil'),
      ('medicos', 'Paciente ve medicos de su pais'),
      ('notificaciones', 'notificaciones_select_propia'),
      ('notificaciones', 'notificaciones_select_super_admin'),
      ('notificaciones', 'notificaciones_update_propia'),
      ('notificaciones', 'notificaciones_update_super_admin'),
      ('notificaciones_email', 'Admin ezpay ve notificaciones'),
      ('notificaciones_pacientes', 'notif_pac_select_propia'),
      ('notificaciones_pacientes', 'notif_pac_update_leida'),
      ('ordenes_examen', 'ordenes_lab_select'),
      ('pagos_proveedor', 'Admin ezpay gestiona pagos'),
      ('pagos_proveedor', 'Proveedor crea pagos'),
      ('pagos_proveedor', 'Proveedor ve pagos segun rol'),
      ('planes_publicidad', 'Cualquiera ve planes publicidad activos'),
      ('planes_publicidad_config', 'Admin gestiona config'),
      ('planes_publicidad_config', 'Cualquiera ve config activa'),
      ('planes_visitador_contratados', 'Proveedor ve sus planes visitador'),
      ('productos_empresa', 'Admin ezpay ve todos los productos'),
      ('productos_empresa', 'Proveedor ve productos de su empresa'),
      ('push_subscriptions', 'Usuario crea sus push subscriptions'),
      ('push_subscriptions', 'Usuario elimina sus push subscriptions'),
      ('push_subscriptions', 'Usuario ve sus push subscriptions'),
      ('push_tokens', 'Paciente gestiona sus tokens'),
      ('receta_items', 'Paciente ve items de sus recetas'),
      ('signos_vitales', 'Admin ve todo signos vitales'),
      ('solicitudes_campana', 'Admin ve solicitudes de su pais'),
      ('solicitudes_campana', 'Proveedor ve sus campañas'),
      ('solicitudes_campana', 'solicitudes_campana admin select'),
      ('solicitudes_campana', 'solicitudes_campana admin update'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_delete'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_insert'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_select'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_update'),
      ('usuario_roles', 'Admins pueden actualizar usuario_roles'),
      ('usuario_roles', 'Admins pueden insertar usuario_roles'),
      ('usuario_roles', 'Admins pueden leer usuario_roles'),
      ('visitas_agendadas', 'Admin ezpay ve todas las visitas'),
      ('visitas_agendadas', 'Admin ve visitas de su pais'),
      ('visitas_agendadas', 'Médico actualiza sus visitas'),
      ('visitas_agendadas', 'Médico ve sus visitas'),
      ('visitas_agendadas', 'Proveedor cancela sus visitas'),
      ('visitas_agendadas', 'Proveedor crea visitas de su empresa'),
      ('visitas_agendadas', 'Proveedor ve visitas segun rol')) s(tab, pol)
         WHERE has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'SELECT') OR has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'INSERT')
            OR has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'UPDATE') OR has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'DELETE')
            OR has_any_column_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'SELECT,INSERT,UPDATE'));
  IF v IS NOT NULL THEN bad := bad||'anon con privilegio en '||v||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM 'e1ef3639c3367e24c1369c0dbf95a994 39' THEN bad := bad||'ACL de secuencias public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK349 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- ALTER POLICY ... TO public (88)
ALTER POLICY "Medico ve su propia auditoria IA" ON public.auditoria_ia TO public;
ALTER POLICY "auditoria_insert_authenticated" ON public.auditoria_logs TO public;
ALTER POLICY "auditoria_select_admin" ON public.auditoria_logs TO public;
ALTER POLICY "campana_metricas admin select" ON public.campana_metricas TO public;
ALTER POLICY "Paciente crea sus vistas" ON public.campana_vistas TO public;
ALTER POLICY "Paciente ve sus vistas" ON public.campana_vistas TO public;
ALTER POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias TO public;
ALTER POLICY "chat_conv_select" ON public.chat_conversaciones TO public;
ALTER POLICY "chat_lect_own" ON public.chat_lecturas TO public;
ALTER POLICY "Medico ve mensajes de sus pacientes" ON public.chat_mensajes TO public;
ALTER POLICY "Paciente envía mensajes" ON public.chat_mensajes TO public;
ALTER POLICY "Paciente ve sus mensajes" ON public.chat_mensajes TO public;
ALTER POLICY "chat_msg_select" ON public.chat_mensajes_internos TO public;
ALTER POLICY "chat_part_select" ON public.chat_participantes TO public;
ALTER POLICY "Admin ve citas de su pais" ON public.citas TO public;
ALTER POLICY "Paciente ve sus citas" ON public.citas TO public;
ALTER POLICY "Admin ve clinicas de su pais" ON public.clinicas TO public;
ALTER POLICY "Paciente ve clinicas de su pais" ON public.clinicas TO public;
ALTER POLICY "cuentas_banco_admin" ON public.cuentas_bancarias_pais TO public;
ALTER POLICY "Admin clinica gestiona disponibilidad de sus medicos" ON public.disponibilidad_medico TO public;
ALTER POLICY "Admin ezpay ve toda disponibilidad" ON public.disponibilidad_medico TO public;
ALTER POLICY "Médico gestiona su disponibilidad" ON public.disponibilidad_medico TO public;
ALTER POLICY "Equipos: admin gestiona" ON public.equipos_visitadores TO public;
ALTER POLICY "Equipos: ver segun rol" ON public.equipos_visitadores TO public;
ALTER POLICY "Paciente ve sus examenes" ON public.examenes TO public;
ALTER POLICY "examenes_laboratorio_select" ON public.examenes TO public;
ALTER POLICY "examenes_laboratorio_update" ON public.examenes TO public;
ALTER POLICY "catalogo_lab_all" ON public.examenes_catalogo TO public;
ALTER POLICY "Admin ve facturas de su pais" ON public.facturas TO public;
ALTER POLICY "Medico actualiza sus facturas" ON public.facturas TO public;
ALTER POLICY "Medico crea sus facturas" ON public.facturas TO public;
ALTER POLICY "Medico ve sus facturas" ON public.facturas TO public;
ALTER POLICY "medicos_actualizar_facturas" ON public.facturas TO public;
ALTER POLICY "medicos_crear_facturas" ON public.facturas TO public;
ALTER POLICY "medicos_ver_facturas" ON public.facturas TO public;
ALTER POLICY "invitaciones_clinica_admin_all" ON public.invitaciones_clinica TO public;
ALTER POLICY "invitaciones_clinica_adminpais_all" ON public.invitaciones_clinica TO public;
ALTER POLICY "inv_lab_clinica_all" ON public.invitaciones_laboratorio TO public;
ALTER POLICY "inv_lab_lab_select" ON public.invitaciones_laboratorio TO public;
ALTER POLICY "invitaciones_medico_admin_all" ON public.invitaciones_medico TO public;
ALTER POLICY "invitaciones_medico_adminpais_all" ON public.invitaciones_medico TO public;
ALTER POLICY "invitaciones_insert_admin" ON public.invitaciones_visitador TO public;
ALTER POLICY "lab_clinicas_clinica_all" ON public.laboratorio_clinicas TO public;
ALTER POLICY "lab_clinicas_lab_select" ON public.laboratorio_clinicas TO public;
ALTER POLICY "Admin ve medicos de su pais" ON public.medicos TO public;
ALTER POLICY "Medico ve su perfil" ON public.medicos TO public;
ALTER POLICY "Paciente ve medicos de su pais" ON public.medicos TO public;
ALTER POLICY "notificaciones_select_propia" ON public.notificaciones TO public;
ALTER POLICY "notificaciones_select_super_admin" ON public.notificaciones TO public;
ALTER POLICY "notificaciones_update_propia" ON public.notificaciones TO public;
ALTER POLICY "notificaciones_update_super_admin" ON public.notificaciones TO public;
ALTER POLICY "Admin ezpay ve notificaciones" ON public.notificaciones_email TO public;
ALTER POLICY "notif_pac_select_propia" ON public.notificaciones_pacientes TO public;
ALTER POLICY "notif_pac_update_leida" ON public.notificaciones_pacientes TO public;
ALTER POLICY "ordenes_lab_select" ON public.ordenes_examen TO public;
ALTER POLICY "Admin ezpay gestiona pagos" ON public.pagos_proveedor TO public;
ALTER POLICY "Proveedor crea pagos" ON public.pagos_proveedor TO public;
ALTER POLICY "Proveedor ve pagos segun rol" ON public.pagos_proveedor TO public;
ALTER POLICY "Cualquiera ve planes publicidad activos" ON public.planes_publicidad TO public;
ALTER POLICY "Admin gestiona config" ON public.planes_publicidad_config TO public;
ALTER POLICY "Cualquiera ve config activa" ON public.planes_publicidad_config TO public;
ALTER POLICY "Proveedor ve sus planes visitador" ON public.planes_visitador_contratados TO public;
ALTER POLICY "Admin ezpay ve todos los productos" ON public.productos_empresa TO public;
ALTER POLICY "Proveedor ve productos de su empresa" ON public.productos_empresa TO public;
ALTER POLICY "Usuario crea sus push subscriptions" ON public.push_subscriptions TO public;
ALTER POLICY "Usuario elimina sus push subscriptions" ON public.push_subscriptions TO public;
ALTER POLICY "Usuario ve sus push subscriptions" ON public.push_subscriptions TO public;
ALTER POLICY "Paciente gestiona sus tokens" ON public.push_tokens TO public;
ALTER POLICY "Paciente ve items de sus recetas" ON public.receta_items TO public;
ALTER POLICY "Admin ve todo signos vitales" ON public.signos_vitales TO public;
ALTER POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana TO public;
ALTER POLICY "Proveedor ve sus campañas" ON public.solicitudes_campana TO public;
ALTER POLICY "solicitudes_campana admin select" ON public.solicitudes_campana TO public;
ALTER POLICY "solicitudes_campana admin update" ON public.solicitudes_campana TO public;
ALTER POLICY "ubicaciones_delete" ON public.ubicaciones_medico_proveedor TO public;
ALTER POLICY "ubicaciones_insert" ON public.ubicaciones_medico_proveedor TO public;
ALTER POLICY "ubicaciones_select" ON public.ubicaciones_medico_proveedor TO public;
ALTER POLICY "ubicaciones_update" ON public.ubicaciones_medico_proveedor TO public;
ALTER POLICY "Admins pueden actualizar usuario_roles" ON public.usuario_roles TO public;
ALTER POLICY "Admins pueden insertar usuario_roles" ON public.usuario_roles TO public;
ALTER POLICY "Admins pueden leer usuario_roles" ON public.usuario_roles TO public;
ALTER POLICY "Admin ezpay ve todas las visitas" ON public.visitas_agendadas TO public;
ALTER POLICY "Admin ve visitas de su pais" ON public.visitas_agendadas TO public;
ALTER POLICY "Médico actualiza sus visitas" ON public.visitas_agendadas TO public;
ALTER POLICY "Médico ve sus visitas" ON public.visitas_agendadas TO public;
ALTER POLICY "Proveedor cancela sus visitas" ON public.visitas_agendadas TO public;
ALTER POLICY "Proveedor crea visitas de su empresa" ON public.visitas_agendadas TO public;
ALTER POLICY "Proveedor ve visitas segun rol" ON public.visitas_agendadas TO public;

-- ---------------------------------------------------------------------------- autochequeo (estado PRE)
DO $autochequeo$
DECLARE bad text := ''; v text; n_falta int; n_rol int;
BEGIN
  -- el conjunto (88 policies de la lista): existen, todas con roles = {public}, y su contenido sin roles
  -- (tabla|nombre|cmd|permissive|USING|CHECK) es el medido
  SELECT count(*) FILTER (WHERE pl.oid IS NULL), count(*) FILTER (WHERE pl.polroles = '{0}'::oid[]),
         md5(string_agg(c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n'
           ORDER BY c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') COLLATE "C"))||' '||count(pl.oid)
    INTO n_falta, n_rol, v
    FROM (VALUES
      ('auditoria_ia', 'Medico ve su propia auditoria IA'),
      ('auditoria_logs', 'auditoria_insert_authenticated'),
      ('auditoria_logs', 'auditoria_select_admin'),
      ('campana_metricas', 'campana_metricas admin select'),
      ('campana_vistas', 'Paciente crea sus vistas'),
      ('campana_vistas', 'Paciente ve sus vistas'),
      ('campanas_publicitarias', 'Admin ve campanas de su pais'),
      ('chat_conversaciones', 'chat_conv_select'),
      ('chat_lecturas', 'chat_lect_own'),
      ('chat_mensajes', 'Medico ve mensajes de sus pacientes'),
      ('chat_mensajes', 'Paciente envía mensajes'),
      ('chat_mensajes', 'Paciente ve sus mensajes'),
      ('chat_mensajes_internos', 'chat_msg_select'),
      ('chat_participantes', 'chat_part_select'),
      ('citas', 'Admin ve citas de su pais'),
      ('citas', 'Paciente ve sus citas'),
      ('clinicas', 'Admin ve clinicas de su pais'),
      ('clinicas', 'Paciente ve clinicas de su pais'),
      ('cuentas_bancarias_pais', 'cuentas_banco_admin'),
      ('disponibilidad_medico', 'Admin clinica gestiona disponibilidad de sus medicos'),
      ('disponibilidad_medico', 'Admin ezpay ve toda disponibilidad'),
      ('disponibilidad_medico', 'Médico gestiona su disponibilidad'),
      ('equipos_visitadores', 'Equipos: admin gestiona'),
      ('equipos_visitadores', 'Equipos: ver segun rol'),
      ('examenes', 'Paciente ve sus examenes'),
      ('examenes', 'examenes_laboratorio_select'),
      ('examenes', 'examenes_laboratorio_update'),
      ('examenes_catalogo', 'catalogo_lab_all'),
      ('facturas', 'Admin ve facturas de su pais'),
      ('facturas', 'Medico actualiza sus facturas'),
      ('facturas', 'Medico crea sus facturas'),
      ('facturas', 'Medico ve sus facturas'),
      ('facturas', 'medicos_actualizar_facturas'),
      ('facturas', 'medicos_crear_facturas'),
      ('facturas', 'medicos_ver_facturas'),
      ('invitaciones_clinica', 'invitaciones_clinica_admin_all'),
      ('invitaciones_clinica', 'invitaciones_clinica_adminpais_all'),
      ('invitaciones_laboratorio', 'inv_lab_clinica_all'),
      ('invitaciones_laboratorio', 'inv_lab_lab_select'),
      ('invitaciones_medico', 'invitaciones_medico_admin_all'),
      ('invitaciones_medico', 'invitaciones_medico_adminpais_all'),
      ('invitaciones_visitador', 'invitaciones_insert_admin'),
      ('laboratorio_clinicas', 'lab_clinicas_clinica_all'),
      ('laboratorio_clinicas', 'lab_clinicas_lab_select'),
      ('medicos', 'Admin ve medicos de su pais'),
      ('medicos', 'Medico ve su perfil'),
      ('medicos', 'Paciente ve medicos de su pais'),
      ('notificaciones', 'notificaciones_select_propia'),
      ('notificaciones', 'notificaciones_select_super_admin'),
      ('notificaciones', 'notificaciones_update_propia'),
      ('notificaciones', 'notificaciones_update_super_admin'),
      ('notificaciones_email', 'Admin ezpay ve notificaciones'),
      ('notificaciones_pacientes', 'notif_pac_select_propia'),
      ('notificaciones_pacientes', 'notif_pac_update_leida'),
      ('ordenes_examen', 'ordenes_lab_select'),
      ('pagos_proveedor', 'Admin ezpay gestiona pagos'),
      ('pagos_proveedor', 'Proveedor crea pagos'),
      ('pagos_proveedor', 'Proveedor ve pagos segun rol'),
      ('planes_publicidad', 'Cualquiera ve planes publicidad activos'),
      ('planes_publicidad_config', 'Admin gestiona config'),
      ('planes_publicidad_config', 'Cualquiera ve config activa'),
      ('planes_visitador_contratados', 'Proveedor ve sus planes visitador'),
      ('productos_empresa', 'Admin ezpay ve todos los productos'),
      ('productos_empresa', 'Proveedor ve productos de su empresa'),
      ('push_subscriptions', 'Usuario crea sus push subscriptions'),
      ('push_subscriptions', 'Usuario elimina sus push subscriptions'),
      ('push_subscriptions', 'Usuario ve sus push subscriptions'),
      ('push_tokens', 'Paciente gestiona sus tokens'),
      ('receta_items', 'Paciente ve items de sus recetas'),
      ('signos_vitales', 'Admin ve todo signos vitales'),
      ('solicitudes_campana', 'Admin ve solicitudes de su pais'),
      ('solicitudes_campana', 'Proveedor ve sus campañas'),
      ('solicitudes_campana', 'solicitudes_campana admin select'),
      ('solicitudes_campana', 'solicitudes_campana admin update'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_delete'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_insert'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_select'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_update'),
      ('usuario_roles', 'Admins pueden actualizar usuario_roles'),
      ('usuario_roles', 'Admins pueden insertar usuario_roles'),
      ('usuario_roles', 'Admins pueden leer usuario_roles'),
      ('visitas_agendadas', 'Admin ezpay ve todas las visitas'),
      ('visitas_agendadas', 'Admin ve visitas de su pais'),
      ('visitas_agendadas', 'Médico actualiza sus visitas'),
      ('visitas_agendadas', 'Médico ve sus visitas'),
      ('visitas_agendadas', 'Proveedor cancela sus visitas'),
      ('visitas_agendadas', 'Proveedor crea visitas de su empresa'),
      ('visitas_agendadas', 'Proveedor ve visitas segun rol')) s(tab, pol)
    LEFT JOIN pg_class c ON c.relnamespace = 'public'::regnamespace AND c.relname = s.tab
    LEFT JOIN pg_policy pl ON pl.polrelid = c.oid AND pl.polname = s.pol;
  IF n_falta <> 0 THEN bad := bad||n_falta||' policies de la lista no existen; '; END IF;
  IF n_rol <> 88 THEN bad := bad||'policies de la lista con roles {public}: '||n_rol||' de 88; '; END IF;
  IF v IS DISTINCT FROM 'd0dfa2b9f7496778c5baabfcc1cca910 88' THEN bad := bad||'contenido del conjunto '||COALESCE(v, '-')||'; '; END IF;
  -- huella de TODAS las policies de public/private/storage: tabla|nombre|cmd|permissive|roles|USING|CHECK
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '96a7fabd0178251b25943688e244ad0f 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  -- policies {public} de public fuera de la WL_ANON_LEGACY (la misma regla de P934)
  v := (SELECT count(*)::text FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid
         WHERE c.relnamespace = 'public'::regnamespace AND pl.polroles = '{0}'::oid[] AND NOT (c.relname = ANY (ARRAY['configuracion_pais','configuracion_sistema','cuentas_proveedor','empresas_proveedoras','liquidaciones_comision','pacientes','perfiles','recetas'])));
  IF v IS DISTINCT FROM '88' THEN bad := bad||'policies {public} fuera de la WL '||COALESCE(v, '-')||'; '; END IF;
  -- anon sigue sin ningun privilegio (tabla ni columna) en las tablas del conjunto
  v := (SELECT string_agg(DISTINCT s.tab, ',') FROM (VALUES
      ('auditoria_ia', 'Medico ve su propia auditoria IA'),
      ('auditoria_logs', 'auditoria_insert_authenticated'),
      ('auditoria_logs', 'auditoria_select_admin'),
      ('campana_metricas', 'campana_metricas admin select'),
      ('campana_vistas', 'Paciente crea sus vistas'),
      ('campana_vistas', 'Paciente ve sus vistas'),
      ('campanas_publicitarias', 'Admin ve campanas de su pais'),
      ('chat_conversaciones', 'chat_conv_select'),
      ('chat_lecturas', 'chat_lect_own'),
      ('chat_mensajes', 'Medico ve mensajes de sus pacientes'),
      ('chat_mensajes', 'Paciente envía mensajes'),
      ('chat_mensajes', 'Paciente ve sus mensajes'),
      ('chat_mensajes_internos', 'chat_msg_select'),
      ('chat_participantes', 'chat_part_select'),
      ('citas', 'Admin ve citas de su pais'),
      ('citas', 'Paciente ve sus citas'),
      ('clinicas', 'Admin ve clinicas de su pais'),
      ('clinicas', 'Paciente ve clinicas de su pais'),
      ('cuentas_bancarias_pais', 'cuentas_banco_admin'),
      ('disponibilidad_medico', 'Admin clinica gestiona disponibilidad de sus medicos'),
      ('disponibilidad_medico', 'Admin ezpay ve toda disponibilidad'),
      ('disponibilidad_medico', 'Médico gestiona su disponibilidad'),
      ('equipos_visitadores', 'Equipos: admin gestiona'),
      ('equipos_visitadores', 'Equipos: ver segun rol'),
      ('examenes', 'Paciente ve sus examenes'),
      ('examenes', 'examenes_laboratorio_select'),
      ('examenes', 'examenes_laboratorio_update'),
      ('examenes_catalogo', 'catalogo_lab_all'),
      ('facturas', 'Admin ve facturas de su pais'),
      ('facturas', 'Medico actualiza sus facturas'),
      ('facturas', 'Medico crea sus facturas'),
      ('facturas', 'Medico ve sus facturas'),
      ('facturas', 'medicos_actualizar_facturas'),
      ('facturas', 'medicos_crear_facturas'),
      ('facturas', 'medicos_ver_facturas'),
      ('invitaciones_clinica', 'invitaciones_clinica_admin_all'),
      ('invitaciones_clinica', 'invitaciones_clinica_adminpais_all'),
      ('invitaciones_laboratorio', 'inv_lab_clinica_all'),
      ('invitaciones_laboratorio', 'inv_lab_lab_select'),
      ('invitaciones_medico', 'invitaciones_medico_admin_all'),
      ('invitaciones_medico', 'invitaciones_medico_adminpais_all'),
      ('invitaciones_visitador', 'invitaciones_insert_admin'),
      ('laboratorio_clinicas', 'lab_clinicas_clinica_all'),
      ('laboratorio_clinicas', 'lab_clinicas_lab_select'),
      ('medicos', 'Admin ve medicos de su pais'),
      ('medicos', 'Medico ve su perfil'),
      ('medicos', 'Paciente ve medicos de su pais'),
      ('notificaciones', 'notificaciones_select_propia'),
      ('notificaciones', 'notificaciones_select_super_admin'),
      ('notificaciones', 'notificaciones_update_propia'),
      ('notificaciones', 'notificaciones_update_super_admin'),
      ('notificaciones_email', 'Admin ezpay ve notificaciones'),
      ('notificaciones_pacientes', 'notif_pac_select_propia'),
      ('notificaciones_pacientes', 'notif_pac_update_leida'),
      ('ordenes_examen', 'ordenes_lab_select'),
      ('pagos_proveedor', 'Admin ezpay gestiona pagos'),
      ('pagos_proveedor', 'Proveedor crea pagos'),
      ('pagos_proveedor', 'Proveedor ve pagos segun rol'),
      ('planes_publicidad', 'Cualquiera ve planes publicidad activos'),
      ('planes_publicidad_config', 'Admin gestiona config'),
      ('planes_publicidad_config', 'Cualquiera ve config activa'),
      ('planes_visitador_contratados', 'Proveedor ve sus planes visitador'),
      ('productos_empresa', 'Admin ezpay ve todos los productos'),
      ('productos_empresa', 'Proveedor ve productos de su empresa'),
      ('push_subscriptions', 'Usuario crea sus push subscriptions'),
      ('push_subscriptions', 'Usuario elimina sus push subscriptions'),
      ('push_subscriptions', 'Usuario ve sus push subscriptions'),
      ('push_tokens', 'Paciente gestiona sus tokens'),
      ('receta_items', 'Paciente ve items de sus recetas'),
      ('signos_vitales', 'Admin ve todo signos vitales'),
      ('solicitudes_campana', 'Admin ve solicitudes de su pais'),
      ('solicitudes_campana', 'Proveedor ve sus campañas'),
      ('solicitudes_campana', 'solicitudes_campana admin select'),
      ('solicitudes_campana', 'solicitudes_campana admin update'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_delete'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_insert'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_select'),
      ('ubicaciones_medico_proveedor', 'ubicaciones_update'),
      ('usuario_roles', 'Admins pueden actualizar usuario_roles'),
      ('usuario_roles', 'Admins pueden insertar usuario_roles'),
      ('usuario_roles', 'Admins pueden leer usuario_roles'),
      ('visitas_agendadas', 'Admin ezpay ve todas las visitas'),
      ('visitas_agendadas', 'Admin ve visitas de su pais'),
      ('visitas_agendadas', 'Médico actualiza sus visitas'),
      ('visitas_agendadas', 'Médico ve sus visitas'),
      ('visitas_agendadas', 'Proveedor cancela sus visitas'),
      ('visitas_agendadas', 'Proveedor crea visitas de su empresa'),
      ('visitas_agendadas', 'Proveedor ve visitas segun rol')) s(tab, pol)
         WHERE has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'SELECT') OR has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'INSERT')
            OR has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'UPDATE') OR has_table_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'DELETE')
            OR has_any_column_privilege('anon', ('public.'||quote_ident(s.tab))::regclass, 'SELECT,INSERT,UPDATE'));
  IF v IS NOT NULL THEN bad := bad||'anon con privilegio en '||v||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT c.relname||'|'||t.attname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid, aclexplode(t.attacl) a
       WHERE c.relnamespace = 'public'::regnamespace AND t.attacl IS NOT NULL AND NOT t.attisdropped) y);
  IF v IS DISTINCT FROM 'dab25af63754e06d699ac3bd454011a6' THEN bad := bad||'grants por columna '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM 'e1ef3639c3367e24c1369c0dbf95a994 39' THEN bad := bad||'ACL de secuencias public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK349 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
