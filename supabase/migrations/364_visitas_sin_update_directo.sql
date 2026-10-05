-- ############################################################################################
-- 364 - visitas_agendadas sin UPDATE directo (familia 2, F2-d)
-- ############################################################################################
-- Recon del 5-oct-2026 (solo lectura contra prod, con la 363 aplicada):
--   * visitas_agendadas tiene 7 policies, todas TO authenticated: 1 INSERT, 4 SELECT y 2 UPDATE sin WITH CHECK:
--       "Médico actualiza sus visitas"  USING (medico_id = auth.uid())
--       "Proveedor cancela sus visitas" USING (empresa_id = mi_empresa_proveedor())
--     Sin WITH CHECK, el WITH CHECK efectivo es el USING: el medico podia poner cualquier estado (confirmar, completar,
--     check-in) en sus visitas, y CUALQUIER cuenta de la empresa (visitador, supervisor, gerente) cualquier columna de
--     cualquier visita de su empresa, salteando las reglas de las RPCs (ventana de cancelacion, dia del check-in,
--     evidencia, aprobada_por, etc.). trg_gate_visita_pais solo mira UPDATE OF medico_id.
--   * Ningun front ni edge hace UPDATE directo: el unico write del cliente es el INSERT de useVisitasAgendadas.ts:180; las
--     edges (notificar-email, procesar-recordatorios, programar-recordatorio) solo leen. Toda la escritura va por 7 RPCs
--     SECURITY DEFINER de dueño postgres (BYPASSRLS, con UPDATE propio), que no dependen de la RLS ni del privilegio del
--     llamante: administrar_visita, cancelar_visita, checkin_visita, checkout_visita, marcar_visitador_presente,
--     notificar_visita_propuesta y notificar_visita_resultado.
--   * ACL: authenticated=arw (SELECT, INSERT, UPDATE); anon nada; sin privilegios por columna.
-- Cambio: DROP de las 2 policies de UPDATE y REVOKE UPDATE de authenticated (regla 12: privilegio de escritura solo junto
-- con la policy que lo habilita). Un UPDATE directo pasa a dar 42501 de privilegio. No se tocan SELECT, INSERT, la policy
-- de INSERT, los 4 triggers ni las RPCs.
-- Huella de policies 6fd0d66d... 311 -> 1929c331... 309; ACL de relaciones de public deedb2e6... -> d05a8b3a...; ACL de
-- funciones sin cambio (c7f89c6d... 380).
-- Probes: P1007 (nuevo); P259 invertido, P781 acepta 42501, nota en P258.
-- Rollback: 364_rollback.sql (texto exacto de las 2 policies + GRANT UPDATE).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  -- las 2 policies de UPDATE, con su texto del recon y sin WITH CHECK; ninguna ALL
  v := (SELECT string_agg(pl.polname||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), 'NULL'), E'\n' ORDER BY pl.polname)
          FROM pg_policy pl WHERE pl.polrelid = 'public.visitas_agendadas'::regclass AND pl.polcmd IN ('w', '*'));
  IF v IS DISTINCT FROM 'Médico actualiza sus visitas|{authenticated}|true|(medico_id = auth.uid())|NULL'||E'\n'
                      ||'Proveedor cancela sus visitas|{authenticated}|true|(empresa_id = mi_empresa_proveedor())|NULL' THEN
    bad := bad||'policies de UPDATE/ALL de visitas_agendadas ['||COALESCE(v, '-')||']; ';
  END IF;
  -- las otras 5 (INSERT + 4 SELECT), texto completo
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.visitas_agendadas'::regclass AND pl.polcmd <> 'w');
  IF v IS DISTINCT FROM '2c45abcf0b0648878762b0c81b480391 5' THEN bad := bad||'las otras 5 policies '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de la tabla
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.visitas_agendadas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.visitas_agendadas', 'UPDATE') THEN bad := bad||'authenticated sin UPDATE; '; END IF;
  IF has_table_privilege('anon', 'public.visitas_agendadas', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
     OR has_any_column_privilege('anon', 'public.visitas_agendadas', 'SELECT,INSERT,UPDATE,REFERENCES') THEN
    bad := bad||'anon con algun privilegio; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.visitas_agendadas'::regclass AND attnum > 0 AND NOT attisdropped AND attacl IS NOT NULL) THEN
    bad := bad||'hay privilegios por columna; ';
  END IF;
  -- las 7 RPCs escritoras: DEFINER, dueño postgres, cuerpo del recon
  v := (SELECT string_agg(p.proname||'|'||md5(p.prosrc)||'|'||p.prosecdef::text||'|'||pg_get_userbyid(p.proowner), ',' ORDER BY p.proname)
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('administrar_visita','cancelar_visita','checkin_visita','checkout_visita',
                                                                                         'marcar_visitador_presente','notificar_visita_propuesta','notificar_visita_resultado'));
  IF v IS DISTINCT FROM 'administrar_visita|666800e7be6ccee444632f933d5146c0|true|postgres,cancelar_visita|866159b76f6af88291dffea24430e5bf|true|postgres,'
                      ||'checkin_visita|1fd274eb3714bc7a88bfa7490d626fa5|true|postgres,checkout_visita|0dfacf94eda53ddf38d777793a806774|true|postgres,'
                      ||'marcar_visitador_presente|6fa4dbd4e9c6bb7b899dab884e33d1ae|true|postgres,notificar_visita_propuesta|b1abf162334a3d817e41e369b32b9768|true|postgres,'
                      ||'notificar_visita_resultado|ebdb579ec423c0dbabce62fadfa424f8|true|postgres' THEN
    bad := bad||'RPCs escritoras ['||COALESCE(v, '-')||']; ';
  END IF;
  -- los 4 triggers
  v := (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'\n' ORDER BY t.tgname))||' '||count(*) FROM pg_trigger t WHERE t.tgrelid = 'public.visitas_agendadas'::regclass AND NOT t.tgisinternal);
  IF v IS DISTINCT FROM 'c51f2cff5295cc99651b2dea48e52d50 4' THEN bad := bad||'triggers '||COALESCE(v, '-')||'; '; END IF;
  -- huellas globales
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '6fd0d66ddce6b6d6d3ac349911c31153 311' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'deedb2e63fe3693b373f78e9cbfb44ce' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'c7f89c6df3048083e3722d6eec7d1998 380' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG364 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- cambio
DROP POLICY "Médico actualiza sus visitas" ON public.visitas_agendadas;
DROP POLICY "Proveedor cancela sus visitas" ON public.visitas_agendadas;
REVOKE UPDATE ON public.visitas_agendadas FROM authenticated;

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.visitas_agendadas'::regclass AND pl.polcmd IN ('w', '*')) THEN
    bad := bad||'quedan policies UPDATE o ALL en visitas_agendadas; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||pl.polpermissive::text
                          ||'|'||COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.visitas_agendadas'::regclass);
  IF v IS DISTINCT FROM '2c45abcf0b0648878762b0c81b480391 5' THEN bad := bad||'las otras 5 policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT relacl::text FROM pg_class WHERE oid = 'public.visitas_agendadas'::regclass);
  IF v IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=ar/postgres,service_role=arwdDxtm/postgres}' THEN bad := bad||'relacl '||COALESCE(v, '-')||'; '; END IF;
  IF has_table_privilege('authenticated', 'public.visitas_agendadas', 'UPDATE') OR has_any_column_privilege('authenticated', 'public.visitas_agendadas', 'UPDATE') THEN
    bad := bad||'authenticated conserva UPDATE; ';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.visitas_agendadas', 'SELECT') OR NOT has_table_privilege('authenticated', 'public.visitas_agendadas', 'INSERT') THEN
    bad := bad||'authenticated perdio SELECT o INSERT; ';
  END IF;
  IF has_table_privilege('authenticated', 'public.visitas_agendadas', 'DELETE') THEN bad := bad||'authenticated con DELETE; '; END IF;
  IF has_table_privilege('anon', 'public.visitas_agendadas', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
     OR has_any_column_privilege('anon', 'public.visitas_agendadas', 'SELECT,INSERT,UPDATE,REFERENCES') THEN
    bad := bad||'anon con algun privilegio; ';
  END IF;
  -- service_role sin cambios (has_table_privilege con lista = ALGUNO; aca hacen falta los 8)
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) pr
              WHERE NOT has_table_privilege('service_role', 'public.visitas_agendadas', pr)) THEN
    bad := bad||'service_role perdio algo; ';
  END IF;
  v := (SELECT string_agg(p.proname||'|'||md5(p.prosrc)||'|'||p.prosecdef::text||'|'||pg_get_userbyid(p.proowner), ',' ORDER BY p.proname)
          FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('administrar_visita','cancelar_visita','checkin_visita','checkout_visita',
                                                                                         'marcar_visitador_presente','notificar_visita_propuesta','notificar_visita_resultado'));
  IF v IS DISTINCT FROM 'administrar_visita|666800e7be6ccee444632f933d5146c0|true|postgres,cancelar_visita|866159b76f6af88291dffea24430e5bf|true|postgres,'
                      ||'checkin_visita|1fd274eb3714bc7a88bfa7490d626fa5|true|postgres,checkout_visita|0dfacf94eda53ddf38d777793a806774|true|postgres,'
                      ||'marcar_visitador_presente|6fa4dbd4e9c6bb7b899dab884e33d1ae|true|postgres,notificar_visita_propuesta|b1abf162334a3d817e41e369b32b9768|true|postgres,'
                      ||'notificar_visita_resultado|ebdb579ec423c0dbabce62fadfa424f8|true|postgres' THEN
    bad := bad||'RPCs escritoras ['||COALESCE(v, '-')||']; ';
  END IF;
  v := (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'\n' ORDER BY t.tgname))||' '||count(*) FROM pg_trigger t WHERE t.tgrelid = 'public.visitas_agendadas'::regclass AND NOT t.tgisinternal);
  IF v IS DISTINCT FROM 'c51f2cff5295cc99651b2dea48e52d50 4' THEN bad := bad||'triggers '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '1929c33129d0f77f80020bdc0603243c 309' THEN bad := bad||'huella de policies'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), '')) FROM (SELECT c.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'd05a8b3a6e300f40365ddc3a5c1c7cde' THEN bad := bad||'ACL de relaciones de public'||' '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'c7f89c6df3048083e3722d6eec7d1998 380' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG364 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
