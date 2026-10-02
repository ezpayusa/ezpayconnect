-- ############################################################################################
-- 346 - familia 1 (privilegios), paso 5: privilegios muertos de authenticated en public
-- ############################################################################################
-- Un privilegio es MUERTO cuando la RLS lo bloquea siempre: tabla de public con RLS activa y ninguna policy
-- PERMISIVA para ese comando (cmd = el comando o ALL) cuyos roles incluyan al grantee o a public. Hoy no abre
-- nada, pero la primera policy permisiva que alguien agregue lo abre al instante. En una vista no actualizable
-- (joins/agregados, sin reglas ni triggers INSTEAD) una escritura tambien es muerta.
-- Medido en prod el 2-oct-2026 sobre f1cd2f3 (tras la 345): 113 privilegios muertos (huella 035a3ec3d3d72bc0a9cf7a685ac113e8 113).
--   authenticated: 97 en 37 tablas (las 37 del recon) y 15 escrituras en 5 vistas
--   (v_citas_hoy, v_consultas_paciente, v_estadisticas_medico, v_pacientes_actividad,
--   v_resumen_mensual; las 8 vistas de public son security_invoker y no actualizables, su SELECT no es muerto).
--   anon: SELECT de liquidaciones_comision.
-- Se REVOCAN 102 (todos de authenticated, grantor postgres, no grantables): 87 en 36 tablas y 15 en 5 vistas:
--   auditoria_ia                 INSERT, UPDATE, DELETE
--   auditoria_logs               UPDATE, DELETE
--   cache_biblioteca             INSERT, UPDATE, DELETE
--   chat_conversaciones          INSERT, UPDATE, DELETE
--   chat_mensajes                UPDATE, DELETE
--   chat_mensajes_internos       INSERT, UPDATE, DELETE
--   chat_participantes           INSERT, UPDATE, DELETE
--   configuracion                DELETE
--   confirmaciones_receta        INSERT, UPDATE, DELETE
--   contratos_comision           INSERT, UPDATE, DELETE
--   cuentas_proveedor            INSERT, UPDATE, DELETE
--   empresas_proveedoras         INSERT, DELETE
--   facturas                     DELETE
--   invitaciones_visitador       UPDATE, DELETE
--   liquidacion_dispensaciones   INSERT, UPDATE, DELETE
--   liquidaciones_comision       INSERT, UPDATE, DELETE
--   medicamentos_categorias      INSERT, UPDATE, DELETE
--   medico_clinicas              INSERT, UPDATE, DELETE
--   medico_correlativos          INSERT, UPDATE, DELETE
--   notificaciones_email         INSERT, UPDATE, DELETE
--   notificaciones_pacientes     DELETE
--   planes_features              INSERT, UPDATE, DELETE
--   planes_limites               INSERT, UPDATE, DELETE
--   planes_publicidad            INSERT, UPDATE, DELETE
--   push_subscriptions           UPDATE
--   recetas                      UPDATE, DELETE
--   recordatorios                INSERT, UPDATE, DELETE
--   recordatorios_citas          INSERT, UPDATE, DELETE
--   recordatorios_programados    UPDATE, DELETE
--   reportes_guardados           UPDATE, DELETE
--   resumen_comisiones           INSERT, UPDATE, DELETE
--   roles                        INSERT, UPDATE, DELETE
--   transacciones                INSERT, UPDATE, DELETE
--   usuario_roles                DELETE
--   visitas_agendadas            DELETE
--   whatsapp_mensajes            DELETE
--   vistas                       INSERT, UPDATE, DELETE en
--                                v_citas_hoy, v_consultas_paciente, v_estadisticas_medico, v_pacientes_actividad, v_resumen_mensual.
-- Se DEJAN 11 a proposito (allowlist de P930):
--   campana_vistas UPDATE: el front registra la vista con upsert (INSERT ... ON CONFLICT DO UPDATE), que exige
--     UPDATE aunque no haya conflicto (medido: sin UPDATE da 42501 y la vista deja de registrarse).
--   recordatorios SELECT y transacciones SELECT: el front las lee con el JWT del usuario (CitasPage; AdminEzPayPage
--     y las 2 ReportesEzPayPage): hoy reciben [], sin SELECT recibirian 42501.
--   liquidaciones_comision SELECT de anon: WL_ANON_LEGACY de P800 (una policy ajena la consulta inline; leccion
--     de la mig 284); se cierra con la 348.
--   SELECT de cache_biblioteca, confirmaciones_receta, medico_clinicas, medico_correlativos, planes_features,
--     planes_limites y resumen_comisiones: no lo lee nadie con el JWT del usuario (ni front, ni edges, ni policies,
--     vistas o funciones INVOKER), pero es su UNICO privilegio y P800 regla (b) exige que authenticated conserve
--     alguno fuera de WL_AUTH, que solo puede achicarse (tope 5). Decision 2-oct-2026: no agrandar WL_AUTH; el
--     SELECT queda y se cierra cuando se rehaga P800 (348).
-- Fuera de alcance: grants por COLUMNA (examenes, examenes_catalogo, notificaciones, notificaciones_pacientes,
-- jornadas_comerciales, visitas_comerciales: todos con policy aplicable), SELECT de las vistas, secuencias,
-- service_role/postgres.
-- Dependencias revisadas: las escrituras del front sobre privilegios revocados (cuentas_proveedor UPDATE,
-- facturas DELETE, recetas UPDATE)
-- hoy no hacen nada (RLS: 0 filas) y pasan a 42501 visible: bug latente del front, no lo arregla esta mig.
-- limpiar_cache_biblioteca_expirada() (INVOKER, escribe cache_biblioteca) no tiene llamadores (front, edges ni
-- pg_cron): como authenticated hoy borra 0 filas, despues 42501. Las edges escriben con service_role.
-- Huellas: relaciones 855f079761052808e9593a8911baaac2 -> deedb2e63fe3693b373f78e9cbfb44ce; conjunto muerto -> ebf9077769fb0682dbabc8d1eba9dff0 11 (= la allowlist). Columnas dab25af6..., secuencias
-- e1ef3639... (39), funciones b20ef072... (368) y pg_default_acl 7143eca7... sin cambio.
-- Probe: P930 (censo con la regla y la allowlist). Rollback: 346_rollback.sql (independiente de 342-345).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
-- Una segunda pasada aborta aca: la huella de relaciones y el conjunto muerto ya no son los PRE.
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- conjunto muerto: privilegio de anon/authenticated/PUBLIC sin policy permisiva aplicable (tablas con RLS) o
  -- escritura sobre una vista no actualizable (misma regla que P930)
  v := (SELECT md5(COALESCE(string_agg(z.s, ',' ORDER BY z.s COLLATE "C"), ''))||' '||count(*) FROM (
      SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||a.privilege_type AS s
        FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
       WHERE c.relnamespace = 'public'::regnamespace
         AND (a.grantee = 0 OR a.grantee IN ('authenticated'::regrole, 'anon'::regrole))
         AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
         AND ((c.relkind IN ('r','p') AND c.relrowsecurity
               AND NOT EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = c.oid AND pl.polpermissive
                     AND pl.polcmd IN ('*', CASE a.privilege_type WHEN 'SELECT' THEN 'r' WHEN 'INSERT' THEN 'a' WHEN 'UPDATE' THEN 'w' ELSE 'd' END)
                     AND (0 = ANY (pl.polroles) OR a.grantee = ANY (pl.polroles))))
           OR (c.relkind = 'v' AND a.privilege_type <> 'SELECT'
               AND (pg_relation_is_updatable(c.oid::regclass, true)
                    & CASE a.privilege_type WHEN 'UPDATE' THEN 4 WHEN 'INSERT' THEN 8 ELSE 16 END) = 0))) z);
  IF v IS DISTINCT FROM '035a3ec3d3d72bc0a9cf7a685ac113e8 113' THEN bad := bad||'conjunto muerto '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '855f079761052808e9593a8911baaac2' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG346 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- REVOKE (lista explicita por relacion)
REVOKE INSERT, UPDATE, DELETE ON public.auditoria_ia FROM authenticated;
REVOKE UPDATE, DELETE ON public.auditoria_logs FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cache_biblioteca FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.chat_conversaciones FROM authenticated;
REVOKE UPDATE, DELETE ON public.chat_mensajes FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.chat_mensajes_internos FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.chat_participantes FROM authenticated;
REVOKE DELETE ON public.configuracion FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.confirmaciones_receta FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.contratos_comision FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cuentas_proveedor FROM authenticated;
REVOKE INSERT, DELETE ON public.empresas_proveedoras FROM authenticated;
REVOKE DELETE ON public.facturas FROM authenticated;
REVOKE UPDATE, DELETE ON public.invitaciones_visitador FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.liquidacion_dispensaciones FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.liquidaciones_comision FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.medicamentos_categorias FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.medico_clinicas FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.medico_correlativos FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.notificaciones_email FROM authenticated;
REVOKE DELETE ON public.notificaciones_pacientes FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.planes_features FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.planes_limites FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.planes_publicidad FROM authenticated;
REVOKE UPDATE ON public.push_subscriptions FROM authenticated;
REVOKE UPDATE, DELETE ON public.recetas FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.recordatorios FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.recordatorios_citas FROM authenticated;
REVOKE UPDATE, DELETE ON public.recordatorios_programados FROM authenticated;
REVOKE UPDATE, DELETE ON public.reportes_guardados FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.resumen_comisiones FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.roles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.transacciones FROM authenticated;
REVOKE DELETE ON public.usuario_roles FROM authenticated;
REVOKE DELETE ON public.visitas_agendadas FROM authenticated;
REVOKE DELETE ON public.whatsapp_mensajes FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.v_citas_hoy FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.v_consultas_paciente FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.v_estadisticas_medico FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.v_pacientes_actividad FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.v_resumen_mensual FROM authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
-- Conjunto muerto = exactamente la allowlist; ACL de relaciones = PRE menos las 102 tuplas revocadas.
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- conjunto muerto: privilegio de anon/authenticated/PUBLIC sin policy permisiva aplicable (tablas con RLS) o
  -- escritura sobre una vista no actualizable (misma regla que P930)
  v := (SELECT md5(COALESCE(string_agg(z.s, ',' ORDER BY z.s COLLATE "C"), ''))||' '||count(*) FROM (
      SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||a.privilege_type AS s
        FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
       WHERE c.relnamespace = 'public'::regnamespace
         AND (a.grantee = 0 OR a.grantee IN ('authenticated'::regrole, 'anon'::regrole))
         AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
         AND ((c.relkind IN ('r','p') AND c.relrowsecurity
               AND NOT EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = c.oid AND pl.polpermissive
                     AND pl.polcmd IN ('*', CASE a.privilege_type WHEN 'SELECT' THEN 'r' WHEN 'INSERT' THEN 'a' WHEN 'UPDATE' THEN 'w' ELSE 'd' END)
                     AND (0 = ANY (pl.polroles) OR a.grantee = ANY (pl.polroles))))
           OR (c.relkind = 'v' AND a.privilege_type <> 'SELECT'
               AND (pg_relation_is_updatable(c.oid::regclass, true)
                    & CASE a.privilege_type WHEN 'UPDATE' THEN 4 WHEN 'INSERT' THEN 8 ELSE 16 END) = 0))) z);
  IF v IS DISTINCT FROM 'ebf9077769fb0682dbabc8d1eba9dff0 11' THEN bad := bad||'conjunto muerto '||COALESCE(v, '-')||'; '; END IF;
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
  IF bad <> '' THEN RAISE EXCEPTION 'MIG346 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
