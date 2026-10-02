-- ############################################################################################
-- 346 ROLLBACK - devuelve a authenticated los 102 privilegios muertos revocados por la 346 (relaciones 855f0797...)
-- ############################################################################################
-- GRANT explicito por relacion desde el inventario PRE (grantor postgres, sin GRANT OPTION, como en el PRE).
-- En las relaciones donde authenticated se habia quedado sin nada el aclitem vuelve al final del array: el texto
-- de relacl cambia de orden, los privilegios no; la huella no depende del orden.
-- Precondicion = estado POST de la 346; autochequeo = huella PRE y conjunto muerto PRE.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado POST)
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
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK346 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- grants del PRE
GRANT INSERT, UPDATE, DELETE ON public.auditoria_ia TO authenticated;
GRANT UPDATE, DELETE ON public.auditoria_logs TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.cache_biblioteca TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.chat_conversaciones TO authenticated;
GRANT UPDATE, DELETE ON public.chat_mensajes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.chat_mensajes_internos TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.chat_participantes TO authenticated;
GRANT DELETE ON public.configuracion TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.confirmaciones_receta TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.contratos_comision TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.cuentas_proveedor TO authenticated;
GRANT INSERT, DELETE ON public.empresas_proveedoras TO authenticated;
GRANT DELETE ON public.facturas TO authenticated;
GRANT UPDATE, DELETE ON public.invitaciones_visitador TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.liquidacion_dispensaciones TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.liquidaciones_comision TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.medicamentos_categorias TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.medico_clinicas TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.medico_correlativos TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.notificaciones_email TO authenticated;
GRANT DELETE ON public.notificaciones_pacientes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.planes_features TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.planes_limites TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.planes_publicidad TO authenticated;
GRANT UPDATE ON public.push_subscriptions TO authenticated;
GRANT UPDATE, DELETE ON public.recetas TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.recordatorios TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.recordatorios_citas TO authenticated;
GRANT UPDATE, DELETE ON public.recordatorios_programados TO authenticated;
GRANT UPDATE, DELETE ON public.reportes_guardados TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.resumen_comisiones TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.roles TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.transacciones TO authenticated;
GRANT DELETE ON public.usuario_roles TO authenticated;
GRANT DELETE ON public.visitas_agendadas TO authenticated;
GRANT DELETE ON public.whatsapp_mensajes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.v_citas_hoy TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.v_consultas_paciente TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.v_estadisticas_medico TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.v_pacientes_actividad TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.v_resumen_mensual TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado PRE)
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
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK346 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
