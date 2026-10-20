-- =====================================================================================================================
-- CLEANUP E2E 20-oct-2026 — SCRIPT 1 de 2: revertir el enrolamiento QA de Dr.Prueba
-- =====================================================================================================================
-- Qué hace: vuelve a NULL medicos.lab_enrolador_id y medicos.lab_enrolador_fecha de Dr.Prueba
--   (55aaa118-1b02-44ed-b2b7-dcd2b8741cd7), enrolado por QA Laboratorio (411d6f8c-a405-49d6-9ed6-fbeb0db05133) el
--   2026-10-20 20:17:09.053916 UTC durante la prueba punta a punta del enrolamiento. No toca ninguna otra columna
--   (ni updated_at) ni a medico.qa (09d243d5-b222-482a-9762-94a582e9e752), cuyo enrolamiento viene de la mig 375 y queda.
--
-- Por qué con el rol de replicación: el trigger trigger_medicos_lab_enrolador_inmutable (función
--   trg_medicos_lab_enrolador_inmutable, md5(prosrc) 2af30509d27efef4ed649c5785883381, mig 375) tiene una rama de UPDATE
--   que impide quitar un laboratorio enrolador ya puesto ("ni siquiera desde la RPC") y NO tiene excepción por GUC:
--   app.enrolamiento_rpc solo exime la otra rama. La única forma de quitarlo es saltear el trigger dentro de esta
--   transacción (session_replication_role en modo réplica, solo alrededor del UPDATE). Los CHECK siguen vigentes:
--   medicos_enrolador_coherente exige las dos columnas NULL o las dos no NULL. Recon: C:\tmp\cleanup_enrol\01.out.
--
-- NO es una migración: no va en supabase/migrations, no cambia catálogo ni huellas, y NO se reaplica (los pre-asserts
--   fallan si Dr.Prueba ya no está enrolado con los valores exactos del 20-oct).
-- Apply: lo corre Oscar con npx supabase db query --linked -f <este archivo>, anotando la hora UTC antes y después.
-- =====================================================================================================================

BEGIN;

-- a) PRE-ASSERTS
DO $$
DECLARE
  v_n     int;
  v_lab   uuid;
  v_fecha timestamptz;
BEGIN
  IF current_setting('session_replication_role') <> 'origin' THEN
    RAISE EXCEPTION 'PRE: session_replication_role no es origin al empezar (%)', current_setting('session_replication_role');
  END IF;

  -- Dr.Prueba enrolado por QA Laboratorio con la fecha exacta de la prueba
  SELECT count(*) INTO v_n FROM public.medicos WHERE id = '55aaa118-1b02-44ed-b2b7-dcd2b8741cd7'::uuid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: Dr.Prueba 55aaa118-1b02-44ed-b2b7-dcd2b8741cd7 no existe (filas = %)', v_n;
  END IF;
  SELECT lab_enrolador_id, lab_enrolador_fecha INTO v_lab, v_fecha
    FROM public.medicos WHERE id = '55aaa118-1b02-44ed-b2b7-dcd2b8741cd7'::uuid;
  IF v_lab IS DISTINCT FROM '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid
     OR v_fecha IS DISTINCT FROM '2026-10-20 20:17:09.053916+00'::timestamptz THEN
    RAISE EXCEPTION 'PRE: Dr.Prueba no tiene el enrolamiento esperado (lab %, fecha %)', v_lab, v_fecha;
  END IF;

  -- medico.qa: enrolamiento de la 375, se deja intacto
  SELECT lab_enrolador_id, lab_enrolador_fecha INTO v_lab, v_fecha
    FROM public.medicos WHERE id = '09d243d5-b222-482a-9762-94a582e9e752'::uuid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PRE: medico.qa 09d243d5-b222-482a-9762-94a582e9e752 no existe';
  END IF;
  IF v_lab IS DISTINCT FROM '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid
     OR v_fecha IS DISTINCT FROM '2026-10-20 14:03:23.274208+00'::timestamptz THEN
    RAISE EXCEPTION 'PRE: medico.qa no tiene el enrolamiento esperado (lab %, fecha %)', v_lab, v_fecha;
  END IF;

  -- el guard PV015 vivo, habilitado y con el cuerpo de la 375
  SELECT count(*) INTO v_n
    FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
   WHERE t.tgrelid = 'public.medicos'::regclass
     AND t.tgname = 'trigger_medicos_lab_enrolador_inmutable'
     AND t.tgenabled = 'O'
     AND md5(p.prosrc) = '2af30509d27efef4ed649c5785883381';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: trigger_medicos_lab_enrolador_inmutable no está habilitado (O) con md5 2af30509d27efef4ed649c5785883381 (filas = %)', v_n;
  END IF;
END
$$;

-- b) saltear el trigger solo en esta transacción
SET LOCAL session_replication_role = replica;

-- c) el UPDATE, exactamente 1 fila
DO $$
DECLARE
  v_n int;
BEGIN
  IF current_setting('session_replication_role') <> 'replica' THEN
    RAISE EXCEPTION 'UPDATE: session_replication_role no quedó en replica (%)', current_setting('session_replication_role');
  END IF;

  UPDATE public.medicos
     SET lab_enrolador_id = NULL,
         lab_enrolador_fecha = NULL
   WHERE id = '55aaa118-1b02-44ed-b2b7-dcd2b8741cd7'::uuid
     AND lab_enrolador_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid
     AND lab_enrolador_fecha = '2026-10-20 20:17:09.053916+00'::timestamptz;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'UPDATE: se esperaba 1 fila de Dr.Prueba y se actualizaron %', v_n;
  END IF;
END
$$;

-- d) volver al modo normal antes de los post-asserts
SET LOCAL session_replication_role = origin;

-- e) POST-ASSERTS
DO $$
DECLARE
  v_n     int;
  v_lab   uuid;
  v_fecha timestamptz;
BEGIN
  IF current_setting('session_replication_role') <> 'origin' THEN
    RAISE EXCEPTION 'POST: session_replication_role no volvió a origin (%)', current_setting('session_replication_role');
  END IF;

  SELECT lab_enrolador_id, lab_enrolador_fecha INTO v_lab, v_fecha
    FROM public.medicos WHERE id = '55aaa118-1b02-44ed-b2b7-dcd2b8741cd7'::uuid;
  IF NOT FOUND OR v_lab IS NOT NULL OR v_fecha IS NOT NULL THEN
    RAISE EXCEPTION 'POST: Dr.Prueba no quedó con lab_enrolador_id y lab_enrolador_fecha en NULL (lab %, fecha %)', v_lab, v_fecha;
  END IF;

  SELECT lab_enrolador_id, lab_enrolador_fecha INTO v_lab, v_fecha
    FROM public.medicos WHERE id = '09d243d5-b222-482a-9762-94a582e9e752'::uuid;
  IF NOT FOUND
     OR v_lab IS DISTINCT FROM '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid
     OR v_fecha IS DISTINCT FROM '2026-10-20 14:03:23.274208+00'::timestamptz THEN
    RAISE EXCEPTION 'POST: medico.qa cambió (lab %, fecha %)', v_lab, v_fecha;
  END IF;

  SELECT count(*) INTO v_n
    FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
   WHERE t.tgrelid = 'public.medicos'::regclass
     AND t.tgname = 'trigger_medicos_lab_enrolador_inmutable'
     AND t.tgenabled = 'O'
     AND md5(p.prosrc) = '2af30509d27efef4ed649c5785883381';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'POST: trigger_medicos_lab_enrolador_inmutable ya no está habilitado (O) con md5 2af30509d27efef4ed649c5785883381 (filas = %)', v_n;
  END IF;
END
$$;

COMMIT;
