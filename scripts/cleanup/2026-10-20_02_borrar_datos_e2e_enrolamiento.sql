-- =====================================================================================================================
-- CLEANUP E2E 20-oct-2026 — SCRIPT 2 de 2: borrar los datos de la prueba punta a punta del enrolamiento
-- =====================================================================================================================
-- Qué borra (todo por lista explícita de ids, nunca por patrón de texto ni por fecha):
--   - solicitudes_alta_medico (3): Alta 1 rechazada, Alta 2 invitada y la del Dr. E2E registrada (QA Laboratorio).
--   - invitaciones_medico (5): la de Alta 2 (pendiente), 3 canceladas y la usada por el Dr. E2E.
--   - notificaciones (10) in-app y notificaciones_email (5) de esas solicitudes e invitaciones.
--   - medico_clinicas id 2062 y la clínica propia del Dr. E2E (17a0b047-3beb-4bec-99b9-be4105a6105e).
--   - el usuario de auth del Dr. E2E (5c88c564-4f30-4a20-a3b7-86321413d473, qa.medico@ezpayconnect.com); caen en
--     cascada su auth.identities, su perfiles y su medicos.
-- De qué prueba: la prueba punta a punta del enrolamiento en prod del 20-oct-2026 (visitador solicita → admin_pais
--   aprueba → correo → registro → enrolado). Recon: C:\tmp\cleanup_enrol\01.out y 02_existencia.out (29/29 existen,
--   0 sobran de la prueba). medico.qa (09d243d5-b222-482a-9762-94a582e9e752) NO entra: su enrolamiento queda.
-- Script 1 (revertir el enrolamiento de Dr.Prueba) YA APLICADO por Oscar el 2026-10-20 23:37:50-23:37:52 UTC y verificado.
--
-- Orden por FK (medidas el 20-oct): solicitudes primero (sus FK a invitaciones_medico y a medicos son RESTRICT) →
--   invitaciones → notificaciones → notificaciones_email → medico_clinicas → clínica (clinicas.doctor_id no tiene FK:
--   no cae con el médico) → auth.users (CASCADE a auth.identities y perfiles; perfiles → medicos en CASCADE).
-- Ningún trigger actúa en DELETE sobre estas tablas: no hace falta saltear triggers.
--
-- NO es una migración: no va en supabase/migrations, no cambia catálogo ni huellas, y NO se reaplica (los pre-asserts
--   fallan si alguna fila ya no existe).
-- Apply: lo corre Oscar con npx supabase db query --linked -f <este archivo>, anotando la hora UTC antes y después.
-- =====================================================================================================================

BEGIN;

-- a) PRE-ASSERTS
DO $$
DECLARE
  v_n     int;
  v_lab   uuid;
  v_fecha timestamptz;
  v_upd   timestamptz;
  r       record;
BEGIN
  -- solicitudes_alta_medico: las 3, QA-MANUAL y de QA Laboratorio
  SELECT count(*) INTO v_n FROM public.solicitudes_alta_medico
   WHERE id = ANY (ARRAY['ef2eed2c-13a4-4204-a141-38a422993340',
                         '674a439d-8c07-4c6e-a6c1-6e232e7a65b0',
                         '093fe70f-8441-4f9f-9356-528a62a4cfb2']::uuid[])
     AND nombre_completo ILIKE '%QA-MANUAL%'
     AND empresa_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid;
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'PRE: se esperaban 3 solicitudes_alta_medico QA-MANUAL de 411d6f8c-a405-49d6-9ed6-fbeb0db05133 y hay %', v_n;
  END IF;

  -- invitaciones_medico: las 5, QA-MANUAL
  SELECT count(*) INTO v_n FROM public.invitaciones_medico
   WHERE id = ANY (ARRAY['a1b0525f-19ea-4cab-8ff1-22bef9275c32',
                         '41c99bd7-9a76-4183-a308-7b16035e93ec',
                         '1e9a3aae-cba1-4d88-982f-460213490c29',
                         '709bdb71-c0a2-4ae8-b646-286d082d832e',
                         'ba93b2b5-abe4-4264-b187-f304f4bd8234']::uuid[])
     AND nombre_completo ILIKE '%QA-MANUAL%';
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'PRE: se esperaban 5 invitaciones_medico QA-MANUAL y hay %', v_n;
  END IF;

  -- notificaciones: las 10
  SELECT count(*) INTO v_n FROM public.notificaciones
   WHERE id = ANY (ARRAY['0ebe17ad-2c1f-47e6-81bf-251f6a399f3e',
                         'a5c8c3a8-2f8a-4101-a6f7-e6f13734bca6',
                         '46e9dd7d-e532-44ca-98eb-1f2baafcea0d',
                         '196529e2-7bcc-45c9-a0a7-480e92155853',
                         '46319607-6e17-4a82-ab42-aa264ff69c5d',
                         'fdb8804a-c476-4735-b0a1-fce7a0df40cd',
                         'f999e360-a64f-4037-891e-0df5660f5550',
                         'eac1c076-9430-4c62-afa2-493fde6f369c',
                         '6e53cc7b-65d1-4cb7-a83f-3a8b50d9b686',
                         '18becee0-1a7e-45ac-bdfa-1e272fddf703']::uuid[]);
  IF v_n <> 10 THEN
    RAISE EXCEPTION 'PRE: se esperaban 10 notificaciones y hay %', v_n;
  END IF;

  -- notificaciones_email: las 5
  SELECT count(*) INTO v_n FROM public.notificaciones_email
   WHERE id = ANY (ARRAY['75f491b5-8264-4439-bbb3-e6cf4a1024a5',
                         '778e8bd1-d701-4ead-8083-5aa928151882',
                         '8856dc85-099e-40b2-a421-9c1d2a359e2d',
                         '68d3ffd6-c3b1-46f9-ab23-8aea2dd38918',
                         'c5495c8e-0ae1-4e69-a791-3ef5ac749f03']::uuid[]);
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'PRE: se esperaban 5 notificaciones_email y hay %', v_n;
  END IF;

  -- Dr. E2E: usuario de auth sin login, 1 perfil, 1 médico QA-MANUAL, 1 identidad
  SELECT count(*) INTO v_n FROM auth.users
   WHERE id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid AND last_sign_in_at IS NULL;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: auth.users del Dr. E2E 5c88c564-4f30-4a20-a3b7-86321413d473 no existe o ya inició sesión (filas = %)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.perfiles WHERE id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: se esperaba 1 perfiles del Dr. E2E y hay %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.medicos
   WHERE id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid AND nombre_completo ILIKE '%QA-MANUAL%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: se esperaba 1 medicos QA-MANUAL del Dr. E2E y hay %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM auth.identities WHERE user_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: se esperaba 1 auth.identities del Dr. E2E y hay %', v_n;
  END IF;

  -- medico_clinicas 2062 y la clínica propia, que solo tiene esa fila
  SELECT count(*) INTO v_n FROM public.medico_clinicas
   WHERE id = 2062
     AND medico_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid
     AND clinica_id = '17a0b047-3beb-4bec-99b9-be4105a6105e'::uuid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: medico_clinicas 2062 no existe con el Dr. E2E y la clínica 17a0b047-3beb-4bec-99b9-be4105a6105e (filas = %)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.clinicas
   WHERE id = '17a0b047-3beb-4bec-99b9-be4105a6105e'::uuid
     AND doctor_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: la clínica 17a0b047-3beb-4bec-99b9-be4105a6105e no existe con doctor_id = Dr. E2E (filas = %)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.medico_clinicas
   WHERE clinica_id = '17a0b047-3beb-4bec-99b9-be4105a6105e'::uuid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PRE: la clínica 17a0b047-3beb-4bec-99b9-be4105a6105e tiene % filas en medico_clinicas (se esperaba solo la 2062)', v_n;
  END IF;

  -- ninguna notificación fuera de las 10 es del Dr. E2E (la FK es SET NULL: quedaría huérfana)
  SELECT count(*) INTO v_n FROM public.notificaciones
   WHERE usuario_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid
     AND id <> ALL (ARRAY['0ebe17ad-2c1f-47e6-81bf-251f6a399f3e',
                          'a5c8c3a8-2f8a-4101-a6f7-e6f13734bca6',
                          '46e9dd7d-e532-44ca-98eb-1f2baafcea0d',
                          '196529e2-7bcc-45c9-a0a7-480e92155853',
                          '46319607-6e17-4a82-ab42-aa264ff69c5d',
                          'fdb8804a-c476-4735-b0a1-fce7a0df40cd',
                          'f999e360-a64f-4037-891e-0df5660f5550',
                          'eac1c076-9430-4c62-afa2-493fde6f369c',
                          '6e53cc7b-65d1-4cb7-a83f-3a8b50d9b686',
                          '18becee0-1a7e-45ac-bdfa-1e272fddf703']::uuid[]);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'PRE: hay % notificaciones del Dr. E2E fuera de las 10 del inventario', v_n;
  END IF;

  -- no-colateral por FK: ninguna otra fila referencia al Dr. E2E (auth.users, perfiles, medicos) ni a su clínica,
  -- salvo las que este script borra o deja caer en cascada. Recorre el catálogo vivo (FK de una columna).
  FOR r IN
    SELECT c.conrelid::regclass AS hija, a.attname::text AS col, c.confrelid::regclass AS padre,
           (c.confrelid = 'public.clinicas'::regclass) AS es_clinica
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
     WHERE c.contype = 'f'
       AND array_length(c.conkey, 1) = 1
       AND c.confrelid IN ('auth.users'::regclass, 'public.perfiles'::regclass, 'public.medicos'::regclass,
                           'public.clinicas'::regclass)
       AND NOT ((c.conrelid = 'auth.identities'::regclass         AND a.attname = 'user_id')
             OR (c.conrelid = 'public.perfiles'::regclass         AND a.attname = 'id')
             OR (c.conrelid = 'public.medicos'::regclass          AND a.attname = 'id')
             OR (c.conrelid = 'public.medico_clinicas'::regclass  AND a.attname IN ('medico_id', 'clinica_id'))
             OR (c.conrelid = 'public.solicitudes_alta_medico'::regclass AND a.attname = 'medico_id'))
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I::text = %L', r.hija, r.col,
                   CASE WHEN r.es_clinica THEN '17a0b047-3beb-4bec-99b9-be4105a6105e'
                        ELSE '5c88c564-4f30-4a20-a3b7-86321413d473' END)
      INTO v_n;
    IF v_n <> 0 THEN
      RAISE EXCEPTION 'PRE: %.% tiene % filas que referencian a % del Dr. E2E (efecto lateral no previsto)', r.hija, r.col, v_n, r.padre;
    END IF;
  END LOOP;

  -- guardas de no-colateral: medico.qa sigue enrolado, Dr.Prueba sin enrolar (script 1)
  SELECT lab_enrolador_id, lab_enrolador_fecha, updated_at INTO v_lab, v_fecha, v_upd
    FROM public.medicos WHERE id = '09d243d5-b222-482a-9762-94a582e9e752'::uuid;
  IF NOT FOUND
     OR v_lab IS DISTINCT FROM '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid
     OR v_fecha IS DISTINCT FROM '2026-10-20 14:03:23.274208+00'::timestamptz
     OR v_upd IS DISTINCT FROM '2026-06-11 12:35:39.155187+00'::timestamptz THEN
    RAISE EXCEPTION 'PRE: medico.qa no está como se esperaba (lab %, fecha %, updated_at %)', v_lab, v_fecha, v_upd;
  END IF;
  SELECT lab_enrolador_id, lab_enrolador_fecha, updated_at INTO v_lab, v_fecha, v_upd
    FROM public.medicos WHERE id = '55aaa118-1b02-44ed-b2b7-dcd2b8741cd7'::uuid;
  IF NOT FOUND OR v_lab IS NOT NULL OR v_fecha IS NOT NULL
     OR v_upd IS DISTINCT FROM '2026-06-09 13:55:47.472288+00'::timestamptz THEN
    RAISE EXCEPTION 'PRE: Dr.Prueba no está como lo dejó el script 1 (lab %, fecha %, updated_at %)', v_lab, v_fecha, v_upd;
  END IF;
END
$$;

-- b) BORRADOS, cada uno con su ROW_COUNT exacto

-- b1) solicitudes_alta_medico (3)
DO $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.solicitudes_alta_medico
   WHERE id = ANY (ARRAY['ef2eed2c-13a4-4204-a141-38a422993340',
                         '674a439d-8c07-4c6e-a6c1-6e232e7a65b0',
                         '093fe70f-8441-4f9f-9356-528a62a4cfb2']::uuid[]);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'b1: se esperaban 3 solicitudes_alta_medico borradas y fueron %', v_n;
  END IF;
END
$$;

-- b2) invitaciones_medico (5)
DO $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.invitaciones_medico
   WHERE id = ANY (ARRAY['a1b0525f-19ea-4cab-8ff1-22bef9275c32',
                         '41c99bd7-9a76-4183-a308-7b16035e93ec',
                         '1e9a3aae-cba1-4d88-982f-460213490c29',
                         '709bdb71-c0a2-4ae8-b646-286d082d832e',
                         'ba93b2b5-abe4-4264-b187-f304f4bd8234']::uuid[]);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'b2: se esperaban 5 invitaciones_medico borradas y fueron %', v_n;
  END IF;
END
$$;

-- b3) notificaciones (10)
DO $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.notificaciones
   WHERE id = ANY (ARRAY['0ebe17ad-2c1f-47e6-81bf-251f6a399f3e',
                         'a5c8c3a8-2f8a-4101-a6f7-e6f13734bca6',
                         '46e9dd7d-e532-44ca-98eb-1f2baafcea0d',
                         '196529e2-7bcc-45c9-a0a7-480e92155853',
                         '46319607-6e17-4a82-ab42-aa264ff69c5d',
                         'fdb8804a-c476-4735-b0a1-fce7a0df40cd',
                         'f999e360-a64f-4037-891e-0df5660f5550',
                         'eac1c076-9430-4c62-afa2-493fde6f369c',
                         '6e53cc7b-65d1-4cb7-a83f-3a8b50d9b686',
                         '18becee0-1a7e-45ac-bdfa-1e272fddf703']::uuid[]);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 10 THEN
    RAISE EXCEPTION 'b3: se esperaban 10 notificaciones borradas y fueron %', v_n;
  END IF;
END
$$;

-- b4) notificaciones_email (5)
DO $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.notificaciones_email
   WHERE id = ANY (ARRAY['75f491b5-8264-4439-bbb3-e6cf4a1024a5',
                         '778e8bd1-d701-4ead-8083-5aa928151882',
                         '8856dc85-099e-40b2-a421-9c1d2a359e2d',
                         '68d3ffd6-c3b1-46f9-ab23-8aea2dd38918',
                         'c5495c8e-0ae1-4e69-a791-3ef5ac749f03']::uuid[]);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'b4: se esperaban 5 notificaciones_email borradas y fueron %', v_n;
  END IF;
END
$$;

-- b5) medico_clinicas 2062 (1)
DO $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.medico_clinicas
   WHERE id = 2062
     AND medico_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid
     AND clinica_id = '17a0b047-3beb-4bec-99b9-be4105a6105e'::uuid;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'b5: se esperaba 1 medico_clinicas borrada (2062) y fueron %', v_n;
  END IF;
END
$$;

-- b6) clínica propia del Dr. E2E (1)
DO $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.clinicas
   WHERE id = '17a0b047-3beb-4bec-99b9-be4105a6105e'::uuid
     AND doctor_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'b6: se esperaba 1 clínica borrada (17a0b047-3beb-4bec-99b9-be4105a6105e) y fueron %', v_n;
  END IF;
END
$$;

-- b7) usuario de auth del Dr. E2E (1); cascada: auth.identities, perfiles → medicos
DO $$
DECLARE v_n int;
BEGIN
  DELETE FROM auth.users
   WHERE id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid
     AND last_sign_in_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'b7: se esperaba 1 auth.users borrado (Dr. E2E) y fueron %', v_n;
  END IF;
END
$$;

-- c) POST-ASSERTS
DO $$
DECLARE
  v_n     int;
  v_lab   uuid;
  v_fecha timestamptz;
  v_upd   timestamptz;
BEGIN
  SELECT count(*) INTO v_n FROM public.solicitudes_alta_medico
   WHERE id = ANY (ARRAY['ef2eed2c-13a4-4204-a141-38a422993340',
                         '674a439d-8c07-4c6e-a6c1-6e232e7a65b0',
                         '093fe70f-8441-4f9f-9356-528a62a4cfb2']::uuid[]);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'POST: quedan % solicitudes_alta_medico del inventario', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.invitaciones_medico
   WHERE id = ANY (ARRAY['a1b0525f-19ea-4cab-8ff1-22bef9275c32',
                         '41c99bd7-9a76-4183-a308-7b16035e93ec',
                         '1e9a3aae-cba1-4d88-982f-460213490c29',
                         '709bdb71-c0a2-4ae8-b646-286d082d832e',
                         'ba93b2b5-abe4-4264-b187-f304f4bd8234']::uuid[]);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'POST: quedan % invitaciones_medico del inventario', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.notificaciones
   WHERE id = ANY (ARRAY['0ebe17ad-2c1f-47e6-81bf-251f6a399f3e',
                         'a5c8c3a8-2f8a-4101-a6f7-e6f13734bca6',
                         '46e9dd7d-e532-44ca-98eb-1f2baafcea0d',
                         '196529e2-7bcc-45c9-a0a7-480e92155853',
                         '46319607-6e17-4a82-ab42-aa264ff69c5d',
                         'fdb8804a-c476-4735-b0a1-fce7a0df40cd',
                         'f999e360-a64f-4037-891e-0df5660f5550',
                         'eac1c076-9430-4c62-afa2-493fde6f369c',
                         '6e53cc7b-65d1-4cb7-a83f-3a8b50d9b686',
                         '18becee0-1a7e-45ac-bdfa-1e272fddf703']::uuid[]);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'POST: quedan % notificaciones del inventario', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.notificaciones_email
   WHERE id = ANY (ARRAY['75f491b5-8264-4439-bbb3-e6cf4a1024a5',
                         '778e8bd1-d701-4ead-8083-5aa928151882',
                         '8856dc85-099e-40b2-a421-9c1d2a359e2d',
                         '68d3ffd6-c3b1-46f9-ab23-8aea2dd38918',
                         'c5495c8e-0ae1-4e69-a791-3ef5ac749f03']::uuid[]);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'POST: quedan % notificaciones_email del inventario', v_n;
  END IF;

  SELECT (SELECT count(*) FROM auth.users       WHERE id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid)
       + (SELECT count(*) FROM auth.identities  WHERE user_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid)
       + (SELECT count(*) FROM public.perfiles  WHERE id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid)
       + (SELECT count(*) FROM public.medicos   WHERE id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid)
       + (SELECT count(*) FROM public.medico_clinicas
           WHERE id = 2062 OR medico_id = '5c88c564-4f30-4a20-a3b7-86321413d473'::uuid)
    INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'POST: quedan % filas del Dr. E2E entre auth.users, auth.identities, perfiles, medicos y medico_clinicas', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.clinicas WHERE id = '17a0b047-3beb-4bec-99b9-be4105a6105e'::uuid;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'POST: la clínica 17a0b047-3beb-4bec-99b9-be4105a6105e sigue existiendo';
  END IF;

  SELECT lab_enrolador_id, lab_enrolador_fecha, updated_at INTO v_lab, v_fecha, v_upd
    FROM public.medicos WHERE id = '09d243d5-b222-482a-9762-94a582e9e752'::uuid;
  IF NOT FOUND
     OR v_lab IS DISTINCT FROM '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid
     OR v_fecha IS DISTINCT FROM '2026-10-20 14:03:23.274208+00'::timestamptz
     OR v_upd IS DISTINCT FROM '2026-06-11 12:35:39.155187+00'::timestamptz THEN
    RAISE EXCEPTION 'POST: medico.qa cambió (lab %, fecha %, updated_at %)', v_lab, v_fecha, v_upd;
  END IF;
  SELECT lab_enrolador_id, lab_enrolador_fecha, updated_at INTO v_lab, v_fecha, v_upd
    FROM public.medicos WHERE id = '55aaa118-1b02-44ed-b2b7-dcd2b8741cd7'::uuid;
  IF NOT FOUND OR v_lab IS NOT NULL OR v_fecha IS NOT NULL
     OR v_upd IS DISTINCT FROM '2026-06-09 13:55:47.472288+00'::timestamptz THEN
    RAISE EXCEPTION 'POST: Dr.Prueba cambió (lab %, fecha %, updated_at %)', v_lab, v_fecha, v_upd;
  END IF;

  SELECT count(*) INTO v_n FROM public.medicos WHERE lab_enrolador_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'POST: se esperaba 1 médico enrolado por 411d6f8c-a405-49d6-9ed6-fbeb0db05133 (medico.qa) y hay %', v_n;
  END IF;
END
$$;

COMMIT;
