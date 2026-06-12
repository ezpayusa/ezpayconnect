-- ============================================================
-- FASE 0 · Pruebas de ESCRITURA NEGATIVA (no persisten)
-- ------------------------------------------------------------
-- Verifican que ciertas escrituras prohibidas FALLEN. Hoy (baseline) varias
-- PASAN indebidamente → quedan en ROJO; se pondrán en VERDE en su fase.
--
-- Seguridad: TODO va dentro de una transacción que termina en ROLLBACK, así
-- que aunque una escritura sea permitida, NO se persiste. Cada probe atrapa la
-- excepción y reporta el veredicto vía settings de sesión, devueltos como
-- result set (no se depende de RAISE NOTICE, que el API puede no propagar).
--
-- Interpretación:
--   BLOQUEADO  → la operación falló por RLS/validación  (VERDE: correcto)
--   PERMITIDO  → la operación se ejecutó sin bloqueo     (ROJO: hueco)
--
-- Diseño de P2/P3 (evita falsos veredictos):
--   * Se capturan DOS citas ajenas DISTINTAS con rol ELEVADO (login role, sin
--     RLS) ANTES de simular al médico, para que P2 y P3 no interfieran entre sí
--     (si P2 cancela su cita, P3 opera sobre OTRA, no sobre una ya cancelada):
--       - probe.cita_p2: ajena (medico_id NOT NULL y <> médico) y estado <> 'cancelada'
--       - probe.cita_p3: ajena (medico_id NOT NULL y <> médico) e id distinto al de P2
--   * La RPC se intenta YA como el médico (RLS aplicada).
--   * El efecto RESULTANTE se verifica de nuevo con rol ELEVADO → PERMITIDO solo
--     si la mutación ocurrió de verdad; BLOQUEADO si lanzó o si no hubo efecto.
--   * Si falta alguna de las dos citas, ese probe reporta N/A.
--
-- Ejecutar: WITH_WRITES=1 bash tests/rls/run.sh, o directo:
--   npx supabase db query --linked -f tests/rls/probes_escritura.sql
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- PROBE 1 — anon NO debe poder INSERT en citas
-- (hoy existe "Allow anon insert citas" WITH CHECK(true) → se espera ROJO)
-- Si el error es 42501 (violación de RLS) → BLOQUEADO/VERDE; cualquier otro
-- error (p.ej. 23502 NOT NULL) significa que la RLS YA dejó pasar y solo falló
-- una constraint → PERMITIDO por RLS / ROJO.
-- ------------------------------------------------------------
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$
DECLARE v_sqlstate TEXT;
BEGIN
  BEGIN
    INSERT INTO public.citas (estado) VALUES ('solicitada');  -- valores mínimos a propósito
    PERFORM set_config('probe.p1', 'PERMITIDO (RLS no bloqueó la inserción anónima)', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
    IF v_sqlstate = '42501' THEN
      PERFORM set_config('probe.p1', 'BLOQUEADO (RLS rechazó: 42501)', false);
    ELSE
      PERFORM set_config('probe.p1', 'PERMITIDO por RLS (falló otra constraint: '||v_sqlstate||')', false);
    END IF;
  END;
END $$;

-- ------------------------------------------------------------
-- Captura con rol ELEVADO (login role, sin RLS), ANTES de simular al médico:
--   probe.medico   = uid de un médico
--   probe.cita_p2  = cita ajena con estado <> 'cancelada' (para P2)
--   probe.cita_p3  = otra cita ajena distinta de cita_p2  (para P3)
-- ------------------------------------------------------------
SELECT set_config('role', 'none', true);   -- volver al login role (elevado)
SELECT set_config('probe.medico',
  (SELECT id FROM public.perfiles WHERE rol = 'medico' ORDER BY id LIMIT 1)::text, false);

SELECT set_config('probe.cita_p2',
  (SELECT id FROM public.citas
     WHERE medico_id IS NOT NULL
       AND medico_id <> NULLIF(current_setting('probe.medico', true), '')::uuid
       AND estado IS DISTINCT FROM 'cancelada'
     ORDER BY id LIMIT 1)::text, false);

SELECT set_config('probe.cita_p3',
  (SELECT id FROM public.citas
     WHERE medico_id IS NOT NULL
       AND medico_id <> NULLIF(current_setting('probe.medico', true), '')::uuid
       AND id IS DISTINCT FROM NULLIF(current_setting('probe.cita_p2', true), '')::bigint
     ORDER BY id LIMIT 1)::text, false);

-- Simular al médico (RLS aplicada)
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.medico', true), 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);

-- ------------------------------------------------------------
-- PROBE 2 — el médico NO debe poder cancelar una cita AJENA vía la RPC
-- SECURITY DEFINER actualizar_estado_cita (hoy no revalida → ROJO/PERMITIDO).
-- Usa probe.cita_p2. Aquí solo se INTENTA y se registra si la RPC lanzó error.
-- ------------------------------------------------------------
DO $$
DECLARE v_cita BIGINT := NULLIF(current_setting('probe.cita_p2', true), '')::bigint;
BEGIN
  IF v_cita IS NULL THEN
    PERFORM set_config('probe.p2_err', 'NA', false);
  ELSE
    BEGIN
      PERFORM public.actualizar_estado_cita(v_cita::int, 'cancelada');  -- la RPC toma integer
      PERFORM set_config('probe.p2_err', '', false);  -- no lanzó
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('probe.p2_err', SQLERRM, false);
    END;
  END IF;
END $$;

-- ------------------------------------------------------------
-- PROBE 3 — el médico NO debe poder autoasignarse una cita AJENA vía la RPC
-- SECURITY DEFINER asignar_medico_cita (hoy no revalida → ROJO/PERMITIDO).
-- Usa probe.cita_p3 (distinta de la de P2, sin tocar por P2).
-- ------------------------------------------------------------
DO $$
DECLARE v_cita BIGINT := NULLIF(current_setting('probe.cita_p3', true), '')::bigint;
BEGIN
  IF v_cita IS NULL THEN
    PERFORM set_config('probe.p3_err', 'NA', false);
  ELSE
    BEGIN
      PERFORM public.asignar_medico_cita(v_cita::int, auth.uid());  -- la RPC toma integer; intentar robarse la cita
      PERFORM set_config('probe.p3_err', '', false);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('probe.p3_err', SQLERRM, false);
    END;
  END IF;
END $$;

-- ------------------------------------------------------------
-- Verificación del efecto RESULTANTE con rol ELEVADO (sin RLS) → veredicto real.
-- P2 lee su cita (cita_p2); P3 lee la suya (cita_p3). N/A independiente por probe.
-- ------------------------------------------------------------
SELECT set_config('role', 'none', true);
DO $$
DECLARE
  v_cita2 BIGINT := NULLIF(current_setting('probe.cita_p2', true), '')::bigint;
  v_cita3 BIGINT := NULLIF(current_setting('probe.cita_p3', true), '')::bigint;
  v_med   UUID   := NULLIF(current_setting('probe.medico', true), '')::uuid;
  v_estado TEXT; v_medico_post UUID;
BEGIN
  -- P2
  IF v_cita2 IS NULL THEN
    PERFORM set_config('probe.p2', 'N/A (no hay cita ajena no-cancelada para probar)', false);
  ELSE
    SELECT estado INTO v_estado FROM public.citas WHERE id = v_cita2;
    IF current_setting('probe.p2_err', true) NOT IN ('', 'NA') THEN
      PERFORM set_config('probe.p2', 'BLOQUEADO (RPC lanzó: '||current_setting('probe.p2_err', true)||')', false);
    ELSIF v_estado = 'cancelada' THEN
      PERFORM set_config('probe.p2', 'PERMITIDO (canceló cita ajena id='||v_cita2||')', false);
    ELSE
      PERFORM set_config('probe.p2', 'BLOQUEADO (no hubo efecto; estado quedó '||COALESCE(v_estado, '?')||')', false);
    END IF;
  END IF;

  -- P3
  IF v_cita3 IS NULL THEN
    PERFORM set_config('probe.p3', 'N/A (no hay segunda cita ajena para probar)', false);
  ELSE
    SELECT medico_id INTO v_medico_post FROM public.citas WHERE id = v_cita3;
    IF current_setting('probe.p3_err', true) NOT IN ('', 'NA') THEN
      PERFORM set_config('probe.p3', 'BLOQUEADO (RPC lanzó: '||current_setting('probe.p3_err', true)||')', false);
    ELSIF v_medico_post = v_med THEN
      PERFORM set_config('probe.p3', 'PERMITIDO (se autoasignó cita ajena id='||v_cita3||')', false);
    ELSE
      PERFORM set_config('probe.p3', 'BLOQUEADO (no hubo efecto; medico_id no cambió)', false);
    END IF;
  END IF;
END $$;

-- Veredictos como result set
SELECT 'P1_anon_insert_citas'         AS probe, current_setting('probe.p1', true) AS verdict, 'BLOQUEADO' AS esperado_post_fix
UNION ALL
SELECT 'P2_medico_cancela_ajena_rpc',  current_setting('probe.p2', true), 'BLOQUEADO'
UNION ALL
SELECT 'P3_medico_roba_cita_rpc',      current_setting('probe.p3', true), 'BLOQUEADO';

ROLLBACK;  -- nada de lo anterior se persiste
