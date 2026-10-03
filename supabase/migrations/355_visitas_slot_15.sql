-- ############################################################################################
-- 355 - franjas de visitador a 15 min, con CHECK en la base
-- ############################################################################################
-- Recon del 3-oct-2026 sobre b9bfa5e (tmp/355/a1, a3, huellas_antes; solo lectura contra prod):
--   * La regla de 15 min de la franja de visitador existe desde d50563d/e4e1cac (11-jun) solo en el front, al
--     guardar (useDisponibilidadMedico.ts:52, MedicoDisponibilidadPage.tsx:34, ClinicaHorariosMedicosPage.tsx:69).
--     En la base, disponibilidad_medico.duracion_slot es integer default 30 y contexto default 'visitador' con
--     CHECK visitador|paciente; nada exige 15. Las policies "Medico gestiona su disponibilidad" y "Admin clinica
--     gestiona disponibilidad de sus medicos" (ALL) permiten escribir cualquier duracion por la API.
--   * A1: 5 franjas visitador con duracion_slot 30, todas del Dr. Juan Perez (5f638655...), creadas el 2026-06-04
--     21:43:26 UTC (antes de la regla), lunes a viernes 09:00-12:00.
--   * Ningun RPC, trigger, edge, script ni seed escribe la tabla (la unica funcion que la nombra,
--     proximo_turno_disponible, solo lee). El fixture vg1 del harness sembraba franjas visitador de 30: pasa a 15.
--   * A3: el front marca un bloque ocupado por igualdad exacta de hora_inicio Y hora_fin (VisitadorAgendarPage),
--     y la base solo por (medico_id, fecha_visita, hora_inicio) (ux_visita_medico_slot): no hay chequeo de
--     solapamiento de rangos. Hoy hay 0 visitas futuras no canceladas (de ninguna duracion).
-- Decisiones (Oscar, 3-oct-2026):
--   (a) toda franja visitador con duracion_slot <> 15 pasa a 15; (b) CHECK: contexto = 'visitador' => 15.
--   Las visitas ya agendadas no se tocan.
-- Cambios:
--   A UPDATE de las 5 franjas de A1 (contexto visitador, duracion_slot <> 15) a 15; el conteo debe ser 5.
--   B CHECK disponibilidad_visitador_slot_15 (contexto <> 'visitador' OR duracion_slot = 15), validado.
-- Sin objetos nuevos ni cambios de privilegios, policies o funciones. Sin errcodes nuevos: la violacion es 23514.
-- OJO: los defaults de la tabla (duracion_slot 30, contexto 'visitador') siguen igual; un INSERT que omita los dos
-- ahora da 23514. Todos los caminos del front mandan los dos.
-- Probes: P951 (visitador 30 -> 23514 por nombre), P952 (visitador 15 OK), P953 (paciente 30 OK), P954 (censo).
-- Rollback: 355_rollback.sql (DROP de la constraint y vuelve a 30 exactamente los 5 ids de A1).
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- precondiciones (estado PRE)
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.disponibilidad_medico'::regclass AND conname = 'disponibilidad_visitador_slot_15') THEN
    bad := bad||'la constraint disponibilidad_visitador_slot_15 ya existe; ';
  END IF;
  -- el conjunto exacto de A1
  v := (SELECT string_agg(d.id::text||':'||d.duracion_slot, ',' ORDER BY d.id) FROM public.disponibilidad_medico d WHERE d.contexto = 'visitador' AND d.duracion_slot <> 15);
  IF v IS DISTINCT FROM '0eec71e2-2312-4f37-8f8f-ac98cd84e19c:30,10c9929e-db4a-4fc1-8f63-f4f88c1ffe6f:30,1127bb97-21ac-478a-b795-8d567bd76daa:30,347d4181-66e5-4663-9550-e6be50702dbb:30,d55802a9-2dac-4758-8408-456c00813dea:30' THEN bad := bad||'franjas visitador <> 15 '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(conname||'|'||pg_get_constraintdef(oid)||'|'||convalidated::text, ',' ORDER BY conname)) FROM pg_constraint WHERE conrelid = 'public.disponibilidad_medico'::regclass);
  IF v IS DISTINCT FROM '28367fef24bd76a473d115b095304ffc' THEN bad := bad||'constraints de disponibilidad_medico '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(d.id::text||':'||d.duracion_slot, ',' ORDER BY d.id), ''))||' '||count(*) FROM public.disponibilidad_medico d WHERE d.contexto = 'visitador');
  IF v IS DISTINCT FROM 'ed27d7c207e7a7816e1ce42357856aba 8' THEN bad := bad||'filas visitador (id, duracion_slot) '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(concat_ws('|', d.id, d.medico_id, d.dia_semana, d.hora_inicio, d.hora_fin, d.clinica_id, d.activo, d.created_at, d.updated_at, d.pais_id, d.contexto), E'\n' ORDER BY d.id), ''))||' '||count(*)
          FROM public.disponibilidad_medico d WHERE d.contexto = 'visitador');
  IF v IS DISTINCT FROM '2d37d28ce79ca8eb234862b2b89d7a16 8' THEN bad := bad||'filas visitador sin duracion '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(d::text, E'\n' ORDER BY d.id), ''))||' '||count(*) FROM public.disponibilidad_medico d WHERE d.contexto = 'paciente');
  IF v IS DISTINCT FROM '01f6e60e339ae572a2e89c336f3089b5 9' THEN bad := bad||'filas paciente '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
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
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG355 PRECONDICION FALLA:%', bad; END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------- A: franjas visitador a 15
DO $a$
DECLARE n int;
BEGIN
  UPDATE public.disponibilidad_medico SET duracion_slot = 15 WHERE contexto = 'visitador' AND duracion_slot <> 15;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 5 THEN RAISE EXCEPTION 'MIG355: el UPDATE afecto % filas, se esperaban 5 (A1)', n; END IF;
END $a$;

-- ---------------------------------------------------------------------------- B: CHECK (validado)
ALTER TABLE public.disponibilidad_medico
  ADD CONSTRAINT disponibilidad_visitador_slot_15 CHECK (contexto <> 'visitador' OR duracion_slot = 15);

-- ---------------------------------------------------------------------------- autochequeo (estado POST)
DO $autochequeo$
DECLARE bad text := ''; v text; n int;
BEGIN
  n := (SELECT count(*) FROM public.disponibilidad_medico WHERE contexto = 'visitador' AND duracion_slot <> 15);
  IF n <> 0 THEN bad := bad||n||' franjas visitador <> 15; '; END IF;
  v := (SELECT pg_get_constraintdef(oid)||'|'||convalidated::text FROM pg_constraint WHERE conrelid = 'public.disponibilidad_medico'::regclass AND conname = 'disponibilidad_visitador_slot_15');
  IF v IS DISTINCT FROM 'CHECK (((contexto <> ''visitador''::text) OR (duracion_slot = 15)))|true' THEN bad := bad||'constraint '||COALESCE(v, 'NO EXISTE')||'; '; END IF;
  v := (SELECT string_agg(d.id::text||':'||d.duracion_slot||':'||d.contexto, ',' ORDER BY d.id) FROM public.disponibilidad_medico d WHERE d.id IN ('0eec71e2-2312-4f37-8f8f-ac98cd84e19c', '10c9929e-db4a-4fc1-8f63-f4f88c1ffe6f', '1127bb97-21ac-478a-b795-8d567bd76daa', '347d4181-66e5-4663-9550-e6be50702dbb', 'd55802a9-2dac-4758-8408-456c00813dea'));
  IF v IS DISTINCT FROM '0eec71e2-2312-4f37-8f8f-ac98cd84e19c:15:visitador,10c9929e-db4a-4fc1-8f63-f4f88c1ffe6f:15:visitador,1127bb97-21ac-478a-b795-8d567bd76daa:15:visitador,347d4181-66e5-4663-9550-e6be50702dbb:15:visitador,d55802a9-2dac-4758-8408-456c00813dea:15:visitador' THEN bad := bad||'los 5 de A1 '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(concat_ws('|', d.id, d.medico_id, d.dia_semana, d.hora_inicio, d.hora_fin, d.clinica_id, d.activo, d.created_at, d.updated_at, d.pais_id, d.contexto), E'\n' ORDER BY d.id), ''))||' '||count(*)
          FROM public.disponibilidad_medico d WHERE d.contexto = 'visitador');
  IF v IS DISTINCT FROM '2d37d28ce79ca8eb234862b2b89d7a16 8' THEN bad := bad||'filas visitador sin duracion '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(d::text, E'\n' ORDER BY d.id), ''))||' '||count(*) FROM public.disponibilidad_medico d WHERE d.contexto = 'paciente');
  IF v IS DISTINCT FROM '01f6e60e339ae572a2e89c336f3089b5 9' THEN bad := bad||'filas paciente '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(d.id::text||':'||d.duracion_slot, ',' ORDER BY d.id), ''))||' '||count(*) FROM public.disponibilidad_medico d WHERE d.contexto = 'visitador');
  IF v IS DISTINCT FROM 'ad122fd78c39dd8ff9fa9fad0e4ebab0 8' THEN bad := bad||'filas visitador (id, duracion_slot) '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(conname||'|'||pg_get_constraintdef(oid)||'|'||convalidated::text, ',' ORDER BY conname)) FROM pg_constraint WHERE conrelid = 'public.disponibilidad_medico'::regclass);
  IF v IS DISTINCT FROM 'b5f7a2e2e350f7d44904dc7103166c99' THEN bad := bad||'constraints de disponibilidad_medico '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||c.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'b2a47be7d2fa41eb92e7c6b8c34d6d49 308' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
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
      SELECT p.oid AS o, p.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
       WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '2015113829d8f952628ea5d625475046 375' THEN bad := bad||'ACL de funciones public/private '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), '')) FROM (
      SELECT pg_get_userbyid(d.defaclrole)||'|'||COALESCE(d.defaclnamespace::regnamespace::text, '-')||'|'||d.defaclobjtype::text||'|'||d.defaclacl::text AS s FROM pg_default_acl d) y);
  IF v IS DISTINCT FROM '7143eca74695a2cefe3468982f6cc04e' THEN bad := bad||'pg_default_acl '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(schemaname||'.'||tablename, ',' ORDER BY 1))||' '||count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime');
  IF v IS DISTINCT FROM 'c236082c1c23535a462f1d305d925b7d 6' THEN bad := bad||'publicacion supabase_realtime '||COALESCE(v, '-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG355 AUTOCHEQUEO FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
