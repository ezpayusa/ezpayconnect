-- ############################################################################################
-- 345 ROLLBACK - devuelve los privilegios de las secuencias al estado PRE (huella 2b8162b517a99df0b708977911009183 39)
-- ############################################################################################
-- GRANT explicito por secuencia y por rol, sacado del inventario PRE medido el 2-oct-2026 (65 sentencias:
-- anon en 32 secuencias, authenticated en 33). El grantor es postgres (duenio), igual que en el PRE.
-- El texto de relacl no queda identico al PRE: un aclitem re-otorgado va al final del array (anon despues de
-- service_role). Los privilegios si: el autochequeo usa la huella, que es independiente del orden.
-- Precondicion = estado POST de la 345; autochequeo = huella PRE y el resto intacto.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado POST)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- ACL exacta de cada secuencia de public/private (POST) y ninguna secuencia de mas ni de menos
  SELECT string_agg(e.sch||'.'||e.seq||'='||COALESCE(c.relacl::text, 'NULL')||' (esperado '||COALESCE(e.acl, 'NULL')||')', '; ' ORDER BY e.sch, e.seq)
    INTO v
    FROM (VALUES
      ('private', 'busqueda_paciente_log_id_seq', NULL::text),
      ('private', 'delivery_autocreate_fallos_id_seq', NULL::text),
      ('private', 'reveal_log_id_seq', NULL::text),
      ('public', 'auditoria_ia_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'cache_biblioteca_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'campana_metricas_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'campana_vistas_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'campanas_publicitarias_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'canjes_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'chat_mensajes_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'citas_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'consentimiento_permisos_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'consentimientos_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'documentos_paciente_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'entrega_evidencias_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'entregas_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'examen_adjuntos_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'examen_liberacion_eventos_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'examen_revisiones_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'examenes_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'expediente_notas_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'expediente_notas_revisiones_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'facturas_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'farmacias_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'medicamentos_clasificacion_log_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'medicamentos_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'medico_clinicas_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'notificaciones_pacientes_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'pacientes_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'planes_publicidad_config_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'planes_publicidad_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'premios_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'puntos_movimientos_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'push_tokens_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}'),
      ('public', 'receta_items_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'recetas_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'referidos_atribucion_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'referidos_paciente_id_seq', '{postgres=rwU/postgres,service_role=rwU/postgres}'),
      ('public', 'signos_vitales_id_seq', '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}')) e(sch, seq, acl)
    LEFT JOIN pg_namespace n ON n.nspname = e.sch
    LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relname = e.seq AND c.relkind = 'S'
   WHERE c.oid IS NULL OR c.relacl::text IS DISTINCT FROM e.acl;
  IF v IS NOT NULL THEN bad := bad||'secuencias: '||v||'; '; END IF;
  v := (SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'S' AND n.nspname IN ('public','private'));
  IF v IS DISTINCT FROM '39' THEN bad := bad||'cantidad de secuencias public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM 'e1ef3639c3367e24c1369c0dbf95a994 39' THEN bad := bad||'huella de secuencias '||COALESCE(v, '-')||'; '; END IF;
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
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  -- el conjunto necesario, recalculado con la regla (la misma de P928): no cambio desde el recon
  v := (SELECT COALESCE(string_agg(DISTINCT s.relname::text, ',' ORDER BY s.relname::text), '') FROM pg_depend d
       JOIN pg_attrdef ad ON ad.oid = d.objid JOIN pg_class t ON t.oid = ad.adrelid
       JOIN pg_class s ON s.oid = d.refobjid AND s.relkind = 'S'
      WHERE d.classid = 'pg_attrdef'::regclass AND d.refclassid = 'pg_class'::regclass
        AND t.relnamespace = 'public'::regnamespace
        AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(t.relacl, acldefault('r', t.relowner))) x
                     WHERE x.grantee = 'authenticated'::regrole AND x.privilege_type = 'INSERT')
        AND EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = t.oid AND pl.polcmd IN ('a','*')
                     AND (0 = ANY (pl.polroles) OR 'authenticated'::regrole = ANY (pl.polroles))));
  IF v IS DISTINCT FROM 'campana_vistas_id_seq,campanas_publicitarias_id_seq,chat_mensajes_id_seq,citas_id_seq,expediente_notas_id_seq,facturas_id_seq,farmacias_id_seq,pacientes_id_seq,planes_publicidad_config_id_seq,push_tokens_id_seq,signos_vitales_id_seq' THEN bad := bad||'conjunto necesario '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK345 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- grants del PRE
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.auditoria_ia_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.auditoria_ia_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.cache_biblioteca_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.cache_biblioteca_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.campana_metricas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.campana_metricas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.campana_vistas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.campana_vistas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.campanas_publicitarias_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.campanas_publicitarias_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.canjes_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.canjes_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.chat_mensajes_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.chat_mensajes_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.citas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.citas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.consentimiento_permisos_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.consentimiento_permisos_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.consentimientos_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.consentimientos_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.documentos_paciente_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.documentos_paciente_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.entrega_evidencias_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.entrega_evidencias_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.entregas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.entregas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.examen_adjuntos_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.examenes_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.examenes_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.expediente_notas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.expediente_notas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.facturas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.facturas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.farmacias_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.farmacias_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.medicamentos_clasificacion_log_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.medicamentos_clasificacion_log_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.medicamentos_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.medicamentos_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.medico_clinicas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.medico_clinicas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.notificaciones_pacientes_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.notificaciones_pacientes_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.pacientes_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.pacientes_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.planes_publicidad_config_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.planes_publicidad_config_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.planes_publicidad_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.planes_publicidad_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.premios_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.premios_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.puntos_movimientos_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.puntos_movimientos_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.push_tokens_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.push_tokens_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.receta_items_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.receta_items_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.recetas_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.recetas_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.referidos_atribucion_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.referidos_atribucion_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.referidos_paciente_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.referidos_paciente_id_seq TO authenticated;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.signos_vitales_id_seq TO anon;
GRANT SELECT, UPDATE, USAGE ON SEQUENCE public.signos_vitales_id_seq TO authenticated;

-- ---------------------------------------------------------------------------- autochequeo (huella PRE)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT c.oid AS o, n.nspname||'.'||c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(COALESCE(c.relacl, acldefault('s', c.relowner))) a
       WHERE n.nspname IN ('public','private') AND c.relkind = 'S') y);
  IF v IS DISTINCT FROM '2b8162b517a99df0b708977911009183 39' THEN bad := bad||'huella de secuencias '||COALESCE(v, '-')||'; '; END IF;
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
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'b20ef072973cc2cc56515e6820851d05 368' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  -- el conjunto necesario, recalculado con la regla (la misma de P928): no cambio desde el recon
  v := (SELECT COALESCE(string_agg(DISTINCT s.relname::text, ',' ORDER BY s.relname::text), '') FROM pg_depend d
       JOIN pg_attrdef ad ON ad.oid = d.objid JOIN pg_class t ON t.oid = ad.adrelid
       JOIN pg_class s ON s.oid = d.refobjid AND s.relkind = 'S'
      WHERE d.classid = 'pg_attrdef'::regclass AND d.refclassid = 'pg_class'::regclass
        AND t.relnamespace = 'public'::regnamespace
        AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(t.relacl, acldefault('r', t.relowner))) x
                     WHERE x.grantee = 'authenticated'::regrole AND x.privilege_type = 'INSERT')
        AND EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = t.oid AND pl.polcmd IN ('a','*')
                     AND (0 = ANY (pl.polroles) OR 'authenticated'::regrole = ANY (pl.polroles))));
  IF v IS DISTINCT FROM 'campana_vistas_id_seq,campanas_publicitarias_id_seq,chat_mensajes_id_seq,citas_id_seq,expediente_notas_id_seq,facturas_id_seq,farmacias_id_seq,pacientes_id_seq,planes_publicidad_config_id_seq,push_tokens_id_seq,signos_vitales_id_seq' THEN bad := bad||'conjunto necesario '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK345 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
