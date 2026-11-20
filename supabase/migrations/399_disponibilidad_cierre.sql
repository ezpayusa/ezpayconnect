-- =====================================================================================================================
-- MIG 399 — disponibilidad_medico: solo un médico activo tiene agenda, nadie la modifica por UPDATE y el país lo pone el
-- servidor. Un solo paso; el front de la 399 es aparte (el gerente sale de la ruta de Horarios Médicos).
-- Diseño: output/diseno-disp-fact-notas-20nov.md, sección 4.2, decisiones D-7, D-8 (a), D-9 (b, DESPUÉS del IGSS: no va
-- acá) y D-10 aprobadas.
--
-- Por qué (medido el 20-nov, ver el diseño, sección 2.1): cualquier perfil publicaba una agenda propia que los pacientes
-- veían (una secretaria, D4); el médico y el admin_clinica reescribían pais_id, clinica_id, activo y contexto por UPDATE, y
-- el admin_clinica le pasaba una franja de un médico a otro médico de la clínica (D2a); el médico apuntaba una franja a una
-- clínica de la que no es miembro (D1a/D1d).
--
-- Censo de escritores (re-confirmado el 20-nov sobre origin/main b9463e9):
--   src/hooks/useDisponibilidadMedico.ts:55 (crearSlot; MedicoDisponibilidadPage /medico/disponibilidad y
--     DisponibilidadVisitasPage /disponibilidad-visitas) INSERT de medico_id (= user.id), dia_semana, hora_inicio, hora_fin,
--     duracion_slot, contexto, clinica_id (el selector de useClinicas.ts:46-48 = clínicas con doctor_id = user, o NULL) y
--     activo; useDisponibilidadMedico.ts:80 DELETE por id;
--   src/clinica/pages/ClinicaHorariosMedicosPage.tsx:64 (admin_clinica) INSERT de medico_id (médico de la clínica),
--     dia_semana, hora_inicio, hora_fin, duracion_slot, contexto y activo (sin clinica_id); :82 DELETE por id.
--   Nadie hace UPDATE ni upsert; nadie manda pais_id. Ninguna edge ni función escribe la tabla (la única función que la
--   nombra es proximo_turno_disponible, DEFINER y solo lectura). La tabla no tiene secuencia (id uuid): el INSERT puede ir
--   por columna sin tocar el conjunto necesario de P928.
--
-- Qué hace (y nada más):
--   1. Privilegios de authenticated: REVOKE INSERT, UPDATE de tabla; GRANT INSERT (medico_id, dia_semana, hora_inicio,
--      hora_fin, duracion_slot, contexto, clinica_id, activo) = exactamente las columnas del censo, SIN pais_id. SELECT y
--      DELETE sin cambio (acotar el DELETE del admin_clinica a su clínica es el paso 2 de D-9, después del IGSS).
--      anon: nada, como antes.
--   2. Policies: las 2 ALL se parten en SELECT + INSERT + DELETE con las mismas expresiones (sin UPDATE, que ya no tiene
--      privilegio); el INSERT lleva WITH CHECK explícito. Las 3 SELECT restantes no se tocan. Quedan 9.
--   3. private.disponibilidad_medico_pais(p_medico_id, p_clinica_id) — DEFINER, STABLE, SET search_path = '', EXECUTE solo
--      postgres y authenticated (private no está expuesto por la API: solo lo llama el guard). Lee el perfil del médico y
--      las clínicas del médico, que el que escribe (p. ej. el admin_clinica) no necesariamente ve por RLS:
--        DM001 = la agenda no es de un médico activo (perfiles.rol = 'medico' AND activo IS TRUE del medico_id; mismo error
--                si el perfil no existe);
--        DM002 = clinica_id no es NULL y no es una clínica del médico: private.clinicas_de(medico_id) = membresía en
--                medico_clinicas + clínicas con doctor_id = el médico (diseño 4.2.4: NULL permitido; la rama doctor_id la
--                necesita el selector del front, que lista por clinicas.doctor_id: hay 2 clínicas cuyo doctor no está en
--                medico_clinicas, medido el 20-nov);
--      y devuelve perfiles.pais_id del médico.
--   4. Guard private.disponibilidad_medico_guard() — trigger BEFORE INSERT, INVOKER, SET search_path = '', EXECUTE solo
--      postgres. Exentos por current_user los roles de servicio (service_role, postgres, supabase_admin,
--      supabase_auth_admin), como el guard de la 398: un guard DEFINER corre siempre como su dueño y esa exención no
--      serviría. Para el resto: NEW.pais_id := private.disponibilidad_medico_pais(NEW.medico_id, NEW.clinica_id) (ignora lo
--      que mande el cliente, que además no tiene el privilegio de la columna).
--   Sin backfill: las 18 filas vivas quedan como están (pais_id sin lectores; clinica_id NULL en las 18).
--   MIG99 = guarda de la migración.
--
-- Estado ANTES, medido el 20-nov-2026 19:38:49 UTC (post-398):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... ba00350e8ff79624e3e612b6272431ae 421
--   ACL de funciones (solo privilegios), public/private .......................... 709076959d684e3def1a793ea7956984 421
--   ACL de relaciones de public ................................................... b95ff92fa952c65cfcc50233099a8362 2445
--     (sin disponibilidad_medico .................................................. c156332334980e794ddf46d24b7dde24 2425)
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... 1af94c4bbdbe3a2f2ca7920a62432b5a 306
--     (sin las de disponibilidad_medico ........................................... 848d46bf693a314f1599df864cba1a84 301)
--   disponibilidad_medico: relacl {postgres=arwdDxtm/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres},
--   sin attacl, sin triggers, RLS sin FORCE, 5 policies (md5 del listado ed98dda92e5bf94706ad470ee90b1967), 18 filas (md5
--   6e83056446399f9ee1ce708c1cdda2d4).
-- md5(prosrc): private.disponibilidad_medico_pais 0c623026703eae1c8a6380fb3cec9bcf, private.disponibilidad_medico_guard a8b697e85dc0e3d40d80360ade2900ed (cuerpos
-- con 0 CR). Huellas post-399: ver el dry-run (en el PR). Rollback: supabase/migrations/399_rollback.sql (va antes que
-- 398_rollback).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/399_disponibilidad_cierre.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 398 está aplicada; la 399 no
  IF to_regprocedure('private.facturas_guard()') IS NULL
     OR NOT has_column_privilege('authenticated', 'public.facturas', 'estado', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.facturas', 'UPDATE') THEN
    bad := bad||'la 398 no está aplicada; ';
  END IF;
  IF to_regprocedure('private.disponibilidad_medico_guard()') IS NOT NULL
     OR to_regprocedure('private.disponibilidad_medico_pais(uuid,uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.disponibilidad_medico'::regclass AND NOT t.tgisinternal) THEN
    bad := bad||'disponibilidad_medico ya tiene guard o triggers (¿la 399 ya se aplicó?); ';
  END IF;
  -- privilegios exactos (relacl ordenado), sin attacl, RLS activa
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.disponibilidad_medico'::regclass)
     IS DISTINCT FROM 'authenticated=arwd/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.disponibilidad_medico'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     OR (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.disponibilidad_medico'::regclass) IS NOT TRUE THEN
    bad := bad||'privilegios o RLS de disponibilidad_medico distintos de los medidos; ';
  END IF;
  -- columnas exactas
  IF (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.disponibilidad_medico'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id:uuid,medico_id:uuid,dia_semana:integer,hora_inicio:time without time zone,hora_fin:time without time zone,duracion_slot:integer,clinica_id:uuid,activo:boolean,created_at:timestamp with time zone,updated_at:timestamp with time zone,pais_id:uuid,contexto:text' THEN
    bad := bad||'columnas de disponibilidad_medico distintas de las medidas; ';
  END IF;
  -- las 5 policies medidas
  IF (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                            COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C"))
        FROM pg_policy pl WHERE pl.polrelid = 'public.disponibilidad_medico'::regclass)
     IS DISTINCT FROM 'ed98dda92e5bf94706ad470ee90b1967' THEN
    bad := bad||'policies de disponibilidad_medico distintas de las medidas; ';
  END IF;
  -- helpers que usan el guard y las policies
  FOR r IN SELECT * FROM (VALUES
      ('private.clinicas_de(uuid)',              '58d51369488e98934b59d6c58f9e02f2'),
      ('public.admin_clinica_de_medico(uuid)',   'd7d90bd2fab4574611a88b8e6ae6c187')) AS t(firma, md)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)) IS DISTINCT FROM r.md THEN
      bad := bad||r.firma||' distinta de la medida; ';
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated', 'public.admin_clinica_de_medico(uuid)', 'EXECUTE') THEN
    bad := bad||'authenticated sin EXECUTE en admin_clinica_de_medico; ';
  END IF;
  -- errcodes DM libres
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND p.prosrc ~ '''DM[0-9]{3}''') THEN
    bad := bad||'el prefijo DM ya está en uso; ';
  END IF;

  -- huellas post-398 (20-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'ba00350e8ff79624e3e612b6272431ae 421' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '709076959d684e3def1a793ea7956984 421' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'b95ff92fa952c65cfcc50233099a8362 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '1af94c4bbdbe3a2f2ca7920a62432b5a 306' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG99: precondición: %', bad USING ERRCODE = 'MIG99';
  END IF;

  PERFORM set_config('mig399.filas', (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.disponibilidad_medico t), true);
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) PRIVILEGIOS: sin UPDATE; INSERT solo de las 8 columnas del censo (sin pais_id)
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE INSERT, UPDATE ON TABLE public.disponibilidad_medico FROM authenticated;
GRANT INSERT (medico_id, dia_semana, hora_inicio, hora_fin, duracion_slot, contexto, clinica_id, activo)
  ON TABLE public.disponibilidad_medico TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) POLICIES: las 2 ALL se parten en SELECT + INSERT + DELETE, con las mismas expresiones
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY "Médico gestiona su disponibilidad" ON public.disponibilidad_medico;
DROP POLICY "Admin clinica gestiona disponibilidad de sus medicos" ON public.disponibilidad_medico;
CREATE POLICY "Médico ve su disponibilidad" ON public.disponibilidad_medico
  FOR SELECT TO authenticated USING (medico_id = auth.uid());
CREATE POLICY "Médico crea su disponibilidad" ON public.disponibilidad_medico
  FOR INSERT TO authenticated WITH CHECK (medico_id = auth.uid());
CREATE POLICY "Médico borra su disponibilidad" ON public.disponibilidad_medico
  FOR DELETE TO authenticated USING (medico_id = auth.uid());
CREATE POLICY "Admin clinica ve disponibilidad de sus medicos" ON public.disponibilidad_medico
  FOR SELECT TO authenticated USING (public.admin_clinica_de_medico(medico_id));
CREATE POLICY "Admin clinica crea disponibilidad de sus medicos" ON public.disponibilidad_medico
  FOR INSERT TO authenticated WITH CHECK (public.admin_clinica_de_medico(medico_id));
CREATE POLICY "Admin clinica borra disponibilidad de sus medicos" ON public.disponibilidad_medico
  FOR DELETE TO authenticated USING (public.admin_clinica_de_medico(medico_id));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) VALIDACIÓN (DEFINER) Y GUARD (INVOKER)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION private.disponibilidad_medico_pais(p_medico_id uuid, p_clinica_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE v_pais uuid; v_medico boolean;
BEGIN
  SELECT p.pais_id, (p.rol = 'medico' AND p.activo IS TRUE) INTO v_pais, v_medico
    FROM public.perfiles p WHERE p.id = p_medico_id;
  IF v_medico IS NOT TRUE THEN
    RAISE EXCEPTION 'La agenda solo puede ser de un médico activo' USING ERRCODE = 'DM001';
  END IF;
  IF p_clinica_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM private.clinicas_de(p_medico_id) AS c(id) WHERE c.id = p_clinica_id) THEN
    RAISE EXCEPTION 'La clínica no es una de las clínicas del médico' USING ERRCODE = 'DM002';
  END IF;
  RETURN v_pais;
END
$fn$;

REVOKE ALL ON FUNCTION private.disponibilidad_medico_pais(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.disponibilidad_medico_pais(uuid, uuid) TO authenticated;

CREATE FUNCTION private.disponibilidad_medico_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF current_user IN ('service_role', 'postgres', 'supabase_admin', 'supabase_auth_admin') THEN
    RETURN NEW;
  END IF;
  NEW.pais_id := private.disponibilidad_medico_pais(NEW.medico_id, NEW.clinica_id);
  RETURN NEW;
END
$fn$;

REVOKE ALL ON FUNCTION private.disponibilidad_medico_guard() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_disponibilidad_medico_guard
  BEFORE INSERT ON public.disponibilidad_medico
  FOR EACH ROW EXECUTE FUNCTION private.disponibilidad_medico_guard();

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- privilegios: tabla SELECT + DELETE; INSERT solo de las 8 columnas; sin UPDATE; anon nada
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.disponibilidad_medico'::regclass)
     IS DISTINCT FROM 'authenticated=rd/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres' THEN
    bad := bad||'relacl de disponibilidad_medico = '||COALESCE((SELECT relacl::text FROM pg_class WHERE oid = 'public.disponibilidad_medico'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||a.attacl::text, ',' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.disponibilidad_medico'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     IS DISTINCT FROM 'medico_id={authenticated=a/postgres},dia_semana={authenticated=a/postgres},hora_inicio={authenticated=a/postgres},'
                    ||'hora_fin={authenticated=a/postgres},duracion_slot={authenticated=a/postgres},clinica_id={authenticated=a/postgres},'
                    ||'activo={authenticated=a/postgres},contexto={authenticated=a/postgres}' THEN
    bad := bad||'attacl de disponibilidad_medico fuera de lo esperado; ';
  END IF;
  v := (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
         WHERE a.attrelid = 'public.disponibilidad_medico'::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND (has_column_privilege('authenticated', 'public.disponibilidad_medico', a.attname, 'INSERT')
                  <> (a.attname IN ('medico_id', 'dia_semana', 'hora_inicio', 'hora_fin', 'duracion_slot', 'contexto', 'clinica_id', 'activo'))
                OR has_column_privilege('authenticated', 'public.disponibilidad_medico', a.attname, 'UPDATE')));
  IF v IS NOT NULL THEN bad := bad||'INSERT/UPDATE de authenticated fuera de lo esperado en: '||v||'; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.disponibilidad_medico', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.disponibilidad_medico', 'DELETE')
     OR has_table_privilege('authenticated', 'public.disponibilidad_medico', 'INSERT,UPDATE,TRUNCATE,TRIGGER,MAINTAIN')
     OR has_any_column_privilege('anon', 'public.disponibilidad_medico', 'SELECT,INSERT,UPDATE,REFERENCES')
     OR has_table_privilege('anon', 'public.disponibilidad_medico', 'DELETE') THEN
    bad := bad||'privilegios de tabla de authenticated o anon fuera de lo esperado; ';
  END IF;

  -- funciones nuevas: cuerpo, DEFINER/INVOKER, search_path vacío, ACL; una sobrecarga de cada una; el trigger exacto
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname IN ('disponibilidad_medico_pais', 'disponibilidad_medico_guard')) <> 2 THEN
    bad := bad||'sobrecargas de las funciones nuevas; ';
  END IF;
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||p.provolatile::text||' '||COALESCE(p.proconfig::text, '-')||' '||
             (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM unnest(p.proacl) x)
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.disponibilidad_medico_pais(uuid,uuid)'))
     IS DISTINCT FROM '0c623026703eae1c8a6380fb3cec9bcf true s {"search_path=\"\""} authenticated=X/postgres,postgres=X/postgres' THEN
    bad := bad||'private.disponibilidad_medico_pais fuera de lo esperado; ';
  END IF;
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.disponibilidad_medico_guard()'))
     IS DISTINCT FROM 'a8b697e85dc0e3d40d80360ade2900ed false {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'private.disponibilidad_medico_guard fuera de lo esperado; ';
  END IF;
  IF (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgfoid::regprocedure::text||' '||t.tgtype::text, ',')
        FROM pg_trigger t WHERE t.tgrelid = 'public.disponibilidad_medico'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_disponibilidad_medico_guard O private.disponibilidad_medico_guard() 7' THEN
    bad := bad||'trigger de disponibilidad_medico fuera de lo esperado; ';
  END IF;

  -- policies: las 6 nuevas exactas y las 3 SELECT que no se tocan, iguales
  IF (SELECT string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                        COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C")
        FROM pg_policy pl WHERE pl.polrelid = 'public.disponibilidad_medico'::regclass
         AND pl.polname NOT IN ('Admin ezpay ve toda disponibilidad', 'Disponibilidad paciente para agendar', 'Visitador ve disponibilidad con plan'))
     IS DISTINCT FROM E'Admin clinica borra disponibilidad de sus medicos|d|{authenticated}|admin_clinica_de_medico(medico_id)|-\n'
                    ||E'Admin clinica crea disponibilidad de sus medicos|a|{authenticated}|-|admin_clinica_de_medico(medico_id)\n'
                    ||E'Admin clinica ve disponibilidad de sus medicos|r|{authenticated}|admin_clinica_de_medico(medico_id)|-\n'
                    ||E'Médico borra su disponibilidad|d|{authenticated}|(medico_id = auth.uid())|-\n'
                    ||E'Médico crea su disponibilidad|a|{authenticated}|-|(medico_id = auth.uid())\n'
                    ||'Médico ve su disponibilidad|r|{authenticated}|(medico_id = auth.uid())|-' THEN
    bad := bad||'las 6 policies nuevas de disponibilidad_medico fuera de lo esperado; ';
  END IF;
  IF (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                            COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C"))
        FROM pg_policy pl WHERE pl.polrelid = 'public.disponibilidad_medico'::regclass
         AND pl.polname IN ('Admin ezpay ve toda disponibilidad', 'Disponibilidad paciente para agendar', 'Visitador ve disponibilidad con plan'))
     IS DISTINCT FROM '5bf64c66a8033073e7dbf35dbd2305d3'
     OR (SELECT count(*) FROM pg_policy pl WHERE pl.polrelid = 'public.disponibilidad_medico'::regclass) <> 9 THEN
    bad := bad||'las 3 policies SELECT que no se tocan cambiaron, o no quedaron 9; ';
  END IF;

  -- datos intactos
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.disponibilidad_medico t)
     IS DISTINCT FROM current_setting('mig399.filas', true) THEN
    bad := bad||'cambiaron filas de disponibilidad_medico; ';
  END IF;

  -- huellas: lo que no es disponibilidad_medico ni las 2 funciones nuevas, igual a la entrada; secuencias igual; conteos nuevos
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname NOT IN ('disponibilidad_medico_pais', 'disponibilidad_medico_guard'));
  IF v IS DISTINCT FROM 'ba00350e8ff79624e3e612b6272431ae 421' THEN bad := bad||'huella de funciones completas sin las 2 nuevas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname NOT IN ('disponibilidad_medico_pais', 'disponibilidad_medico_guard')) y);
  IF v IS DISTINCT FROM '709076959d684e3def1a793ea7956984 421' THEN bad := bad||'huella de ACL de funciones sin las 2 nuevas '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 423 THEN
    bad := bad||'no quedaron 423 funciones en public/private; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'disponibilidad_medico') x);
  IF v IS DISTINCT FROM 'c156332334980e794ddf46d24b7dde24 2425' THEN bad := bad||'huella de ACL de relaciones sin disponibilidad_medico '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) <> 2443 THEN
    bad := bad||'la ACL de relaciones de public no quedó en 2443 entradas; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.disponibilidad_medico'::regclass) y);
  IF v IS DISTINCT FROM '848d46bf693a314f1599df864cba1a84 301' THEN bad := bad||'huella de policies sin disponibilidad_medico '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) <> 310 THEN
    bad := bad||'no quedaron 310 policies; ';
  END IF;

  -- P800 (j)/(k) y P931
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR (a.grantee = 'anon'::regrole AND f.oid <> 'public.catalogo_planes_visitador_publico()'::regprocedure)));
  IF v IS NOT NULL THEN bad := bad||'EXECUTE para PUBLIC/anon: '||v||'; '; END IF;
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
           AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%'));
  IF v IS NOT NULL THEN bad := bad||'DEFINER sin search_path: '||v||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG99: autochequeo: %', bad USING ERRCODE = 'MIG99';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
