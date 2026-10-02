-- ############################################################################################
-- 349 - familia 2 (policies), paso 2 (F2-b): 88 policies {public} que anon no alcanza -> TO authenticated
-- ############################################################################################
-- Una policy con roles = {public} se aplica a todos los roles. Para anon solo importa si anon tiene el privilegio de
-- tabla del comando: sin el privilegio, el acceso muere en 42501 antes de llegar a la RLS. Medido el 2-oct-2026 sobre
-- 6c8d305: de las 106 policies {public} de public, 18 son de las tablas de la WL_ANON_LEGACY (F2-c, fuera de aca) y
-- 88 estan en 41 tablas donde anon no tiene NINGUN privilegio (ni de tabla ni de columna): anon nunca las evalua.
-- Pasarlas a TO authenticated no cambia el comportamiento (service_role tiene BYPASSRLS; los demas roles que
-- consultan via la API son anon y authenticated) y deja los roles explicitos: si alguien le diera un privilegio a
-- anon en una de estas tablas, la policy ya no se le aplicaria. Ninguna menciona roles (current_user, session_user,
-- pg_has_role, auth.role()) en su USING/CHECK. Las 3 {public} de storage.objects (lectura publica de buckets) quedan.
-- Por comando: SELECT 44, INSERT 11, UPDATE 11, DELETE 2, ALL 20. Tablas (41):
--   auditoria_ia, auditoria_logs, campana_metricas, campana_vistas, campanas_publicitarias, chat_conversaciones
--   chat_lecturas, chat_mensajes, chat_mensajes_internos, chat_participantes, citas, clinicas
--   cuentas_bancarias_pais, disponibilidad_medico, equipos_visitadores, examenes, examenes_catalogo, facturas
--   invitaciones_clinica, invitaciones_laboratorio, invitaciones_medico, invitaciones_visitador
--   laboratorio_clinicas, medicos, notificaciones, notificaciones_email, notificaciones_pacientes, ordenes_examen
--   pagos_proveedor, planes_publicidad, planes_publicidad_config, planes_visitador_contratados, productos_empresa
--   push_subscriptions, push_tokens, receta_items, signos_vitales, solicitudes_campana
--   ubicaciones_medico_proveedor, usuario_roles, visitas_agendadas.
-- Solo cambia polroles: USING, CHECK, cmd y permissive quedan identicos (contenido sin roles d0dfa2b9... 88).
-- Huella de policies de public/private/storage 96a7fabd0178251b25943688e244ad0f 309 -> fc06b02c0b09efd90f774e612e53d454 309.
-- ACL de relaciones deedb2e6..., columnas dab25af6..., secuencias e1ef3639... (39), funciones b20ef072... (368) y
-- pg_default_acl 7143eca7... sin cambio.
-- Probes: P934 (censo: 0 {public} en public fuera de la WL), P935 (funcional: mismo resultado para authenticated
-- antes y despues, anon sigue en 42501 de privilegio); P884 ajustado (fijaba {public} en 4 de estas policies).
-- Rollback: 349_rollback.sql (correrlo ANTES que 348_rollback: su precondicion exige la huella de la 348).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
-- Una segunda pasada aborta aca: las 88 ya no estan en {public} y la huella cambio.
DO $precondicion$
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG349 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- ALTER POLICY ... TO authenticated (88)
ALTER POLICY "Medico ve su propia auditoria IA" ON public.auditoria_ia TO authenticated;
ALTER POLICY "auditoria_insert_authenticated" ON public.auditoria_logs TO authenticated;
ALTER POLICY "auditoria_select_admin" ON public.auditoria_logs TO authenticated;
ALTER POLICY "campana_metricas admin select" ON public.campana_metricas TO authenticated;
ALTER POLICY "Paciente crea sus vistas" ON public.campana_vistas TO authenticated;
ALTER POLICY "Paciente ve sus vistas" ON public.campana_vistas TO authenticated;
ALTER POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias TO authenticated;
ALTER POLICY "chat_conv_select" ON public.chat_conversaciones TO authenticated;
ALTER POLICY "chat_lect_own" ON public.chat_lecturas TO authenticated;
ALTER POLICY "Medico ve mensajes de sus pacientes" ON public.chat_mensajes TO authenticated;
ALTER POLICY "Paciente envía mensajes" ON public.chat_mensajes TO authenticated;
ALTER POLICY "Paciente ve sus mensajes" ON public.chat_mensajes TO authenticated;
ALTER POLICY "chat_msg_select" ON public.chat_mensajes_internos TO authenticated;
ALTER POLICY "chat_part_select" ON public.chat_participantes TO authenticated;
ALTER POLICY "Admin ve citas de su pais" ON public.citas TO authenticated;
ALTER POLICY "Paciente ve sus citas" ON public.citas TO authenticated;
ALTER POLICY "Admin ve clinicas de su pais" ON public.clinicas TO authenticated;
ALTER POLICY "Paciente ve clinicas de su pais" ON public.clinicas TO authenticated;
ALTER POLICY "cuentas_banco_admin" ON public.cuentas_bancarias_pais TO authenticated;
ALTER POLICY "Admin clinica gestiona disponibilidad de sus medicos" ON public.disponibilidad_medico TO authenticated;
ALTER POLICY "Admin ezpay ve toda disponibilidad" ON public.disponibilidad_medico TO authenticated;
ALTER POLICY "Médico gestiona su disponibilidad" ON public.disponibilidad_medico TO authenticated;
ALTER POLICY "Equipos: admin gestiona" ON public.equipos_visitadores TO authenticated;
ALTER POLICY "Equipos: ver segun rol" ON public.equipos_visitadores TO authenticated;
ALTER POLICY "Paciente ve sus examenes" ON public.examenes TO authenticated;
ALTER POLICY "examenes_laboratorio_select" ON public.examenes TO authenticated;
ALTER POLICY "examenes_laboratorio_update" ON public.examenes TO authenticated;
ALTER POLICY "catalogo_lab_all" ON public.examenes_catalogo TO authenticated;
ALTER POLICY "Admin ve facturas de su pais" ON public.facturas TO authenticated;
ALTER POLICY "Medico actualiza sus facturas" ON public.facturas TO authenticated;
ALTER POLICY "Medico crea sus facturas" ON public.facturas TO authenticated;
ALTER POLICY "Medico ve sus facturas" ON public.facturas TO authenticated;
ALTER POLICY "medicos_actualizar_facturas" ON public.facturas TO authenticated;
ALTER POLICY "medicos_crear_facturas" ON public.facturas TO authenticated;
ALTER POLICY "medicos_ver_facturas" ON public.facturas TO authenticated;
ALTER POLICY "invitaciones_clinica_admin_all" ON public.invitaciones_clinica TO authenticated;
ALTER POLICY "invitaciones_clinica_adminpais_all" ON public.invitaciones_clinica TO authenticated;
ALTER POLICY "inv_lab_clinica_all" ON public.invitaciones_laboratorio TO authenticated;
ALTER POLICY "inv_lab_lab_select" ON public.invitaciones_laboratorio TO authenticated;
ALTER POLICY "invitaciones_medico_admin_all" ON public.invitaciones_medico TO authenticated;
ALTER POLICY "invitaciones_medico_adminpais_all" ON public.invitaciones_medico TO authenticated;
ALTER POLICY "invitaciones_insert_admin" ON public.invitaciones_visitador TO authenticated;
ALTER POLICY "lab_clinicas_clinica_all" ON public.laboratorio_clinicas TO authenticated;
ALTER POLICY "lab_clinicas_lab_select" ON public.laboratorio_clinicas TO authenticated;
ALTER POLICY "Admin ve medicos de su pais" ON public.medicos TO authenticated;
ALTER POLICY "Medico ve su perfil" ON public.medicos TO authenticated;
ALTER POLICY "Paciente ve medicos de su pais" ON public.medicos TO authenticated;
ALTER POLICY "notificaciones_select_propia" ON public.notificaciones TO authenticated;
ALTER POLICY "notificaciones_select_super_admin" ON public.notificaciones TO authenticated;
ALTER POLICY "notificaciones_update_propia" ON public.notificaciones TO authenticated;
ALTER POLICY "notificaciones_update_super_admin" ON public.notificaciones TO authenticated;
ALTER POLICY "Admin ezpay ve notificaciones" ON public.notificaciones_email TO authenticated;
ALTER POLICY "notif_pac_select_propia" ON public.notificaciones_pacientes TO authenticated;
ALTER POLICY "notif_pac_update_leida" ON public.notificaciones_pacientes TO authenticated;
ALTER POLICY "ordenes_lab_select" ON public.ordenes_examen TO authenticated;
ALTER POLICY "Admin ezpay gestiona pagos" ON public.pagos_proveedor TO authenticated;
ALTER POLICY "Proveedor crea pagos" ON public.pagos_proveedor TO authenticated;
ALTER POLICY "Proveedor ve pagos segun rol" ON public.pagos_proveedor TO authenticated;
ALTER POLICY "Cualquiera ve planes publicidad activos" ON public.planes_publicidad TO authenticated;
ALTER POLICY "Admin gestiona config" ON public.planes_publicidad_config TO authenticated;
ALTER POLICY "Cualquiera ve config activa" ON public.planes_publicidad_config TO authenticated;
ALTER POLICY "Proveedor ve sus planes visitador" ON public.planes_visitador_contratados TO authenticated;
ALTER POLICY "Admin ezpay ve todos los productos" ON public.productos_empresa TO authenticated;
ALTER POLICY "Proveedor ve productos de su empresa" ON public.productos_empresa TO authenticated;
ALTER POLICY "Usuario crea sus push subscriptions" ON public.push_subscriptions TO authenticated;
ALTER POLICY "Usuario elimina sus push subscriptions" ON public.push_subscriptions TO authenticated;
ALTER POLICY "Usuario ve sus push subscriptions" ON public.push_subscriptions TO authenticated;
ALTER POLICY "Paciente gestiona sus tokens" ON public.push_tokens TO authenticated;
ALTER POLICY "Paciente ve items de sus recetas" ON public.receta_items TO authenticated;
ALTER POLICY "Admin ve todo signos vitales" ON public.signos_vitales TO authenticated;
ALTER POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana TO authenticated;
ALTER POLICY "Proveedor ve sus campañas" ON public.solicitudes_campana TO authenticated;
ALTER POLICY "solicitudes_campana admin select" ON public.solicitudes_campana TO authenticated;
ALTER POLICY "solicitudes_campana admin update" ON public.solicitudes_campana TO authenticated;
ALTER POLICY "ubicaciones_delete" ON public.ubicaciones_medico_proveedor TO authenticated;
ALTER POLICY "ubicaciones_insert" ON public.ubicaciones_medico_proveedor TO authenticated;
ALTER POLICY "ubicaciones_select" ON public.ubicaciones_medico_proveedor TO authenticated;
ALTER POLICY "ubicaciones_update" ON public.ubicaciones_medico_proveedor TO authenticated;
ALTER POLICY "Admins pueden actualizar usuario_roles" ON public.usuario_roles TO authenticated;
ALTER POLICY "Admins pueden insertar usuario_roles" ON public.usuario_roles TO authenticated;
ALTER POLICY "Admins pueden leer usuario_roles" ON public.usuario_roles TO authenticated;
ALTER POLICY "Admin ezpay ve todas las visitas" ON public.visitas_agendadas TO authenticated;
ALTER POLICY "Admin ve visitas de su pais" ON public.visitas_agendadas TO authenticated;
ALTER POLICY "Médico actualiza sus visitas" ON public.visitas_agendadas TO authenticated;
ALTER POLICY "Médico ve sus visitas" ON public.visitas_agendadas TO authenticated;
ALTER POLICY "Proveedor cancela sus visitas" ON public.visitas_agendadas TO authenticated;
ALTER POLICY "Proveedor crea visitas de su empresa" ON public.visitas_agendadas TO authenticated;
ALTER POLICY "Proveedor ve visitas segun rol" ON public.visitas_agendadas TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG349 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
