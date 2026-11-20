-- =====================================================================================================================
-- MIG 400 — expediente_notas: el país de la nota lo pone el servidor (sale del paciente) y authenticated solo puede hacer
-- UPDATE de las 9 columnas que manda el front. Sin front. El guard de la nota (private.expediente_notas_guardia) NO se toca.
-- Diseño: output/diseno-disp-fact-notas-20nov.md, sección 4.3, decisiones D-10 (derivar pais_id) y D-11 (a) (los vitales
-- viejos salen del UPDATE; en el INSERT quedan en el backlog).
--
-- Por qué (medido el 20-nov, diseño 2.3): pais_id era libre en el INSERT y en una nota abierta (y el cambio generaba una
-- revisión de tipo 'edicion'); los vitales viejos, nota y signos_vitales también se escribían en una nota abierta sin rangos.
-- Hoy nadie lee esas columnas, pero un dato del país escrito por el cliente no puede quedar abierto.
--
-- Censo de escritores (re-confirmado el 20-nov sobre origin/main b47bfb9):
--   src/hooks/useConsultas.ts:107 (crearOActualizarConsulta sin id, desde ConsultaPage.tsx:352) INSERT .select().single() y
--   src/hooks/useConsultas.ts:94 (con id) UPDATE .select(): las dos mandan el mismo payload {...data, medico_id: user.id},
--   donde data = {cita_id, paciente_id, ...soap} y soap = motivo_consulta, subjetivo, objetivo, analisis, plan, diagnostico
--   (ConsultaPage.tsx:65-72, SOAP_VACIO / soapDeNota). Total: cita_id, paciente_id, medico_id + los 6 SOAP = 9 columnas.
--   El UPDATE manda cita_id, paciente_id y medico_id sin cambiar: PostgREST arma SET col = valor y eso exige el privilegio
--   aunque el valor no cambie; que no cambien lo sigue garantizando NT007 del guard.
--   Funciones que escriben la tabla (prosrc vivo): public.corregir_nota_consulta (DEFINER, 6 SOAP + corregida_at, llave
--   'corregir:') y private.cerrar_nota_al_completar (DEFINER, cerrada_at, llave 'cerrar:'); las dos son de postgres, dueño de
--   la tabla, y no dependen de los privilegios de authenticated. Ninguna edge escribe (asistente-ia solo select('id')).
--   Nadie manda pais_id, los vitales viejos, imc, nota ni signos_vitales.
--
-- Qué hace (y nada más):
--   1. Privilegios de authenticated: REVOKE UPDATE de tabla (quita también cualquier UPDATE por columna) y GRANT UPDATE de
--      las 9 columnas del censo. INSERT y SELECT de tabla sin cambio (el INSERT se queda de TABLA: P928 calcula el conjunto
--      necesario de secuencias con el INSERT de tabla, y expediente_notas_id_seq está en ese conjunto); sin DELETE, como antes.
--      Quedan fuera del UPDATE: pais_id, nota, signos_vitales, los vitales viejos, imc, created_at, updated_at, updated_by,
--      cerrada_at y corregida_at. Los triggers que asignan NEW.col no necesitan privilegio, y las 2 funciones DEFINER corren
--      como postgres.
--   2. private.expediente_notas_fija_pais() — trigger BEFORE INSERT OR UPDATE, DEFINER, SET search_path = '', EXECUTE solo
--      postgres (la función de un trigger no necesita EXECUTE del rol que dispara: se chequea en CREATE TRIGGER, como el
--      guard). NEW.pais_id := pacientes.pais_id del paciente de la nota, ignorando lo que mande el cliente; si el paciente no
--      tiene país, la nota queda con pais_id NULL (no se frena una nota clínica por un dato administrativo; hoy 0 de 28
--      pacientes sin país; la columna no tiene lectores). Se fija SIEMPRE, también para service_role, postgres y las
--      funciones DEFINER: es un dato derivado. Es DEFINER porque con INVOKER la RLS de pacientes podría esconderle la fila al
--      que escribe y dejaría pais_id en NULL sin avisar; solo lee el país del paciente de la fila que ya se está escribiendo.
--      pacientes.pais_id y expediente_notas.pais_id tienen FK a la misma tabla (configuracion_pais), así que la copia no rompe
--      la FK.
--      Orden de disparo: los triggers BEFORE disparan por nombre; trg_expediente_notas_pais va DESPUÉS de
--      trg_calcular_imc_expediente y de trg_expediente_notas_guardia. El guard no ve el cambio de pais_id que pone este
--      trigger: no genera una revisión por él ni lo cuenta en el chequeo del cierre (C3, NT009), así que una nota vieja con
--      pais_id NULL se sigue cerrando al completar la cita (P1198). Un cambio de paciente ya lo frenó el guard (NT007) antes
--      de llegar acá. Al revés no sirve: antes del guard, el cierre de esas notas daría NT009.
--      Efecto conocido: si postgres o service_role mandan SET pais_id = <otro> en una nota abierta, el guard ve el cambio y
--      registra una revisión 'edicion' antes de que este trigger devuelva el país del paciente (revisión sin cambio visible).
--      authenticated no llega a ese caso (no tiene UPDATE de pais_id).
--   3. Sin backfill de las 5 notas vivas (pais_id NULL en las 5): 3 están cerradas y cualquier UPDATE sin llave da NT006 en el
--      guard, también para postgres (medido en el dry-run). Las 2 abiertas toman el país en su próxima escritura (la edición
--      del médico o el cierre al completar la cita), por este mismo trigger.
--   MIG00 = guarda de la migración (convención MIG + los dos últimos dígitos; MIG00 no estaba en uso).
--
-- Estado ANTES, medido el 20-nov-2026 20:09:18 UTC (post-399):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... c290831c4ccc8e33706d9097a5d97182 423
--   ACL de funciones (solo privilegios), public/private .......................... a14a1f17ee0fc72d9271147e4925297e 423
--   ACL de relaciones de public ................................................... 5fb4dc549e169a4129f72d9d92e3113b 2443
--     (sin expediente_notas ....................................................... b1d6c7e0439818b91d147dfd118e1e31 2424)
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... dabf9556bae56bcb910de70405314ad8 310
--   expediente_notas: relacl {postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}, sin
--   attacl, RLS sin FORCE, 6 policies (md5 del listado 291215175f82a9111ec8d9d4a7cafb3f), 2 triggers BEFORE INSERT/UPDATE
--   (trg_calcular_imc_expediente 1b9ad49a5cd1464c54d9a211e5763532, trg_expediente_notas_guardia
--   950c36d4959f5568e3a6fbf351713541), 5 filas (md5 8aefc703c3c4418315c3291a42718e10), 4 revisiones.
-- md5(prosrc) de private.expediente_notas_fija_pais: 95e689efe029bb47b6c9718f4e3c8d7b (cuerpo con 0 CR).
-- Huellas post-400, medidas en el dry-run del 20-nov-2026 (txid 464684, ROLLBACK):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... f1581e8802f3a06dc7d1737c6aad51dd 424
--     (sin private.expediente_notas_fija_pais = la de entrada .................... c290831c4ccc8e33706d9097a5d97182 423)
--   ACL de funciones (solo privilegios), public/private .......................... d026ae246b0262142684e187b7b8710f 424
--     (sin private.expediente_notas_fija_pais = la de entrada .................... a14a1f17ee0fc72d9271147e4925297e 423)
--   ACL de relaciones de public ................................................... d17d651fdbe1b592147983a9b133dbcf 2442
--     (sin expediente_notas = la de entrada ....................................... b1d6c7e0439818b91d147dfd118e1e31 2424)
--   ACL de secuencias de public (sin cambio) ...................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage (sin cambio) .................................. dabf9556bae56bcb910de70405314ad8 310
-- Rollback: supabase/migrations/400_rollback.sql (va antes que 399_rollback).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/400_expediente_notas_pais.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 399 está aplicada; la 400 no
  IF to_regprocedure('private.disponibilidad_medico_guard()') IS NULL
     OR has_table_privilege('authenticated', 'public.disponibilidad_medico', 'UPDATE') THEN
    bad := bad||'la 399 no está aplicada; ';
  END IF;
  IF to_regprocedure('private.expediente_notas_fija_pais()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND t.tgname = 'trg_expediente_notas_pais') THEN
    bad := bad||'expediente_notas ya tiene el trigger de país (¿la 400 ya se aplicó?); ';
  END IF;
  -- privilegios exactos (relacl ordenado), sin attacl, RLS activa
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.expediente_notas'::regclass)
     IS DISTINCT FROM 'authenticated=arw/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     OR (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.expediente_notas'::regclass) IS NOT TRUE THEN
    bad := bad||'privilegios o RLS de expediente_notas distintos de los medidos; ';
  END IF;
  -- columnas exactas
  IF (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id:integer,cita_id:integer,paciente_id:integer,medico_id:uuid,nota:text,diagnostico:text,signos_vitales:jsonb,'
                    ||'created_at:timestamp with time zone,motivo_consulta:text,subjetivo:text,objetivo:text,analisis:text,plan:text,'
                    ||'presion_arterial:text,frecuencia_cardiaca:integer,frecuencia_respiratoria:integer,temperatura:numeric(4,2),'
                    ||'peso_kg:numeric(5,2),talla_cm:numeric(5,2),imc:numeric(4,2),saturacion_o2:integer,glucosa:integer,pais_id:uuid,'
                    ||'updated_at:timestamp with time zone,updated_by:uuid,cerrada_at:timestamp with time zone,corregida_at:timestamp with time zone' THEN
    bad := bad||'columnas de expediente_notas distintas de las medidas; ';
  END IF;
  -- el país se copia del paciente: las dos columnas apuntan a configuracion_pais
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.expediente_notas'::regclass AND c.contype = 'f'
                   AND c.confrelid = 'public.configuracion_pais'::regclass
                   AND c.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attname = 'pais_id')])
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.pacientes'::regclass AND c.contype = 'f'
                   AND c.confrelid = 'public.configuracion_pais'::regclass
                   AND c.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = 'public.pacientes'::regclass AND a.attname = 'pais_id')]) THEN
    bad := bad||'pais_id de expediente_notas o de pacientes sin FK a configuracion_pais; ';
  END IF;
  -- las 6 policies medidas
  IF (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                            COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C"))
        FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass)
     IS DISTINCT FROM '291215175f82a9111ec8d9d4a7cafb3f' THEN
    bad := bad||'policies de expediente_notas distintas de las medidas; ';
  END IF;
  -- los 2 triggers medidos (por oid de la función, no por texto)
  IF (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgtype::text, ',' ORDER BY t.tgname COLLATE "C")
        FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_calcular_imc_expediente O 23,trg_expediente_notas_guardia O 23'
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND t.tgname = 'trg_calcular_imc_expediente'
                      AND t.tgfoid = 'public.calcular_imc_signos_vitales()'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND t.tgname = 'trg_expediente_notas_guardia'
                      AND t.tgfoid = 'private.expediente_notas_guardia()'::regprocedure) THEN
    bad := bad||'triggers de expediente_notas distintos de los medidos; ';
  END IF;
  -- el guard (que no se toca), el IMC y los 2 escritores DEFINER, con su md5 y su dueño
  FOR r IN SELECT * FROM (VALUES
      ('private.expediente_notas_guardia()',                                          '950c36d4959f5568e3a6fbf351713541', true),
      ('public.calcular_imc_signos_vitales()',                                        '1b9ad49a5cd1464c54d9a211e5763532', false),
      ('public.corregir_nota_consulta(integer,text,text,text,text,text,text,text)',  '1d39e9e839feebc889e392701beef913', true),
      ('private.cerrar_nota_al_completar()',                                          '9938ab3a0332d6fa35e4d51a1694e417', true)) AS t(firma, md, secdef)
  LOOP
    IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma))
       IS DISTINCT FROM r.md||' '||r.secdef::text||' postgres' THEN
      bad := bad||r.firma||' distinta de la medida; ';
    END IF;
  END LOOP;

  -- huellas post-399 (20-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM 'c290831c4ccc8e33706d9097a5d97182 423' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'a14a1f17ee0fc72d9271147e4925297e 423' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '5fb4dc549e169a4129f72d9d92e3113b 2443' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
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
  IF v IS DISTINCT FROM 'dabf9556bae56bcb910de70405314ad8 310' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG00: precondición: %', bad USING ERRCODE = 'MIG00';
  END IF;

  PERFORM set_config('mig400.filas', (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.expediente_notas t), true);
  PERFORM set_config('mig400.revisiones', (SELECT count(*)||' '||COALESCE(md5(string_agg(rv::text, E'\n' ORDER BY rv::text)), '-') FROM public.expediente_notas_revisiones rv), true);
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) PRIVILEGIOS: UPDATE solo de las 9 columnas del front; INSERT y SELECT de tabla sin cambio
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE UPDATE ON TABLE public.expediente_notas FROM authenticated;
GRANT UPDATE (cita_id, paciente_id, medico_id, motivo_consulta, subjetivo, objetivo, analisis, plan, diagnostico)
  ON TABLE public.expediente_notas TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) TRIGGER DE PAÍS (DEFINER), separado del guard
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION private.expediente_notas_fija_pais()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  NEW.pais_id := (SELECT p.pais_id FROM public.pacientes p WHERE p.id = NEW.paciente_id);
  RETURN NEW;
END
$fn$;

REVOKE ALL ON FUNCTION private.expediente_notas_fija_pais() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_expediente_notas_pais
  BEFORE INSERT OR UPDATE ON public.expediente_notas
  FOR EACH ROW EXECUTE FUNCTION private.expediente_notas_fija_pais();

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- privilegios: tabla SELECT + INSERT; UPDATE solo de las 9 columnas; sin DELETE; anon nada
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.expediente_notas'::regclass)
     IS DISTINCT FROM 'authenticated=ar/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres' THEN
    bad := bad||'relacl de expediente_notas = '||COALESCE((SELECT relacl::text FROM pg_class WHERE oid = 'public.expediente_notas'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||a.attacl::text, ',' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     IS DISTINCT FROM 'cita_id={authenticated=w/postgres},paciente_id={authenticated=w/postgres},medico_id={authenticated=w/postgres},'
                    ||'diagnostico={authenticated=w/postgres},motivo_consulta={authenticated=w/postgres},subjetivo={authenticated=w/postgres},'
                    ||'objetivo={authenticated=w/postgres},analisis={authenticated=w/postgres},plan={authenticated=w/postgres}' THEN
    bad := bad||'attacl de expediente_notas fuera de lo esperado; ';
  END IF;
  v := (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
         WHERE a.attrelid = 'public.expediente_notas'::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND has_column_privilege('authenticated', 'public.expediente_notas', a.attname, 'UPDATE')
               <> (a.attname IN ('cita_id', 'paciente_id', 'medico_id', 'motivo_consulta', 'subjetivo', 'objetivo', 'analisis', 'plan', 'diagnostico')));
  IF v IS NOT NULL THEN bad := bad||'UPDATE de authenticated fuera de lo esperado en: '||v||'; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.expediente_notas', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.expediente_notas', 'INSERT')
     OR has_table_privilege('authenticated', 'public.expediente_notas', 'UPDATE,DELETE,TRUNCATE,TRIGGER,MAINTAIN')
     OR has_any_column_privilege('anon', 'public.expediente_notas', 'SELECT,INSERT,UPDATE,REFERENCES')
     OR has_table_privilege('anon', 'public.expediente_notas', 'DELETE') THEN
    bad := bad||'privilegios de tabla de authenticated o anon fuera de lo esperado; ';
  END IF;
  IF NOT has_sequence_privilege('authenticated', 'public.expediente_notas_id_seq', 'USAGE') THEN
    bad := bad||'authenticated perdió USAGE de expediente_notas_id_seq; ';
  END IF;

  -- función nueva: cuerpo, DEFINER, search_path vacío, EXECUTE solo postgres; una sobrecarga
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'expediente_notas_fija_pais') <> 1 THEN
    bad := bad||'sobrecargas de la función nueva; ';
  END IF;
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')||' '||pg_get_userbyid(p.proowner)
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.expediente_notas_fija_pais()'))
     IS DISTINCT FROM '95e689efe029bb47b6c9718f4e3c8d7b true {"search_path=\"\""} {postgres=X/postgres} postgres' THEN
    bad := bad||'private.expediente_notas_fija_pais fuera de lo esperado; ';
  END IF;
  -- los 3 triggers, en este orden de disparo (por nombre): IMC, guard, país
  IF (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgtype::text, ',' ORDER BY t.tgname COLLATE "C")
        FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_calcular_imc_expediente O 23,trg_expediente_notas_guardia O 23,trg_expediente_notas_pais O 23'
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.expediente_notas'::regclass AND t.tgname = 'trg_expediente_notas_pais'
                      AND t.tgfoid = 'private.expediente_notas_fija_pais()'::regprocedure)
     OR NOT ('trg_expediente_notas_guardia' COLLATE "C" < 'trg_expediente_notas_pais' COLLATE "C") THEN
    bad := bad||'triggers de expediente_notas fuera de lo esperado; ';
  END IF;
  -- el guard, el IMC, los 2 escritores DEFINER y las 6 policies, intactos
  IF (SELECT md5(p.prosrc)||' '||p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
        FROM pg_proc p WHERE p.oid = to_regprocedure('private.expediente_notas_guardia()'))
     IS DISTINCT FROM '950c36d4959f5568e3a6fbf351713541 true {"search_path=\"\""} {postgres=X/postgres}'
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.calcular_imc_signos_vitales()')) IS DISTINCT FROM '1b9ad49a5cd1464c54d9a211e5763532'
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.corregir_nota_consulta(integer,text,text,text,text,text,text,text)')) IS DISTINCT FROM '1d39e9e839feebc889e392701beef913'
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('private.cerrar_nota_al_completar()')) IS DISTINCT FROM '9938ab3a0332d6fa35e4d51a1694e417' THEN
    bad := bad||'el guard, el IMC o los escritores DEFINER cambiaron; ';
  END IF;
  IF (SELECT md5(string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                            COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C"))
        FROM pg_policy pl WHERE pl.polrelid = 'public.expediente_notas'::regclass)
     IS DISTINCT FROM '291215175f82a9111ec8d9d4a7cafb3f' THEN
    bad := bad||'policies de expediente_notas cambiaron; ';
  END IF;

  -- datos intactos (la migración no escribe filas)
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.expediente_notas t)
     IS DISTINCT FROM current_setting('mig400.filas', true)
     OR (SELECT count(*)||' '||COALESCE(md5(string_agg(rv::text, E'\n' ORDER BY rv::text)), '-') FROM public.expediente_notas_revisiones rv)
     IS DISTINCT FROM current_setting('mig400.revisiones', true) THEN
    bad := bad||'cambiaron filas de expediente_notas o de sus revisiones; ';
  END IF;

  -- huellas: lo que no es expediente_notas ni la función nueva, igual a la entrada; secuencias y policies iguales; conteos nuevos
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.proname <> 'expediente_notas_fija_pais');
  IF v IS DISTINCT FROM 'c290831c4ccc8e33706d9097a5d97182 423' THEN bad := bad||'huella de funciones completas sin la nueva '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
         AND f.proname <> 'expediente_notas_fija_pais') y);
  IF v IS DISTINCT FROM 'a14a1f17ee0fc72d9271147e4925297e 423' THEN bad := bad||'huella de ACL de funciones sin la nueva '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 424 THEN
    bad := bad||'no quedaron 424 funciones en public/private; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'expediente_notas') x);
  IF v IS DISTINCT FROM 'b1d6c7e0439818b91d147dfd118e1e31 2424' THEN bad := bad||'huella de ACL de relaciones sin expediente_notas '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) <> 2442 THEN
    bad := bad||'la ACL de relaciones de public no quedó en 2442 entradas; ';
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
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'dabf9556bae56bcb910de70405314ad8 310' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

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
    RAISE EXCEPTION 'MIG00: autochequeo: %', bad USING ERRCODE = 'MIG00';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
