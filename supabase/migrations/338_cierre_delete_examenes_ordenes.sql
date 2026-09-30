-- ############################################################################################
-- 338 - cierre del DELETE directo sobre examenes y ordenes_examen (+ MAINTAIN de ordenes_examen)
-- ############################################################################################
-- Spec P4 v3 ("MIG 336 - Cierre del DELETE directo (D8)", renumerada: la 336 real fue el fix de
-- liberacion concurrente). Recon de solo lectura del 30-sep-2026 (tmp/recon_338/):
--   * authenticated tiene DELETE en examenes y en ordenes_examen, y MAINTAIN en ordenes_examen
--     (aclexplode; information_schema.role_table_grants no muestra MAINTAIN).
--   * 5 policies de DELETE vivas: examenes_laboratorio_delete, examenes_medico_delete,
--     examenes_superadmin_delete, ordenes_lab_delete, ordenes_medico_delete.
--   * Nadie borra: 0 funciones con DELETE FROM sobre estas tablas, 0 .delete() en src/ y
--     supabase/functions/, y examen_estado no tiene 'cancelado'. No hace falta excepcion.
--   * examenes.orden_id es ON DELETE CASCADE: borrar una orden sin historia borra sus examenes,
--     completados incluidos, y el cascade corre con los privilegios del duenio. Cerrar el DELETE de
--     ordenes_examen corta ese camino. La FK en si NO se toca aca (backlog).
--
-- Queda: examenes = SELECT + UPDATE por columna (archivo_url, estado, fecha_resultado, resultados,
-- de la 332) para authenticated; ordenes_examen = SELECT. service_role y postgres sin cambios
-- (postgres sigue borrando fixtures sin historia; lo prueba P915).
-- Fuera de alcance: la FK examenes_orden_id_fkey, examenes_catalogo, examen_adjuntos.
-- Sin errcodes nuevos: el DELETE directo cae en 42501 del propio Postgres (falta de privilegio).
-- Probes: P881 y P884 ajustados; P914 (DELETE directo por actor -> 42501) y P915 (catalogo post-338).
-- Rollback: 338_rollback.sql.
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones
-- Estado PRE medido en prod el 30-sep-2026 (pg_policies con el search_path por defecto; md5 de
-- prosrc como la 336). Una segunda pasada aborta aca: las 5 policies ya no existen.
DO $pre$
DECLARE bad text := ''; x text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('examenes',       'examenes_laboratorio_delete', '{public}',        '(laboratorio_id = mi_empresa_proveedor())'),
      ('examenes',       'examenes_medico_delete',      '{authenticated}', '(medico_id = auth.uid())'),
      ('examenes',       'examenes_superadmin_delete',  '{authenticated}', 'private.tiene_rol(ARRAY[''super_admin''::text])'),
      ('ordenes_examen', 'ordenes_lab_delete',          '{public}',        '(laboratorio_id = mi_empresa_proveedor())'),
      ('ordenes_examen', 'ordenes_medico_delete',       '{authenticated}', '(medico_id = auth.uid())')) v(t, p, roles, q) LOOP
    SELECT cmd||' '||permissive||' '||roles::text||' '||COALESCE(qual, '<null>')||' '||COALESCE(with_check, '<null>') INTO x
      FROM pg_policies WHERE schemaname = 'public' AND tablename = r.t AND policyname = r.p;
    IF x IS DISTINCT FROM 'DELETE PERMISSIVE '||r.roles||' '||r.q||' <null>' THEN
      bad := bad||r.p||': '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  -- privilegios de authenticated por aclexplode (MAINTAIN no sale en information_schema)
  SELECT string_agg(a.privilege_type, ',' ORDER BY a.privilege_type) INTO x
    FROM aclexplode((SELECT relacl FROM pg_class WHERE oid = 'public.examenes'::regclass)) a
   WHERE a.grantee = 'authenticated'::regrole;
  IF x IS DISTINCT FROM 'DELETE,SELECT' THEN bad := bad||'authenticated en examenes: '||COALESCE(x, '-')||'; '; END IF;
  SELECT string_agg(a.privilege_type, ',' ORDER BY a.privilege_type) INTO x
    FROM aclexplode((SELECT relacl FROM pg_class WHERE oid = 'public.ordenes_examen'::regclass)) a
   WHERE a.grantee = 'authenticated'::regrole;
  IF x IS DISTINCT FROM 'DELETE,MAINTAIN,SELECT' THEN bad := bad||'authenticated en ordenes_examen: '||COALESCE(x, '-')||'; '; END IF;
  -- el resto de las policies (SELECT/UPDATE) de las dos tablas: 9, texto exacto
  SELECT md5(string_agg(tablename||'|'||policyname||'|'||cmd||'|'||permissive||'|'||roles::text||'|'||COALESCE(qual,'')||'|'||COALESCE(with_check,''), E'\n' ORDER BY tablename, policyname))||' '||count(*)
    INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('examenes','ordenes_examen') AND cmd NOT IN ('DELETE','ALL');
  IF x IS DISTINCT FROM '9b00f7f65a4d8e0c48a5561d1e1d3dbb 9' THEN bad := bad||'policies SELECT/UPDATE: '||COALESCE(x, '-')||'; '; END IF;
  -- RPCs de la 332 y de liberacion/correccion: md5 de prosrc vivo
  FOR r IN SELECT * FROM (VALUES
      ('public.crear_orden_examen_medico(bigint,uuid,jsonb,text)',             '79a994588ab2b4458135272efb59b867'),
      ('public.crear_orden_examen_walkin(jsonb,text,text,text,text,text)',     '434d122370e340d895c8540a290379f3'),
      ('public.liberar_examen_al_paciente(integer)',                           'd1321b5fd0d994da4605b959249ba3b7'),
      ('public.liberar_orden_al_paciente(uuid)',                               '10a82b4176a65a58cb46ec5f2dca0447'),
      ('public.revertir_liberacion_examen(integer)',                           '8884c3445e9f29fa8850beab66a07775'),
      ('public.corregir_resultado_examen(integer,text,text,text)',             '9a2a4b5b33e6b6f0bc0ddd454906f848')) v(f, m) LOOP
    SELECT md5(p.prosrc) INTO x FROM pg_proc p WHERE p.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG338 PRECONDICION FALLA:%', bad; END IF;
END $pre$;

-- ACL PRE de las dos tablas (tabla y columnas) sin authenticated: el autochequeo exige que el resto
-- (postgres, service_role, anon, PUBLIC) quede exactamente igual
CREATE TEMP TABLE _acl338 ON COMMIT DROP AS
SELECT c.relname AS t, NULL::text AS col, a.grantee, a.privilege_type, a.grantor, a.is_grantable
  FROM pg_class c, aclexplode(c.relacl) a
 WHERE c.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass) AND a.grantee <> 'authenticated'::regrole
UNION ALL
SELECT t.relname, at.attname, a.grantee, a.privilege_type, a.grantor, a.is_grantable
  FROM pg_class t JOIN pg_attribute at ON at.attrelid = t.oid AND at.attnum > 0 AND NOT at.attisdropped, aclexplode(at.attacl) a
 WHERE t.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass);

-- --------------------------------------------------------------------------- policies DELETE
DROP POLICY examenes_laboratorio_delete ON public.examenes;
DROP POLICY examenes_medico_delete      ON public.examenes;
DROP POLICY examenes_superadmin_delete  ON public.examenes;
DROP POLICY ordenes_lab_delete          ON public.ordenes_examen;
DROP POLICY ordenes_medico_delete       ON public.ordenes_examen;

-- ---------------------------------------------------------------------------------- grants
REVOKE DELETE ON TABLE public.examenes, public.ordenes_examen FROM authenticated, anon, PUBLIC;
REVOKE MAINTAIN ON TABLE public.ordenes_examen FROM authenticated, anon, PUBLIC;

-- ---------------------------------------------------------------------------- autochequeo
DO $chk$
DECLARE bad text := ''; x text; r record; v_tab text; v_priv text; v_rol text;
BEGIN
  -- 0 policies DELETE o ALL en las dos tablas
  SELECT string_agg(tablename||'.'||policyname||':'||cmd, ',') INTO x
    FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('examenes','ordenes_examen') AND cmd IN ('DELETE','ALL');
  IF x IS NOT NULL THEN bad := bad||'quedan policies DELETE/ALL: '||x||'; '; END IF;
  -- el resto de las policies, textualmente igual
  SELECT md5(string_agg(tablename||'|'||policyname||'|'||cmd||'|'||permissive||'|'||roles::text||'|'||COALESCE(qual,'')||'|'||COALESCE(with_check,''), E'\n' ORDER BY tablename, policyname))||' '||count(*)
    INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('examenes','ordenes_examen');
  IF x IS DISTINCT FROM '9b00f7f65a4d8e0c48a5561d1e1d3dbb 9' THEN bad := bad||'policies SELECT/UPDATE cambiaron: '||COALESCE(x, '-')||'; '; END IF;
  -- sin DELETE ni MAINTAIN para authenticated ni anon (has_table_privilege: incluye lo heredado de PUBLIC)
  FOREACH v_tab IN ARRAY ARRAY['public.examenes','public.ordenes_examen'] LOOP
    FOREACH v_rol IN ARRAY ARRAY['authenticated','anon'] LOOP
      FOREACH v_priv IN ARRAY ARRAY['DELETE','MAINTAIN'] LOOP
        IF has_table_privilege(v_rol, v_tab, v_priv) THEN bad := bad||v_rol||' con '||v_priv||' en '||v_tab||'; '; END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  -- 0 entradas PUBLIC (grantee 0) en tabla ni columnas
  IF EXISTS (SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
              WHERE c.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass) AND a.grantee = 0)
     OR EXISTS (SELECT 1 FROM pg_attribute at, aclexplode(at.attacl) a
              WHERE at.attrelid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass) AND a.grantee = 0) THEN
    bad := bad||'hay entradas PUBLIC; '; END IF;
  -- authenticated: SELECT a nivel tabla en las dos
  SELECT string_agg(a.privilege_type, ',' ORDER BY a.privilege_type) INTO x
    FROM aclexplode((SELECT relacl FROM pg_class WHERE oid = 'public.examenes'::regclass)) a WHERE a.grantee = 'authenticated'::regrole;
  IF x IS DISTINCT FROM 'SELECT' THEN bad := bad||'authenticated en examenes: '||COALESCE(x, '-')||'; '; END IF;
  SELECT string_agg(a.privilege_type, ',' ORDER BY a.privilege_type) INTO x
    FROM aclexplode((SELECT relacl FROM pg_class WHERE oid = 'public.ordenes_examen'::regclass)) a WHERE a.grantee = 'authenticated'::regrole;
  IF x IS DISTINCT FROM 'SELECT' THEN bad := bad||'authenticated en ordenes_examen: '||COALESCE(x, '-')||'; '; END IF;
  -- grants por columna: exactamente los de la 332 (UPDATE de authenticated en 4 columnas de examenes)
  SELECT string_agg(t2.relname||'.'||at.attname||':'||pg_get_userbyid(a.grantee)||':'||a.privilege_type, ',' ORDER BY t2.relname||'.'||at.attname||':'||pg_get_userbyid(a.grantee)||':'||a.privilege_type) INTO x
    FROM pg_class t2 JOIN pg_attribute at ON at.attrelid = t2.oid AND at.attnum > 0 AND NOT at.attisdropped, aclexplode(at.attacl) a
   WHERE t2.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass);
  IF x IS DISTINCT FROM 'examenes.archivo_url:authenticated:UPDATE,examenes.estado:authenticated:UPDATE,examenes.fecha_resultado:authenticated:UPDATE,examenes.resultados:authenticated:UPDATE' THEN
    bad := bad||'grants por columna: '||COALESCE(x, '-')||'; '; END IF;
  -- el resto de la ACL (postgres, service_role, ...) igual a la PRE
  IF EXISTS (
      (SELECT t, col, grantee, privilege_type, grantor, is_grantable FROM _acl338
       EXCEPT
       SELECT c.relname, NULL::text, a.grantee, a.privilege_type, a.grantor, a.is_grantable
         FROM pg_class c, aclexplode(c.relacl) a
        WHERE c.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass) AND a.grantee <> 'authenticated'::regrole
       EXCEPT
       SELECT t2.relname, at.attname, a.grantee, a.privilege_type, a.grantor, a.is_grantable
         FROM pg_class t2 JOIN pg_attribute at ON at.attrelid = t2.oid AND at.attnum > 0 AND NOT at.attisdropped, aclexplode(at.attacl) a
        WHERE t2.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass))
      UNION ALL
      (SELECT c.relname, NULL::text, a.grantee, a.privilege_type, a.grantor, a.is_grantable
         FROM pg_class c, aclexplode(c.relacl) a
        WHERE c.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass) AND a.grantee <> 'authenticated'::regrole
       UNION ALL
       SELECT t2.relname, at.attname, a.grantee, a.privilege_type, a.grantor, a.is_grantable
         FROM pg_class t2 JOIN pg_attribute at ON at.attrelid = t2.oid AND at.attnum > 0 AND NOT at.attisdropped, aclexplode(at.attacl) a
        WHERE t2.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass)
       EXCEPT
       SELECT t, col, grantee, privilege_type, grantor, is_grantable FROM _acl338)) THEN
    bad := bad||'ACL de postgres/service_role o por columna distinta de la PRE; '; END IF;
  -- service_role conserva DELETE y MAINTAIN
  IF NOT (has_table_privilege('service_role', 'public.examenes', 'DELETE') AND has_table_privilege('service_role', 'public.ordenes_examen', 'DELETE')
          AND has_table_privilege('service_role', 'public.ordenes_examen', 'MAINTAIN')) THEN
    bad := bad||'service_role perdio DELETE o MAINTAIN; '; END IF;
  -- RPCs sin cambios
  FOR r IN SELECT * FROM (VALUES
      ('public.crear_orden_examen_medico(bigint,uuid,jsonb,text)',             '79a994588ab2b4458135272efb59b867'),
      ('public.crear_orden_examen_walkin(jsonb,text,text,text,text,text)',     '434d122370e340d895c8540a290379f3'),
      ('public.liberar_examen_al_paciente(integer)',                           'd1321b5fd0d994da4605b959249ba3b7'),
      ('public.liberar_orden_al_paciente(uuid)',                               '10a82b4176a65a58cb46ec5f2dca0447'),
      ('public.revertir_liberacion_examen(integer)',                           '8884c3445e9f29fa8850beab66a07775'),
      ('public.corregir_resultado_examen(integer,text,text,text)',             '9a2a4b5b33e6b6f0bc0ddd454906f848')) v(f, m) LOOP
    SELECT md5(p2.prosrc) INTO x FROM pg_proc p2 WHERE p2.oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x, 'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG338 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
