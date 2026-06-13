-- ============================================================
-- FASE 0-2 · Pruebas de ESCRITURA/AISLAMIENTO (no persisten)
-- ------------------------------------------------------------
-- Verifican que accesos prohibidos FALLEN y que las features reparadas
-- funcionen. Todo dentro de una transacción que termina en ROLLBACK.
-- Veredicto vía settings de sesión, devueltos como result set.
--
--   BLOQUEADO  → falló por RLS/validación   (VERDE cuando se espera bloqueo)
--   PERMITIDO  → se ejecutó sin bloqueo      (ROJO cuando se espera bloqueo)
--   OK         → la operación legítima funcionó (VERDE en features reparadas)
--
-- Nota: la RLS WITH CHECK se evalúa ANTES que NOT NULL → 42501 = RLS bloqueó.
-- Las probes de Fase 2 inlinean la relación "médico tiene cita con el paciente"
-- (no usan el helper nuevo) para poder capturar el baseline ANTES de aplicar 070.
-- ============================================================

BEGIN;

-- ===== P1 + P4/P5/P6 — anon NO debe insertar (citas/notificaciones/cuentas/empresas) =====
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);

DO $$ DECLARE s TEXT;
BEGIN
  BEGIN INSERT INTO public.citas (estado) VALUES ('solicitada');
    PERFORM set_config('probe.p1', 'PERMITIDO (insertó como anon)', false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p1','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p1','PERMITIDO por RLS (falló otra constraint: '||s||')',false); END IF;
  END;
END $$;

DO $$ DECLARE s TEXT;
BEGIN
  BEGIN INSERT INTO public.notificaciones (titulo) VALUES ('rls_probe');
    PERFORM set_config('probe.p4', 'PERMITIDO (insertó como anon)', false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p4','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p4','PERMITIDO por RLS (falló otra constraint: '||s||')',false); END IF;
  END;
END $$;

DO $$ DECLARE s TEXT;
BEGIN
  BEGIN INSERT INTO public.cuentas_proveedor (nombre_completo) VALUES ('rls_probe');
    PERFORM set_config('probe.p5', 'PERMITIDO (insertó como anon)', false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p5','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p5','PERMITIDO por RLS (falló otra constraint: '||s||')',false); END IF;
  END;
END $$;

DO $$ DECLARE s TEXT;
BEGIN
  BEGIN INSERT INTO public.empresas_proveedoras (nombre_empresa) VALUES ('rls_probe');
    PERFORM set_config('probe.p6', 'PERMITIDO (insertó como anon)', false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p6','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p6','PERMITIDO por RLS (falló otra constraint: '||s||')',false); END IF;
  END;
END $$;

-- ===== Captura (rol ELEVADO) para P2/P3 (citas ajenas) =====
SELECT set_config('role', 'none', true);
SELECT set_config('probe.medico',
  (SELECT id FROM public.perfiles WHERE rol='medico' ORDER BY id LIMIT 1)::text, false);
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

SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.medico', true), 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);

-- P2 — médico cancela cita ajena vía RPC definer
DO $$ DECLARE v_cita BIGINT := NULLIF(current_setting('probe.cita_p2', true), '')::bigint;
BEGIN
  IF v_cita IS NULL THEN PERFORM set_config('probe.p2_err','NA',false);
  ELSE BEGIN
    PERFORM public.actualizar_estado_cita(v_cita, 'cancelada');  -- RPC bigint (Fase 3)
    PERFORM set_config('probe.p2_err','',false);
  EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.p2_err', SQLERRM, false); END; END IF;
END $$;

-- P3 — médico se autoasigna cita ajena vía RPC definer
DO $$ DECLARE v_cita BIGINT := NULLIF(current_setting('probe.cita_p3', true), '')::bigint;
BEGIN
  IF v_cita IS NULL THEN PERFORM set_config('probe.p3_err','NA',false);
  ELSE BEGIN
    PERFORM public.asignar_medico_cita(v_cita, auth.uid());  -- RPC bigint (Fase 3)
    PERFORM set_config('probe.p3_err','',false);
  EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.p3_err', SQLERRM, false); END; END IF;
END $$;

-- Verificación P2/P3 con rol ELEVADO (efecto real)
SELECT set_config('role', 'none', true);
DO $$
DECLARE v_cita2 BIGINT := NULLIF(current_setting('probe.cita_p2', true), '')::bigint;
        v_cita3 BIGINT := NULLIF(current_setting('probe.cita_p3', true), '')::bigint;
        v_med UUID := NULLIF(current_setting('probe.medico', true), '')::uuid;
        v_estado TEXT; v_medico_post UUID;
BEGIN
  IF v_cita2 IS NULL THEN PERFORM set_config('probe.p2','N/A (no hay cita ajena no-cancelada)',false);
  ELSE
    SELECT estado INTO v_estado FROM public.citas WHERE id = v_cita2;
    IF current_setting('probe.p2_err', true) NOT IN ('', 'NA') THEN
      PERFORM set_config('probe.p2','BLOQUEADO (RPC lanzó: '||current_setting('probe.p2_err', true)||')',false);
    ELSIF v_estado='cancelada' THEN PERFORM set_config('probe.p2','PERMITIDO (canceló cita ajena id='||v_cita2||')',false);
    ELSE PERFORM set_config('probe.p2','BLOQUEADO (no hubo efecto; estado quedó '||COALESCE(v_estado,'?')||')',false); END IF;
  END IF;
  IF v_cita3 IS NULL THEN PERFORM set_config('probe.p3','N/A (no hay segunda cita ajena)',false);
  ELSE
    SELECT medico_id INTO v_medico_post FROM public.citas WHERE id = v_cita3;
    IF current_setting('probe.p3_err', true) NOT IN ('', 'NA') THEN
      PERFORM set_config('probe.p3','BLOQUEADO (RPC lanzó: '||current_setting('probe.p3_err', true)||')',false);
    ELSIF v_medico_post = v_med THEN PERFORM set_config('probe.p3','PERMITIDO (se autoasignó cita ajena id='||v_cita3||')',false);
    ELSE PERFORM set_config('probe.p3','BLOQUEADO (no hubo efecto; medico_id no cambió)',false); END IF;
  END IF;
END $$;

-- ============================================================
-- FASE 2 · Aislamiento PHI por CITA (P7/P8/P11) + features (P9/P10)
--          + escritura a paciente ajeno (P12/P13) + paciente (P14)
-- ------------------------------------------------------------
-- Captura (ELEVADO): un médico CON cita, un paciente que atiende (cita),
-- un paciente AJENO (sin cita con él), y un paciente con receta_items.
-- ------------------------------------------------------------
SELECT set_config('probe.medico_cp',
  (SELECT medico_id::text FROM public.citas WHERE medico_id IS NOT NULL ORDER BY medico_id LIMIT 1), false);
SELECT set_config('probe.pac_de',
  (SELECT paciente_id::text FROM public.citas
     WHERE medico_id = NULLIF(current_setting('probe.medico_cp', true), '')::uuid
     ORDER BY paciente_id LIMIT 1), false);
SELECT set_config('probe.pac_ajeno',
  (SELECT id::text FROM public.pacientes
     WHERE id NOT IN (SELECT paciente_id FROM public.citas
                      WHERE medico_id = NULLIF(current_setting('probe.medico_cp', true), '')::uuid)
     ORDER BY id LIMIT 1), false);
SELECT set_config('probe.paciente_u',
  (SELECT p.auth_user_id::text FROM public.pacientes p
     JOIN public.recetas r ON r.paciente_id = p.id
     JOIN public.receta_items ri ON ri.receta_id = r.id
     WHERE p.auth_user_id IS NOT NULL LIMIT 1), false);

-- Simular al médico_cp
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.medico_cp', true), 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);

-- P7 — el médico NO debe ver historial de pacientes SIN cita con él
DO $$ DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.historial_medico h
   WHERE COALESCE(h.medico_id,'') <> auth.uid()::text
     AND ( h.paciente_id !~ '^[0-9]+$'
           OR ( h.paciente_id::bigint NOT IN (SELECT c.paciente_id FROM public.citas c WHERE c.medico_id = auth.uid())
                AND h.paciente_id::bigint NOT IN (SELECT p.id FROM public.pacientes p WHERE p.medico_id = auth.uid()) ) );
  IF n > 0 THEN PERFORM set_config('probe.p7','PERMITIDO (ve '||n||' historiales de pacientes sin cita)',false);
  ELSE PERFORM set_config('probe.p7','BLOQUEADO (0 historiales ajenos visibles)',false); END IF;
END $$;

-- P8 — el médico NO debe ver recetas_avanzadas de pacientes SIN cita
DO $$ DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.recetas_avanzadas r
   WHERE COALESCE(r.medico_id,'') <> auth.uid()::text
     AND ( r.paciente_id !~ '^[0-9]+$'
           OR ( r.paciente_id::bigint NOT IN (SELECT c.paciente_id FROM public.citas c WHERE c.medico_id = auth.uid())
                AND r.paciente_id::bigint NOT IN (SELECT p.id FROM public.pacientes p WHERE p.medico_id = auth.uid()) ) );
  IF n > 0 THEN PERFORM set_config('probe.p8','PERMITIDO (ve '||n||' recetas avanzadas de pacientes sin cita)',false);
  ELSE PERFORM set_config('probe.p8','BLOQUEADO (0 recetas avanzadas ajenas visibles)',false); END IF;
END $$;

-- P11 — el médico NO debe ver expediente de pacientes SIN cita
DO $$ DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.expediente_notas e
   WHERE e.medico_id IS DISTINCT FROM auth.uid()
     AND e.paciente_id NOT IN (SELECT c.paciente_id FROM public.citas c WHERE c.medico_id = auth.uid())
     AND e.paciente_id NOT IN (SELECT p.id FROM public.pacientes p WHERE p.medico_id = auth.uid());
  IF n > 0 THEN PERFORM set_config('probe.p11','PERMITIDO (ve '||n||' notas de pacientes sin cita)',false);
  ELSE PERFORM set_config('probe.p11','BLOQUEADO (0 notas ajenas visibles)',false); END IF;
END $$;

-- P9 — feature reparada: el médico SÍ inserta su nota para un paciente que ATIENDE
DO $$ DECLARE s TEXT; v BIGINT := NULLIF(current_setting('probe.pac_de', true), '')::bigint;
BEGIN
  IF v IS NULL THEN PERFORM set_config('probe.p9','N/A (médico sin cita-paciente)',false);
  ELSE BEGIN
    INSERT INTO public.expediente_notas (paciente_id, medico_id) VALUES (v::int, auth.uid());
    PERFORM set_config('probe.p9','OK (insertó su nota de expediente)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE; PERFORM set_config('probe.p9','BLOQUEADO ('||s||')',false); END; END IF;
END $$;

-- P10 — feature reparada: el médico SÍ inserta signos para un paciente que ATIENDE
DO $$ DECLARE s TEXT; v BIGINT := NULLIF(current_setting('probe.pac_de', true), '')::bigint;
BEGIN
  IF v IS NULL THEN PERFORM set_config('probe.p10','N/A (médico sin cita-paciente)',false);
  ELSE BEGIN
    INSERT INTO public.signos_vitales (paciente_id, medico_id) VALUES (v::int, auth.uid());
    PERFORM set_config('probe.p10','OK (insertó signos vitales)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE; PERFORM set_config('probe.p10','BLOQUEADO ('||s||')',false); END; END IF;
END $$;

-- P12 — el médico NO debe insertar historial para un paciente AJENO (sin cita)
DO $$ DECLARE s TEXT; v TEXT := NULLIF(current_setting('probe.pac_ajeno', true), '');
BEGIN
  IF v IS NULL THEN PERFORM set_config('probe.p12','N/A (no hay paciente ajeno)',false);
  ELSE BEGIN
    INSERT INTO public.historial_medico (paciente_id, medico_id) VALUES (v, auth.uid()::text);
    PERFORM set_config('probe.p12','PERMITIDO (insertó historial para paciente sin cita)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p12','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p12','PERMITIDO por RLS (falló otra constraint: '||s||')',false); END IF;
  END; END IF;
END $$;

-- P13 — el médico NO debe insertar nota de expediente para un paciente AJENO
DO $$ DECLARE s TEXT; v BIGINT := NULLIF(current_setting('probe.pac_ajeno', true), '')::bigint;
BEGIN
  IF v IS NULL THEN PERFORM set_config('probe.p13','N/A (no hay paciente ajeno)',false);
  ELSE BEGIN
    INSERT INTO public.expediente_notas (paciente_id, medico_id) VALUES (v::int, auth.uid());
    PERFORM set_config('probe.p13','PERMITIDO (insertó nota para paciente sin cita)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p13','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p13','BLOQUEADO (otra constraint: '||s||')',false); END IF;
  END; END IF;
END $$;

-- P15 — el médico NO debe ver citas de OTROS médicos (lectura scoped de citas)
DO $$ DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.citas c WHERE c.medico_id IS DISTINCT FROM auth.uid();
  IF n > 0 THEN PERFORM set_config('probe.p15','PERMITIDO (ve '||n||' citas ajenas)',false);
  ELSE PERFORM set_config('probe.p15','BLOQUEADO (0 citas ajenas visibles)',false); END IF;
END $$;

-- P14 — el paciente SÍ ve los items de SUS recetas (y NO los ajenos)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.paciente_u', true), 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE propios INT; ajenos INT;
BEGIN
  IF NULLIF(current_setting('probe.paciente_u', true), '') IS NULL THEN
    PERFORM set_config('probe.p14','N/A (sin paciente con receta_items)',false);
  ELSE
    SELECT count(*) INTO propios FROM public.receta_items ri
      WHERE ri.receta_id IN (SELECT r.id FROM public.recetas r JOIN public.pacientes p ON r.paciente_id=p.id WHERE p.auth_user_id=auth.uid());
    SELECT count(*) INTO ajenos FROM public.receta_items ri
      WHERE ri.receta_id NOT IN (SELECT r.id FROM public.recetas r JOIN public.pacientes p ON r.paciente_id=p.id WHERE p.auth_user_id=auth.uid());
    PERFORM set_config('probe.p14','ve '||propios||' propios / '||ajenos||' ajenos',false);
  END IF;
END $$;

-- P16 — el paciente NO debe ver citas de OTROS pacientes (lectura scoped de citas)
DO $$ DECLARE n INT;
BEGIN
  IF NULLIF(current_setting('probe.paciente_u', true), '') IS NULL THEN
    PERFORM set_config('probe.p16','N/A (sin paciente)',false);
  ELSE
    SELECT count(*) INTO n FROM public.citas c
     WHERE c.paciente_id NOT IN (SELECT p.id FROM public.pacientes p WHERE p.auth_user_id = auth.uid());
    IF n > 0 THEN PERFORM set_config('probe.p16','PERMITIDO (ve '||n||' citas ajenas)',false);
    ELSE PERFORM set_config('probe.p16','BLOQUEADO (0 citas ajenas visibles)',false); END IF;
  END IF;
END $$;

-- P17 — el paciente NO puede crear su cita ya 'agendada' (crear_cita fuerza 'solicitada').
-- Usa ::int para que la llamada resuelva pre-071 (integer) y post-071 (bigint).
DO $$ DECLARE v_pac BIGINT; v_id BIGINT; v_estado TEXT;
BEGIN
  v_pac := (SELECT id FROM public.pacientes WHERE auth_user_id = auth.uid() LIMIT 1);
  IF v_pac IS NULL THEN PERFORM set_config('probe.p17','N/A (sin paciente)',false);
  ELSE BEGIN
    v_id := public.crear_cita(v_pac::int, NULL, NULL, CURRENT_DATE, '06:00'::time, '06:15'::time, 'probe', NULL, 'agendada', NULL);
    SELECT estado INTO v_estado FROM public.citas WHERE id = v_id;
    IF v_estado = 'solicitada' THEN
      PERFORM set_config('probe.p17','BLOQUEADO (forzó solicitada, ignoró agendada)',false);
    ELSE
      PERFORM set_config('probe.p17','PERMITIDO (paciente creó en estado '||COALESCE(v_estado,'?')||')',false);
    END IF;
  EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.p17','N/A (crear_cita lanzó: '||SQLERRM||')',false); END;
  END IF;
END $$;

-- P18 — un authenticated NO-admin NO debe poder asociar un médico a una clínica ajena
SELECT set_config('role', 'none', true);
SELECT set_config('probe.clin_x', (SELECT id::text FROM public.clinicas ORDER BY id LIMIT 1), false);
SELECT set_config('probe.med_x',  (SELECT id::text FROM public.perfiles WHERE rol='medico' ORDER BY id DESC LIMIT 1), false);
-- atacante: un médico cualquiera (no admin de clin_x)
SELECT set_config('request.jwt.claims',
  json_build_object('sub', (SELECT id FROM public.perfiles WHERE rol='medico' ORDER BY id LIMIT 1), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE s TEXT;
BEGIN
  BEGIN
    PERFORM public.asociar_medico_clinica(
      NULLIF(current_setting('probe.med_x', true), '')::uuid,
      NULLIF(current_setting('probe.clin_x', true), '')::uuid, false);
    PERFORM set_config('probe.p18','PERMITIDO (asoció médico a clínica ajena)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p18','BLOQUEADO (permiso/autorización: 42501)',false);
    ELSE PERFORM set_config('probe.p18','BLOQUEADO ('||s||')',false); END IF;
  END;
END $$;

-- P19 — flujo: un médico MIEMBRO de una clínica NO es admin de ella (gate que usa
-- crear-staff-clinica: rol admin_clinica/gerente + pertenencia). Debe rechazar.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.med_mem',
  (SELECT mc.medico_id::text FROM public.medico_clinicas mc JOIN public.perfiles p ON p.id=mc.medico_id
   WHERE p.rol='medico' ORDER BY mc.medico_id, mc.clinica_id LIMIT 1), false);
SELECT set_config('probe.clin_mem',
  (SELECT mc.clinica_id::text FROM public.medico_clinicas mc JOIN public.perfiles p ON p.id=mc.medico_id
   WHERE p.rol='medico' ORDER BY mc.medico_id, mc.clinica_id LIMIT 1), false);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.med_mem', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE es_admin BOOLEAN;
BEGIN
  IF NULLIF(current_setting('probe.med_mem', true), '') IS NULL THEN
    PERFORM set_config('probe.p19','N/A (sin médico miembro)',false);
  ELSE
    es_admin := private.es_admin_clinica(NULLIF(current_setting('probe.clin_mem', true), '')::uuid);
    IF es_admin THEN PERFORM set_config('probe.p19','PERMITIDO (médico miembro cuenta como admin!)',false);
    ELSE PERFORM set_config('probe.p19','BLOQUEADO (médico miembro NO es admin → no crea staff)',false); END IF;
  END IF;
END $$;

-- ============================================================
-- FASE 4 · tablas abiertas
-- ============================================================
-- P20 — anon NO debe poder ESCRIBIR en medicos (insert; cubre el CRUD cerrado).
-- (DELETE/UPDATE quedan cerrados por el mismo DROP de medicos_insert/update/delete;
--  insert se prueba con el patrón 42501, sin ruido de FK.)
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$ DECLARE s TEXT;
BEGIN
  BEGIN INSERT INTO public.medicos DEFAULT VALUES;
    PERFORM set_config('probe.p20','PERMITIDO (insertó médico)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p20','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p20','PERMITIDO por RLS (otra constraint: '||s||')',false); END IF;
  END;
END $$;

-- P21 — un authenticated común (médico) NO debe escribir medicamentos
SELECT set_config('request.jwt.claims',
  json_build_object('sub', (SELECT id FROM public.perfiles WHERE rol='medico' ORDER BY id LIMIT 1), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE s TEXT;
BEGIN
  BEGIN INSERT INTO public.medicamentos DEFAULT VALUES;
    PERFORM set_config('probe.p21','PERMITIDO (insertó medicamento)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p21','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p21','PERMITIDO por RLS (otra constraint: '||s||')',false); END IF;
  END;
END $$;

-- P22 — un authenticated común (médico) NO debe escribir farmacias
DO $$ DECLARE s TEXT;
BEGIN
  BEGIN INSERT INTO public.farmacias DEFAULT VALUES;
    PERFORM set_config('probe.p22','PERMITIDO (insertó farmacia)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;
    IF s='42501' THEN PERFORM set_config('probe.p22','BLOQUEADO (RLS rechazó: 42501)',false);
    ELSE PERFORM set_config('probe.p22','PERMITIDO por RLS (otra constraint: '||s||')',false); END IF;
  END;
END $$;

-- P23 — anon NO debe leer cuentas_bancarias_pais
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$ DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM public.cuentas_bancarias_pais;
  IF n > 0 THEN PERFORM set_config('probe.p23','PERMITIDO (anon ve '||n||' cuentas bancarias)',false);
  ELSE PERFORM set_config('probe.p23','BLOQUEADO (0 cuentas visibles)',false); END IF;
END $$;

-- P25 — anon NO debe leer PII de medicos (cédula). Hoy lee; post = sin acceso a la columna.
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$ DECLARE s TEXT; n INT;
BEGIN
  BEGIN
    SELECT count(cedula_profesional) INTO n FROM public.medicos;
    PERFORM set_config('probe.p25','PERMITIDO (anon lee cédula de '||n||' médicos)',false);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE;
    PERFORM set_config('probe.p25','BLOQUEADO (sin acceso a la columna PII: '||s||')',false);
  END;
END $$;

-- P24 — POSITIVO: un usuario autenticado de país X SÍ ve la cuenta de su país (checkout legítimo)
SELECT set_config('role', 'none', true);
SELECT set_config('probe.user_px',
  (SELECT id::text FROM public.cuentas_proveedor
    WHERE pais_id = (SELECT pais_id FROM public.cuentas_bancarias_pais WHERE activo=true LIMIT 1) LIMIT 1), false);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.user_px', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT;
BEGIN
  IF NULLIF(current_setting('probe.user_px', true), '') IS NULL THEN
    PERFORM set_config('probe.p24','N/A (sin proveedor de ese país)',false);
  ELSE
    SELECT count(*) INTO n FROM public.cuentas_bancarias_pais;  -- la política limita a mi_pais()
    IF n > 0 THEN PERFORM set_config('probe.p24','OK (ve '||n||' cuenta(s) de su país)',false);
    ELSE PERFORM set_config('probe.p24','REGRESIÓN (no ve la cuenta de su país)',false); END IF;
  END IF;
END $$;

-- ===== Veredictos como result set =====
SELECT 'P1_anon_insert_citas'              AS probe, current_setting('probe.p1', true)  AS verdict, 'BLOQUEADO' AS esperado_post_fix
UNION ALL SELECT 'P2_medico_cancela_ajena_rpc',         current_setting('probe.p2', true),  'BLOQUEADO'
UNION ALL SELECT 'P3_medico_roba_cita_rpc',             current_setting('probe.p3', true),  'BLOQUEADO'
UNION ALL SELECT 'P4_anon_insert_notificaciones',       current_setting('probe.p4', true),  'BLOQUEADO'
UNION ALL SELECT 'P5_anon_insert_cuentas_proveedor',    current_setting('probe.p5', true),  'BLOQUEADO'
UNION ALL SELECT 'P6_anon_insert_empresas_proveedoras', current_setting('probe.p6', true),  'BLOQUEADO'
UNION ALL SELECT 'P7_medico_ve_historial_sin_cita',     current_setting('probe.p7', true),  'BLOQUEADO'
UNION ALL SELECT 'P8_medico_ve_recetas_adv_sin_cita',   current_setting('probe.p8', true),  'BLOQUEADO'
UNION ALL SELECT 'P11_medico_ve_expediente_sin_cita',   current_setting('probe.p11', true), 'BLOQUEADO'
UNION ALL SELECT 'P9_medico_inserta_expediente_propio', current_setting('probe.p9', true),  'OK'
UNION ALL SELECT 'P10_medico_inserta_signos_propio',    current_setting('probe.p10', true), 'OK'
UNION ALL SELECT 'P12_medico_inserta_historial_ajeno',  current_setting('probe.p12', true), 'BLOQUEADO'
UNION ALL SELECT 'P13_medico_inserta_expediente_ajeno', current_setting('probe.p13', true), 'BLOQUEADO'
UNION ALL SELECT 'P14_paciente_ve_sus_receta_items',    current_setting('probe.p14', true), '>0 propios / 0 ajenos'
UNION ALL SELECT 'P15_medico_ve_citas_ajenas',          current_setting('probe.p15', true), 'BLOQUEADO'
UNION ALL SELECT 'P16_paciente_ve_citas_ajenas',        current_setting('probe.p16', true), 'BLOQUEADO'
UNION ALL SELECT 'P17_paciente_no_crea_agendada',       current_setting('probe.p17', true), 'BLOQUEADO'
UNION ALL SELECT 'P18_authn_asocia_medico_clinica',     current_setting('probe.p18', true), 'BLOQUEADO'
UNION ALL SELECT 'P19_medico_miembro_no_es_admin',      current_setting('probe.p19', true), 'BLOQUEADO'
UNION ALL SELECT 'P20_anon_escribe_medicos',            current_setting('probe.p20', true), 'BLOQUEADO'
UNION ALL SELECT 'P21_authn_escribe_medicamentos',      current_setting('probe.p21', true), 'BLOQUEADO'
UNION ALL SELECT 'P22_authn_escribe_farmacias',         current_setting('probe.p22', true), 'BLOQUEADO'
UNION ALL SELECT 'P23_anon_lee_cuentas_bancarias',      current_setting('probe.p23', true), 'BLOQUEADO'
UNION ALL SELECT 'P25_anon_lee_pii_medicos',            current_setting('probe.p25', true), 'BLOQUEADO'
UNION ALL SELECT 'P24_proveedor_ve_cuenta_su_pais',     current_setting('probe.p24', true), 'OK (>0)';

ROLLBACK;  -- nada de lo anterior se persiste
