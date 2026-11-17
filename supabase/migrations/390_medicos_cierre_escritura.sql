-- =====================================================================================================================
-- MIG 390 — D13: authenticated deja de escribir public.medicos (INSERT / UPDATE / DELETE).
-- Diseño: output/diseno-d13-medicos-17nov.md (17-nov-2026), las 8 decisiones aprobadas como recomienda.
--
-- Por qué: authenticated tenía INSERT/UPDATE/DELETE de TABLA sobre medicos (relacl authenticated=awd; solo el SELECT es por
-- columna desde la 375). Con la policy medicos_update_propio (id = auth.uid()) cualquiera de las 14 filas (médico,
-- asistente, secretaria, enfermería, admin_clinica, gerente) escribía las 16 columnas de su propia fila: se cambiaba de
-- país (y salía del alcance de su admin_pais y de los pacientes de su país), se reactivaba solo después de que un admin lo
-- desactivara, se asignaba cualquier clínica o reescribía created_at (demostrado en BEGIN … ROLLBACK el 17-nov). Las 2
-- policies ALL de admins daban además INSERT/UPDATE/DELETE directos a super_admin, admin_pais, admin_clinica y gerente.
--
-- Censo de escritores legítimos de authenticated sobre medicos (17-nov, origin/main 36e8b24, las 38 edges vivas, prosrc
-- vivo): NINGUNO. El front no escribe la tabla (único from('medicos'): lectura en AdminEzPayPage.tsx:68); la única edge
-- que la escribe es crear-staff-clinica, con service_role; las 5 funciones que la escriben son DEFINER (enrolar_medico,
-- guardar_foto_medico, registrar_clinica_desde_invitacion, registrar_medico_desde_invitacion,
-- resolver_propuesta_especialidad). Por eso NO hay GRANT UPDATE por columna (D1).
--
-- Qué hace (y nada más):
--   1. REVOKE INSERT, UPDATE, DELETE ON public.medicos FROM authenticated, anon (anon no tenía nada: no-op documental).
--      El SELECT por columna de la 375 NO se toca.
--   2. DROP POLICY medicos_update_propio (sin privilegio de UPDATE queda inerte; borrarla evita que un GRANT futuro reabra
--      el agujero) (D2).
--   3. "Admin ve medicos de su pais" y medicos_admin_clinica pasan de ALL a FOR SELECT con el MISMO USING (DROP + CREATE con
--      el mismo nombre, roles {authenticated}, PERMISSIVE) (D2). Además del cmd cambia una sola cosa: medicos_admin_clinica
--      tenía WITH CHECK explícito (igual al USING) y una policy SELECT no admite WITH CHECK; ese CHECK solo regía escrituras,
--      que con el REVOKE ya no existen. "Admin ve medicos de su pais" no tenía WITH CHECK.
--   Sin guard nuevo (D3): solo escriben funciones DEFINER (postgres), service_role y los fixtures del harness (postgres); el
--   trigger de lab_enrolador_* queda como está. Sin errcodes nuevos (MIG90 = guarda).
--
-- Huellas medidas el 17-nov-2026 21:10:53 UTC (estado post-389):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ........ b7fa10f3493ad056a9ccba88db348511 415
--   ACL de funciones (solo privilegios), public/private ............................. 8fef2a52615f811185465e5ea088d16e 415
--   ACL de relaciones de public ...................................................... 3cf6dfbb1762182068245ac7c3e816f8 2444
--   policies public/private/storage .................................................. 4b9da3e2955e1156feca9c8585c37fab 313
-- Qué se mueve: SOLO medicos. ACL de relaciones 2444 -> 2441 (las 3 tuplas a/w/d de authenticated); sin medicos =
-- 4dc4aa6105a3ec55c413ffdb0630de6f 2425 antes y después. Policies 313 -> 312 (1 DROP; 2 cambian de cmd); sin las de medicos
-- = bf1bfba9adf6f04c20939687ed68cbc6 308 antes y después. Funciones completas y ACL de funciones: sin cambio.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/390_medicos_cierre_escritura.sql
-- Rollback: supabase/migrations/390_rollback.sql (cadena: 390_rollback -> 389_rollback -> 388_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 390 no está aplicada
  IF NOT EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polname = 'medicos_update_propio') THEN
    bad := bad||'medicos_update_propio no existe (390 aplicada); ';
  END IF;
  -- ACL de la tabla y por columna, exactas
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=awd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de medicos distinto del medido; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id={authenticated=r/postgres}; clinica_id={authenticated=r/postgres}; nombre_completo={authenticated=r/postgres}; especialidad={authenticated=r/postgres}; telefono={authenticated=r/postgres}; email={authenticated=r/postgres}; cedula_profesional={authenticated=r/postgres}; horario_atencion={authenticated=r/postgres}; activo={authenticated=r/postgres}; created_at={authenticated=r/postgres}; updated_at={authenticated=r/postgres}; pais_id={authenticated=r/postgres}; foto_url={authenticated=r/postgres}; especialidad_id={authenticated=r/postgres}; lab_enrolador_id=-; lab_enrolador_fecha=-' THEN
    bad := bad||'attacl de medicos distinto del medido; ';
  END IF;
  -- las 5 policies, con su definición
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass);
  IF v IS DISTINCT FROM 'b6ae15146d9eb9afb43d15e6c94ef727 5' THEN bad := bad||'policies de medicos '||COALESCE(v, '-')||'; '; END IF;
  -- trigger y funciones de las que depende o que escriben medicos (md5(prosrc) + DEFINER + config + ACL)
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text, '; ') FROM pg_trigger t
       WHERE t.tgrelid = 'public.medicos'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trigger_medicos_lab_enrolador_inmutable->trg_medicos_lab_enrolador_inmutable()' THEN
    bad := bad||'triggers de medicos distintos de los medidos; ';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.trg_medicos_lab_enrolador_inmutable()', '2af30509d27efef4ed649c5785883381 false {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.enrolar_medico(uuid)', '58e441f3a68a5f80645f9b8f0452ffca true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.guardar_foto_medico(text)', '674bdb1e55ec23ede97b12b9d983d246 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)', 'ed19aae358ba091ef9e82ed18451615b true {"search_path=\"\""} {postgres=X/postgres,service_role=X/postgres}'),
      ('public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text)', '72889dea4724bc61f4b21ec3a3da158e true {"search_path=\"\""} {postgres=X/postgres,service_role=X/postgres}'),
      ('public.resolver_propuesta_especialidad(uuid,boolean)', '631526917880f984b8d7df5c108ece75 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.get_auth_user_rol()', '51df907aba35bf44abd671a3f23b7234 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.get_auth_user_pais_id()', '2a9bfcd0913e5879081e927d78a22b28 true {search_path=public} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.tiene_rol(text[])', '2032eb10b9e9a90e5be58100607370e3 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}'),
      ('private.clinicas_del_usuario()', 'a7e165e7525086b582b92e2c4592050d true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}')) AS t(firma, esperado)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.esperado THEN bad := bad||r.firma||' distinta de la medida ('||COALESCE(v, 'no existe')||'); '; END IF;
  END LOOP;

  -- huellas post-389 (17-nov-2026 21:10:53 UTC); la 389 aplicada está dentro de funciones completas (guard 8e7102b6)
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
  IF v IS DISTINCT FROM '3cf6dfbb1762182068245ac7c3e816f8 2444' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '4b9da3e2955e1156feca9c8585c37fab 313' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG90: precondición: %', bad USING ERRCODE = 'MIG90';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Sin escritura directa de authenticated (SELECT por columna intacto)
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.medicos FROM authenticated, anon;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Policies: fuera la de UPDATE propio; las 2 de admins pasan de ALL a SELECT con el mismo USING
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY medicos_update_propio ON public.medicos;

DROP POLICY "Admin ve medicos de su pais" ON public.medicos;
CREATE POLICY "Admin ve medicos de su pais" ON public.medicos
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text)
         OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

DROP POLICY medicos_admin_clinica ON public.medicos;
CREATE POLICY medicos_admin_clinica ON public.medicos
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.tiene_rol(ARRAY['admin_clinica'::text, 'gerente'::text])
         AND (clinica_id IN (SELECT private.clinicas_del_usuario() AS clinicas_del_usuario)));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- ACL: authenticated sin privilegios de tabla; columnas iguales
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de medicos '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id={authenticated=r/postgres}; clinica_id={authenticated=r/postgres}; nombre_completo={authenticated=r/postgres}; especialidad={authenticated=r/postgres}; telefono={authenticated=r/postgres}; email={authenticated=r/postgres}; cedula_profesional={authenticated=r/postgres}; horario_atencion={authenticated=r/postgres}; activo={authenticated=r/postgres}; created_at={authenticated=r/postgres}; updated_at={authenticated=r/postgres}; pais_id={authenticated=r/postgres}; foto_url={authenticated=r/postgres}; especialidad_id={authenticated=r/postgres}; lab_enrolador_id=-; lab_enrolador_fecha=-' THEN
    bad := bad||'attacl de medicos cambió; ';
  END IF;
  IF has_table_privilege('authenticated', 'public.medicos', 'INSERT') OR has_table_privilege('authenticated', 'public.medicos', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.medicos', 'DELETE') THEN
    bad := bad||'authenticated todavía escribe medicos a nivel tabla; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.medicos'::regclass AND a.attnum > 0 AND NOT a.attisdropped
               AND (has_column_privilege('authenticated', 'public.medicos', a.attname::text, 'UPDATE')
                    OR has_column_privilege('authenticated', 'public.medicos', a.attname::text, 'INSERT'))) THEN
    bad := bad||'authenticated todavía escribe alguna columna de medicos; ';
  END IF;
  IF has_table_privilege('anon', 'public.medicos', 'SELECT') OR has_table_privilege('anon', 'public.medicos', 'INSERT')
     OR has_table_privilege('anon', 'public.medicos', 'UPDATE') OR has_table_privilege('anon', 'public.medicos', 'DELETE') THEN
    bad := bad||'anon con privilegios sobre medicos; ';
  END IF;
  -- policies exactas: 4, todas SELECT, el USING de las 2 de admins igual al de antes
  FOR r IN SELECT * FROM (VALUES
      ('Admin ve medicos de su pais', '((get_auth_user_rol() = ''super_admin''::text) OR ((get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = get_auth_user_pais_id())))'),
      ('Medico ve su perfil', '(id = auth.uid())'),
      ('medicos_admin_clinica', '(private.tiene_rol(ARRAY[''admin_clinica''::text, ''gerente''::text]) AND (clinica_id IN ( SELECT private.clinicas_del_usuario() AS clinicas_del_usuario)))')) AS t(nombre, usando)
  LOOP
    v := (SELECT pl.polcmd::text||'|'||pl.polpermissive::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                 COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-')
            FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polname = r.nombre);
    IF v IS DISTINCT FROM 'r|true|{authenticated}|'||r.usando||'|-' THEN bad := bad||'policy '||r.nombre||': '||COALESCE(v, 'no existe')||'; '; END IF;
  END LOOP;
  IF (SELECT pl.polcmd::text FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polname = 'Paciente ve medicos de su pais') IS DISTINCT FROM 'r' THEN
    bad := bad||'policy Paciente ve medicos de su pais cambió; ';
  END IF;
  IF (SELECT count(*) FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass) <> 4
     OR EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polcmd <> 'r') THEN
    bad := bad||'medicos no quedó con 4 policies, todas SELECT; ';
  END IF;
  -- trigger intacto
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text||' '||md5(p.prosrc), '; ') FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
       WHERE t.tgrelid = 'public.medicos'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trigger_medicos_lab_enrolador_inmutable->trg_medicos_lab_enrolador_inmutable() 2af30509d27efef4ed649c5785883381' THEN
    bad := bad||'trigger de medicos cambió; ';
  END IF;

  -- huellas: funciones sin cambio; relaciones y policies se mueven SOLO por medicos
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'b7fa10f3493ad056a9ccba88db348511 415' THEN bad := bad||'cambió alguna función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'cambió la ACL de alguna función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'medicos') x);
  IF v IS DISTINCT FROM '4dc4aa6105a3ec55c413ffdb0630de6f 2425' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) <> 2441 THEN
    bad := bad||'la ACL de relaciones no tiene 2441 tuplas; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.medicos'::regclass) y);
  IF v IS DISTINCT FROM 'bf1bfba9adf6f04c20939687ed68cbc6 308' THEN bad := bad||'cambió una policy de otra tabla '||COALESCE(v, '-')||'; '; END IF;
  -- 0 DEFINER sin search_path (criterio de P931)
  IF EXISTS (SELECT 1 FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
               AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%')) THEN
    bad := bad||'hay funciones DEFINER sin search_path; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG90: autochequeo: %', bad USING ERRCODE = 'MIG90';
  END IF;
END $autochequeo$;

COMMIT;
