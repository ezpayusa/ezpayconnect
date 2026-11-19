-- =====================================================================================================================
-- MIG 392 — authenticated deja de escribir public.clinicas por API directa (sin INSERT, UPDATE ni DELETE).
-- Diseño: output/diseno-citas-clinicas-17nov.md (17-nov-2026), sección 4.2 y decisiones D-2, D-8 y D-10 aprobadas como
-- recomienda. D-3 (quién activa, desactiva o cambia de país una clínica; sin DELETE) queda para después: hoy nadie lo hace.
--
-- Por qué: authenticated tenía INSERT/UPDATE/DELETE de TABLA sobre clinicas (relacl authenticated=arwd), sin guard de
-- columnas salvo el de tema (PT001). Demostrado en BEGIN … ROLLBACK el 17-nov (recon, sección 2.2):
--   - cualquier autenticado (paciente o proveedor incluidos) creaba clínicas de cualquier país a su nombre
--     ("Doctores pueden crear clinicas": WITH CHECK doctor_id = auth.uid(), sin mirar rol ni perfiles.activo);
--   - el doctor_id (incluida una cuenta inactiva: San Rafael y Sion son de e56879c0, rol cliente, activo=false) cambiaba
--     de país su clínica, la desactivaba o la BORRABA EN CASCADA (medicos.clinica_id, medico_clinicas,
--     laboratorio_clinicas e invitaciones_laboratorio son ON DELETE CASCADE: medido, medicos 14 -> 13);
--   - admin_pais y super_admin escribían directo por la policy ALL "Admin ve clinicas de su pais".
--
-- Censo de escritores (19-nov, main b70887a), re-medido para esta migración:
--   front: src/clinica/pages/ClinicaConfiguracionPage.tsx:35 -> RPC actualizar_clinica (nombre, direccion, telefono,
--   email); src/pages/admin-ezpay/SolicitudesPersonalizacionPage.tsx:78 -> RPC aprobar_personalizacion (tema);
--   src/hooks/useClinicas.ts:78 -> RPC crear_clinica_con_dueno + UPDATE directo L90, y L120/L152/L167/L201/L209
--   (actualizarClinica, eliminarClinica, setClinicaActiva): SIN llamadores (los 2 usos de useClinicas(),
--   MedicoDisponibilidadPage y DisponibilidadVisitasPage, solo leen `clinicas`). Edges: registrar-clinica-invitacion ->
--   RPC registrar_clinica_desde_invitacion (service_role); crear-invitacion-medico solo lee clinicas.pais_id.
--   Base: las únicas funciones de public/private que escriben clinicas son DEFINER (actualizar_clinica,
--   aprobar_personalizacion, private.crear_clinica_con_dueno_interno, que usan crear_clinica_con_dueno y
--   registrar_clinica_desde_invitacion); ninguna con SQL dinámico sobre clinicas.
--   => ningún flujo vivo escribe clinicas por API directa.
--
-- Qué hace (y nada más):
--   1. REVOKE INSERT, UPDATE, DELETE ON public.clinicas FROM authenticated, anon. El SELECT de tabla no se toca. Sin
--      GRANT por columna: ninguna columna necesita UPDATE directo (los datos de contacto ya van por actualizar_clinica).
--      clinicas.id es uuid con gen_random_uuid(): no hay secuencia.
--   2. Policies: DROP "Doctores pueden crear clinicas" [a], "Doctores pueden actualizar sus clinicas" [w] y "Doctores
--      pueden eliminar sus clinicas" [d]; "Admin ve clinicas de su pais" pasa de ALL a FOR SELECT con el MISMO USING (DROP
--      + CREATE con el mismo nombre, TO authenticated, PERMISSIVE; no tenía WITH CHECK). Quedan 4 policies, todas SELECT:
--      "Admin ve clinicas de su pais", "Doctores pueden ver sus clinicas", "Paciente ve clinicas de su pais" y
--      clinicas_select_miembro.
--   3. El trigger trigger_guard_tema_clinicas (private.trg_guard_tema_columns, INVOKER, PT001) se queda: lo usa
--      aprobar_personalizacion con el GUC app.personalizacion_rpc.
--   No toca funciones: endurecer actualizar_clinica (search_path = '' y ERRCODE CL001 al "No autorizado") queda en el
--   backlog (opcional en el diseño); CL001 sigue libre. MIG92 = guarda.
--
-- Estado ANTES, medido el 19-nov-2026 (post-391, verificado tras el apply de la 391):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... ba4eb8a509c74d2ff82d61193ec6c201 415
--   ACL de funciones (solo privilegios), public/private .......................... 8fef2a52615f811185465e5ea088d16e 415
--   ACL de relaciones de public ................................................... 09f3ee5bed234919c828c33092abced8 2438
--   ACL de secuencias de public ................................................... fdaa79023984e271fe2922f357fb7a98 232
--   policies public/private/storage ............................................... cc5aec00f4bf6e8c88925aa44cf64b4e 311
--   policies de clinicas (polname|cmd|perm|roles|using|check) ..................... 66d88cbf341b3d8607949fd024e865ff 7
-- Qué se mueve: ACL de relaciones 2438 -> 2435 (clinicas: authenticated arwd -> r; sin clinicas
-- b3db143c292843ccbc3f1279badea2b1 2418 antes y después); policies 311 -> 308 (sin clinicas
-- 0598c3a5369c356715e17f45ef26fc14 304 antes y después). Funciones, ACL de funciones y secuencias NO se mueven.
-- Huellas post-392 (medidas en el dry-run del 19-nov, BEGIN … ROLLBACK, txid 417485):
--   funciones completas ba4eb8a509c74d2ff82d61193ec6c201 415 (sin cambio); ACL de funciones 8fef2a52615f811185465e5ea088d16e 415
--   (sin cambio); ACL de relaciones de public e80ed9f7e17759b9196a8f5ce91996d5 2435; ACL de secuencias
--   fdaa79023984e271fe2922f357fb7a98 232 (sin cambio); policies 83a71d544e684f90ace0f0dc834230cc 308; policies de clinicas
--   c5c8342eb321cebc7b49c1930b934ec9 4.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/392_clinicas_cierre_escritura.sql
-- Rollback: supabase/migrations/392_rollback.sql (cadena: 392_rollback -> 391_rollback -> 390_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 391 está aplicada
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass AND pl.polname = 'citas_update_admin_clinica')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.citas'::regclass AND c.conname = 'citas_estado_valido')
     OR (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas'::regclass)
        IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'la 391 no está aplicada; ';
  END IF;
  -- la 392 no está aplicada
  IF NOT EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.clinicas'::regclass AND pl.polname = 'Doctores pueden crear clinicas')
     OR (SELECT pl.polcmd::text FROM pg_policy pl WHERE pl.polrelid = 'public.clinicas'::regclass AND pl.polname = 'Admin ve clinicas de su pais') IS DISTINCT FROM '*' THEN
    bad := bad||'la 392 ya está aplicada (o a medias); ';
  END IF;
  -- ACL de la tabla y por columna, exactas
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.clinicas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de clinicas distinto del medido; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.clinicas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; doctor_id=-; nombre=-; direccion=-; telefono=-; email=-; horarios=-; activa=-; created_at=-; updated_at=-; pais_id=-; logo_url=-; color_primario=-; color_secundario=-; color_fondo=-' THEN
    bad := bad||'attacl de clinicas distinto del medido; ';
  END IF;
  IF (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.clinicas'::regclass) IS DISTINCT FROM true THEN
    bad := bad||'clinicas sin RLS; ';
  END IF;
  -- las 7 policies, con su definición
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.clinicas'::regclass);
  IF v IS DISTINCT FROM '66d88cbf341b3d8607949fd024e865ff 7' THEN bad := bad||'policies de clinicas '||COALESCE(v, '-')||'; '; END IF;
  -- constraints y triggers
  IF (SELECT string_agg(c.conname||' '||c.contype::text||' '||pg_get_constraintdef(c.oid), '; ' ORDER BY c.conname) FROM pg_constraint c
       WHERE c.conrelid = 'public.clinicas'::regclass)
     IS DISTINCT FROM 'clinicas_pais_id_fkey f FOREIGN KEY (pais_id) REFERENCES configuracion_pais(id) ON DELETE SET NULL; clinicas_pkey p PRIMARY KEY (id)' THEN
    bad := bad||'constraints de clinicas distintos de los medidos; ';
  END IF;
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text||' '||md5(p.prosrc), '; ' ORDER BY t.tgname) FROM pg_trigger t
       JOIN pg_proc p ON p.oid = t.tgfoid WHERE t.tgrelid = 'public.clinicas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trigger_guard_tema_clinicas->private.trg_guard_tema_columns() c28b30d803b7edec11a8e21e02baa399' THEN
    bad := bad||'triggers de clinicas distintos de los medidos; ';
  END IF;
  IF (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'\n' ORDER BY t.tgname)) FROM pg_trigger t
       WHERE t.tgrelid = 'public.clinicas'::regclass AND NOT t.tgisinternal) IS DISTINCT FROM '3e752cb84d4cc09628dacdfbffd134ad' THEN
    bad := bad||'definición del trigger de clinicas distinta de la medida; ';
  END IF;
  -- funciones que escriben clinicas o de las que dependen sus policies (md5(prosrc) + DEFINER + config + ACL)
  FOR r IN SELECT * FROM (VALUES
      ('public.actualizar_clinica(uuid,text,text,text,text)', '2c339791c4fe1b0142157725146ab208 true {search_path=public} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.aprobar_personalizacion(uuid)', '1be49d9abf92a4da3a5c43f4e1f1aa3d true {search_path=public} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.crear_clinica_con_dueno(uuid,text,uuid,text,text,text)', '1815db2eba25796cf4cb363fa6bdfa1b true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.crear_clinica_con_dueno_interno(uuid,text,uuid,text,text,text)', 'bdd97d7989bdddf4ddfe4dce49da7fae true {"search_path=\"\""} {postgres=X/postgres}'),
      ('public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text)', 'ed19aae358ba091ef9e82ed18451615b true {"search_path=\"\""} {postgres=X/postgres,service_role=X/postgres}'),
      ('private.trg_guard_tema_columns()', 'c28b30d803b7edec11a8e21e02baa399 false {search_path=public} {postgres=X/postgres}'),
      ('private.clinicas_del_usuario()', 'a7e165e7525086b582b92e2c4592050d true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}'),
      ('public.get_auth_user_rol()', '51df907aba35bf44abd671a3f23b7234 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.get_auth_user_pais_id()', '2a9bfcd0913e5879081e927d78a22b28 true {search_path=public} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}')) AS t(firma, esperado)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.esperado THEN bad := bad||r.firma||' distinta de la medida ('||COALESCE(v, 'no existe')||'); '; END IF;
  END LOOP;

  -- huellas post-391 (19-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'ba4eb8a509c74d2ff82d61193ec6c201 415' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '09f3ee5bed234919c828c33092abced8 2438' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'fdaa79023984e271fe2922f357fb7a98 232' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'cc5aec00f4bf6e8c88925aa44cf64b4e 311' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG92: precondición: %', bad USING ERRCODE = 'MIG92';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Privilegios: authenticated conserva solo el SELECT de tabla
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.clinicas FROM authenticated, anon;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Policies: fuera las 3 de escritura del dueño; la de admins pasa de ALL a SELECT con el mismo USING
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY "Doctores pueden crear clinicas" ON public.clinicas;
DROP POLICY "Doctores pueden actualizar sus clinicas" ON public.clinicas;
DROP POLICY "Doctores pueden eliminar sus clinicas" ON public.clinicas;

DROP POLICY "Admin ve clinicas de su pais" ON public.clinicas;
CREATE POLICY "Admin ve clinicas de su pais" ON public.clinicas
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text)
         OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- ACL: tabla y columnas exactas
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.clinicas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de clinicas '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.clinicas'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.clinicas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; doctor_id=-; nombre=-; direccion=-; telefono=-; email=-; horarios=-; activa=-; created_at=-; updated_at=-; pais_id=-; logo_url=-; color_primario=-; color_secundario=-; color_fondo=-' THEN
    bad := bad||'attacl de clinicas cambió; ';
  END IF;
  IF has_table_privilege('authenticated', 'public.clinicas', 'INSERT') OR has_table_privilege('authenticated', 'public.clinicas', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.clinicas', 'DELETE') OR NOT has_table_privilege('authenticated', 'public.clinicas', 'SELECT') THEN
    bad := bad||'privilegios de tabla de authenticated sobre clinicas; ';
  END IF;
  v := (SELECT string_agg(a.attname::text, ',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid = 'public.clinicas'::regclass AND a.attnum > 0 AND NOT a.attisdropped
          AND (has_column_privilege('authenticated', 'public.clinicas', a.attname::text, 'UPDATE') OR has_column_privilege('authenticated', 'public.clinicas', a.attname::text, 'INSERT')));
  IF v IS NOT NULL THEN bad := bad||'columnas escribibles por authenticated: '||v||'; '; END IF;
  v := (SELECT string_agg(a.attname::text, ',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid = 'public.clinicas'::regclass AND a.attnum > 0 AND NOT a.attisdropped
          AND (has_column_privilege('anon', 'public.clinicas', a.attname::text, 'SELECT') OR has_column_privilege('anon', 'public.clinicas', a.attname::text, 'UPDATE')
               OR has_column_privilege('anon', 'public.clinicas', a.attname::text, 'INSERT')));
  IF v IS NOT NULL OR has_table_privilege('anon', 'public.clinicas', 'SELECT') OR has_table_privilege('anon', 'public.clinicas', 'INSERT')
     OR has_table_privilege('anon', 'public.clinicas', 'UPDATE') OR has_table_privilege('anon', 'public.clinicas', 'DELETE') THEN
    bad := bad||'anon con privilegios sobre clinicas; ';
  END IF;
  -- policies exactas: 4, todas SELECT
  FOR r IN SELECT * FROM (VALUES
      ('Admin ve clinicas de su pais', 'r|true|{authenticated}|((get_auth_user_rol() = ''super_admin''::text) OR ((get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = get_auth_user_pais_id())))|-'),
      ('Doctores pueden ver sus clinicas', 'r|true|{authenticated}|(doctor_id = auth.uid())|-'),
      ('Paciente ve clinicas de su pais', E'r|true|{authenticated}|((EXISTS ( SELECT 1\n   FROM pacientes pa\n  WHERE ((pa.auth_user_id = auth.uid()) AND (pa.pais_id = clinicas.pais_id)))) OR (EXISTS ( SELECT 1\n   FROM perfiles p\n  WHERE ((p.id = auth.uid()) AND (p.pais_id = clinicas.pais_id)))))|-'),
      ('clinicas_select_miembro', 'r|true|{authenticated}|(id IN ( SELECT private.clinicas_del_usuario() AS clinicas_del_usuario))|-')) AS t(nombre, esperado)
  LOOP
    v := (SELECT pl.polcmd::text||'|'||pl.polpermissive::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                 COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-')
            FROM pg_policy pl WHERE pl.polrelid = 'public.clinicas'::regclass AND pl.polname = r.nombre);
    IF v IS DISTINCT FROM r.esperado THEN bad := bad||'policy '||r.nombre||': '||COALESCE(v, 'no existe')||'; '; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_policy pl WHERE pl.polrelid = 'public.clinicas'::regclass) <> 4 THEN
    bad := bad||'clinicas no quedó con 4 policies; ';
  END IF;
  IF (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.clinicas'::regclass) IS DISTINCT FROM true THEN
    bad := bad||'clinicas sin RLS; ';
  END IF;
  -- constraints y trigger intactos
  IF (SELECT string_agg(c.conname||' '||c.contype::text||' '||pg_get_constraintdef(c.oid), '; ' ORDER BY c.conname) FROM pg_constraint c
       WHERE c.conrelid = 'public.clinicas'::regclass)
     IS DISTINCT FROM 'clinicas_pais_id_fkey f FOREIGN KEY (pais_id) REFERENCES configuracion_pais(id) ON DELETE SET NULL; clinicas_pkey p PRIMARY KEY (id)' THEN
    bad := bad||'constraints de clinicas cambiaron; ';
  END IF;
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text||' '||md5(p.prosrc), '; ' ORDER BY t.tgname) FROM pg_trigger t
       JOIN pg_proc p ON p.oid = t.tgfoid WHERE t.tgrelid = 'public.clinicas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trigger_guard_tema_clinicas->private.trg_guard_tema_columns() c28b30d803b7edec11a8e21e02baa399'
     OR (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'\n' ORDER BY t.tgname)) FROM pg_trigger t
          WHERE t.tgrelid = 'public.clinicas'::regclass AND NOT t.tgisinternal) IS DISTINCT FROM '3e752cb84d4cc09628dacdfbffd134ad' THEN
    bad := bad||'trigger de clinicas cambió; ';
  END IF;

  -- huellas: funciones, ACL de funciones y secuencias sin cambio; solo se mueven clinicas (ACL) y sus policies
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'ba4eb8a509c74d2ff82d61193ec6c201 415' THEN bad := bad||'cambió una función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'cambió la ACL de alguna función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'clinicas') x);
  IF v IS DISTINCT FROM 'b3db143c292843ccbc3f1279badea2b1 2418' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) <> 2435 THEN
    bad := bad||'la ACL de relaciones no tiene 2435 tuplas; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'fdaa79023984e271fe2922f357fb7a98 232' THEN bad := bad||'cambió la ACL de alguna secuencia '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.clinicas'::regclass) y);
  IF v IS DISTINCT FROM '0598c3a5369c356715e17f45ef26fc14 304' THEN bad := bad||'cambió una policy de otra tabla '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) <> 308 THEN
    bad := bad||'no quedaron 308 policies; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG92: autochequeo: %', bad USING ERRCODE = 'MIG92';
  END IF;
END $autochequeo$;

COMMIT;
