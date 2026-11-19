-- =====================================================================================================================
-- ROLLBACK DE LA MIG 391 — vuelve al estado post-390 EXACTO de public.citas: INSERT/UPDATE/DELETE de tabla para
-- authenticated (sin UPDATE por columna), USAGE de citas_id_seq para authenticated, la policy citas_update_admin_clinica,
-- "Admin ve citas de su pais" como ALL, sin el CHECK citas_estado_valido, y actualizar_estado_cita con su cuerpo vivo
-- anterior EXACTO (md5 3ff6976362482995bd17cb2322bcc082, con CRLF, SET search_path = public, con la rama del paciente).
-- Va ANTES que 390_rollback.
--
-- La guarda exige el estado post-391 exacto en citas y el resto sin cambio. El cuerpo viejo se arma con un literal E'…'
-- (sus fines de línea son CRLF en el prosrc vivo; el repo exige LF) y se verifica su md5 ANTES de ejecutar el CREATE.
-- Para que el relacl de citas_id_seq vuelva con el mismo ORDEN ({postgres, authenticated, service_role}) se saca y se
-- vuelve a dar ALL a service_role después de authenticated. En citas no hace falta: authenticated=r sigue en su lugar y
-- el GRANT lo amplía ahí mismo.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/391_rollback.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN: estado post-391
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de citas distinto del post-391; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.citas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; medico_id=-; paciente_id=-; fecha=-; hora_inicio=-; hora_fin=-; motivo=-; estado={authenticated=w/postgres}; notas=-; created_at=-; pais_id=-; clinica_id=-; motivo_cancelacion=-; notificado_cancelacion=-; llegada_at=-' THEN
    bad := bad||'attacl de citas distinto del post-391; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas_id_seq'::regclass)
     IS DISTINCT FROM '{postgres=rwU/postgres,service_role=rwU/postgres}' THEN
    bad := bad||'relacl de citas_id_seq distinto del post-391; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass AND pl.polname = 'citas_update_admin_clinica')
     OR (SELECT count(*) FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass) <> 5
     OR (SELECT pl.polcmd::text FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass AND pl.polname = 'Admin ve citas de su pais') IS DISTINCT FROM 'r' THEN
    bad := bad||'policies de citas distintas del post-391; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.citas'::regclass AND c.conname = 'citas_estado_valido') THEN
    bad := bad||'falta citas_estado_valido; ';
  END IF;
  IF (SELECT md5(p.prosrc)||' '||COALESCE(p.proconfig::text, '-') FROM pg_proc p WHERE p.oid = 'public.actualizar_estado_cita(bigint,text)'::regprocedure)
     IS DISTINCT FROM '2ba9ced73a3e54ec332e29046a4ef7e1 {"search_path=\"\""}' THEN
    bad := bad||'actualizar_estado_cita distinta de la de la 391; ';
  END IF;
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid <> 'public.actualizar_estado_cita(bigint,text)'::regprocedure);
  IF v IS DISTINCT FROM 'f77409daaefb397a694df37e705b526c 414' THEN bad := bad||'cambió otra función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'citas') x);
  IF v IS DISTINCT FROM '5630afd89298ee43cfb84ac79702fa89 2421' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S' AND cl.relname <> 'citas_id_seq') x);
  IF v IS DISTINCT FROM 'c8611a41675650223e1b63d4f46ea33f 226' THEN bad := bad||'cambió la ACL de otra secuencia '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.citas'::regclass) y);
  IF v IS DISTINCT FROM 'e4da334a129ac3766bb4f4a599cc109b 306' THEN bad := bad||'cambió una policy de otra tabla '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG91: rollback, precondición: %', bad USING ERRCODE = 'MIG91';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Privilegios de antes (el UPDATE por columna se saca primero; después vuelve la escritura de tabla)
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE UPDATE (estado) ON public.citas FROM authenticated;
GRANT INSERT, UPDATE, DELETE ON public.citas TO authenticated;
REVOKE ALL ON SEQUENCE public.citas_id_seq FROM service_role;
GRANT USAGE ON SEQUENCE public.citas_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.citas_id_seq TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Policies y CHECK de antes de la 391
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY "Admin ve citas de su pais" ON public.citas;
CREATE POLICY "Admin ve citas de su pais" ON public.citas
  AS PERMISSIVE FOR ALL TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text)
         OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

CREATE POLICY citas_update_admin_clinica ON public.citas
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (private.puede_gestionar_citas(clinica_id))
  WITH CHECK (private.puede_gestionar_citas(clinica_id));

ALTER TABLE public.citas DROP CONSTRAINT citas_estado_valido;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) actualizar_estado_cita con su cuerpo anterior EXACTO (CRLF), verificado por md5 antes de ejecutar
-- ---------------------------------------------------------------------------------------------------------------------
DO $restaura$
DECLARE cuerpo text;
BEGIN
  cuerpo := E'\r\n'
    || E'DECLARE v public.citas%ROWTYPE;\r\n'
    || E'BEGIN\r\n'
    || E'  SELECT * INTO v FROM public.citas WHERE id = p_cita_id;\r\n'
    || E'  IF NOT FOUND THEN RAISE EXCEPTION ''Cita no encontrada''; END IF;\r\n'
    || E'  -- citas.estado es TEXT: validar contra el conjunto permitido antes de escribir.\r\n'
    || E'  IF p_estado NOT IN (''solicitada'',''agendada'',''confirmada'',''en_curso'',''completada'',''cancelada'',''no_show'') THEN\r\n'
    || E'    RAISE EXCEPTION ''Estado de cita inválido: %'', p_estado;\r\n'
    || E'  END IF;\r\n'
    || E'  IF NOT COALESCE(\r\n'
    || E'       v.medico_id = auth.uid()\r\n'
    || E'    OR EXISTS (SELECT 1 FROM public.pacientes p WHERE p.id = v.paciente_id AND p.auth_user_id = auth.uid())\r\n'
    || E'    OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))\r\n'
    || E'    OR private.tiene_rol(ARRAY[''super_admin''])\r\n'
    || E'  , false) THEN\r\n'
    || E'    RAISE EXCEPTION ''No autorizado para modificar esta cita'';\r\n'
    || E'  END IF;\r\n'
    || E'  UPDATE public.citas SET estado = p_estado WHERE id = p_cita_id;\r\n'
    || E'END;\r\n'
    || E'';
  IF md5(cuerpo) IS DISTINCT FROM '3ff6976362482995bd17cb2322bcc082' THEN
    RAISE EXCEPTION 'MIG91: rollback, el cuerpo armado no es el original (md5 %)', md5(cuerpo) USING ERRCODE = 'MIG91';
  END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public.actualizar_estado_cita(p_cita_id bigint, p_estado text) RETURNS void '
                 'LANGUAGE plpgsql SECURITY DEFINER SET search_path TO %L AS %L', 'public', cuerpo);
END $restaura$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) AUTOCHEQUEO: estado post-390 exacto
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de citas '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.citas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; medico_id=-; paciente_id=-; fecha=-; hora_inicio=-; hora_fin=-; motivo=-; estado=-; notas=-; created_at=-; pais_id=-; clinica_id=-; motivo_cancelacion=-; notificado_cancelacion=-; llegada_at=-' THEN
    bad := bad||'attacl de citas '||COALESCE((SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.citas'::regclass AND a.attnum > 0 AND NOT a.attisdropped), '-')||'; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas_id_seq'::regclass)
     IS DISTINCT FROM '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}' THEN
    bad := bad||'relacl de citas_id_seq '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas_id_seq'::regclass), '-')||'; ';
  END IF;
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass);
  IF v IS DISTINCT FROM '5d9748ae48bd989252aacb18317e894d 6' THEN bad := bad||'policies de citas '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT string_agg(c.conname||' '||c.contype::text||' '||pg_get_constraintdef(c.oid), '; ' ORDER BY c.conname) FROM pg_constraint c
       WHERE c.conrelid = 'public.citas'::regclass)
     IS DISTINCT FROM 'Citas_pkey p PRIMARY KEY (id); citas_clinica_id_fkey f FOREIGN KEY (clinica_id) REFERENCES clinicas(id) ON DELETE SET NULL; citas_pais_id_fkey f FOREIGN KEY (pais_id) REFERENCES configuracion_pais(id) ON DELETE SET NULL; fk_citas_medico f FOREIGN KEY (medico_id) REFERENCES medicos(id)' THEN
    bad := bad||'constraints de citas distintos de los de antes; ';
  END IF;
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
        FROM pg_proc p WHERE p.oid = 'public.actualizar_estado_cita(bigint,text)'::regprocedure)
     IS DISTINCT FROM '3ff6976362482995bd17cb2322bcc082 true {search_path=public} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    bad := bad||'actualizar_estado_cita no volvió a la de antes; ';
  END IF;

  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'b7fa10f3493ad056a9ccba88db348511 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'c8fe9f329d5ddffcc83a289fd4a51875 2441' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'd5dfaf71beb73aea67d0855089ff4131 233' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '58ea95b27b7f611f3cc1133b086ed507 312' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG91: rollback, autochequeo: %', bad USING ERRCODE = 'MIG91';
  END IF;
END $autochequeo$;

COMMIT;
