-- =====================================================================================================================
-- MIG 391 — authenticated deja de escribir public.citas por API directa, salvo la columna estado (UPDATE del médico sobre
-- sus citas), y actualizar_estado_cita pierde la rama del paciente.
-- Diseño: output/diseno-citas-clinicas-17nov.md (17-nov-2026), decisiones D-1, D-4, D-8 y D-10 aprobadas como recomienda.
--
-- Por qué: authenticated tenía INSERT/UPDATE/DELETE de TABLA sobre citas (relacl authenticated=arwd) y no hay guard de
-- columnas. Demostrado en BEGIN … ROLLBACK el 17-nov (recon, sección 2):
--   - el médico (citas_update_medico) reescribía paciente_id, pais_id, clinica_id, fecha, llegada_at, created_at y estado de
--     sus citas; la secretaria, el admin_clinica y el gerente (citas_update_admin_clinica) lo mismo en las citas de su clínica,
--     además de medico_id. Como private.medico_atiende_paciente sale de citas, reasignar paciente_id le daba al médico (o al
--     staff que se pone de medico_id: los 14 perfiles de clínica tienen fila en medicos) la ficha, el historial, el
--     expediente, los vitales, las recetas y los documentos de CUALQUIER paciente (medido: 0/0/0/0 -> 1/0/0/25);
--   - admin_pais y super_admin hacían INSERT/UPDATE/DELETE directos por la policy ALL "Admin ve citas de su pais";
--   - el paciente dueño se autoconfirmaba (o pasaba a en_curso) por actualizar_estado_cita, que lo aceptaba sin transición.
--
-- Censo de escritores directos de authenticated (17-nov, origin/main b4ea867): SOLO el médico, y solo la columna estado:
-- src/medico/hooks/useMedicoCitas.ts:107 (.update({ estado })) y src/pages/ConsultaPage.tsx:457 -> src/hooks/useCitas.ts:73
-- (updateCita(cita.id, { estado })). useCitas.deleteCita no tiene llamadores. Ninguna edge escribe citas. Todos los demás
-- caminos son RPC DEFINER: crear_cita, actualizar_estado_cita, asignar_medico_cita, marcar_llegada_cita,
-- cancelar_cita_paciente y notificar_cancelacion.
-- Efecto colateral conocido: /consulta/:citaId también está montada bajo PrivateLayout (sin gate de rol). Un no-médico que
-- llegue ahí por las rutas viejas y toque "en curso" recibe 42501 (antes lo hacía por citas_update_admin_clinica o por la
-- policy ALL). No es un flujo diseñado: la nota la escribe solo el médico (exp_insert_medico).
--
-- Qué hace (y nada más):
--   1. REVOKE INSERT, UPDATE, DELETE ON public.citas FROM authenticated, anon; GRANT UPDATE (estado) TO authenticated.
--      El SELECT de tabla no se toca. REVOKE USAGE ON SEQUENCE public.citas_id_seq FROM authenticated, anon (sin INSERT
--      directo, citas sale del conjunto necesario de la 345: P928/P929).
--   2. Policies: DROP citas_update_admin_clinica; "Admin ve citas de su pais" pasa de ALL a FOR SELECT con el MISMO USING
--      (DROP + CREATE con el mismo nombre, TO authenticated, PERMISSIVE; no tenía WITH CHECK). citas_update_medico se queda
--      (USING/CHECK medico_id = auth.uid()): es la que habilita el UPDATE (estado) del médico. Quedan 5 policies:
--      "Admin ve citas de su pais" [r], "Paciente ve sus citas" [r], citas_select_admin_clinica [r], citas_select_medico [r],
--      citas_update_medico [w].
--   3. CHECK citas_estado_valido: estado IN ('solicitada','agendada','confirmada','en_espera','en_curso','completada',
--      'cancelada','no_show'). Valores: src/webapp/types/webapp.types.ts:28 (los 8), src/types/index.ts:50 (7, sin
--      en_espera), la lista de actualizar_estado_cita (7) + 'en_espera' de marcar_llegada_cita. Los datos vivos cumplen
--      (la precondición lo exige), así que va directo, sin NOT VALID.
--      OJO, DEFAULT: el DEFAULT vivo de citas.estado es el TEXTO '''agendada''' (con las comillas adentro) y el de motivo y
--      notas es el texto 'NULL'. Con el CHECK, un INSERT que omite estado da 23514 en vez de guardar basura. Ningún escritor
--      vivo lo omite (el único INSERT es crear_cita, que siempre lo pasa); el fixture de P929 lo omitía y se ajustó. Corregir
--      los DEFAULT queda fuera de esta migración (decisión aparte).
--   4. actualizar_estado_cita(bigint, text): misma firma, mismo retorno (void), DEFINER y ACL (CREATE OR REPLACE la
--      conserva). Cambios: sin la rama del paciente dueño; SET search_path = '' (antes 'public'); ERRCODE en los 3 errores,
--      con el MISMO texto; p_estado NULL da CI002 (antes llegaba al UPDATE y daba 23502). Para médico, admin_clinica,
--      gerente y super_admin el comportamiento es el mismo. Errcodes nuevos (prefijo CI, citas):
--        CI001 = no autorizado para modificar esta cita (incluye al paciente dueño)
--        CI002 = estado de cita inválido
--        CI003 = cita no encontrada
--   Sin guard nuevo: el único UPDATE directo que queda es el de estado, sobre las citas del propio médico; las transiciones
--   por RPC y el cierre de ese UPDATE son el paso 2 (migs 393/394, después del IGSS).
--   MIG91 = guarda.
--
-- Estado ANTES, medido el 17-nov-2026 21:48:46 UTC (post-390):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... b7fa10f3493ad056a9ccba88db348511 415
--   ACL de funciones (solo privilegios), public/private .......................... 8fef2a52615f811185465e5ea088d16e 415
--   ACL de relaciones de public ................................................... c8fe9f329d5ddffcc83a289fd4a51875 2441
--   policies public/private/storage ............................................... 58ea95b27b7f611f3cc1133b086ed507 312
--   ACL de secuencias de public ................................................... d5dfaf71beb73aea67d0855089ff4131 233
--   policies de citas (polname|cmd|perm|roles|using|check) ........................ 5d9748ae48bd989252aacb18317e894d 6
--   md5 de filas de citas ......................................................... 5be7553f9e6bc59b7b28dda4958f6f56 41
-- Qué se mueve: funciones completas (solo actualizar_estado_cita; sin ella f77409daaefb397a694df37e705b526c 414 antes y
-- después); ACL de funciones NO; ACL de relaciones 2441 -> 2438 (citas: authenticated arwd -> r; sin citas
-- 5630afd89298ee43cfb84ac79702fa89 2421 antes y después); policies 312 -> 311 (sin citas e4da334a129ac3766bb4f4a599cc109b
-- 306 antes y después); ACL de secuencias 233 -> 232 (sin citas_id_seq c8611a41675650223e1b63d4f46ea33f 226 antes y después).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/391_citas_cierre_escritura.sql
-- Rollback: supabase/migrations/391_rollback.sql (cadena: 391_rollback -> 390_rollback -> 389_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 390 está aplicada
  IF EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.medicos'::regclass AND pl.polname = 'medicos_update_propio')
     OR (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.medicos'::regclass)
        IS DISTINCT FROM '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'la 390 no está aplicada; ';
  END IF;
  -- la 391 no está aplicada
  IF NOT EXISTS (SELECT 1 FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass AND pl.polname = 'citas_update_admin_clinica')
     OR EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.citas'::regclass AND c.conname = 'citas_estado_valido') THEN
    bad := bad||'la 391 ya está aplicada (o a medias); ';
  END IF;
  -- ACL de la tabla, por columna y de la secuencia, exactas
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de citas distinto del medido; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.citas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; medico_id=-; paciente_id=-; fecha=-; hora_inicio=-; hora_fin=-; motivo=-; estado=-; notas=-; created_at=-; pais_id=-; clinica_id=-; motivo_cancelacion=-; notificado_cancelacion=-; llegada_at=-' THEN
    bad := bad||'attacl de citas distinto del medido; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas_id_seq'::regclass)
     IS DISTINCT FROM '{postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}' THEN
    bad := bad||'relacl de citas_id_seq distinto del medido; ';
  END IF;
  IF (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.citas'::regclass) IS DISTINCT FROM true THEN
    bad := bad||'citas sin RLS; ';
  END IF;
  -- las 6 policies, con su definición
  v := (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
                   ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                   COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname))||' '||count(*)
          FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass);
  IF v IS DISTINCT FROM '5d9748ae48bd989252aacb18317e894d 6' THEN bad := bad||'policies de citas '||COALESCE(v, '-')||'; '; END IF;
  -- constraints y triggers
  IF (SELECT string_agg(c.conname||' '||c.contype::text||' '||pg_get_constraintdef(c.oid), '; ' ORDER BY c.conname) FROM pg_constraint c
       WHERE c.conrelid = 'public.citas'::regclass)
     IS DISTINCT FROM 'Citas_pkey p PRIMARY KEY (id); citas_clinica_id_fkey f FOREIGN KEY (clinica_id) REFERENCES clinicas(id) ON DELETE SET NULL; citas_pais_id_fkey f FOREIGN KEY (pais_id) REFERENCES configuracion_pais(id) ON DELETE SET NULL; fk_citas_medico f FOREIGN KEY (medico_id) REFERENCES medicos(id)' THEN
    bad := bad||'constraints de citas distintos de los medidos; ';
  END IF;
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text||' '||md5(p.prosrc), '; ' ORDER BY t.tgname) FROM pg_trigger t
       JOIN pg_proc p ON p.oid = t.tgfoid WHERE t.tgrelid = 'public.citas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_cerrar_nota_al_completar->private.cerrar_nota_al_completar() 9938ab3a0332d6fa35e4d51a1694e417; trg_exigir_nota_al_completar->private.exigir_nota_al_completar() 102adac580dfb08ed65158f065a98b3e; trg_historial_cita->insertar_historial_cita() 0bb179c09d5df913f05d835b390abe38; trg_otorgar_puntos_referido->otorgar_puntos_referido() 241407b80b7944b304fba8f489fffe0e; trg_reset_notif_cancel->private.reset_notificado_cancelacion() 7fd78826edbbe638973425a3e6ff6552' THEN
    bad := bad||'triggers de citas distintos de los medidos; ';
  END IF;
  IF (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'\n' ORDER BY t.tgname)) FROM pg_trigger t
       WHERE t.tgrelid = 'public.citas'::regclass AND NOT t.tgisinternal) IS DISTINCT FROM 'b570a505cf44b041eb0b847341777395' THEN
    bad := bad||'definición de los triggers de citas distinta de la medida; ';
  END IF;
  -- funciones que escriben citas o de las que dependen las policies (md5(prosrc) + DEFINER + config + ACL)
  FOR r IN SELECT * FROM (VALUES
      ('public.actualizar_estado_cita(bigint,text)', '3ff6976362482995bd17cb2322bcc082 true {search_path=public} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.marcar_llegada_cita(bigint)', 'eb3cd66eed4e1a5da74a25538196993e true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.crear_cita(bigint,uuid,uuid,date,time without time zone,time without time zone,text,text,text,uuid)', 'd6fbb644c4d486201eadd4d6c04be22f true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.cancelar_cita_paciente(integer,text)', '747e308bead83bfe3283d340921dd974 true {search_path=public} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.asignar_medico_cita(bigint,uuid)', '9c08b24e10b42f791356d2e5527c02a4 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('public.notificar_cancelacion(bigint)', '111e182bad57420ae224e88301a5fdfb true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
      ('private.medico_atiende_paciente(bigint)', 'ffbb220849b4c21896d103faf8d05abd true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}'),
      ('private.medico_atiende_paciente(text)', '908549b99c604bf96f76b3fa2b81e2c3 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}'),
      ('private.puede_gestionar_citas(uuid)', '88a1a0a2c7c902dfa3eea2bd49ae8b01 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}'),
      ('private.es_admin_clinica(uuid)', 'f7287955dcc4dd697e50c02154f3b420 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}'),
      ('private.tiene_rol(text[])', '2032eb10b9e9a90e5be58100607370e3 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres}')) AS t(firma, esperado)
  LOOP
    v := (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
            FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.esperado THEN bad := bad||r.firma||' distinta de la medida ('||COALESCE(v, 'no existe')||'); '; END IF;
  END LOOP;
  IF (SELECT pg_get_function_result(p.oid) FROM pg_proc p WHERE p.oid = 'public.actualizar_estado_cita(bigint,text)'::regprocedure) IS DISTINCT FROM 'void' THEN
    bad := bad||'actualizar_estado_cita no devuelve void; ';
  END IF;
  -- datos: ningún estado vivo queda fuera del CHECK
  v := (SELECT string_agg(DISTINCT c.estado, ',') FROM public.citas c
         WHERE c.estado IS NULL OR c.estado NOT IN ('solicitada','agendada','confirmada','en_espera','en_curso','completada','cancelada','no_show'));
  IF v IS NOT NULL THEN bad := bad||'estados fuera del CHECK: '||v||'; '; END IF;

  -- huellas post-390 (17-nov-2026 21:48:46 UTC)
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
    RAISE EXCEPTION 'MIG91: precondición: %', bad USING ERRCODE = 'MIG91';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) Privilegios: authenticated conserva SELECT de tabla y UPDATE solo de estado; la secuencia sin USAGE
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.citas FROM authenticated, anon;
GRANT UPDATE (estado) ON public.citas TO authenticated;
REVOKE USAGE ON SEQUENCE public.citas_id_seq FROM authenticated, anon;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) Policies: fuera la de UPDATE del staff; la de admins pasa de ALL a SELECT con el mismo USING
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY citas_update_admin_clinica ON public.citas;

DROP POLICY "Admin ve citas de su pais" ON public.citas;
CREATE POLICY "Admin ve citas de su pais" ON public.citas
  AS PERMISSIVE FOR SELECT TO authenticated
  USING ((public.get_auth_user_rol() = 'super_admin'::text)
         OR ((public.get_auth_user_rol() = 'admin_pais'::text) AND (pais_id = public.get_auth_user_pais_id())));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) CHECK de estado
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.citas ADD CONSTRAINT citas_estado_valido
  CHECK (estado IN ('solicitada','agendada','confirmada','en_espera','en_curso','completada','cancelada','no_show'));

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) actualizar_estado_cita sin la rama del paciente, con search_path = '' y errcodes CI001-CI003
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actualizar_estado_cita(p_cita_id bigint, p_estado text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $fn$
DECLARE v public.citas%ROWTYPE;
BEGIN
  SELECT * INTO v FROM public.citas WHERE id = p_cita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cita no encontrada' USING ERRCODE = 'CI003'; END IF;
  IF p_estado IS NULL OR p_estado NOT IN ('solicitada','agendada','confirmada','en_curso','completada','cancelada','no_show') THEN
    RAISE EXCEPTION 'Estado de cita inválido: %', p_estado USING ERRCODE = 'CI002';
  END IF;
  IF NOT COALESCE(
       v.medico_id = auth.uid()
    OR (v.clinica_id IS NOT NULL AND private.es_admin_clinica(v.clinica_id))
    OR private.tiene_rol(ARRAY['super_admin'])
  , false) THEN
    RAISE EXCEPTION 'No autorizado para modificar esta cita' USING ERRCODE = 'CI001';
  END IF;
  UPDATE public.citas SET estado = p_estado WHERE id = p_cita_id;
END;
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- ACL: tabla, columnas y secuencia exactas
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas'::regclass)
     IS DISTINCT FROM '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}' THEN
    bad := bad||'relacl de citas '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.citas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id=-; medico_id=-; paciente_id=-; fecha=-; hora_inicio=-; hora_fin=-; motivo=-; estado={authenticated=w/postgres}; notas=-; created_at=-; pais_id=-; clinica_id=-; motivo_cancelacion=-; notificado_cancelacion=-; llegada_at=-' THEN
    bad := bad||'attacl de citas '||COALESCE((SELECT string_agg(a.attname||'='||COALESCE(a.attacl::text, '-'), '; ' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.citas'::regclass AND a.attnum > 0 AND NOT a.attisdropped), '-')||'; ';
  END IF;
  IF has_table_privilege('authenticated', 'public.citas', 'INSERT') OR has_table_privilege('authenticated', 'public.citas', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.citas', 'DELETE') OR NOT has_table_privilege('authenticated', 'public.citas', 'SELECT') THEN
    bad := bad||'privilegios de tabla de authenticated sobre citas; ';
  END IF;
  v := (SELECT string_agg(a.attname::text, ',' ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid = 'public.citas'::regclass AND a.attnum > 0 AND NOT a.attisdropped
          AND (has_column_privilege('authenticated', 'public.citas', a.attname::text, 'UPDATE') OR has_column_privilege('authenticated', 'public.citas', a.attname::text, 'INSERT')));
  IF v IS DISTINCT FROM 'estado' THEN bad := bad||'columnas escribibles por authenticated: '||COALESCE(v, '-')||'; '; END IF;
  IF has_table_privilege('anon', 'public.citas', 'SELECT') OR has_table_privilege('anon', 'public.citas', 'INSERT')
     OR has_table_privilege('anon', 'public.citas', 'UPDATE') OR has_table_privilege('anon', 'public.citas', 'DELETE')
     OR has_column_privilege('anon', 'public.citas', 'estado', 'UPDATE') THEN
    bad := bad||'anon con privilegios sobre citas; ';
  END IF;
  IF (SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas_id_seq'::regclass)
     IS DISTINCT FROM '{postgres=rwU/postgres,service_role=rwU/postgres}' THEN
    bad := bad||'relacl de citas_id_seq '||COALESCE((SELECT c.relacl::text FROM pg_class c WHERE c.oid = 'public.citas_id_seq'::regclass), '-')||'; ';
  END IF;
  -- policies exactas: 5
  FOR r IN SELECT * FROM (VALUES
      ('Admin ve citas de su pais', 'r|true|{authenticated}|((get_auth_user_rol() = ''super_admin''::text) OR ((get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = get_auth_user_pais_id())))|-'),
      ('Paciente ve sus citas', E'r|true|{authenticated}|(paciente_id IN ( SELECT pacientes.id\n   FROM pacientes\n  WHERE (pacientes.auth_user_id = auth.uid())))|-'),
      ('citas_select_admin_clinica', 'r|true|{authenticated}|private.puede_gestionar_citas(clinica_id)|-'),
      ('citas_select_medico', 'r|true|{authenticated}|(medico_id = auth.uid())|-'),
      ('citas_update_medico', 'w|true|{authenticated}|(medico_id = auth.uid())|(medico_id = auth.uid())')) AS t(nombre, esperado)
  LOOP
    v := (SELECT pl.polcmd::text||'|'||pl.polpermissive::text||'|'||ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                 COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-')
            FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass AND pl.polname = r.nombre);
    IF v IS DISTINCT FROM r.esperado THEN bad := bad||'policy '||r.nombre||': '||COALESCE(v, 'no existe')||'; '; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_policy pl WHERE pl.polrelid = 'public.citas'::regclass) <> 5 THEN
    bad := bad||'citas no quedó con 5 policies; ';
  END IF;
  -- CHECK presente y validado
  IF (SELECT c.contype::text||' '||c.convalidated::text||' '||pg_get_constraintdef(c.oid) FROM pg_constraint c
       WHERE c.conrelid = 'public.citas'::regclass AND c.conname = 'citas_estado_valido')
     IS DISTINCT FROM 'c true CHECK ((estado = ANY (ARRAY[''solicitada''::text, ''agendada''::text, ''confirmada''::text, ''en_espera''::text, ''en_curso''::text, ''completada''::text, ''cancelada''::text, ''no_show''::text])))' THEN
    bad := bad||'CHECK citas_estado_valido: '||COALESCE((SELECT c.contype::text||' '||c.convalidated::text||' '||pg_get_constraintdef(c.oid) FROM pg_constraint c
       WHERE c.conrelid = 'public.citas'::regclass AND c.conname = 'citas_estado_valido'), 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_constraint c WHERE c.conrelid = 'public.citas'::regclass) <> 5 THEN
    bad := bad||'citas no quedó con 5 constraints; ';
  END IF;
  -- triggers intactos
  IF (SELECT string_agg(t.tgname||'->'||t.tgfoid::regprocedure::text||' '||md5(p.prosrc), '; ' ORDER BY t.tgname) FROM pg_trigger t
       JOIN pg_proc p ON p.oid = t.tgfoid WHERE t.tgrelid = 'public.citas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_cerrar_nota_al_completar->private.cerrar_nota_al_completar() 9938ab3a0332d6fa35e4d51a1694e417; trg_exigir_nota_al_completar->private.exigir_nota_al_completar() 102adac580dfb08ed65158f065a98b3e; trg_historial_cita->insertar_historial_cita() 0bb179c09d5df913f05d835b390abe38; trg_otorgar_puntos_referido->otorgar_puntos_referido() 241407b80b7944b304fba8f489fffe0e; trg_reset_notif_cancel->private.reset_notificado_cancelacion() 7fd78826edbbe638973425a3e6ff6552'
     OR (SELECT md5(string_agg(pg_get_triggerdef(t.oid), E'
' ORDER BY t.tgname)) FROM pg_trigger t
          WHERE t.tgrelid = 'public.citas'::regclass AND NOT t.tgisinternal) IS DISTINCT FROM 'b570a505cf44b041eb0b847341777395' THEN
    bad := bad||'triggers de citas cambiaron; ';
  END IF;
  -- actualizar_estado_cita: cuerpo nuevo, DEFINER, search_path = '', misma ACL, misma firma y retorno
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||pg_get_function_result(p.oid)||' '||pg_get_function_identity_arguments(p.oid)
        FROM pg_proc p WHERE p.oid = 'public.actualizar_estado_cita(bigint,text)'::regprocedure)
     IS DISTINCT FROM '2ba9ced73a3e54ec332e29046a4ef7e1 true {"search_path=\"\""} {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} void p_cita_id bigint, p_estado text' THEN
    bad := bad||'actualizar_estado_cita: '||COALESCE((SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||pg_get_function_result(p.oid)||' '||pg_get_function_identity_arguments(p.oid)
        FROM pg_proc p WHERE p.oid = 'public.actualizar_estado_cita(bigint,text)'::regprocedure), 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'actualizar_estado_cita' AND p.pronamespace = 'public'::regnamespace) <> 1 THEN
    bad := bad||'más de una sobrecarga de actualizar_estado_cita; ';
  END IF;

  -- huellas: solo se mueven citas, citas_id_seq y actualizar_estado_cita
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid <> 'public.actualizar_estado_cita(bigint,text)'::regprocedure);
  IF v IS DISTINCT FROM 'f77409daaefb397a694df37e705b526c 414' THEN bad := bad||'cambió otra función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '8fef2a52615f811185465e5ea088d16e 415' THEN bad := bad||'cambió la ACL de alguna función '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'citas') x);
  IF v IS DISTINCT FROM '5630afd89298ee43cfb84ac79702fa89 2421' THEN bad := bad||'cambió la ACL de otra relación '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) <> 2438 THEN
    bad := bad||'la ACL de relaciones no tiene 2438 tuplas; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S' AND cl.relname <> 'citas_id_seq') x);
  IF v IS DISTINCT FROM 'c8611a41675650223e1b63d4f46ea33f 226' THEN bad := bad||'cambió la ACL de otra secuencia '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') <> 232 THEN
    bad := bad||'la ACL de secuencias no tiene 232 tuplas; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.citas'::regclass) y);
  IF v IS DISTINCT FROM 'e4da334a129ac3766bb4f4a599cc109b 306' THEN bad := bad||'cambió una policy de otra tabla '||COALESCE(v, '-')||'; '; END IF;
  -- 0 DEFINER sin search_path (criterio de P931)
  IF EXISTS (SELECT 1 FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
               AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%')) THEN
    bad := bad||'hay funciones DEFINER sin search_path; ';
  END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG91: autochequeo: %', bad USING ERRCODE = 'MIG91';
  END IF;
END $autochequeo$;

COMMIT;
