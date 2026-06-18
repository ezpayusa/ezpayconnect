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

-- ============================================================
-- FASE 5 · Storage (acceso al objeto = poder firmar la URL). storage.objects RLS.
-- ============================================================
-- Captura (ELEVADO): el examen vinculado al objeto de resultados y sus actores.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.res_pac_auth',
  (SELECT p.auth_user_id::text FROM public.pacientes p
    WHERE p.id = (SELECT e.paciente_id FROM public.examenes e
                  JOIN storage.objects o ON COALESCE(NULLIF(split_part(e.archivo_url,'/resultados-examenes/',2),''), e.archivo_url) = o.name
                  WHERE o.bucket_id='resultados-examenes' LIMIT 1)), false);
SELECT set_config('probe.res_med',
  (SELECT e.medico_id::text FROM public.examenes e
    JOIN storage.objects o ON COALESCE(NULLIF(split_part(e.archivo_url,'/resultados-examenes/',2),''), e.archivo_url) = o.name
    WHERE o.bucket_id='resultados-examenes' LIMIT 1), false);
SELECT set_config('probe.res_med_ajeno',
  (SELECT id::text FROM public.perfiles
    WHERE rol='medico' AND id <> NULLIF(current_setting('probe.res_med', true),'')::uuid ORDER BY id LIMIT 1), false);

-- P26 — anon NO accede a un resultado de examen (no puede ver el objeto → no firma)
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$ DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='resultados-examenes';
  IF n > 0 THEN PERFORM set_config('probe.p26','PERMITIDO (anon ve '||n||' objeto(s) de resultados)',false);
  ELSE PERFORM set_config('probe.p26','BLOQUEADO (0 objetos visibles)',false); END IF;
END $$;

-- P27 — un médico AJENO (no ordenó, no atiende, no es el lab) NO accede al resultado
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.res_med_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT;
BEGIN
  IF NULLIF(current_setting('probe.res_med_ajeno', true), '') IS NULL THEN PERFORM set_config('probe.p27','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='resultados-examenes';
    IF n > 0 THEN PERFORM set_config('probe.p27','PERMITIDO (médico ajeno ve '||n||' objeto(s))',false);
    ELSE PERFORM set_config('probe.p27','BLOQUEADO (0 objetos visibles)',false); END IF;
  END IF;
END $$;

-- P28 — POSITIVO: el paciente DUEÑO del examen SÍ accede a su resultado
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.res_pac_auth', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT;
BEGIN
  IF NULLIF(current_setting('probe.res_pac_auth', true), '') IS NULL THEN PERFORM set_config('probe.p28','N/A (paciente sin auth)',false);
  ELSE
    SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='resultados-examenes';
    IF n > 0 THEN PERFORM set_config('probe.p28','OK (ve '||n||' objeto(s) de su examen)',false);
    ELSE PERFORM set_config('probe.p28','REGRESIÓN (no ve su propio resultado)',false); END IF;
  END IF;
END $$;

-- P29 — POSITIVO: el médico que ORDENÓ el examen SÍ accede a su resultado
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.res_med', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT;
BEGIN
  IF NULLIF(current_setting('probe.res_med', true), '') IS NULL THEN PERFORM set_config('probe.p29','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='resultados-examenes';
    IF n > 0 THEN PERFORM set_config('probe.p29','OK (ve '||n||' objeto(s) de su examen)',false);
    ELSE PERFORM set_config('probe.p29','REGRESIÓN (no ve el resultado que ordenó)',false); END IF;
  END IF;
END $$;

-- ---- Comprobantes (financiero): aislamiento por empresa ----
-- Captura (ELEVADO): un comprobante concreto + su proveedor dueño y uno ajeno.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.comp_obj',
  (SELECT name FROM storage.objects WHERE bucket_id='comprobantes' ORDER BY name LIMIT 1), false);
SELECT set_config('probe.comp_dueno',
  (SELECT cp.id::text FROM public.cuentas_proveedor cp
    WHERE cp.activo AND cp.empresa_id = split_part(current_setting('probe.comp_obj', true),'/',1)::uuid
    ORDER BY cp.id LIMIT 1), false);
SELECT set_config('probe.comp_ajeno',
  (SELECT cp.id::text FROM public.cuentas_proveedor cp
    WHERE cp.activo AND cp.empresa_id <> split_part(current_setting('probe.comp_obj', true),'/',1)::uuid
    ORDER BY cp.id LIMIT 1), false);

-- P30 — anon NO lee un comprobante
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$ DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM storage.objects
    WHERE bucket_id='comprobantes' AND name = current_setting('probe.comp_obj', true);
  IF n > 0 THEN PERFORM set_config('probe.p30','PERMITIDO (anon ve el comprobante)',false);
  ELSE PERFORM set_config('probe.p30','BLOQUEADO (0)',false); END IF;
END $$;

-- P31 — un proveedor de OTRA empresa NO lee el comprobante ajeno
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.comp_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT;
BEGIN
  IF NULLIF(current_setting('probe.comp_ajeno', true), '') IS NULL THEN PERFORM set_config('probe.p31','N/A (sin proveedor ajeno)',false);
  ELSE
    SELECT count(*) INTO n FROM storage.objects
      WHERE bucket_id='comprobantes' AND name = current_setting('probe.comp_obj', true);
    IF n > 0 THEN PERFORM set_config('probe.p31','PERMITIDO (proveedor ajeno ve el comprobante)',false);
    ELSE PERFORM set_config('probe.p31','BLOQUEADO (0)',false); END IF;
  END IF;
END $$;

-- P32 — POSITIVO: el proveedor DUEÑO SÍ lee su comprobante
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.comp_dueno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT;
BEGIN
  IF NULLIF(current_setting('probe.comp_dueno', true), '') IS NULL THEN PERFORM set_config('probe.p32','N/A (sin proveedor dueño)',false);
  ELSE
    SELECT count(*) INTO n FROM storage.objects
      WHERE bucket_id='comprobantes' AND name = current_setting('probe.comp_obj', true);
    IF n > 0 THEN PERFORM set_config('probe.p32','OK (ve su comprobante)',false);
    ELSE PERFORM set_config('probe.p32','REGRESIÓN (no ve su propio comprobante)',false); END IF;
  END IF;
END $$;

-- ---- ESCRITURA NEGATIVA/POSITIVA: nadie escribe en folder de otra empresa ----
-- Verifica empíricamente el fix del punto 2 (INSERT/UPDATE scoped) en AMBOS buckets.
-- Captura (ELEVADO): el lab del examen de resultados y su usuario.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.res_lab_emp',
  (SELECT e.laboratorio_id::text FROM public.examenes e
    JOIN storage.objects o ON COALESCE(NULLIF(split_part(e.archivo_url,'/resultados-examenes/',2),''), e.archivo_url) = o.name
    WHERE o.bucket_id='resultados-examenes' LIMIT 1), false);
SELECT set_config('probe.res_lab_uid',
  (SELECT cp.id::text FROM public.cuentas_proveedor cp
    WHERE cp.activo AND cp.empresa_id = NULLIF(current_setting('probe.res_lab_emp', true),'')::uuid
    ORDER BY cp.id LIMIT 1), false);

-- P33 — NEGATIVA: proveedor AJENO NO sube/sobrescribe en el folder de OTRA empresa (comprobantes)
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.comp_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$
BEGIN
  INSERT INTO storage.objects(bucket_id, name, owner)
    VALUES ('comprobantes', split_part(current_setting('probe.comp_obj', true),'/',1)||'/__probe_ajeno.txt',
            current_setting('probe.comp_ajeno', true)::uuid);
  PERFORM set_config('probe.p33','PERMITIDO (escribió en folder ajeno!)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p33','BLOQUEADO (RLS rechazó: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p33','BLOQUEADO? (otro error: '||SQLSTATE||')',false);
END $$;

-- P34 — POSITIVA: proveedor DUEÑO SÍ sube a SU propio folder (comprobantes)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.comp_dueno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$
BEGIN
  INSERT INTO storage.objects(bucket_id, name, owner)
    VALUES ('comprobantes', split_part(current_setting('probe.comp_obj', true),'/',1)||'/__probe_dueno.txt',
            current_setting('probe.comp_dueno', true)::uuid);
  PERFORM set_config('probe.p34','OK (subió a su propio folder)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p34','REGRESIÓN (no pudo subir a su folder: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p34','REGRESIÓN? (otro error: '||SQLSTATE||')',false);
END $$;

-- P35 — NEGATIVA: un proveedor AJENO NO sube en el folder del LABORATORIO (resultados)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.comp_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$
BEGIN
  IF NULLIF(current_setting('probe.res_lab_emp', true),'') IS NULL THEN PERFORM set_config('probe.p35','N/A',false);
  ELSE
    INSERT INTO storage.objects(bucket_id, name, owner)
      VALUES ('resultados-examenes', current_setting('probe.res_lab_emp', true)||'/__probe_ajeno.txt',
              current_setting('probe.comp_ajeno', true)::uuid);
    PERFORM set_config('probe.p35','PERMITIDO (escribió resultado en folder de lab ajeno!)',false);
  END IF;
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p35','BLOQUEADO (RLS rechazó: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p35','BLOQUEADO? (otro error: '||SQLSTATE||')',false);
END $$;

-- P36 — POSITIVA: el LABORATORIO dueño SÍ sube a SU propio folder (resultados, upload legítimo)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.res_lab_uid', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$
BEGIN
  IF NULLIF(current_setting('probe.res_lab_uid', true),'') IS NULL THEN PERFORM set_config('probe.p36','N/A (lab sin usuario)',false);
  ELSE
    INSERT INTO storage.objects(bucket_id, name, owner)
      VALUES ('resultados-examenes', current_setting('probe.res_lab_emp', true)||'/__probe_lab.txt',
              current_setting('probe.res_lab_uid', true)::uuid);
    PERFORM set_config('probe.p36','OK (lab subió a su propio folder)',false);
  END IF;
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p36','REGRESIÓN (lab no pudo subir a su folder: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p36','REGRESIÓN? (otro error: '||SQLSTATE||')',false);
END $$;

-- ============================================================
-- PASADA DEFINER · funciones SECURITY DEFINER con revalidación del caller
-- ============================================================
-- Captura (ELEVADO) de actores reales.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.sa',
  (SELECT id::text FROM public.perfiles WHERE rol='super_admin' ORDER BY id LIMIT 1), false);
SELECT set_config('probe.np_pac',
  (SELECT c.paciente_id::text FROM public.citas c WHERE c.medico_id IS NOT NULL ORDER BY c.id LIMIT 1), false);
SELECT set_config('probe.np_medico',  -- médico que SÍ atiende a ese paciente
  (SELECT c.medico_id::text FROM public.citas c WHERE c.medico_id IS NOT NULL ORDER BY c.id LIMIT 1), false);
SELECT set_config('probe.np_ajeno',   -- médico SIN cita con ese paciente
  (SELECT m.id::text FROM public.perfiles m WHERE m.rol='medico'
     AND NOT EXISTS (SELECT 1 FROM public.citas c2 WHERE c2.medico_id=m.id
        AND c2.paciente_id = NULLIF(current_setting('probe.np_pac', true),'')::bigint)
     ORDER BY m.id LIMIT 1), false);
SELECT set_config('probe.nl_lab',
  (SELECT e.laboratorio_id::text FROM public.examenes e WHERE e.laboratorio_id IS NOT NULL AND e.medico_id IS NOT NULL ORDER BY e.id LIMIT 1), false);
SELECT set_config('probe.nl_medico', -- médico que ordenó a ese lab
  (SELECT e.medico_id::text FROM public.examenes e WHERE e.laboratorio_id IS NOT NULL AND e.medico_id IS NOT NULL ORDER BY e.id LIMIT 1), false);
SELECT set_config('probe.av_visita',
  (SELECT v.id::text FROM public.visitas_agendadas v WHERE v.medico_id IS NOT NULL ORDER BY v.id LIMIT 1), false);
SELECT set_config('probe.av_medico', -- médico de esa visita (parte VISITADA, no aprueba)
  (SELECT v.medico_id::text FROM public.visitas_agendadas v WHERE v.medico_id IS NOT NULL ORDER BY v.id LIMIT 1), false);
SELECT set_config('probe.av_emp_member', -- miembro proveedor de la empresa de la visita (aprobador legítimo)
  (SELECT cp.id::text FROM public.cuentas_proveedor cp WHERE cp.activo
     AND cp.empresa_id = (SELECT v.empresa_id FROM public.visitas_agendadas v WHERE v.medico_id IS NOT NULL ORDER BY v.id LIMIT 1)
     ORDER BY cp.id LIMIT 1), false);
-- "ajeno universal" para notif lab y visita: el médico que atiende al paciente np_pac
-- (no es miembro del lab nl_lab ni parte de la visita av_visita).
SELECT set_config('probe.ajeno', current_setting('probe.np_medico', true), false);

-- P37 — promo: anon NO dispara broadcast masivo
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$ BEGIN
  PERFORM public.enviar_notificacion_promocion('__probe_promo','__probe_promo','general');
  PERFORM set_config('probe.p37','PERMITIDO (anon disparó broadcast)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p37','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p37','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P38 — promo: un médico (authenticated, no super_admin) NO dispara broadcast
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.enviar_notificacion_promocion('__probe_promo2','__probe_promo2','general');
  PERFORM set_config('probe.p38','PERMITIDO (médico disparó broadcast)',false);
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p38','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P39 — promo POSITIVO: super_admin SÍ dispara el broadcast
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.enviar_notificacion_promocion('__probe_promo_sa','__probe_promo_sa','general');
  PERFORM set_config('probe.p39_err','',false);
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p39_err', SQLSTATE, false);
END $$;
-- Verificación del efecto en rol ELEVADO (la RLS de notificaciones_pacientes
-- ocultaría las filas si se contara como el propio super_admin authenticated).
SELECT set_config('role', 'none', true);
DO $$ DECLARE n INT; BEGIN
  IF NULLIF(current_setting('probe.p39_err', true),'') IS NOT NULL THEN
    PERFORM set_config('probe.p39','REGRESIÓN (lanzó '||current_setting('probe.p39_err', true)||')',false);
  ELSE
    SELECT count(*) INTO n FROM public.notificaciones_pacientes WHERE titulo='__probe_promo_sa';
    IF n > 0 THEN PERFORM set_config('probe.p39','OK (broadcast a '||n||' pacientes)',false);
    ELSE PERFORM set_config('probe.p39','REGRESIÓN (no insertó)',false); END IF;
  END IF;
END $$;

-- P40 — notificar_paciente: médico AJENO (sin cita con el paciente) NO notifica
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.np_ajeno', true),'') IS NULL THEN PERFORM set_config('probe.p40','N/A',false);
  ELSE
    PERFORM public.notificar_paciente(NULLIF(current_setting('probe.np_pac', true),'')::int,'cita','__p','m','/x');
    PERFORM set_config('probe.p40','PERMITIDO (notificó a paciente ajeno)',false);
  END IF;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p40','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P41 — notificar_paciente POSITIVO: el médico que lo atiende SÍ notifica
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE v INT; BEGIN
  v := public.notificar_paciente(NULLIF(current_setting('probe.np_pac', true),'')::int,'cita','__p_ok','m','/x');
  IF v IS NOT NULL THEN PERFORM set_config('probe.p41','OK (notificó id '||v||')',false);
  ELSE PERFORM set_config('probe.p41','REGRESIÓN (no devolvió id)',false); END IF;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p41','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P42 — notificar_laboratorio: un médico AJENO al lab (no le ordenó) NO notifica
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.nl_lab', true),'') IS NULL THEN PERFORM set_config('probe.p42','N/A',false);
  ELSE
    PERFORM public.notificar_laboratorio(current_setting('probe.nl_lab', true)::uuid,'orden_examen','__l','m','/x');
    PERFORM set_config('probe.p42','PERMITIDO (notificó a lab ajeno)',false);
  END IF;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p42','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P43 — notificar_laboratorio POSITIVO: el médico que ordenó a ese lab SÍ notifica
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.nl_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE arr uuid[]; BEGIN
  arr := public.notificar_laboratorio(current_setting('probe.nl_lab', true)::uuid,'orden_examen','__l_ok','m','/x');
  IF array_length(arr,1) >= 1 THEN PERFORM set_config('probe.p43','OK (notificó '||array_length(arr,1)||' cuenta(s))',false);
  ELSE PERFORM set_config('probe.p43','OK (lab sin cuentas activas, pero autorizó)',false); END IF;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p43','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P44 — administrar_visita: un ajeno (ni médico de la visita ni su empresa) NO la administra
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE r jsonb; BEGIN
  IF NULLIF(current_setting('probe.av_visita', true),'') IS NULL THEN PERFORM set_config('probe.p44','N/A (sin visitas)',false);
  ELSE
    r := public.administrar_visita(current_setting('probe.av_visita', true)::uuid,'rechazar',NULL,NULL,NULL,'__probe');
    IF r ? 'success' THEN PERFORM set_config('probe.p44','PERMITIDO (administró visita ajena)',false);
    ELSE PERFORM set_config('probe.p44','BLOQUEADO? (devolvió: '||r::text||')',false); END IF;
  END IF;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p44','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P45 — administrar_visita POSITIVO: un miembro de la empresa proveedora SÍ la administra
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.av_emp_member', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE r jsonb; BEGIN
  IF NULLIF(current_setting('probe.av_emp_member', true),'') IS NULL THEN PERFORM set_config('probe.p45','N/A (empresa sin proveedor activo)',false);
  ELSE
    r := public.administrar_visita(current_setting('probe.av_visita', true)::uuid,'rechazar',NULL,NULL,NULL,'__probe_ok');
    IF r ? 'success' THEN PERFORM set_config('probe.p45','OK (proveedor administró su visita)',false);
    ELSE PERFORM set_config('probe.p45','REGRESIÓN (devolvió: '||r::text||')',false); END IF;
  END IF;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p45','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P46 — notificar_paciente POSITIVO: STAFF de clínica (rama "clínica" de la regla,
--   cubre useClinicaCitas). Staff miembro de una clínica con cita del paciente,
--   que NO es el médico de la cita ni lo atiende → solo pasa por la rama staff.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.cs_pac', (
  SELECT c.paciente_id::text FROM public.citas c
  JOIN public.medico_clinicas staff ON staff.clinica_id = c.clinica_id
  WHERE c.clinica_id IS NOT NULL AND staff.medico_id <> c.medico_id
    AND NOT EXISTS (SELECT 1 FROM public.citas c2 WHERE c2.medico_id=staff.medico_id AND c2.paciente_id=c.paciente_id)
  ORDER BY c.id LIMIT 1), false);
SELECT set_config('probe.cs_staff', (
  SELECT staff.medico_id::text FROM public.citas c
  JOIN public.medico_clinicas staff ON staff.clinica_id = c.clinica_id
  WHERE c.clinica_id IS NOT NULL AND staff.medico_id <> c.medico_id
    AND NOT EXISTS (SELECT 1 FROM public.citas c2 WHERE c2.medico_id=staff.medico_id AND c2.paciente_id=c.paciente_id)
  ORDER BY c.id LIMIT 1), false);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.cs_staff', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE v INT; BEGIN
  IF NULLIF(current_setting('probe.cs_staff', true),'') IS NULL THEN PERFORM set_config('probe.p46','N/A (sin staff candidato)',false);
  ELSE
    v := public.notificar_paciente(NULLIF(current_setting('probe.cs_pac', true),'')::int,'cita','__p_staff','m','/x');
    IF v IS NOT NULL THEN PERFORM set_config('probe.p46','OK (staff notificó id '||v||')',false);
    ELSE PERFORM set_config('probe.p46','REGRESIÓN (no devolvió id)',false); END IF;
  END IF;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.p46','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- ============================================================
-- FASE 6 · roles alineados al catálogo + FK anti fail-open
-- ============================================================
-- P47 — POSITIVO: super_admin (rol admin real) ve un recurso admin-gated
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.cuentas_proveedor;  -- política admin → super_admin ve todas
  IF n > 0 THEN PERFORM set_config('probe.p47','OK (super_admin ve '||n||' cuentas)',false);
  ELSE PERFORM set_config('probe.p47','REGRESIÓN (super_admin no ve nada)',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p47','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P48 — NEGATIVO: no se puede asignar un rol FUERA del catálogo (cierra el fail-open)
SELECT set_config('role', 'none', true);
SELECT set_config('probe.fk_target', (SELECT id::text FROM public.perfiles ORDER BY id LIMIT 1), false);
DO $$ BEGIN
  UPDATE public.perfiles SET rol='admin' WHERE id = current_setting('probe.fk_target', true)::uuid;
  PERFORM set_config('probe.p48','PERMITIDO (asignó rol fuera del catálogo)',false);
EXCEPTION
  WHEN foreign_key_violation THEN PERFORM set_config('probe.p48','BLOQUEADO (FK rechazó: 23503)',false);
  WHEN others THEN PERFORM set_config('probe.p48','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P49 — POSITIVO: un rol VÁLIDO del catálogo sí se asigna
SELECT set_config('role', 'none', true);
DO $$ BEGIN
  UPDATE public.perfiles SET rol='gerente' WHERE id = current_setting('probe.fk_target', true)::uuid;
  PERFORM set_config('probe.p49','OK (asignó rol válido del catálogo)',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.p49','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- ---- Remapeo a super_admin (farmacia_medicamentos / reportes_guardados) ----
-- Trick 42501: RLS WITH CHECK se evalúa ANTES que NOT NULL → 42501 = RLS bloqueó;
-- otro SQLSTATE (o éxito) = RLS permitió (solo faltó dato de prueba).
-- P50 — super_admin SÍ edita farmacia_medicamentos
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.farmacia_medicamentos DEFAULT VALUES;
  PERFORM set_config('probe.p50','OK (RLS permitió el INSERT)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p50','REGRESIÓN (RLS bloqueó a super_admin: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p50','OK (RLS permitió; faltó dato: '||SQLSTATE||')',false);
END $$;

-- P51 — un no-super_admin (médico) NO edita farmacia_medicamentos
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.farmacia_medicamentos DEFAULT VALUES;
  PERFORM set_config('probe.p51','PERMITIDO (médico editó farmacia!)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p51','BLOQUEADO (RLS: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p51','PERMITIDO? (RLS dejó pasar: '||SQLSTATE||')',false);
END $$;

-- P52 — super_admin SÍ crea reportes_guardados
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.reportes_guardados DEFAULT VALUES;
  PERFORM set_config('probe.p52','OK (RLS permitió el INSERT)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p52','REGRESIÓN (RLS bloqueó a super_admin: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p52','OK (RLS permitió; faltó dato: '||SQLSTATE||')',false);
END $$;

-- P53 — un no-super_admin (médico) NO crea reportes_guardados
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.reportes_guardados DEFAULT VALUES;
  PERFORM set_config('probe.p53','PERMITIDO (médico creó reporte!)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p53','BLOQUEADO (RLS: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p53','PERMITIDO? (RLS dejó pasar: '||SQLSTATE||')',false);
END $$;

-- P54 — POSITIVO: super_admin VE reportes_guardados sin error
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.reportes_guardados;
  PERFORM set_config('probe.p54','OK (super_admin ve reportes, n='||n||')',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.p54','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- ============================================================
-- INCREMENTO 0 (paneles) · cerrar huecos planes_asignaciones + campanas + tipo
-- ============================================================
-- Captura (ELEVADO) de actores reales.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.asig_emp',
  (SELECT id::text FROM public.planes_asignaciones WHERE empresa_id IS NOT NULL ORDER BY id LIMIT 1), false);
SELECT set_config('probe.asig_emp_owner',
  (SELECT cp.id::text FROM public.cuentas_proveedor cp WHERE cp.activo
     AND cp.empresa_id = (SELECT empresa_id FROM public.planes_asignaciones WHERE empresa_id IS NOT NULL ORDER BY id LIMIT 1)
     ORDER BY cp.id LIMIT 1), false);
SELECT set_config('probe.asig_emp_ajeno',
  (SELECT cp.id::text FROM public.cuentas_proveedor cp WHERE cp.activo
     AND cp.empresa_id <> (SELECT empresa_id FROM public.planes_asignaciones WHERE empresa_id IS NOT NULL ORDER BY id LIMIT 1)
     ORDER BY cp.id LIMIT 1), false);
SELECT set_config('probe.asig_med',
  (SELECT id::text FROM public.planes_asignaciones WHERE medico_id IS NOT NULL ORDER BY id LIMIT 1), false);
SELECT set_config('probe.asig_med_owner',
  (SELECT medico_id::text FROM public.planes_asignaciones WHERE medico_id IS NOT NULL ORDER BY id LIMIT 1), false);
SELECT set_config('probe.solicitud',
  (SELECT id::text FROM public.solicitudes_campana ORDER BY id LIMIT 1), false);
SELECT set_config('probe.campana',
  (SELECT id::text FROM public.campanas_publicitarias ORDER BY id LIMIT 1), false);
SELECT set_config('probe.emp_target',
  (SELECT id::text FROM public.empresas_proveedoras ORDER BY id LIMIT 1), false);
SELECT set_config('probe.forge_emp',  -- una empresa ajena al médico, para intentar forjarla
  (SELECT empresa_id::text FROM public.planes_asignaciones WHERE empresa_id IS NOT NULL ORDER BY id LIMIT 1), false);

-- P55 — NEG: un proveedor AJENO NO ve la asignación de otra empresa
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.asig_emp_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.planes_asignaciones WHERE id = current_setting('probe.asig_emp', true)::uuid;
  IF n > 0 THEN PERFORM set_config('probe.p55','PERMITIDO (ve asignación ajena)',false);
  ELSE PERFORM set_config('probe.p55','BLOQUEADO (0)',false); END IF;
END $$;

-- P56 — NEG: un proveedor AJENO NO actualiza la asignación ajena
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.asig_emp_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.planes_asignaciones SET visitas_usadas = COALESCE(visitas_usadas,0)
    WHERE id = current_setting('probe.asig_emp', true)::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p56','PERMITIDO (actualizó '||n||' fila ajena)',false);
  ELSE PERFORM set_config('probe.p56','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p56','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p56','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P57 — NEG: un no-super_admin NO inserta en campanas_publicitarias
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.campanas_publicitarias (titulo, descripcion, tipo, activa, fecha_inicio, fecha_fin)
  VALUES ('__probe','__probe','general', true, CURRENT_DATE, CURRENT_DATE);
  PERFORM set_config('probe.p57','PERMITIDO (no-super insertó campaña)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p57','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p57','PERMITIDO? (RLS dejó pasar: '||SQLSTATE||')',false);
END $$;

-- P58 — NEG: un no-super_admin NO borra una campaña
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  DELETE FROM public.campanas_publicitarias WHERE id = current_setting('probe.campana', true)::int;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p58','PERMITIDO (borró '||n||' campaña)',false);
  ELSE PERFORM set_config('probe.p58','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p58','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p58','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P59 — NEG: asignar un tipo FUERA del catálogo a empresas_proveedoras
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  UPDATE public.empresas_proveedoras SET tipo = '__tipo_invalido'
    WHERE id = current_setting('probe.emp_target', true)::uuid;
  PERFORM set_config('probe.p59','PERMITIDO (asignó tipo fuera de catálogo)',false);
EXCEPTION WHEN check_violation THEN PERFORM set_config('probe.p59','BLOQUEADO (CHECK: 23514)',false);
  WHEN others THEN PERFORM set_config('probe.p59','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P60 — POS: el proveedor DUEÑO ve y gestiona SU asignación
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.asig_emp_owner', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; v INT; BEGIN
  SELECT count(*) INTO v FROM public.planes_asignaciones WHERE id = current_setting('probe.asig_emp', true)::uuid;
  UPDATE public.planes_asignaciones SET visitas_usadas = COALESCE(visitas_usadas,0)
    WHERE id = current_setting('probe.asig_emp', true)::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF v > 0 AND n > 0 THEN PERFORM set_config('probe.p60','OK (ve y actualiza su asignación)',false);
  ELSE PERFORM set_config('probe.p60','REGRESIÓN (ve='||v||' upd='||n||')',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p60','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P61 — POS: un MÉDICO real (rol=medico, sin empresa) SÍ crea SU fila legítima
--   (medico_id=auth.uid(), empresa_id NULL). Truco 42501: 42501=RLS bloqueó;
--   otro SQLSTATE (NOT NULL)=RLS permitió la fila.
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.planes_asignaciones (medico_id, empresa_id, estado)
  VALUES (current_setting('probe.np_medico', true)::uuid, NULL, 'activo');
  PERFORM set_config('probe.p61','OK (RLS permite su fila de médico)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p61','REGRESIÓN (RLS bloqueó su fila: 42501)',false);
  WHEN others THEN PERFORM set_config('probe.p61','OK (RLS permite; faltó dato: '||SQLSTATE||')',false);
END $$;

-- P62 — POS: super_admin publica una campaña vía RPC
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE v INT; BEGIN
  v := public.aprobar_solicitud_campana(current_setting('probe.solicitud', true)::uuid, '__probe');
  IF v IS NOT NULL THEN PERFORM set_config('probe.p62','OK (publicó campaña id '||v||')',false);
  ELSE PERFORM set_config('probe.p62','REGRESIÓN (no devolvió id)',false); END IF;
EXCEPTION
  WHEN undefined_function THEN PERFORM set_config('probe.p62','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p62','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P63 — NEG: un no-super_admin NO puede aprobar vía RPC
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE v INT; BEGIN
  v := public.aprobar_solicitud_campana(current_setting('probe.solicitud', true)::uuid, '__probe');
  PERFORM set_config('probe.p63','PERMITIDO (no-super aprobó!)',false);
EXCEPTION
  WHEN undefined_function THEN PERFORM set_config('probe.p63','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p63','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P64 — NEG (semántica DUAL): un MÉDICO real NO puede forjar un empresa_id ajeno
--   (medico_id=auth.uid() + empresa_id=ajeno). El WITH CHECK separado lo rechaza.
--   42501 = RLS bloqueó (correcto); otro SQLSTATE = RLS dejó pasar (forja).
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.planes_asignaciones (medico_id, empresa_id, estado)
  VALUES (current_setting('probe.np_medico', true)::uuid, current_setting('probe.forge_emp', true)::uuid, 'activo');
  PERFORM set_config('probe.p64','PERMITIDO (médico forjó empresa_id ajeno)',false);
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p64','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p64','PERMITIDO? (RLS dejó pasar: '||SQLSTATE||')',false);
END $$;

-- ============================================================
-- INCREMENTO 1 (paneles) · Farmacia tenant (promoción super_admin + scoping)
-- ============================================================
-- Captura (ELEVADO) de actores. Orden: P67 (no-super promueve→falla) → P68
-- (super promueve→liga la farmacia) → P65/P66 (ajeno) → P69 (dueño) → P70 (público).
SELECT set_config('role', 'none', true);
SELECT set_config('probe.farm',
  (SELECT id::text FROM public.farmacias ORDER BY id LIMIT 1), false);
SELECT set_config('probe.farm_emp',
  (SELECT id::text FROM public.empresas_proveedoras WHERE tipo='farmacia' LIMIT 1), false);
SELECT set_config('probe.farm_owner',  -- ADMIN de la empresa promovida (con permiso de edición)
  (SELECT cp.id::text FROM public.cuentas_proveedor cp
     WHERE cp.empresa_id = current_setting('probe.farm_emp', true)::uuid
       AND cp.rol_en_empresa='admin' AND cp.activo ORDER BY cp.id LIMIT 1), false);
SELECT set_config('probe.farm_ajeno',
  (SELECT cp.id::text FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id=cp.empresa_id
     WHERE e.tipo <> 'farmacia' AND cp.activo ORDER BY cp.id LIMIT 1), false);
SELECT set_config('probe.farm_ajeno_emp',
  (SELECT cp.empresa_id::text FROM public.cuentas_proveedor cp
     WHERE cp.id = NULLIF(current_setting('probe.farm_ajeno', true),'')::uuid), false);
-- Aislamiento ENTRE tenants: convertir la empresa del ajeno en OTRA empresa-farmacia
-- (así P65/P66 prueban tenant-vs-tenant, no usuario-sin-empresa). Dentro del ROLLBACK.
UPDATE public.empresas_proveedoras SET tipo='farmacia'
  WHERE id = NULLIF(current_setting('probe.farm_ajeno_emp', true),'')::uuid;

-- P67 — NEG: un no-super_admin NO promueve una farmacia (vía RPC)
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.promover_farmacia_a_tenant(current_setting('probe.farm', true)::int, current_setting('probe.farm_emp', true)::uuid);
  PERFORM set_config('probe.p67','PERMITIDO (no-super promovió)',false);
EXCEPTION
  WHEN undefined_function THEN PERFORM set_config('probe.p67','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p67','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P68 — POS: super_admin promueve la farmacia a tenant (la liga a su empresa)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.promover_farmacia_a_tenant(current_setting('probe.farm', true)::int, current_setting('probe.farm_emp', true)::uuid);
  PERFORM set_config('probe.p68','OK (super_admin promovió la farmacia)',false);
EXCEPTION
  WHEN undefined_function THEN PERFORM set_config('probe.p68','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p68','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P65 — NEG: un proveedor AJENO NO gestiona la farmacia-tenant ajena
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.farm_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.farmacias SET activo = activo WHERE id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p65','PERMITIDO (gestionó farmacia ajena)',false);
  ELSE PERFORM set_config('probe.p65','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p65','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p65','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P66 — NEG: un proveedor AJENO NO edita el inventario de la farmacia-tenant ajena
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.farm_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.farmacia_medicamentos SET activo = activo WHERE farmacia_id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p66','PERMITIDO (editó inventario ajeno '||n||')',false);
  ELSE PERFORM set_config('probe.p66','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p66','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p66','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P69 — POS: el DUEÑO (miembro de la empresa) gestiona su farmacia-tenant + inventario
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.farm_owner', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n1 INT; n2 INT; BEGIN
  UPDATE public.farmacias SET activo = activo WHERE id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n1 = ROW_COUNT;
  UPDATE public.farmacia_medicamentos SET activo = activo WHERE farmacia_id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n2 = ROW_COUNT;
  IF n1 > 0 AND n2 > 0 THEN PERFORM set_config('probe.p69','OK (gestiona farmacia + inventario: '||n1||'/'||n2||')',false);
  ELSE PERFORM set_config('probe.p69','REGRESIÓN (farmacia='||n1||' inv='||n2||')',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p69','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P70 — POS: la búsqueda del médico sigue viendo el catálogo/inventario DE SU PAÍS.
-- Usa un médico en un país que SÍ tiene catálogo (post-096 el read es país-scoped; np_medico
-- podría estar en un país sin farmacias → 0 legítimo pero no prueba la no-regresión).
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', (SELECT p.id::text FROM public.perfiles p WHERE p.rol='medico'
       AND p.pais_id IN (SELECT f.pais_id FROM public.farmacia_medicamentos fm JOIN public.farmacias f ON f.id=fm.farmacia_id)
     LIMIT 1), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
-- Post aislamiento por país (096): el médico ve el catálogo de SU país. Contamos lo visible
-- bajo su RLS (país-filtrado) en vez de atar a una farmacia con país posiblemente inconsistente.
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.farmacia_medicamentos;
  IF n > 0 THEN PERFORM set_config('probe.p70','OK (médico ve inventario de su país: '||n||')',false);
  ELSE PERFORM set_config('probe.p70','REGRESIÓN (no ve catálogo)',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p70','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P71 — NEG (anti-suplantación): promover una farmacia que YA es tenant → RECHAZADA.
--   La farmacia ya fue promovida en P68 → el RPC valida empresa_id IS NULL y rechaza.
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.sa', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.promover_farmacia_a_tenant(current_setting('probe.farm', true)::int, current_setting('probe.farm_emp', true)::uuid);
  PERFORM set_config('probe.p71','PERMITIDO (reapropió una farmacia ya tenant!)',false);
EXCEPTION
  WHEN undefined_function THEN PERFORM set_config('probe.p71','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p71','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- ============================================================
-- INCREMENTO 2 · FRENTE A — permisos data-driven + anti-escalada de roles
-- ============================================================
-- Reparto (ELEVADO, dentro del ROLLBACK): reasigno cuentas reales a la empresa-
-- farmacia (probe.farm_emp) con roles. farmacia probe.farm ya es tenant (P68).
SELECT set_config('role', 'none', true);
SELECT set_config('probe.fa_admin',  -- admin de LA MISMA empresa del reparto (farm_emp)
  (SELECT cp.id::text FROM public.cuentas_proveedor cp
     WHERE cp.empresa_id = current_setting('probe.farm_emp', true)::uuid
       AND cp.rol_en_empresa='admin' AND cp.activo ORDER BY cp.id LIMIT 1), false);
SELECT set_config('probe.fa_ajeno',
  (SELECT id::text FROM public.cuentas_proveedor
     WHERE empresa_id <> current_setting('probe.farm_emp', true)::uuid AND activo ORDER BY id LIMIT 1), false);
SELECT set_config('probe.fa_gerente',
  (SELECT id::text FROM public.cuentas_proveedor
     WHERE id NOT IN (NULLIF(current_setting('probe.fa_admin',true),'')::uuid, NULLIF(current_setting('probe.fa_ajeno',true),'')::uuid)
     ORDER BY id LIMIT 1 OFFSET 0), false);
SELECT set_config('probe.fa_cajero',
  (SELECT id::text FROM public.cuentas_proveedor
     WHERE id NOT IN (NULLIF(current_setting('probe.fa_admin',true),'')::uuid, NULLIF(current_setting('probe.fa_ajeno',true),'')::uuid)
     ORDER BY id LIMIT 1 OFFSET 1), false);
SELECT set_config('probe.fa_inv',
  (SELECT id::text FROM public.cuentas_proveedor
     WHERE id NOT IN (NULLIF(current_setting('probe.fa_admin',true),'')::uuid, NULLIF(current_setting('probe.fa_ajeno',true),'')::uuid)
     ORDER BY id LIMIT 1 OFFSET 2), false);
SELECT set_config('probe.fa_target',
  (SELECT id::text FROM public.cuentas_proveedor
     WHERE id NOT IN (NULLIF(current_setting('probe.fa_admin',true),'')::uuid, NULLIF(current_setting('probe.fa_ajeno',true),'')::uuid)
     ORDER BY id LIMIT 1 OFFSET 3), false);
-- Usuario auth SIN cuenta de proveedor → candidato para el ALTA (INSERT)
SELECT set_config('probe.alta_user',
  (SELECT id::text FROM auth.users WHERE id NOT IN (SELECT id FROM public.cuentas_proveedor) ORDER BY id LIMIT 1), false);
-- Reasignación del reparto a la empresa-farmacia con sus roles (ROLLBACK)
UPDATE public.cuentas_proveedor SET empresa_id=current_setting('probe.farm_emp',true)::uuid, rol_en_empresa='gerente_farmacia', activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.fa_gerente',true),'')::uuid;
UPDATE public.cuentas_proveedor SET empresa_id=current_setting('probe.farm_emp',true)::uuid, rol_en_empresa='cajero',           activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.fa_cajero',true),'')::uuid;
UPDATE public.cuentas_proveedor SET empresa_id=current_setting('probe.farm_emp',true)::uuid, rol_en_empresa='inventario',       activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.fa_inv',true),'')::uuid;
UPDATE public.cuentas_proveedor SET empresa_id=current_setting('probe.farm_emp',true)::uuid, rol_en_empresa='dependiente',      activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.fa_target',true),'')::uuid;

-- ---- RLS por PERMISO (tenant farmacia) ----
-- P72 — NEG: rol sin inventario_editar (cajero) NO edita inventario
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_cajero', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.farmacia_medicamentos SET activo = activo WHERE farmacia_id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p72','PERMITIDO (sin permiso editó inventario '||n||')',false);
  ELSE PERFORM set_config('probe.p72','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p72','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p72','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P73 — NEG: rol sin config_empresa (cajero) NO edita datos de la farmacia
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_cajero', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.farmacias SET activo = activo WHERE id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p73','PERMITIDO (sin permiso editó datos)',false);
  ELSE PERFORM set_config('probe.p73','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p73','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p73','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P74 — POS: rol Inventario SÍ edita inventario
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.farmacia_medicamentos SET activo = activo WHERE farmacia_id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p74','OK (Inventario editó inventario: '||n||')',false);
  ELSE PERFORM set_config('probe.p74','REGRESIÓN (0 filas)',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p74','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P75 — NEG: rol Inventario NO edita los DATOS de la farmacia (no config_empresa)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.farmacias SET activo = activo WHERE id = current_setting('probe.farm', true)::int;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p75','PERMITIDO (Inventario editó datos)',false);
  ELSE PERFORM set_config('probe.p75','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p75','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p75','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- ---- Anti-escalada (RPC asignar_rol_miembro) — los NEGATIVOS son los críticos ----
-- P76 — NEG: Gerente asigna ADMIN → rechazado (nivel)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_target', true)::uuid, 'admin');
  PERFORM set_config('probe.p76','PERMITIDO (Gerente asignó Admin!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p76','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p76','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P77 — NEG: Gerente modifica/degrada a un ADMIN existente → rechazado
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_admin', true)::uuid, 'cajero');
  PERFORM set_config('probe.p77','PERMITIDO (Gerente degradó a un Admin!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p77','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p77','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P78 — NEG: Gerente asigna otro GERENTE → rechazado (mismo nivel)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_target', true)::uuid, 'gerente_farmacia');
  PERFORM set_config('probe.p78','PERMITIDO (Gerente asignó otro Gerente!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p78','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p78','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P79 — NEG: un rol operativo (Cajero) asigna CUALQUIER rol → rechazado (sin usuarios_roles)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_cajero', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_target', true)::uuid, 'cajero');
  PERFORM set_config('probe.p79','PERMITIDO (operativo asignó rol!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p79','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p79','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P80 — NEG: asignar rol en EMPRESA AJENA → rechazado (scope)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_ajeno', true)::uuid, 'cajero');
  PERFORM set_config('probe.p80','PERMITIDO (asignó en empresa ajena!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p80','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p80','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P82 — POS: Gerente asigna un rol OPERATIVO (Cajero) → permitido (antes de promover el target a admin)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_target', true)::uuid, 'cajero');
  PERFORM set_config('probe.p82','OK (Gerente asignó Cajero)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p82','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p82','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P86 — NEG (último Admin): el ÚNICO Admin activo se degrada a sí mismo → BLOQUEADO
--   (corre ANTES de P81, cuando la empresa-farmacia tiene exactamente 1 Admin)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_admin', true)::uuid, 'cajero');
  PERFORM set_config('probe.p86','PERMITIDO (dejó la empresa sin Admin!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p86','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p86','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P81 — POS: Admin asigna CUALQUIER rol, incluido Admin → permitido
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.fa_target', true)::uuid, 'admin');
  PERFORM set_config('probe.p81','OK (Admin asignó Admin)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p81','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p81','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- ---- PUERTA TRASERA (ajuste a): asignar_rol_miembro = único camino ----
-- P83 — NEG: un no-admin cambia el rol de OTRO por UPDATE DIRECTO → BLOQUEADO
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.cuentas_proveedor SET rol_en_empresa='admin' WHERE id = current_setting('probe.fa_target', true)::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p83','PERMITIDO (UPDATE directo cambió rol ajeno)',false);
  ELSE PERFORM set_config('probe.p83','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p83','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p83','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P84 — NEG: un miembro se AUTO-ASCIENDE a admin por UPDATE DIRECTO → BLOQUEADO
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_cajero', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.cuentas_proveedor SET rol_en_empresa='admin' WHERE id = current_setting('probe.fa_cajero', true)::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p84','PERMITIDO (auto-ascenso por UPDATE directo)',false);
  ELSE PERFORM set_config('probe.p84','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p84','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p84','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P85 — NEG: un admin de FARMACIA usa el RPC legado cambiar_rol_proveedor → BLOQUEADO
--   (camino único: en farmacia los roles se cambian con asignar_rol_miembro)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.cambiar_rol_proveedor(current_setting('probe.fa_cajero', true)::uuid, 'supervisor');
  PERFORM set_config('probe.p85','PERMITIDO (RPC legado cambió rol en farmacia)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p85','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p85','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- ---- ALTA de miembros de farmacia (RPC alta_miembro_farmacia, misma jerarquía) ----
-- P88 — NEG: Gerente da de alta ADMIN → BLOQUEADO (nivel)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.alta_miembro_farmacia(current_setting('probe.alta_user', true)::uuid, current_setting('probe.farm_emp', true)::uuid, 'Nuevo', 'nuevo@probe.test', 'admin', NULL);
  PERFORM set_config('probe.p88','PERMITIDO (Gerente dio de alta Admin!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p88','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p88','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P89 — NEG: alta en EMPRESA AJENA → BLOQUEADO (scope)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.alta_miembro_farmacia(current_setting('probe.alta_user', true)::uuid, current_setting('probe.farm_ajeno_emp', true)::uuid, 'Nuevo', 'nuevo@probe.test', 'cajero', NULL);
  PERFORM set_config('probe.p89','PERMITIDO (alta en empresa ajena!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p89','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p89','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P90 — NEG: alta de un rol INEXISTENTE → BLOQUEADO
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.alta_miembro_farmacia(current_setting('probe.alta_user', true)::uuid, current_setting('probe.farm_emp', true)::uuid, 'Nuevo', 'nuevo@probe.test', 'rol_fantasma', NULL);
  PERFORM set_config('probe.p90','PERMITIDO (alta de rol inexistente!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p90','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p90','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P87 — POS: Gerente da de alta un CAJERO (nivel inferior) → OK (inserta)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.alta_miembro_farmacia(current_setting('probe.alta_user', true)::uuid, current_setting('probe.farm_emp', true)::uuid, 'Nuevo', 'nuevo@probe.test', 'cajero', NULL);
  PERFORM set_config('probe.p87','OK (Gerente dio de alta un Cajero)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p87','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p87','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- ============================================================
-- INCREMENTO 2 · Alta por INVITACIÓN (invitar_miembro_farmacia + consumo) + puerta trasera
-- ============================================================
-- Captura (ELEVADO): dos invitados frescos (auth sin cuenta) con su EMAIL REAL de
-- auth.users (el consumo ata contra ese email verificado), una empresa NO-farmacia,
-- y tokens sembrados (expirado farmacia; lab con el email real de invitee2).
SELECT set_config('role', 'none', true);
SELECT set_config('probe.invitee',
  (SELECT id::text FROM auth.users WHERE id NOT IN (SELECT id FROM public.cuentas_proveedor) ORDER BY id LIMIT 1), false);
SELECT set_config('probe.invitee_email',
  (SELECT email FROM auth.users WHERE id = current_setting('probe.invitee', true)::uuid), false);
SELECT set_config('probe.invitee2',
  (SELECT id::text FROM auth.users WHERE id NOT IN (SELECT id FROM public.cuentas_proveedor)
     AND id <> current_setting('probe.invitee', true)::uuid ORDER BY id LIMIT 1), false);
SELECT set_config('probe.invitee2_email',
  (SELECT email FROM auth.users WHERE id = current_setting('probe.invitee2', true)::uuid), false);
SELECT set_config('probe.lab_emp',
  (SELECT id::text FROM public.empresas_proveedoras WHERE tipo <> 'farmacia' ORDER BY id LIMIT 1), false);
DO $$ DECLARE t uuid; BEGIN  -- token EXPIRADO (farmacia)
  INSERT INTO public.invitaciones_visitador (empresa_id, email, nombre_completo, rol, estado, expires_at)
  VALUES (current_setting('probe.farm_emp', true)::uuid, current_setting('probe.invitee_email', true), 'Exp', 'cajero', 'pendiente', now() - interval '1 day')
  RETURNING token INTO t;
  PERFORM set_config('probe.exp_token', t::text, false);
END $$;
DO $$ DECLARE t uuid; BEGIN  -- token VISITADOR/LAB (empresa no-farmacia), email = invitee2 real
  INSERT INTO public.invitaciones_visitador (empresa_id, email, nombre_completo, rol, estado, expires_at)
  VALUES (current_setting('probe.lab_emp', true)::uuid, current_setting('probe.invitee2_email', true), 'Lab Inv', 'visitador_medico', 'pendiente', now() + interval '7 days')
  RETURNING token INTO t;
  PERFORM set_config('probe.lab_token', t::text, false);
END $$;

-- P91 — NEG: Gerente invita ADMIN → BLOQUEADO (nivel)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.invitar_miembro_farmacia('nuevo1@probe.test','Nuevo','admin',NULL);
  PERFORM set_config('probe.p91','PERMITIDO (Gerente invitó Admin!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p91','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p91','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P92 — NEG: Gerente invita otro GERENTE → BLOQUEADO (mismo nivel)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.invitar_miembro_farmacia('nuevo2@probe.test','Nuevo','gerente_farmacia',NULL);
  PERFORM set_config('probe.p92','PERMITIDO (Gerente invitó Gerente!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p92','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p92','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P93 — NEG: un operativo (Cajero) invita → BLOQUEADO (sin usuarios_roles)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_cajero', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.invitar_miembro_farmacia('nuevo3@probe.test','Nuevo','cajero',NULL);
  PERFORM set_config('probe.p93','PERMITIDO (operativo invitó!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p93','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p93','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P94 — NEG: invitar un rol INEXISTENTE → BLOQUEADO
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.invitar_miembro_farmacia('nuevo4@probe.test','Nuevo','rol_fantasma',NULL);
  PERFORM set_config('probe.p94','PERMITIDO (invitó rol inexistente!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p94','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p94','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P95 — POS: Gerente invita un CAJERO (inferior) → OK (captura el token)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE v_tok uuid; BEGIN
  v_tok := public.invitar_miembro_farmacia(current_setting('probe.invitee_email', true),'Invitado','cajero',NULL);
  PERFORM set_config('probe.inv_token', v_tok::text, false);
  PERFORM set_config('probe.p95','OK (Gerente invitó Cajero)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p95','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p95','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P96 — PUERTA TRASERA: INSERT directo de invitación en farmacia → BLOQUEADO
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.invitaciones_visitador (empresa_id, email, nombre_completo, rol, estado, expires_at)
  VALUES (current_setting('probe.farm_emp', true)::uuid, 'directo@probe.test', 'Directo', 'admin', 'pendiente', now() + interval '7 days');
  PERFORM set_config('probe.p96','PERMITIDO (INSERT directo de invitación!)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p96','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p96','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P97 — POS + PT: el invitado (AUTENTICADO, email verificado) acepta el token →
--   membresía con id=auth.uid(), rol FIJADO (cajero) y empresa del token. Sin
--   parámetros de rol/empresa/user_id → no manipulable.
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.invitee', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.inv_token', true),'') IS NULL THEN PERFORM set_config('probe.p97','N/A (sin token: invitar no existe)',false);
  ELSE
    PERFORM public.aceptar_invitacion_proveedor(current_setting('probe.inv_token', true)::uuid);
    PERFORM set_config('probe.p97_done','1',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p97','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p97','REGRESIÓN ('||SQLSTATE||')',false);
END $$;
SELECT set_config('role', 'none', true);
DO $$ DECLARE v_rol text; v_emp uuid; BEGIN
  IF current_setting('probe.p97_done', true) = '1' THEN
    SELECT rol_en_empresa, empresa_id INTO v_rol, v_emp FROM public.cuentas_proveedor
      WHERE id = current_setting('probe.invitee', true)::uuid;
    IF v_rol = 'cajero' AND v_emp = current_setting('probe.farm_emp', true)::uuid THEN
      PERFORM set_config('probe.p97','OK (alta con rol FIJADO cajero en empresa del token)',false);
    ELSE PERFORM set_config('probe.p97','REGRESIÓN (rol/empresa efectivos: '||COALESCE(v_rol,'?')||'/'||COALESCE(v_emp::text,'?')||')',false); END IF;
  ELSIF NULLIF(current_setting('probe.p97', true),'') IS NULL THEN PERFORM set_config('probe.p97','REGRESIÓN (no consumió)',false);
  END IF;
END $$;

-- P98 — PT: re-aceptar un token YA USADO → BLOQUEADO (un solo uso)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.invitee', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.inv_token', true),'') IS NULL THEN PERFORM set_config('probe.p98','N/A (sin token)',false);
  ELSE
    PERFORM public.aceptar_invitacion_proveedor(current_setting('probe.inv_token', true)::uuid);
    PERFORM set_config('probe.p98','PERMITIDO (reusó token usado!)',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p98','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p98','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P99 — PT: aceptar un token EXPIRADO → BLOQUEADO
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.invitee', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.aceptar_invitacion_proveedor(current_setting('probe.exp_token', true)::uuid);
  PERFORM set_config('probe.p99','PERMITIDO (consumió token expirado!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p99','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p99','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- ---- Binding contra el email AUTENTICADO (PT) + no-regresión visitador/lab ----
-- setup P100: el Gerente crea una invitación de farmacia para invitee_email
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fa_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE v_tok uuid; BEGIN
  v_tok := public.invitar_miembro_farmacia(current_setting('probe.invitee_email', true),'Bind','cajero',NULL);
  PERFORM set_config('probe.bind_token', v_tok::text, false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.bind_token','',false);
END $$;

-- P100 — PT: OTRO usuario autenticado (email ≠ invitación) acepta el token → BLOQUEADO
--   (binding contra el email verificado del autenticado, no contra un parámetro)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.invitee2', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.bind_token', true),'') IS NULL THEN PERFORM set_config('probe.p100','N/A (sin token; invitar no existe)',false);
  ELSE
    PERFORM public.aceptar_invitacion_proveedor(current_setting('probe.bind_token', true)::uuid);
    PERFORM set_config('probe.p100','PERMITIDO (otro autenticado consumió token ajeno!)',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p100','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p100','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P101 — NO-REGRESIÓN: invitado correcto (autenticado, email coincide) acepta una
--   invitación VISITADOR/LAB e2e → OK (empresa+rol del token).
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.invitee2', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.aceptar_invitacion_proveedor(current_setting('probe.lab_token', true)::uuid);
  PERFORM set_config('probe.p101_done','1',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p101','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p101','REGRESIÓN ('||SQLSTATE||')',false);
END $$;
SELECT set_config('role', 'none', true);
DO $$ DECLARE v_emp uuid; v_rol text; BEGIN
  IF current_setting('probe.p101_done', true) = '1' THEN
    SELECT empresa_id, rol_en_empresa INTO v_emp, v_rol FROM public.cuentas_proveedor
      WHERE id = current_setting('probe.invitee2', true)::uuid;
    IF v_emp = current_setting('probe.lab_emp', true)::uuid AND v_rol = 'visitador_medico'
      THEN PERFORM set_config('probe.p101','OK (consumo visitador/lab e2e: empresa+rol del token)',false);
      ELSE PERFORM set_config('probe.p101','REGRESIÓN (efectivo '||COALESCE(v_emp::text,'?')||'/'||COALESCE(v_rol,'?')||')',false); END IF;
  ELSIF NULLIF(current_setting('probe.p101', true),'') IS NULL THEN PERFORM set_config('probe.p101','REGRESIÓN (no consumió)',false);
  END IF;
END $$;

-- P102 — PT: el camino viejo (registrar_visitador_desde_invitacion, anon, user_id
--   arbitrario) debe estar CERRADO → invocarlo como anon = función inexistente.
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role', 'anon', true);
DO $$ BEGIN
  PERFORM public.registrar_visitador_desde_invitacion(
    current_setting('probe.exp_token', true)::uuid, current_setting('probe.invitee', true)::uuid, 'z@probe.test','Z',NULL);
  PERFORM set_config('probe.p102','PERMITIDO (camino viejo reachable por anon!)',false);
EXCEPTION
  WHEN undefined_function THEN PERFORM set_config('probe.p102','BLOQUEADO (función inexistente)',false);
  WHEN insufficient_privilege THEN PERFORM set_config('probe.p102','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p102','PERMITIDO? (alcanzó el cuerpo: '||SQLSTATE||')',false);
END $$;

-- ============================================================
-- FIX visibilidad personal de clínica (obtener_personal_clinica) — P110/P111
-- ============================================================
-- Captura (ELEVADO): una clínica con varios miembros, un admin/miembro de ESA
-- clínica, y un AJENO (no miembro).
SELECT set_config('role', 'none', true);
SELECT set_config('probe.clin',
  (SELECT mc.clinica_id::text FROM public.medico_clinicas mc GROUP BY mc.clinica_id ORDER BY count(*) DESC LIMIT 1), false);
SELECT set_config('probe.clin_member',
  (SELECT mc.medico_id::text FROM public.medico_clinicas mc
    WHERE mc.clinica_id = current_setting('probe.clin', true)::uuid ORDER BY mc.medico_id LIMIT 1), false);
SELECT set_config('probe.clin_ajeno',
  (SELECT cp.id::text FROM public.cuentas_proveedor cp WHERE cp.activo
    AND cp.id NOT IN (SELECT medico_id FROM public.medico_clinicas WHERE clinica_id = current_setting('probe.clin', true)::uuid)
    ORDER BY cp.id LIMIT 1), false);
-- Clínica B: otra clínica donde clin_member NO es miembro (test cross-clínica)
SELECT set_config('probe.clin_b',
  (SELECT c.id::text FROM public.clinicas c
    WHERE c.id <> current_setting('probe.clin', true)::uuid
      AND NOT EXISTS (SELECT 1 FROM public.medico_clinicas mc
                      WHERE mc.clinica_id = c.id AND mc.medico_id = current_setting('probe.clin_member', true)::uuid)
    ORDER BY c.id LIMIT 1), false);

-- P110 — POS: un MIEMBRO de la clínica ve a todo su equipo (>1)
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.clin_member', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.obtener_personal_clinica(current_setting('probe.clin', true)::uuid);
  IF n > 1 THEN PERFORM set_config('probe.p110','OK (ve '||n||' miembros de su clínica)',false);
  ELSIF n = 1 THEN PERFORM set_config('probe.p110','REGRESIÓN (solo se ve a sí mismo: 1)',false);
  ELSE PERFORM set_config('probe.p110','REGRESIÓN (0 miembros)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p110','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p110','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P111 — NEG: un AJENO (no miembro) NO ve el personal de esa clínica
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.clin_ajeno', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  IF NULLIF(current_setting('probe.clin_ajeno', true),'') IS NULL THEN PERFORM set_config('probe.p111','N/A (sin ajeno)',false);
  ELSE
    SELECT count(*) INTO n FROM public.obtener_personal_clinica(current_setting('probe.clin', true)::uuid);
    PERFORM set_config('probe.p111','PERMITIDO (ajeno vio '||n||' miembros!)',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p111','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p111','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P112 — NEG (cross-clínica): un MIEMBRO de la Clínica A NO ve el personal de la Clínica B
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.clin_member', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  IF NULLIF(current_setting('probe.clin_b', true),'') IS NULL THEN PERFORM set_config('probe.p112','N/A (sin clínica B)',false);
  ELSE
    SELECT count(*) INTO n FROM public.obtener_personal_clinica(current_setting('probe.clin_b', true)::uuid);
    PERFORM set_config('probe.p112','PERMITIDO (miembro de A vio '||n||' de la Clínica B!)',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p112','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p112','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P113 — NEG (robustez): llamar obtener_personal_clinica con p_clinica_id NULL → BLOQUEADO
--   (sin el guard NULL, la condición trivaluada NO lanzaba y devolvía 0 filas).
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.clin_member', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.obtener_personal_clinica(NULL);
  PERFORM set_config('probe.p113','PERMITIDO (NULL no lanzó; devolvió '||n||' filas)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p113','N/A (RPC no existe aún)',false);
  WHEN others THEN PERFORM set_config('probe.p113','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- ============================================================
-- INCREMENTO 3 · Empresas Afines — SEGURIDAD (Inc.3.A) · P114–P121
-- ============================================================
-- Captura (ELEVADO): empresa afín + su admin existente; se piden prestadas cuentas
-- para roles marketing/lectura/gerente (re-asignadas a la afín; ROLLBACK), un
-- producto afín activo ficticio, y un auth.user libre para el alta.
SELECT set_config('role', 'none', true);
SELECT set_config('probe.af_emp',
  (SELECT id::text FROM public.empresas_proveedoras WHERE tipo='empresa_afin' ORDER BY id LIMIT 1), false);
-- médico PURO (no es cuenta_proveedor) → solo ve productos por la policy "Médico ve productos activos",
-- nunca por membresía. (Evita que un id compartido perfil/cuenta contamine P114/P134.)
SELECT set_config('probe.af_medico',
  (SELECT id::text FROM public.perfiles WHERE rol='medico'
     AND id NOT IN (SELECT id FROM public.cuentas_proveedor) ORDER BY id LIMIT 1), false);
-- 4 cuentas prestadas (las fixtures de farmacia ya corrieron; reusarlas es inocuo) y
-- re-asignadas A LA AFÍN con sus roles data-driven, incluido el admin (ROLLBACK).
SELECT set_config('probe.af_admin',   (SELECT id::text FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 0), false);
SELECT set_config('probe.af_mkt',     (SELECT id::text FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 1), false);
SELECT set_config('probe.af_lectura', (SELECT id::text FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 2), false);
SELECT set_config('probe.af_gerente', (SELECT id::text FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 3), false);
SELECT set_config('probe.af_alta_user',
  (SELECT id::text FROM auth.users WHERE id NOT IN (SELECT id FROM public.cuentas_proveedor) ORDER BY id LIMIT 1), false);
UPDATE public.cuentas_proveedor SET empresa_id=NULLIF(current_setting('probe.af_emp',true),'')::uuid, rol_en_empresa='admin',     activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.af_admin',true),'')::uuid;
UPDATE public.cuentas_proveedor SET empresa_id=NULLIF(current_setting('probe.af_emp',true),'')::uuid, rol_en_empresa='marketing', activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.af_mkt',true),'')::uuid;
UPDATE public.cuentas_proveedor SET empresa_id=NULLIF(current_setting('probe.af_emp',true),'')::uuid, rol_en_empresa='lectura',   activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.af_lectura',true),'')::uuid;
UPDATE public.cuentas_proveedor SET empresa_id=NULLIF(current_setting('probe.af_emp',true),'')::uuid, rol_en_empresa='gerente',   activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.af_gerente',true),'')::uuid;
-- Producto afín activo ficticio (para el test de visibilidad del médico)
DO $$ DECLARE v_id uuid; BEGIN
  IF NULLIF(current_setting('probe.af_emp',true),'') IS NOT NULL THEN
    INSERT INTO public.productos_empresa (empresa_id, nombre_producto, precio_unitario, estado)
      VALUES (current_setting('probe.af_emp',true)::uuid, 'Probe Afin Visible', 10, 'activo')
      RETURNING id INTO v_id;
    PERFORM set_config('probe.af_prod', v_id::text, false);
  END IF;
END $$;
-- afín B (2ª empresa afín) + producto + miembro admin + solicitud → aislamiento afín↔afín (ROLLBACK)
DO $$ DECLARE v_b uuid; v_pais uuid; BEGIN
  SELECT pais_id INTO v_pais FROM public.empresas_proveedoras WHERE id = current_setting('probe.af_emp',true)::uuid;
  INSERT INTO public.empresas_proveedoras (nombre_empresa, email_contacto, tipo, pais_id)
    VALUES ('Probe Afin B', 'afinb@probe.test', 'empresa_afin', v_pais) RETURNING id INTO v_b;
  PERFORM set_config('probe.af_emp_b', v_b::text, false);
  INSERT INTO public.productos_empresa (empresa_id, nombre_producto, precio_unitario, estado)
    VALUES (v_b, 'Probe Afin B Producto', 10, 'activo');
END $$;
SELECT set_config('probe.af_b_member', (SELECT id::text FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 4), false);
UPDATE public.cuentas_proveedor SET empresa_id=NULLIF(current_setting('probe.af_emp_b',true),'')::uuid, rol_en_empresa='admin', activo=true, equipo_id=NULL WHERE id=NULLIF(current_setting('probe.af_b_member',true),'')::uuid;
DO $$ DECLARE v_id uuid; BEGIN
  IF NULLIF(current_setting('probe.af_b_member',true),'') IS NOT NULL THEN
    INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado, pais_id)
      VALUES (current_setting('probe.af_emp_b',true)::uuid, current_setting('probe.af_b_member',true)::uuid, 'Solic Afin B', now(), now()+interval '7 days', 'borrador',
              (SELECT pais_id FROM public.empresas_proveedoras WHERE id=current_setting('probe.af_emp_b',true)::uuid))
      RETURNING id INTO v_id;
    PERFORM set_config('probe.af_b_solic', v_id::text, false);
  END IF;
END $$;
-- solicitud PROPIA de afín A (de af_mkt) para tests de auto-aprobación/edición de contenido
DO $$ DECLARE v_id uuid; BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado, pais_id)
    VALUES (current_setting('probe.af_emp',true)::uuid, current_setting('probe.af_mkt',true)::uuid, 'Solic Afin A', now(), now()+interval '7 days', 'borrador',
            (SELECT pais_id FROM public.empresas_proveedoras WHERE id=current_setting('probe.af_emp',true)::uuid))
    RETURNING id INTO v_id;
  PERFORM set_config('probe.af_a_solic', v_id::text, false);
END $$;
-- producto activo de una empresa NO-afín (para confirmar que el médico la SIGUE viendo tras el fix)
DO $$ DECLARE v_e uuid; BEGIN
  SELECT id INTO v_e FROM public.empresas_proveedoras WHERE tipo <> 'empresa_afin' ORDER BY id LIMIT 1;
  PERFORM set_config('probe.nonafin_emp', COALESCE(v_e::text,''), false);
  IF v_e IS NOT NULL THEN
    INSERT INTO public.productos_empresa (empresa_id, nombre_producto, precio_unitario, estado)
      VALUES (v_e, 'Probe NoAfin Visible', 10, 'activo');
  END IF;
END $$;

-- P114 — BARRERA: el MÉDICO NO ve productos de empresa_afin en su búsqueda
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  IF NULLIF(current_setting('probe.af_medico',true),'') IS NULL THEN PERFORM set_config('probe.p114','N/A (sin médico puro)',false);
  ELSE
    SELECT count(*) INTO n FROM public.productos_empresa
      WHERE empresa_id = NULLIF(current_setting('probe.af_emp',true),'')::uuid AND estado='activo';
    IF n > 0 THEN PERFORM set_config('probe.p114','VISIBLE (médico ve '||n||' productos afín!)',false);
    ELSE PERFORM set_config('probe.p114','OCULTO (0 productos afín al médico)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p114','OCULTO ('||SQLSTATE||')',false);
END $$;

-- P115 — NO-REGRESIÓN: el AFÍN sigue viendo SUS propios productos
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.productos_empresa
    WHERE empresa_id = NULLIF(current_setting('probe.af_emp',true),'')::uuid;
  IF n > 0 THEN PERFORM set_config('probe.p115','OK (afín ve '||n||' productos propios)',false);
  ELSE PERFORM set_config('probe.p115','REGRESIÓN (afín no ve sus productos)',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p115','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P116 — POS: el rol MARKETING del afín CREA una campaña (publicidad_gestionar)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, pais_id)
    VALUES (NULLIF(current_setting('probe.af_emp',true),'')::uuid, NULLIF(current_setting('probe.af_mkt',true),'')::uuid,
            'Probe Campaña Afín', now(), now() + interval '7 days',
            (SELECT pais_id FROM public.empresas_proveedoras WHERE id=NULLIF(current_setting('probe.af_emp',true),'')::uuid));
  PERFORM set_config('probe.p116','OK (marketing creó campaña)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p116','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p116','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P117 — NEG: el rol LECTURA del afín NO crea campañas
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_lectura', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, pais_id)
    VALUES (NULLIF(current_setting('probe.af_emp',true),'')::uuid, NULLIF(current_setting('probe.af_lectura',true),'')::uuid,
            'Probe Campaña Lectura', now(), now() + interval '7 days',
            (SELECT pais_id FROM public.empresas_proveedoras WHERE id=NULLIF(current_setting('probe.af_emp',true),'')::uuid));
  PERFORM set_config('probe.p117','PERMITIDO (lectura creó campaña!)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p117','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p117','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P118 — POS: el ADMIN del afín da de alta un MARKETING (alta_miembro_farmacia generalizada)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.af_alta_user', true),'') IS NULL THEN PERFORM set_config('probe.p118','N/A (sin auth.user libre)',false);
  ELSE
    PERFORM public.alta_miembro_farmacia(current_setting('probe.af_alta_user', true)::uuid,
      current_setting('probe.af_emp', true)::uuid, 'Nuevo Afín', 'nuevoafin@probe.test', 'marketing', NULL);
    PERFORM set_config('probe.p118','OK (admin afín dio de alta marketing)',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p118','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p118','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P119 — NEG: el GERENTE del afín NO da de alta un ADMIN (jerarquía anti-escalada)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.alta_miembro_farmacia(current_setting('probe.af_alta_user', true)::uuid,
    current_setting('probe.af_emp', true)::uuid, 'Nuevo', 'nuevoafin2@probe.test', 'admin', NULL);
  PERFORM set_config('probe.p119','PERMITIDO (gerente afín dio de alta Admin!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p119','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p119','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P120 — PT: el RPC legado cambiar_rol_proveedor debe estar CERRADO para empresa_afin
--   (camino único = asignar_rol_miembro). Antes de 083 el admin afín podía usarlo.
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  PERFORM public.cambiar_rol_proveedor(current_setting('probe.af_mkt', true)::uuid, 'lectura');
  PERFORM set_config('probe.p120','PERMITIDO (RPC legado cambió rol en afín!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p120','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p120','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P121 — POS: el GERENTE del afín EDITA productos por permiso data-driven 'productos_editar'
--   (su rol no está en el string-list legado admin/editor/catalogo)
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.productos_empresa SET nombre_producto = nombre_producto
    WHERE empresa_id = NULLIF(current_setting('probe.af_emp',true),'')::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p121','OK (gerente editó '||n||' productos via productos_editar)',false);
  ELSE PERFORM set_config('probe.p121','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p121','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p121','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- ---- ANTI-AUTO-APROBACIÓN de publicidad (pieza 7) ----
-- P122 — NEG ★: marketing del afín UPDATE de SU solicitud poniendo estado='publicada' → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.solicitudes_campana SET estado='publicada' WHERE id = NULLIF(current_setting('probe.af_a_solic',true),'')::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p122','PERMITIDO (afín auto-aprobó su campaña!)',false);
  ELSE PERFORM set_config('probe.p122','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p122','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p122','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P123 — POS: marketing del afín edita el CONTENIDO de SU solicitud (estado intacto) → OK
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.solicitudes_campana SET titulo='Solic Afin A (editada)' WHERE id = NULLIF(current_setting('probe.af_a_solic',true),'')::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p123','OK (afín editó contenido de su solicitud)',false);
  ELSE PERFORM set_config('probe.p123','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p123','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p123','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P124 — NEG: marketing del afín INSERT solicitud con empresa_id de OTRA empresa (afín B) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, pais_id)
    VALUES (NULLIF(current_setting('probe.af_emp_b',true),'')::uuid, NULLIF(current_setting('probe.af_mkt',true),'')::uuid, 'Cross empresa', now(), now()+interval '7 days',
            (SELECT pais_id FROM public.empresas_proveedoras WHERE id=NULLIF(current_setting('probe.af_emp_b',true),'')::uuid));
  PERFORM set_config('probe.p124','PERMITIDO (insertó en empresa ajena!)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p124','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p124','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P125 — NEG: marketing del afín INSERT solicitud PROPIA que NACE 'publicada' → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado, pais_id)
    VALUES (NULLIF(current_setting('probe.af_emp',true),'')::uuid, NULLIF(current_setting('probe.af_mkt',true),'')::uuid, 'Nace publicada', now(), now()+interval '7 days', 'publicada',
            (SELECT pais_id FROM public.empresas_proveedoras WHERE id=NULLIF(current_setting('probe.af_emp',true),'')::uuid));
  PERFORM set_config('probe.p125','PERMITIDO (nació publicada!)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p125','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p125','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P126 — NEG: marketing del afín UPDATE solicitud de OTRA empresa (afín B) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.solicitudes_campana SET titulo='hack' WHERE id = NULLIF(current_setting('probe.af_b_solic',true),'')::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p126','PERMITIDO (editó solicitud ajena!)',false);
  ELSE PERFORM set_config('probe.p126','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p126','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p126','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- ---- AISLAMIENTO afín↔afín (productos / solicitudes / miembros) ----
-- P127 — NEG: afín A NO ve productos de afín B
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.productos_empresa WHERE empresa_id = NULLIF(current_setting('probe.af_emp_b',true),'')::uuid;
  IF n > 0 THEN PERFORM set_config('probe.p127','VISIBLE (afín A ve '||n||' productos de afín B!)',false);
  ELSE PERFORM set_config('probe.p127','OCULTO (0 productos de B)',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p127','OCULTO ('||SQLSTATE||')',false);
END $$;

-- P128 — NEG: afín A NO edita productos de afín B
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  UPDATE public.productos_empresa SET nombre_producto=nombre_producto WHERE empresa_id = NULLIF(current_setting('probe.af_emp_b',true),'')::uuid;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN PERFORM set_config('probe.p128','PERMITIDO (editó productos de B!)',false);
  ELSE PERFORM set_config('probe.p128','BLOQUEADO (0 filas)',false); END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p128','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p128','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P129 — NEG: afín A NO ve solicitudes de afín B
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.solicitudes_campana WHERE empresa_id = NULLIF(current_setting('probe.af_emp_b',true),'')::uuid;
  IF n > 0 THEN PERFORM set_config('probe.p129','VISIBLE (afín A ve '||n||' solicitudes de afín B!)',false);
  ELSE PERFORM set_config('probe.p129','OCULTO (0 solicitudes de B)',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p129','OCULTO ('||SQLSTATE||')',false);
END $$;

-- ---- ANTI-ESCALADA + último-admin + scope de miembros (afín) ----
-- P130 — NEG: gerente del afín NO asigna rol admin (jerarquía, asignar_rol_miembro)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_gerente', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.af_mkt', true)::uuid, 'admin');
  PERFORM set_config('probe.p130','PERMITIDO (gerente afín asignó Admin!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p130','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p130','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P131 — NEG: admin del afín A NO asigna rol a un miembro de afín B (scope/aislamiento)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  PERFORM public.asignar_rol_miembro(current_setting('probe.af_b_member', true)::uuid, 'lectura');
  PERFORM set_config('probe.p131','PERMITIDO (admin A tocó miembro de B!)',false);
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p131','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p131','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P132 — NEG: el guard de ÚLTIMO ADMIN sigue vigente para afín (admin se auto-degrada → BLOQUEADO).
--   AISLADO: empresa afín de prueba con UN SOLO admin (no usa la empresa afín real,
--   cuyo conteo de admins puede estar contaminado por cuentas QA reales). Todo en la
--   transacción del harness (ROLLBACK). Pide prestada una cuenta distinta de las que
--   usan otros probes afín (af_admin/mkt/lectura/gerente/b_member) y la re-asigna como
--   ÚNICO admin de la empresa aislada.
SELECT set_config('role','none',true);
DO $$ DECLARE v_emp uuid; v_admin uuid; v_pais uuid; BEGIN
  SELECT pais_id INTO v_pais FROM public.empresas_proveedoras WHERE id = current_setting('probe.af_emp',true)::uuid;
  INSERT INTO public.empresas_proveedoras (nombre_empresa, email_contacto, tipo, pais_id, estado)
    VALUES ('Probe Afin UltimoAdmin', 'p132@probe.test', 'empresa_afin', v_pais, 'activa')
    RETURNING id INTO v_emp;
  SELECT id INTO v_admin FROM public.cuentas_proveedor
    WHERE id NOT IN (
      NULLIF(current_setting('probe.af_admin',true),'')::uuid,
      NULLIF(current_setting('probe.af_mkt',true),'')::uuid,
      NULLIF(current_setting('probe.af_lectura',true),'')::uuid,
      NULLIF(current_setting('probe.af_gerente',true),'')::uuid,
      NULLIF(current_setting('probe.af_b_member',true),'')::uuid
    ) ORDER BY id LIMIT 1;
  IF v_admin IS NOT NULL THEN
    UPDATE public.cuentas_proveedor SET empresa_id=v_emp, rol_en_empresa='admin', activo=true, equipo_id=NULL WHERE id=v_admin;
    PERFORM set_config('probe.p132_admin', v_admin::text, false);
  END IF;
END $$;
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p132_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.p132_admin', true),'') IS NULL THEN PERFORM set_config('probe.p132','N/A (sin cuenta para fixture)',false);
  ELSE
    PERFORM public.asignar_rol_miembro(current_setting('probe.p132_admin', true)::uuid, 'lectura');
    PERFORM set_config('probe.p132','PERMITIDO (afín quedó sin admin!)',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p132','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p132','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P133 — NEG (cross-tipo): el afín NO ve datos privados de laboratorio/visitador
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_admin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  SELECT (SELECT count(*) FROM public.visitas_agendadas) + (SELECT count(*) FROM public.ordenes_examen) INTO n;
  IF n > 0 THEN PERFORM set_config('probe.p133','VISIBLE (afín ve '||n||' filas lab/visitador!)',false);
  ELSE PERFORM set_config('probe.p133','OCULTO (0 filas lab/visitador)',false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p133','OCULTO ('||SQLSTATE||')',false);
END $$;

-- P134 — POS (no sobre-filtrado): el médico SIGUE viendo productos activos de tipos NO-afín
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  IF NULLIF(current_setting('probe.af_medico',true),'') IS NULL THEN PERFORM set_config('probe.p134','N/A (sin médico puro)',false);
  ELSE
    SELECT count(*) INTO n FROM public.productos_empresa
      WHERE empresa_id = NULLIF(current_setting('probe.nonafin_emp',true),'')::uuid AND estado='activo';
    IF n > 0 THEN PERFORM set_config('probe.p134','OK (médico ve '||n||' productos NO-afín activos)',false);
    ELSE PERFORM set_config('probe.p134','REGRESIÓN (sobre-filtrado: médico no ve NO-afín)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p134','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- ============================================================
-- INCREMENTO 4 · Saneo QR de despacho (A-refinada) · P135–P146
-- ------------------------------------------------------------
-- GUARDADO: si los RPC nuevos no existen aún (pre-migración 085) TODO queda
-- 'N/A (pendiente migración 085)' = rojo. Fixture en la transacción del harness
-- (ROLLBACK): 2 empresas farmacia con ítems (A,B) + 1 sin ítems (C) + actor sin
-- permiso (delivery) + receta médico con ítem para A y para B + receta con token
-- EXPIRADO. Todos los datos nuevos se tocan solo dentro del guard.
-- ============================================================
SELECT set_config('role','none',true);
DO $$
DECLARE
  v_pais uuid; v_empA uuid; v_empB uuid; v_empC uuid; v_farmA int; v_farmB int;
  v_actorA uuid; v_actorB uuid; v_actorC uuid; v_noperm uuid;
  v_medico uuid; v_paciente bigint; v_r1 bigint; v_iA bigint; v_iB bigint;
  v_ra1 uuid; v_tok1 text; v_r3 bigint; v_iA3 bigint; v_ra3 uuid; v_tok3 text;
  v_rY bigint; v_iY1 bigint; v_raY uuid; v_tokY text;
BEGIN
  IF to_regprocedure('public.verificar_receta_despacho(text)') IS NULL THEN
    PERFORM set_config('probe.qr_ready','0',false);
    PERFORM set_config('probe.p135','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p136','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p137','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p138','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p139','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p140','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p141','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p142','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p143','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p144','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p145','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p146','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p147','N/A (pendiente migración 085)',false);
    PERFORM set_config('probe.p148','N/A (pendiente migración 085)',false);
    RETURN;
  END IF;
  SELECT pais_id INTO v_pais FROM public.empresas_proveedoras WHERE tipo='empresa_afin' LIMIT 1;
  SELECT id INTO v_actorA FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 6;
  SELECT id INTO v_actorB FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 7;
  SELECT id INTO v_actorC FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 8;
  SELECT id INTO v_noperm FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 9;
  SELECT id INTO v_medico FROM public.perfiles WHERE rol='medico' ORDER BY id LIMIT 1;
  SELECT id INTO v_paciente FROM public.pacientes ORDER BY id LIMIT 1;
  IF v_noperm IS NULL OR v_paciente IS NULL OR v_medico IS NULL THEN
    PERFORM set_config('probe.qr_ready','0',false);
    PERFORM set_config('probe.p135','N/A (datos insuficientes)',false);  -- (el resto hereda N/A si quedó del run previo)
    RETURN;
  END IF;
  PERFORM set_config('probe.qr_ready','1',false);
  -- empresas farmacia + sucursales
  INSERT INTO public.empresas_proveedoras (nombre_empresa,email_contacto,tipo,pais_id,estado) VALUES ('QR FarmA','qra@probe.test','farmacia',v_pais,'activa') RETURNING id INTO v_empA;
  INSERT INTO public.empresas_proveedoras (nombre_empresa,email_contacto,tipo,pais_id,estado) VALUES ('QR FarmB','qrb@probe.test','farmacia',v_pais,'activa') RETURNING id INTO v_empB;
  INSERT INTO public.empresas_proveedoras (nombre_empresa,email_contacto,tipo,pais_id,estado) VALUES ('QR FarmC','qrc@probe.test','farmacia',v_pais,'activa') RETURNING id INTO v_empC;
  INSERT INTO public.farmacias (nombre,empresa_id,tipo,pais_id) VALUES ('Suc A',v_empA,'farmacia',v_pais) RETURNING id INTO v_farmA;
  INSERT INTO public.farmacias (nombre,empresa_id,tipo,pais_id) VALUES ('Suc B',v_empB,'farmacia',v_pais) RETURNING id INTO v_farmB;
  UPDATE public.cuentas_proveedor SET empresa_id=v_empA, rol_en_empresa='admin',    activo=true, equipo_id=NULL WHERE id=v_actorA;
  UPDATE public.cuentas_proveedor SET empresa_id=v_empB, rol_en_empresa='admin',    activo=true, equipo_id=NULL WHERE id=v_actorB;
  UPDATE public.cuentas_proveedor SET empresa_id=v_empC, rol_en_empresa='admin',    activo=true, equipo_id=NULL WHERE id=v_actorC;
  UPDATE public.cuentas_proveedor SET empresa_id=v_empA, rol_en_empresa='delivery', activo=true, equipo_id=NULL WHERE id=v_noperm;  -- delivery: sin recetas_dispensar
  -- R1: receta con ítem para farmacia A y para B + recetas_avanzadas (token fuerte por DEFAULT)
  INSERT INTO public.recetas (medico_id,paciente_id,estado) VALUES (v_medico,v_paciente,'activa') RETURNING id INTO v_r1;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id) VALUES (v_r1,'Med A1','1','c/8h',2,v_farmA) RETURNING id INTO v_iA;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id) VALUES (v_r1,'Med B1','1','c/12h',1,v_farmB) RETURNING id INTO v_iB;
  INSERT INTO public.recetas_avanzadas (receta_base_id,paciente_id,medico_id,estado_dispensacion) VALUES (v_r1, v_paciente::text, v_medico::text, 'pendiente') RETURNING id, dispatch_token INTO v_ra1, v_tok1;
  -- R3: token EXPIRADO (vencido ayer)
  INSERT INTO public.recetas (medico_id,paciente_id,estado) VALUES (v_medico,v_paciente,'activa') RETURNING id INTO v_r3;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id) VALUES (v_r3,'Med A3','1','c/8h',1,v_farmA) RETURNING id INTO v_iA3;
  INSERT INTO public.recetas_avanzadas (receta_base_id,paciente_id,medico_id,estado_dispensacion,dispatch_token_expira_at) VALUES (v_r3, v_paciente::text, v_medico::text, 'pendiente', now() - interval '1 day') RETURNING id, dispatch_token INTO v_ra3, v_tok3;
  -- RY: OTRA receta con un ítem en la MISMA farmacia A (para binding token↔receta y array mixto)
  INSERT INTO public.recetas (medico_id,paciente_id,estado) VALUES (v_medico,v_paciente,'activa') RETURNING id INTO v_rY;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id) VALUES (v_rY,'Med Y1','1','c/8h',1,v_farmA) RETURNING id INTO v_iY1;
  INSERT INTO public.recetas_avanzadas (receta_base_id,paciente_id,medico_id,estado_dispensacion) VALUES (v_rY, v_paciente::text, v_medico::text, 'pendiente') RETURNING id, dispatch_token INTO v_raY, v_tokY;
  PERFORM set_config('probe.qr_actorA', v_actorA::text, false);
  PERFORM set_config('probe.qr_actorB', v_actorB::text, false);
  PERFORM set_config('probe.qr_actorC', v_actorC::text, false);
  PERFORM set_config('probe.qr_noperm', v_noperm::text, false);
  PERFORM set_config('probe.qr_medico', v_medico::text, false);
  PERFORM set_config('probe.qr_tok1', v_tok1, false);
  PERFORM set_config('probe.qr_tok3', v_tok3, false);
  PERFORM set_config('probe.qr_iA', v_iA::text, false);
  PERFORM set_config('probe.qr_iB', v_iB::text, false);
  PERFORM set_config('probe.qr_iY1', v_iY1::text, false);
  PERFORM set_config('probe.qr_tokY', v_tokY, false);
END $$;

-- Helper de aserción: cada probe corre como un actor (jwt) y captura el veredicto.
-- P135 — NEG: autenticado SIN recetas_dispensar (delivery) + token válido → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_noperm', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p135','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.verificar_receta_despacho(current_setting('probe.qr_tok1', true));
       PERFORM set_config('probe.p135','PERMITIDO (sin permiso vio receta!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p135','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p135','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P136 — NEG: token viejo/adivinado (formato EZP-…) → no resuelve → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p136','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.verificar_receta_despacho('EZP-1700000000-ABC123');
       PERFORM set_config('probe.p136','PERMITIDO (token viejo resolvió!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p136','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p136','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P137 — NEG: verificar cross-farmacia (actor de empresa C, sin ítems en la receta) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorC', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p137','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.verificar_receta_despacho(current_setting('probe.qr_tok1', true));
       PERFORM set_config('probe.p137','PERMITIDO (farmacia ajena vio receta!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p137','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p137','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P146 — AISLAMIENTO POR ÍTEM: actor A verifica → ve SOLO su ítem (A1), NO el de B (B1)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; v_a bool; v_b bool; BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p146','N/A (pendiente migración 085)',false);
  ELSE
    v := public.verificar_receta_despacho(current_setting('probe.qr_tok1', true));
    v_a := EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') e WHERE (e->>'item_id') = current_setting('probe.qr_iA',true));
    v_b := EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') e WHERE (e->>'item_id') = current_setting('probe.qr_iB',true));
    IF v_a AND NOT v_b THEN PERFORM set_config('probe.p146','OK (ve solo su ítem A, no el de B)',false);
    ELSE PERFORM set_config('probe.p146','FUGA (a='||v_a||' b='||v_b||')',false); END IF;
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p146','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p146','ERROR ('||SQLSTATE||')',false);
END $$;

-- P144 — PHI MÍNIMA: el payload NO trae teléfono (ni PII de más)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p144','N/A (pendiente migración 085)',false);
  ELSE
    v := public.verificar_receta_despacho(current_setting('probe.qr_tok1', true));
    IF (v ? 'telefono') OR (v::text ILIKE '%telefono%') OR (v::text ILIKE '%direccion%') OR (v::text ILIKE '%diagnostico%') OR (v::text ILIKE '%firma%')
      THEN PERFORM set_config('probe.p144','FUGA (trae PII de más!)',false);
      ELSE PERFORM set_config('probe.p144','OK (PHI mínima: sin teléfono/PII)',false); END IF;
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p144','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p144','ERROR ('||SQLSTATE||')',false);
END $$;

-- P143 — NEG: token NULL/vacío → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p143','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.verificar_receta_despacho(NULL);
       PERFORM set_config('probe.p143','PERMITIDO (token NULL resolvió!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p143','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p143','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P145 — NEG: token EXPIRADO → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p145','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.verificar_receta_despacho(current_setting('probe.qr_tok3', true));
       PERFORM set_config('probe.p145','PERMITIDO (token expirado resolvió!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p145','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p145','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P139 — NEG: registrar sin permiso (delivery) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_noperm', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p139','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.registrar_dispensacion(current_setting('probe.qr_tok1', true), ARRAY[NULLIF(current_setting('probe.qr_iA',true),'')::bigint], 'X');
       PERFORM set_config('probe.p139','PERMITIDO (sin permiso despachó!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p139','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p139','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P140 — NEG: registrar cross-farmacia (actor B intenta despachar el ítem de A) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorB', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p140','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.registrar_dispensacion(current_setting('probe.qr_tok1', true), ARRAY[NULLIF(current_setting('probe.qr_iA',true),'')::bigint], 'X');
       PERFORM set_config('probe.p140','PERMITIDO (despachó ítem de otra farmacia!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p140','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p140','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P142 — NEG: médico (sin cuenta de farmacia) intenta registrar → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p142','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.registrar_dispensacion(current_setting('probe.qr_tok1', true), ARRAY[NULLIF(current_setting('probe.qr_iA',true),'')::bigint], 'X');
       PERFORM set_config('probe.p142','PERMITIDO (médico despachó!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p142','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p142','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P138 — POSITIVO: actor A (recetas_dispensar, farmacia asignada) verifica + despacha SU ítem → OK
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; v_n int; BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p138','N/A (pendiente migración 085)',false);
  ELSE
    PERFORM public.verificar_receta_despacho(current_setting('probe.qr_tok1', true));   -- ve su ítem
    v := public.registrar_dispensacion(current_setting('probe.qr_tok1', true), ARRAY[NULLIF(current_setting('probe.qr_iA',true),'')::bigint], 'Farmaceutico A');
    v_n := (v->>'despachados')::int;
    IF v_n = 1 THEN PERFORM set_config('probe.p138','OK (despachó su ítem A)',false);
    ELSE PERFORM set_config('probe.p138','REGRESIÓN (despachados='||COALESCE(v_n,-1)||')',false); END IF;
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p138','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p138','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P141 — NEG: re-despacho del mismo ítem (ya dispensado por P138) → BLOQUEADO.
--   La ACCIÓN corre como el actor; la VERIFICACIÓN de estado de receta_items corre
--   con role='none' (bypass RLS) porque un actor de farmacia no puede LEER receta_items.
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p141_act','N/A (pendiente migración 085)',false);
  ELSE
    BEGIN
      PERFORM public.registrar_dispensacion(current_setting('probe.qr_tok1', true), ARRAY[NULLIF(current_setting('probe.qr_iA',true),'')::bigint], 'X');
      PERFORM set_config('probe.p141_act','PERMITIDO',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p141_act','BLOQUEADO',false);
    END;
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p141_act','N/A (RPC no existe)',false);
END $$;
SELECT set_config('role','none',true);  -- verificación de estado bypass RLS
DO $$ DECLARE v_bpend bool; BEGIN
  IF current_setting('probe.p141_act', true) NOT IN ('BLOQUEADO','PERMITIDO') THEN PERFORM set_config('probe.p141',current_setting('probe.p141_act',true),false);
  ELSE
    SELECT (dispensado = false) INTO v_bpend FROM public.receta_items WHERE id = NULLIF(current_setting('probe.qr_iB',true),'')::bigint;
    IF current_setting('probe.p141_act',true)='BLOQUEADO' AND COALESCE(v_bpend,false)
      THEN PERFORM set_config('probe.p141','BLOQUEADO (re-despacho; ítem B sigue pendiente)',false);
      ELSE PERFORM set_config('probe.p141','FALLO (act='||current_setting('probe.p141_act',true)||' B_pend='||COALESCE(v_bpend::text,'NULL')||')',false); END IF;
  END IF;
END $$;

-- P147 — NEG (binding token↔receta): token de R1 + ítem de la PROPIA farmacia A pero de
--   OTRA receta (RY) → BLOQUEADO (el array NO puede despachar fuera de la receta del token).
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p147','N/A (pendiente migración 085)',false);
  ELSE PERFORM public.registrar_dispensacion(current_setting('probe.qr_tok1', true), ARRAY[NULLIF(current_setting('probe.qr_iY1',true),'')::bigint], 'X');
       PERFORM set_config('probe.p147','PERMITIDO (despachó ítem de otra receta vía array!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p147','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p147','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P148 — array MIXTO: token de RY + [iY1 (propio, RY) , iB (R1/otra farmacia)] → despacha
--   SOLO iY1; iB queda intacto (no escrito).
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.qr_actorA', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.qr_ready', true) <> '1' THEN PERFORM set_config('probe.p148_n','N/A (pendiente migración 085)',false);
  ELSE
    v := public.registrar_dispensacion(current_setting('probe.qr_tokY', true),
           ARRAY[NULLIF(current_setting('probe.qr_iY1',true),'')::bigint, NULLIF(current_setting('probe.qr_iB',true),'')::bigint], 'Farm A');
    PERFORM set_config('probe.p148_n', COALESCE((v->>'despachados'),'?'), false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p148_n','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p148_n','ERROR ('||SQLSTATE||')',false);
END $$;
SELECT set_config('role','none',true);  -- verificación de estado bypass RLS
DO $$ DECLARE v_b_intacto bool; BEGIN
  IF current_setting('probe.p148_n', true) !~ '^[0-9]+$' THEN PERFORM set_config('probe.p148',current_setting('probe.p148_n',true),false);
  ELSE
    SELECT (dispensado = false) INTO v_b_intacto FROM public.receta_items WHERE id = NULLIF(current_setting('probe.qr_iB',true),'')::bigint;
    IF current_setting('probe.p148_n',true)='1' AND COALESCE(v_b_intacto,false)
      THEN PERFORM set_config('probe.p148','OK (despachó solo el propio; ajeno intacto)',false);
      ELSE PERFORM set_config('probe.p148','FUGA (despachados='||current_setting('probe.p148_n',true)||' b_intacto='||COALESCE(v_b_intacto::text,'NULL')||')',false); END IF;
  END IF;
END $$;

-- ============================================================
-- INCREMENTO 5 (Frente A) · Catálogo de farmacia + CSV · P149–P158
-- Fixture (ROLLBACK): empresa farmacia A (sucursal + cuenta admin c/ inventario_editar
-- + cuenta cajero SIN permiso) + empresa farmacia B (sucursal + med ajeno).
-- P149–P152 corren siempre (RLS escritura ya existe; P151 = lectura, rojo pre-086).
-- P153–P158 guardan en el RPC cargar_catalogo_farmacia (N/A pre-086).
-- ============================================================
SELECT set_config('role','none',true);
DO $$
DECLARE v_pais uuid; v_eA uuid; v_eB uuid; v_fA int; v_fB int; v_inv uuid; v_sin uuid; v_mA uuid; v_mB uuid; v_clin uuid;
BEGIN
  SELECT pais_id INTO v_pais FROM public.empresas_proveedoras WHERE tipo='empresa_afin' LIMIT 1;
  SELECT id INTO v_inv FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 10;
  SELECT id INTO v_sin FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 11;
  -- actor clínico NO-médico, NO-proveedor (enfermera/asistente → perfil rol no medico/super_admin)
  SELECT id INTO v_clin FROM public.perfiles WHERE rol NOT IN ('medico','super_admin')
    AND id NOT IN (SELECT id FROM public.cuentas_proveedor) ORDER BY id LIMIT 1;
  IF v_sin IS NULL THEN
    PERFORM set_config('probe.cat_ready','0',false);
    PERFORM set_config('probe.p149','N/A (datos insuficientes)',false);
    PERFORM set_config('probe.p150','N/A',false); PERFORM set_config('probe.p151','N/A',false);
    PERFORM set_config('probe.p152','N/A',false); PERFORM set_config('probe.p153','N/A',false);
    PERFORM set_config('probe.p154','N/A',false); PERFORM set_config('probe.p155','N/A',false);
    PERFORM set_config('probe.p156','N/A',false); PERFORM set_config('probe.p157','N/A',false);
    PERFORM set_config('probe.p158','N/A',false);
    PERFORM set_config('probe.p159','N/A',false); PERFORM set_config('probe.p160','N/A',false); RETURN;
  END IF;
  PERFORM set_config('probe.cat_ready','1',false);
  INSERT INTO public.empresas_proveedoras (nombre_empresa,email_contacto,tipo,pais_id,estado) VALUES ('CAT FarmA','cata@p.test','farmacia',v_pais,'activa') RETURNING id INTO v_eA;
  INSERT INTO public.empresas_proveedoras (nombre_empresa,email_contacto,tipo,pais_id,estado) VALUES ('CAT FarmB','catb@p.test','farmacia',v_pais,'activa') RETURNING id INTO v_eB;
  INSERT INTO public.farmacias (nombre,empresa_id,tipo,pais_id) VALUES ('CAT SucA',v_eA,'farmacia',v_pais) RETURNING id INTO v_fA;
  INSERT INTO public.farmacias (nombre,empresa_id,tipo,pais_id) VALUES ('CAT SucB',v_eB,'farmacia',v_pais) RETURNING id INTO v_fB;
  UPDATE public.cuentas_proveedor SET empresa_id=v_eA, rol_en_empresa='admin',  activo=true, equipo_id=NULL WHERE id=v_inv;
  UPDATE public.cuentas_proveedor SET empresa_id=v_eA, rol_en_empresa='cajero', activo=true, equipo_id=NULL WHERE id=v_sin;
  INSERT INTO public.farmacia_medicamentos (farmacia_id,nombre_medicamento,stock_actual,stock_minimo,precio_unitario,activo) VALUES (v_fA,'MED PROPIO A',10,1,5.0,true) RETURNING id INTO v_mA;
  INSERT INTO public.farmacia_medicamentos (farmacia_id,nombre_medicamento,stock_actual,stock_minimo,precio_unitario,activo) VALUES (v_fB,'MED AJENO B',20,1,9.0,true) RETURNING id INTO v_mB;
  PERFORM set_config('probe.cat_inv',v_inv::text,false); PERFORM set_config('probe.cat_sin',v_sin::text,false);
  PERFORM set_config('probe.cat_fA',v_fA::text,false);   PERFORM set_config('probe.cat_fB',v_fB::text,false);
  PERFORM set_config('probe.cat_mA',v_mA::text,false);   PERFORM set_config('probe.cat_mB',v_mB::text,false);
  PERFORM set_config('probe.cat_clinico', COALESCE(v_clin::text,''), false);
END $$;

-- P149 — NEG: cuenta SIN inventario_editar (cajero) edita inventario → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_sin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p149','N/A (datos insuficientes)',false);
  ELSE
    UPDATE public.farmacia_medicamentos SET precio_unitario=999 WHERE id=NULLIF(current_setting('probe.cat_mA',true),'')::uuid;
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n>0 THEN PERFORM set_config('probe.p149','PERMITIDO (cajero editó inventario!)',false);
    ELSE PERFORM set_config('probe.p149','BLOQUEADO (0 filas)',false); END IF;
  END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p149','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p149','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P150 — NEG: cuenta de empresa A edita catálogo de empresa B (ajeno) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p150','N/A',false);
  ELSE
    UPDATE public.farmacia_medicamentos SET precio_unitario=999 WHERE id=NULLIF(current_setting('probe.cat_mB',true),'')::uuid;
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n>0 THEN PERFORM set_config('probe.p150','PERMITIDO (editó catálogo ajeno!)',false);
    ELSE PERFORM set_config('probe.p150','BLOQUEADO (0 filas)',false); END IF;
  END IF;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p150','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p150','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P151 — NEG (B, rojo pre-086): cuenta de farmacia A LEE catálogo de empresa B → OCULTO(0)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p151','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id=NULLIF(current_setting('probe.cat_fB',true),'')::int;
    IF n>0 THEN PERFORM set_config('probe.p151','VISIBLE (farmacia ve '||n||' ajeno!)',false);
    ELSE PERFORM set_config('probe.p151','OCULTO (0 ajeno)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p151','OCULTO ('||SQLSTATE||')',false);
END $$;

-- P152 — POS (no-regresión disponibilidad): médico VE inventario de farmacia → OK
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' OR NULLIF(current_setting('probe.af_medico',true),'') IS NULL THEN PERFORM set_config('probe.p152','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id IN (NULLIF(current_setting('probe.cat_fA',true),'')::int, NULLIF(current_setting('probe.cat_fB',true),'')::int);
    IF n>0 THEN PERFORM set_config('probe.p152','OK (médico ve '||n||' disponibilidad)',false);
    ELSE PERFORM set_config('probe.p152','REGRESIÓN (médico no ve disponibilidad)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p152','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P153 — NEG: RPC carga sin inventario_editar (cajero) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_sin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL THEN PERFORM set_config('probe.p153','N/A (pendiente migración 086)',false);
  ELSE PERFORM public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int, '[{"nombre_medicamento":"CAT X"}]'::jsonb);
       PERFORM set_config('probe.p153','PERMITIDO (cargó sin permiso!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p153','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p153','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P154 — NEG: RPC carga a farmacia AJENA (empresa B) → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL THEN PERFORM set_config('probe.p154','N/A (pendiente migración 086)',false);
  ELSE PERFORM public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fB',true),'')::int, '[{"nombre_medicamento":"CAT X"}]'::jsonb);
       PERFORM set_config('probe.p154','PERMITIDO (cargó a farmacia ajena!)',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p154','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p154','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P155 — POS idempotencia: cargar el mismo nombre 2 veces → 1 sola fila
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL THEN PERFORM set_config('probe.p155_done','0',false);
  ELSE
    PERFORM public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int, '[{"nombre_medicamento":"CAT IDEM","stock_actual":"3"}]'::jsonb);
    PERFORM public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int, '[{"nombre_medicamento":"  cat   idem ","stock_actual":"7"}]'::jsonb);  -- misma forma normalizada
    PERFORM set_config('probe.p155_done','1',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p155_done','0',false);
  WHEN others THEN PERFORM set_config('probe.p155_done','err',false);
END $$;
SELECT set_config('role','none',true);  -- verificación de estado bypass RLS
DO $$ DECLARE n INT; BEGIN
  IF current_setting('probe.p155_done',true)<>'1' THEN PERFORM set_config('probe.p155','N/A (pendiente migración 086)',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id=NULLIF(current_setting('probe.cat_fA',true),'')::int AND nombre_normalizado = 'CAT IDEM';
    IF n=1 THEN PERFORM set_config('probe.p155','OK (idempotente: 1 fila)',false);
    ELSE PERFORM set_config('probe.p155','FALLO (filas='||n||')',false); END IF;
  END IF;
END $$;

-- P156 — POS reporte por fila: [{vacío},{válido}] → 1 rechazada, ≥1 válida
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL THEN PERFORM set_config('probe.p156','N/A (pendiente migración 086)',false);
  ELSE
    v := public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int, '[{"nombre_medicamento":""},{"nombre_medicamento":"CAT VALIDO","stock_actual":"2"}]'::jsonb);
    IF (v->>'total_rechazadas')::int = 1 AND ((v->>'insertadas')::int + (v->>'actualizadas')::int) >= 1
      THEN PERFORM set_config('probe.p156','OK (1 rechazada, válida entró)',false);
      ELSE PERFORM set_config('probe.p156','FALLO ('||v::text||')',false); END IF;
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p156','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p156','FALLO ('||SQLSTATE||')',false);
END $$;

-- P157 — POS: stock vacío NO borra el existente (conserva)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL THEN PERFORM set_config('probe.p157_done','0',false);
  ELSE PERFORM public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int, '[{"nombre_medicamento":"MED PROPIO A","stock_actual":""}]'::jsonb);
       PERFORM set_config('probe.p157_done','1',false); END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p157_done','0',false);
  WHEN others THEN PERFORM set_config('probe.p157_done','err',false);
END $$;
SELECT set_config('role','none',true);
DO $$ DECLARE v INT; BEGIN
  IF current_setting('probe.p157_done',true)<>'1' THEN PERFORM set_config('probe.p157','N/A (pendiente migración 086)',false);
  ELSE
    SELECT stock_actual INTO v FROM public.farmacia_medicamentos WHERE id=NULLIF(current_setting('probe.cat_mA',true),'')::uuid;
    IF v=10 THEN PERFORM set_config('probe.p157','OK (stock conservado=10, blanco no borró)',false);
    ELSE PERFORM set_config('probe.p157','FALLO (stock='||COALESCE(v::text,'NULL')||')',false); END IF;
  END IF;
END $$;

-- P158 — POS: rol con inventario_editar carga su catálogo → OK
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL THEN PERFORM set_config('probe.p158','N/A (pendiente migración 086)',false);
  ELSE
    v := public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int, '[{"nombre_medicamento":"CAT POS","stock_actual":"5","precio_unitario":"12.5"}]'::jsonb);
    IF ((v->>'insertadas')::int + (v->>'actualizadas')::int) >= 1 THEN PERFORM set_config('probe.p158','OK (cargó su catálogo)',false);
    ELSE PERFORM set_config('probe.p158','FALLO ('||v::text||')',false); END IF;
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p158','N/A (RPC no existe)',false);
  WHEN others THEN PERFORM set_config('probe.p158','FALLO ('||SQLSTATE||')',false);
END $$;

-- P159 — NEG (B, rojo pre-086): ANON NO lee farmacia_medicamentos → OCULTO(0)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', NULL, true);
SELECT set_config('role','anon',true);
DO $$ DECLARE n INT; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p159','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id IN (NULLIF(current_setting('probe.cat_fA',true),'')::int, NULLIF(current_setting('probe.cat_fB',true),'')::int);
    IF n>0 THEN PERFORM set_config('probe.p159','VISIBLE (anon lee '||n||'!)',false);
    ELSE PERFORM set_config('probe.p159','OCULTO (0 anon)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p159','OCULTO ('||SQLSTATE||')',false);
END $$;

-- P160 — POS: lado clínico NO-médico (enfermera/asistente) VE disponibilidad → OK
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_clinico', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n INT; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' OR NULLIF(current_setting('probe.cat_clinico',true),'') IS NULL THEN PERFORM set_config('probe.p160','N/A (sin clínico no-médico)',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id IN (NULLIF(current_setting('probe.cat_fA',true),'')::int, NULLIF(current_setting('probe.cat_fB',true),'')::int) AND COALESCE(activo,true);
    IF n>0 THEN PERFORM set_config('probe.p160','OK (clínico no-médico ve '||n||' disponibilidad)',false);
    ELSE PERFORM set_config('probe.p160','REGRESIÓN (clínico no-médico no ve disponibilidad)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p160','REGRESIÓN ('||SQLSTATE||')',false);
END $$;

-- P161 — POS: dup INTRA-ARCHIVO (dos filas → misma clave normalizada) → reporta la
-- superada y deja UNA fila (gana la última); no colapsa en silencio.
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL OR current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p161_done','0',false);
  ELSE
    v := public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int,
      '[{"nombre_medicamento":"DUP TEST","stock_actual":"1"},{"nombre_medicamento":"  dup   test ","stock_actual":"9"}]'::jsonb);
    PERFORM set_config('probe.p161_rech', COALESCE((v->>'total_rechazadas'),'?'), false);
    PERFORM set_config('probe.p161_done','1',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p161_done','0',false);
  WHEN others THEN PERFORM set_config('probe.p161_done','err',false);
END $$;
SELECT set_config('role','none',true);
DO $$ DECLARE n INT; st INT; BEGIN
  IF current_setting('probe.p161_done',true)<>'1' THEN PERFORM set_config('probe.p161','N/A (pendiente migración 087)',false);
  ELSE
    SELECT count(*), max(stock_actual) INTO n, st FROM public.farmacia_medicamentos
      WHERE farmacia_id=NULLIF(current_setting('probe.cat_fA',true),'')::int AND nombre_normalizado='DUP TEST';
    IF n=1 AND st=9 AND current_setting('probe.p161_rech',true)='1'
      THEN PERFORM set_config('probe.p161','OK (1 fila, última gana stock=9, 1 superada reportada)',false);
      ELSE PERFORM set_config('probe.p161','FALLO (n='||COALESCE(n::text,'?')||' stock='||COALESCE(st::text,'?')||' rech='||current_setting('probe.p161_rech',true)||')',false); END IF;
  END IF;
END $$;

-- P162 — POS (conducta nueva de normalización b): "500 mg" y "500MG" son la MISMA
-- clave (espacio dígito↔unidad eliminado) → 1 fila, última gana, 1 superada reportada.
-- Verde SOLO tras 088 (regla b); con la regla previa serían 2 filas distintas.
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; BEGIN
  IF to_regprocedure('public.cargar_catalogo_farmacia(integer,jsonb)') IS NULL OR current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p162_done','0',false);
  ELSE
    v := public.cargar_catalogo_farmacia(NULLIF(current_setting('probe.cat_fA',true),'')::int,
      '[{"nombre_medicamento":"NORMTEST 500 MG","stock_actual":"3"},{"nombre_medicamento":"normtest 500mg","stock_actual":"8"}]'::jsonb);
    PERFORM set_config('probe.p162_rech', COALESCE((v->>'total_rechazadas'),'?'), false);
    PERFORM set_config('probe.p162_done','1',false);
  END IF;
EXCEPTION WHEN undefined_function THEN PERFORM set_config('probe.p162_done','0',false);
  WHEN others THEN PERFORM set_config('probe.p162_done','err',false);
END $$;
SELECT set_config('role','none',true);
DO $$ DECLARE n INT; st INT; BEGIN
  IF current_setting('probe.p162_done',true)<>'1' THEN PERFORM set_config('probe.p162','N/A (pendiente migración 088)',false);
  ELSE
    SELECT count(*), max(stock_actual) INTO n, st FROM public.farmacia_medicamentos
      WHERE farmacia_id=NULLIF(current_setting('probe.cat_fA',true),'')::int AND nombre_normalizado='NORMTEST 500MG';
    IF n=1 AND st=8 AND current_setting('probe.p162_rech',true)='1'
      THEN PERFORM set_config('probe.p162','OK ("500 mg"="500MG": 1 fila, última gana stock=8, 1 superada)',false);
      ELSE PERFORM set_config('probe.p162','FALLO (n='||COALESCE(n::text,'?')||' stock='||COALESCE(st::text,'?')||' rech='||current_setting('probe.p162_rech',true)||')',false); END IF;
  END IF;
END $$;

-- ============================================================
-- FRENTE B · Bandeja de recetas entrantes (P163–P174). Fixture en este BEGIN…ROLLBACK.
-- ============================================================
DO $$
DECLARE v_eA uuid; v_fA int; v_fB int; v_norx uuid; v_med uuid; v_pac int;
        v_rx bigint; v_rx2 bigint; v_rxB bigint; v_itA bigint; v_itB bigint;
BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.rx_ready','0',false); RETURN; END IF;
  v_fA := NULLIF(current_setting('probe.cat_fA',true),'')::int;
  v_fB := NULLIF(current_setting('probe.cat_fB',true),'')::int;
  SELECT empresa_id INTO v_eA FROM public.farmacias WHERE id=v_fA;
  SELECT id INTO v_med FROM public.perfiles WHERE rol='medico' ORDER BY id LIMIT 1;
  SELECT id INTO v_pac FROM public.pacientes ORDER BY id LIMIT 1;
  SELECT id INTO v_norx FROM public.cuentas_proveedor ORDER BY id LIMIT 1 OFFSET 12;
  IF v_med IS NULL OR v_pac IS NULL OR v_norx IS NULL THEN PERFORM set_config('probe.rx_ready','0',false); RETURN; END IF;
  -- usuario en empresa A con rol 'finanzas': SIN recetas_dispensar (sirve P164) y SIN
  -- recetas_reportes pero CON finanzas_reportes (sirve S-NEG2/S-SUC de stats).
  UPDATE public.cuentas_proveedor SET empresa_id=v_eA, rol_en_empresa='finanzas', activo=true, equipo_id=NULL, sucursal_id=NULL WHERE id=v_norx;

  -- (a) receta MIXTA (ítem en A + ítem en B) CON recetas_avanzadas (despachable)
  INSERT INTO public.recetas (medico_id,paciente_id,estado) VALUES (v_med,v_pac,'activa') RETURNING id INTO v_rx;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id)
    VALUES (v_rx,'MED PROPIO A','1 tab','c/8h',2,v_fA) RETURNING id INTO v_itA;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id)
    VALUES (v_rx,'MED AJENO B','1 tab','c/12h',1,v_fB) RETURNING id INTO v_itB;
  INSERT INTO public.recetas_avanzadas (receta_base_id,paciente_id,medico_id,estado_dispensacion)
    VALUES (v_rx,v_pac::text,v_med::text,'pendiente');

  -- (b) receta SOLO B (para aislamiento: A no debe verla)
  INSERT INTO public.recetas (medico_id,paciente_id,estado) VALUES (v_med,v_pac,'activa') RETURNING id INTO v_rxB;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id)
    VALUES (v_rxB,'SOLO B','1','c/24h',1,v_fB);
  INSERT INTO public.recetas_avanzadas (receta_base_id,paciente_id,medico_id,estado_dispensacion)
    VALUES (v_rxB,v_pac::text,v_med::text,'pendiente');

  -- (c) receta SIN recetas_avanzadas (edge: no despachable, rechazo limpio)
  INSERT INTO public.recetas (medico_id,paciente_id,estado) VALUES (v_med,v_pac,'activa') RETURNING id INTO v_rx2;
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia,cantidad,farmacia_id)
    VALUES (v_rx2,'MED PROPIO A','1','c/8h',1,v_fA);

  PERFORM set_config('probe.rx_ready','1',false);
  PERFORM set_config('probe.rx_disp',v_rx::text,false);
  PERFORM set_config('probe.rx_only_b',v_rxB::text,false);
  PERFORM set_config('probe.rx_notoken',v_rx2::text,false);
  PERFORM set_config('probe.rx_itA',v_itA::text,false);
  PERFORM set_config('probe.rx_itB',v_itB::text,false);
  PERFORM set_config('probe.rx_norx',v_norx::text,false);
END $$;

-- Helper: ¿existen las RPC de Frente B? (guarda rojo-primero)
DO $$ BEGIN
  PERFORM set_config('probe.rx_rpc',
    CASE WHEN to_regprocedure('public.listar_recetas_entrantes()') IS NOT NULL
          AND to_regprocedure('public.registrar_dispensacion_dirigida(bigint,bigint[],text)') IS NOT NULL
         THEN '1' ELSE '0' END, false);
END $$;

-- P163 — POS/aislamiento: A lista entrantes → ve la MIXTA (solo su ítem A) y la edge;
-- NO ve la receta SOLO-B.
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; n_total int; n_disp int; n_notoken int; n_b int; n_items int; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p163','N/A (pendiente 090)',false);
  ELSE
    v := public.listar_recetas_entrantes();
    n_total := jsonb_array_length(v);
    SELECT count(*) INTO n_disp    FROM jsonb_array_elements(v) e WHERE (e->>'receta_id')::bigint = NULLIF(current_setting('probe.rx_disp',true),'')::bigint;
    SELECT count(*) INTO n_notoken FROM jsonb_array_elements(v) e WHERE (e->>'receta_id')::bigint = NULLIF(current_setting('probe.rx_notoken',true),'')::bigint;
    SELECT count(*) INTO n_b       FROM jsonb_array_elements(v) e WHERE (e->>'receta_id')::bigint = NULLIF(current_setting('probe.rx_only_b',true),'')::bigint;
    SELECT jsonb_array_length(e->'items_pendientes') INTO n_items FROM jsonb_array_elements(v) e WHERE (e->>'receta_id')::bigint = NULLIF(current_setting('probe.rx_disp',true),'')::bigint;
    -- POSITIVO (A ve LAS SUYAS, count>0): mixta + edge presentes, 1 ítem propio en la mixta.
    -- NEGATIVO (no verde-vacío): SOLO-B ausente.
    IF n_total>0 AND n_disp=1 AND n_notoken=1 AND n_b=0 AND n_items=1
      THEN PERFORM set_config('probe.p163','OK (A ve sus 2 recetas [mixta 1 ítem propio + edge]; NO ve SOLO-B)',false);
      ELSE PERFORM set_config('probe.p163','FALLO (total='||n_total||' disp='||n_disp||' notoken='||n_notoken||' soloB='||n_b||' items='||COALESCE(n_items,-1)||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p163','FALLO ('||SQLERRM||')',false); END $$;

-- P174 — token NUNCA filtrado: el payload de listar no contiene dispatch_token (solo tiene_token)
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p174','N/A (pendiente 090)',false);
  ELSE
    v := public.listar_recetas_entrantes();
    IF v::text NOT ILIKE '%dispatch_token%' AND v::text ILIKE '%tiene_token%' THEN PERFORM set_config('probe.p174','OK (tiene_token sí; dispatch_token NO)',false);
    ELSE PERFORM set_config('probe.p174','FALLO (token filtrado en payload)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p174','FALLO ('||SQLERRM||')',false); END $$;

-- P168 — PHI: el payload no contiene diagnóstico/teléfono/dirección
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p168','N/A (pendiente 090)',false);
  ELSE
    v := public.listar_recetas_entrantes();
    IF v::text NOT ILIKE '%diagnostico%' AND v::text NOT ILIKE '%telefono%' AND v::text NOT ILIKE '%direccion%'
      THEN PERFORM set_config('probe.p168','OK (sin diagnóstico/teléfono/dirección)',false);
      ELSE PERFORM set_config('probe.p168','FALLO (PHI sensible en payload)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p168','FALLO ('||SQLERRM||')',false); END $$;

-- P164 — NEG: usuario SIN recetas_dispensar → listar BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.rx_norx', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p164','N/A (pendiente 090)',false);
  ELSE
    BEGIN v := public.listar_recetas_entrantes(); PERFORM set_config('probe.p164','FALLO (PERMITIDO sin permiso)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p164','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P165 — NEG: anon → listar BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT set_config('role','anon',true);
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p165','N/A (pendiente 090)',false);
  ELSE
    BEGIN v := public.listar_recetas_entrantes(); PERFORM set_config('probe.p165','FALLO (PERMITIDO anon)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p165','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P171 — NEG: farmacéutico vacío → BLOQUEADO (antes de cualquier escritura)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p171','N/A (pendiente 090)',false);
  ELSE
    BEGIN PERFORM public.registrar_dispensacion_dirigida(NULLIF(current_setting('probe.rx_disp',true),'')::bigint, ARRAY[NULLIF(current_setting('probe.rx_itA',true),'')::bigint], '   ');
      PERFORM set_config('probe.p171','FALLO (PERMITIDO farmacéutico vacío)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p171','BLOQUEADO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P172 — edge: receta SIN recetas_avanzadas → RECHAZO limpio (sin FK crudo)
DO $$ BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p172','N/A (pendiente 090)',false);
  ELSE
    BEGIN PERFORM public.registrar_dispensacion_dirigida(NULLIF(current_setting('probe.rx_notoken',true),'')::bigint,
            ARRAY[(SELECT id FROM public.receta_items WHERE receta_id=NULLIF(current_setting('probe.rx_notoken',true),'')::bigint LIMIT 1)], 'Farm QA');
      PERFORM set_config('probe.p172','FALLO (despachó sin recetas_avanzadas)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p172','BLOQUEADO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P166 (LLAMADA) — A despacha [itemA, itemB] bajo rol farmacia (authenticated, cat_inv).
-- La verificación va aparte como role='none' (ground-truth) porque dispensaciones/
-- receta_items están RLS-cerradas para la farmacia (lo que prueba P170): leerlas como
-- la farmacia daría 0/NULL falsos.
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p166_disp','na',false);
  ELSE
    BEGIN
      v := public.registrar_dispensacion_dirigida(NULLIF(current_setting('probe.rx_disp',true),'')::bigint,
             ARRAY[NULLIF(current_setting('probe.rx_itA',true),'')::bigint, NULLIF(current_setting('probe.rx_itB',true),'')::bigint], 'Farm QA');
      PERFORM set_config('probe.p166_disp', COALESCE(v->>'despachados','?'), false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p166_disp','err:'||SQLERRM, false); END;
  END IF;
END $$;
-- VERIFICACIÓN ground-truth (bypassa RLS): el RPC ya escribió; ahora leemos como owner.
SELECT set_config('role','none',true);

-- P166 (VEREDICTO): despachados=1 (solo A) y itemB ajeno intacto (dispensado=false)
DO $$ DECLARE b_disp boolean; d text; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p166','N/A (pendiente 090)',false);
  ELSE
    d := current_setting('probe.p166_disp',true);
    SELECT dispensado INTO b_disp FROM public.receta_items WHERE id=NULLIF(current_setting('probe.rx_itB',true),'')::bigint;
    IF d='1' AND b_disp IS NOT NULL AND b_disp=false THEN PERFORM set_config('probe.p166','OK (1 despachado=A; B ajeno intacto)',false);
    ELSE PERFORM set_config('probe.p166','FALLO (despachados='||COALESCE(d,'?')||' B_dispensado='||COALESCE(b_disp::text,'NULL')||')',false); END IF;
  END IF;
END $$;

-- P169 — POS (ground-truth): tras P166, stock baja (10→8) + 1 dispensación + estado parcial
DO $$ DECLARE v_st int; v_disp int; v_estado text; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p169','N/A (pendiente 090)',false);
  ELSE
    SELECT stock_actual INTO v_st FROM public.farmacia_medicamentos WHERE farmacia_id=NULLIF(current_setting('probe.cat_fA',true),'')::int AND nombre_medicamento='MED PROPIO A';
    SELECT count(*) INTO v_disp FROM public.dispensaciones WHERE receta_avanzada_id IN (SELECT id FROM public.recetas_avanzadas WHERE receta_base_id=NULLIF(current_setting('probe.rx_disp',true),'')::bigint);
    SELECT estado_dispensacion INTO v_estado FROM public.recetas_avanzadas WHERE receta_base_id=NULLIF(current_setting('probe.rx_disp',true),'')::bigint;
    IF v_st=8 AND v_disp=1 AND v_estado='parcial' THEN PERFORM set_config('probe.p169','OK (stock 10→8, 1 dispensación, estado parcial)',false);
    ELSE PERFORM set_config('probe.p169','FALLO (stock='||COALESCE(v_st::text,'?')||' disp='||COALESCE(v_disp::text,'?')||' estado='||COALESCE(v_estado,'?')||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p169','FALLO ('||SQLERRM||')',false); END $$;

-- P173 — auditoría (ground-truth): la fila dispensaciones lleva despachado_por = actor
DO $$ DECLARE v_dp uuid; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p173','N/A (pendiente 090)',false);
  ELSE
    SELECT despachado_por INTO v_dp FROM public.dispensaciones WHERE receta_avanzada_id IN (SELECT id FROM public.recetas_avanzadas WHERE receta_base_id=NULLIF(current_setting('probe.rx_disp',true),'')::bigint) LIMIT 1;
    IF v_dp = NULLIF(current_setting('probe.cat_inv',true),'')::uuid THEN PERFORM set_config('probe.p173','OK (despachado_por = actor)',false);
    ELSE PERFORM set_config('probe.p173','FALLO (despachado_por='||COALESCE(v_dp::text,'NULL')||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p173','FALLO ('||SQLERRM||')',false); END $$;

-- P167 — NEG: re-despacho de itemA ya dispensado → no-op (error 'sin ítems')
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.rx_rpc',true)<>'1' THEN PERFORM set_config('probe.p167','N/A (pendiente 090)',false);
  ELSE
    BEGIN PERFORM public.registrar_dispensacion_dirigida(NULLIF(current_setting('probe.rx_disp',true),'')::bigint, ARRAY[NULLIF(current_setting('probe.rx_itA',true),'')::bigint], 'Farm QA');
      PERFORM set_config('probe.p167','FALLO (re-despachó ítem ya dispensado)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p167','BLOQUEADO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P170 — NEG: lectura DIRECTA por tabla (recetas/receta_items/dispensaciones) por la farmacia → 0
DO $$ DECLARE n1 int; n2 int; n3 int; BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' THEN PERFORM set_config('probe.p170','N/A',false);
  ELSE
    SELECT count(*) INTO n1 FROM public.recetas WHERE id=NULLIF(current_setting('probe.rx_disp',true),'')::bigint;
    SELECT count(*) INTO n2 FROM public.receta_items WHERE receta_id=NULLIF(current_setting('probe.rx_disp',true),'')::bigint;
    SELECT count(*) INTO n3 FROM public.dispensaciones WHERE farmacia_id=NULLIF(current_setting('probe.cat_fA',true),'')::int;
    IF n1=0 AND n2=0 AND n3=0 THEN PERFORM set_config('probe.p170','OCULTO (0/0/0 por tabla; RLS no se afloja)',false);
    ELSE PERFORM set_config('probe.p170','FALLO (recetas='||n1||' items='||n2||' disp='||n3||')',false); END IF;
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- FRENTE C.1 · Maquinaria de sucursal (P175–P179). Rojo-primero: pre-091 las funciones
-- no existen → N/A (pendiente 091). Reusa el fixture de catálogo (cat_inv=admin empA,
-- cat_sin=cajero empA, cat_fA/cat_fB=farmacias empA/empB, probe.medico=médico).
-- ============================================================
-- guarda: ¿existe la maquinaria C.1?
DO $$ BEGIN
  PERFORM set_config('probe.c1_rpc',
    CASE WHEN to_regprocedure('public.crear_sucursal(text,text,text,text,text)') IS NOT NULL
          AND to_regprocedure('private.mi_sucursal()') IS NOT NULL
         THEN '1' ELSE '0' END, false);
END $$;

-- P175 — C-POS1: admin crea sucursal → OK; empresa de la sucursal = la del actor (forzada)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v_id int; v_emp uuid; v_exp uuid; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' OR current_setting('probe.c1_rpc',true)<>'1' THEN PERFORM set_config('probe.p175','N/A (pendiente 091)',false);
  ELSE
    v_id := public.crear_sucursal('C1 SUC POS', 'Dir 1', NULL, NULL, NULL);
    SELECT empresa_id INTO v_emp FROM public.farmacias WHERE id = v_id;
    SELECT empresa_id INTO v_exp FROM public.farmacias WHERE id = NULLIF(current_setting('probe.cat_fA',true),'')::int;
    IF v_id IS NOT NULL AND v_emp = v_exp THEN PERFORM set_config('probe.p175','OK (creada id='||v_id||', empresa forzada = la del actor)',false);
    ELSE PERFORM set_config('probe.p175','FALLO (id='||COALESCE(v_id::text,'?')||' emp='||COALESCE(v_emp::text,'?')||' exp='||COALESCE(v_exp::text,'?')||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p175','FALLO ('||SQLERRM||')',false); END $$;

-- P176 — C-NEG4: cajero (sin sucursales_gestionar) crea → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_sin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' OR current_setting('probe.c1_rpc',true)<>'1' THEN PERFORM set_config('probe.p176','N/A (pendiente 091)',false);
  ELSE
    BEGIN PERFORM public.crear_sucursal('C1 SUC CAJERO'); PERFORM set_config('probe.p176','FALLO (PERMITIDO sin permiso)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p176','BLOQUEADO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P177 — C-NEG5: empresa FORZADA — admin de A crea → empresa = A y NUNCA la de B
-- (crear como cat_inv; VERIFICAR como owner: post-098 el actor ya no ve farmacias ajenas).
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v_id int; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' OR current_setting('probe.c1_rpc',true)<>'1' THEN PERFORM set_config('probe.p177_id','',false);
  ELSE v_id := public.crear_sucursal('C1 SUC FORZADA'); PERFORM set_config('probe.p177_id', v_id::text, false); END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p177_id','err',false); END $$;
SELECT set_config('role','none',true);
DO $$ DECLARE v_emp uuid; v_a uuid; v_b uuid; BEGIN
  IF NULLIF(current_setting('probe.p177_id',true),'') IS NULL OR current_setting('probe.p177_id',true)='err' THEN PERFORM set_config('probe.p177','N/A (pendiente 091)',false);
  ELSE
    SELECT empresa_id INTO v_emp FROM public.farmacias WHERE id = current_setting('probe.p177_id',true)::int;
    SELECT empresa_id INTO v_a FROM public.farmacias WHERE id = NULLIF(current_setting('probe.cat_fA',true),'')::int;
    SELECT empresa_id INTO v_b FROM public.farmacias WHERE id = NULLIF(current_setting('probe.cat_fB',true),'')::int;
    IF v_emp = v_a AND v_emp <> v_b THEN PERFORM set_config('probe.p177','OK (empresa = A, NUNCA B; sin parámetro de empresa)',false);
    ELSE PERFORM set_config('probe.p177','FALLO (emp='||COALESCE(v_emp::text,'?')||' A='||COALESCE(v_a::text,'?')||' B='||COALESCE(v_b::text,'?')||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p177','FALLO ('||SQLERRM||')',false); END $$;

-- P178 — mi_sucursal() = NULL para empresa-wide (admin) Y para no-proveedor (médico)
DO $$ DECLARE v_admin int; v_med int; BEGIN
  IF current_setting('probe.c1_rpc',true)<>'1' THEN PERFORM set_config('probe.p178','N/A (pendiente 091)',false);
  ELSE
    -- mi_sucursal() es SECURITY DEFINER: solo necesita auth.uid() vía jwt.claims (no el role).
    PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true))::text, true);
    SELECT private.mi_sucursal() INTO v_admin;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.medico', true))::text, true);
    SELECT private.mi_sucursal() INTO v_med;
    IF v_admin IS NULL AND v_med IS NULL THEN PERFORM set_config('probe.p178','OK (admin empresa-wide NULL; médico no-proveedor NULL)',false);
    ELSE PERFORM set_config('probe.p178','FALLO (admin='||COALESCE(v_admin::text,'NULL')||' medico='||COALESCE(v_med::text,'NULL')||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('role','none',true); PERFORM set_config('probe.p178','FALLO ('||SQLERRM||')',false); END $$;

-- P179 — C no-proveedor: médico crea sucursal → BLOQUEADO (lo frena el gate de permiso/empresa)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.medico', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.c1_rpc',true)<>'1' THEN PERFORM set_config('probe.p179','N/A (pendiente 091)',false);
  ELSE
    BEGIN PERFORM public.crear_sucursal('C1 SUC MEDICO'); PERFORM set_config('probe.p179','FALLO (PERMITIDO no-proveedor)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p179','BLOQUEADO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P180 — fail-closed: borrar una sucursal con staff scoped (sucursal_id=X) → BLOQUEADO
-- por el FK ON DELETE RESTRICT. Sucursal fresca (sin otras refs) para aislar este FK.
-- Como owner (role none) para bypassear RLS y que el FK sea el único blocker.
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true))::text, true);
DO $$ DECLARE v_id int; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' OR current_setting('probe.c1_rpc',true)<>'1' THEN PERFORM set_config('probe.p180','N/A (pendiente 091)',false);
  ELSE
    v_id := public.crear_sucursal('C1 SUC P180');   -- DEFINER; auth.uid()=cat_inv (admin) → permitido
    UPDATE public.cuentas_proveedor SET sucursal_id = v_id WHERE id = NULLIF(current_setting('probe.cat_sin',true),'')::uuid;
    BEGIN
      DELETE FROM public.farmacias WHERE id = v_id;
      PERFORM set_config('probe.p180','FALLO (borró sucursal con staff scoped — fail-open)',false);
    EXCEPTION WHEN foreign_key_violation THEN PERFORM set_config('probe.p180','BLOQUEADO (FK RESTRICT, fail-closed)',false);
             WHEN others THEN PERFORM set_config('probe.p180','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p180','FALLO ('||SQLERRM||')',false); END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- STATS por sucursal (P181–P190). Fixture: siembra dispensaciones 'completada' en empA
-- (STATPOP×6 = sobre k; STATRARE×1 = bajo k; STATPOP rechazada×1 = excluida; STAT2×1 en
-- 2da sucursal empA) y 1 en empB (aislamiento). Todo en el BEGIN…ROLLBACK.
-- ============================================================
DO $$
DECLARE v_eA uuid; v_fB int; v_fA1 int; v_fA2 int; v_ra_a uuid; v_ra_b uuid; v_pac text; v_med text;
BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' THEN PERFORM set_config('probe.st_ready','0',false); RETURN; END IF;
  v_fB := NULLIF(current_setting('probe.cat_fB',true),'')::int;
  SELECT empresa_id INTO v_eA FROM public.farmacias WHERE id = NULLIF(current_setting('probe.cat_fA',true),'')::int;
  SELECT id, paciente_id, medico_id INTO v_ra_a, v_pac, v_med FROM public.recetas_avanzadas WHERE receta_base_id = NULLIF(current_setting('probe.rx_disp',true),'')::bigint;
  SELECT id INTO v_ra_b FROM public.recetas_avanzadas WHERE receta_base_id = NULLIF(current_setting('probe.rx_only_b',true),'')::bigint;
  IF v_ra_a IS NULL OR v_ra_b IS NULL THEN PERFORM set_config('probe.st_ready','0',false); RETURN; END IF;
  -- DOS sucursales FRESCAS en empA (aisladas de v_fA, que P166 ya tocó con un despacho).
  INSERT INTO public.farmacias (nombre, empresa_id, tipo, pais_id) SELECT 'ST SUC A1', v_eA, 'farmacia', pais_id FROM public.empresas_proveedoras WHERE id=v_eA RETURNING id INTO v_fA1;
  INSERT INTO public.farmacias (nombre, empresa_id, tipo, pais_id) SELECT 'ST SUC A2', v_eA, 'farmacia', pais_id FROM public.empresas_proveedoras WHERE id=v_eA RETURNING id INTO v_fA2;
  -- STATPOP × 6 (completada) en sucursal A1 → sobre k
  INSERT INTO public.dispensaciones (receta_avanzada_id,farmacia_id,paciente_id,medico_id,codigo_qr,medicamentos_dispensados,cantidad_items,total_dispensado,estado_dispensacion,fecha_dispensacion)
  SELECT v_ra_a, v_fA1, v_pac, v_med, 'STATS', jsonb_build_array(jsonb_build_object('nombre','STATPOP','cantidad',1)), 1, 10, 'completada', now() FROM generate_series(1,6);
  -- STATRARE × 1 (completada) → bajo k
  INSERT INTO public.dispensaciones (receta_avanzada_id,farmacia_id,paciente_id,medico_id,codigo_qr,medicamentos_dispensados,cantidad_items,total_dispensado,estado_dispensacion,fecha_dispensacion)
  VALUES (v_ra_a, v_fA1, v_pac, v_med, 'STATS', jsonb_build_array(jsonb_build_object('nombre','STATRARE','cantidad',1)), 1, 10, 'completada', now());
  -- STATPOP rechazada × 1 → NO debe contar (montos/clínico solo completada)
  INSERT INTO public.dispensaciones (receta_avanzada_id,farmacia_id,paciente_id,medico_id,codigo_qr,medicamentos_dispensados,cantidad_items,total_dispensado,estado_dispensacion,fecha_dispensacion)
  VALUES (v_ra_a, v_fA1, v_pac, v_med, 'STATS', jsonb_build_array(jsonb_build_object('nombre','STATPOP','cantidad',1)), 1, 999, 'rechazada', now());
  -- STAT2 × 1 en sucursal A2
  INSERT INTO public.dispensaciones (receta_avanzada_id,farmacia_id,paciente_id,medico_id,codigo_qr,medicamentos_dispensados,cantidad_items,total_dispensado,estado_dispensacion,fecha_dispensacion)
  VALUES (v_ra_a, v_fA2, v_pac, v_med, 'STATS', jsonb_build_array(jsonb_build_object('nombre','STAT2','cantidad',1)), 1, 10, 'completada', now());
  -- STATB × 1 en empB (aislamiento)
  INSERT INTO public.dispensaciones (receta_avanzada_id,farmacia_id,paciente_id,medico_id,codigo_qr,medicamentos_dispensados,cantidad_items,total_dispensado,estado_dispensacion,fecha_dispensacion)
  VALUES (v_ra_b, v_fB, v_pac, v_med, 'STATS', jsonb_build_array(jsonb_build_object('nombre','STATB','cantidad',1)), 1, 10, 'completada', now());
  PERFORM set_config('probe.st_fa1', v_fA1::text, false);
  PERFORM set_config('probe.st_fa2', v_fA2::text, false);
  PERFORM set_config('probe.st_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.st_ready','0',false); PERFORM set_config('probe.st_err', SQLERRM, false); END $$;

-- guarda: ¿existen las RPC de stats?
DO $$ BEGIN
  PERFORM set_config('probe.st_rpc',
    CASE WHEN to_regprocedure('public.stats_finanzas_sucursal(date,date,integer)') IS NOT NULL
          AND to_regprocedure('public.stats_recetas_sucursal(date,date,integer)') IS NOT NULL
         THEN '1' ELSE '0' END, false);
END $$;

-- P181 — S-POS1: admin (finanzas_reportes) → stats_finanzas: sucursal A total=70 (7 completadas, no la rechazada 999); empB ausente
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v jsonb; v_tot numeric; v_n int; v_fb int; BEGIN
  IF current_setting('probe.st_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p181','N/A (pendiente 092)',false);
  ELSE
    v := public.stats_finanzas_sucursal('2000-01-01','2999-12-31');
    SELECT (e->>'total_dispensado')::numeric, (e->>'dispensaciones')::int INTO v_tot, v_n FROM jsonb_array_elements(v) e WHERE (e->>'sucursal_id')::int = NULLIF(current_setting('probe.st_fa1',true),'')::int;
    SELECT count(*) INTO v_fb FROM jsonb_array_elements(v) e WHERE (e->>'sucursal_id')::int = NULLIF(current_setting('probe.cat_fB',true),'')::int;
    IF v_tot=70 AND v_n=7 AND v_fb=0 THEN PERFORM set_config('probe.p181','OK (sucA1 total=70/7 completadas; rechazada excluida; empB ausente)',false);
    ELSE PERFORM set_config('probe.p181','FALLO (tot='||COALESCE(v_tot::text,'?')||' n='||COALESCE(v_n::text,'?')||' fb='||v_fb||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p181','FALLO ('||SQLERRM||')',false); END $$;

-- P182 — S-POS2: admin (recetas_reportes) → stats_recetas: STATPOP presente; sin paciente/medico/receta
DO $$ DECLARE v jsonb; n_pop int; BEGIN
  IF current_setting('probe.st_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p182','N/A (pendiente 092)',false);
  ELSE
    v := public.stats_recetas_sucursal('2000-01-01','2999-12-31');
    SELECT count(*) INTO n_pop FROM jsonb_array_elements(v) e WHERE e->>'medicamento'='STATPOP' AND (e->>'veces_dispensado')::int = 6;
    IF n_pop=1 THEN PERFORM set_config('probe.p182','OK (STATPOP veces=6 por nombre; agregado)',false);
    ELSE PERFORM set_config('probe.p182','FALLO (n_pop='||n_pop||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p182','FALLO ('||SQLERRM||')',false); END $$;

-- P183 — S-NEG1: cajero (sin finanzas_reportes) → stats_finanzas BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_sin', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p183','N/A (pendiente 092)',false);
  ELSE BEGIN PERFORM public.stats_finanzas_sucursal('2000-01-01','2999-12-31'); PERFORM set_config('probe.p183','FALLO (PERMITIDO sin finanzas_reportes)',false);
       EXCEPTION WHEN others THEN PERFORM set_config('probe.p183','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P184 — S-NEG2: finanzas (tiene finanzas_reportes, NO recetas_reportes) → stats_recetas BLOQUEADO (separación)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.rx_norx', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.rx_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p184','N/A (pendiente 092)',false);
  ELSE BEGIN PERFORM public.stats_recetas_sucursal('2000-01-01','2999-12-31'); PERFORM set_config('probe.p184','FALLO (financiero pudo ver clínico)',false);
       EXCEPTION WHEN others THEN PERFORM set_config('probe.p184','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P185 — S-NEG3: anon → ambas BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT set_config('role','anon',true);
DO $$ DECLARE a boolean:=false; b boolean:=false; BEGIN
  IF current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p185','N/A (pendiente 092)',false);
  ELSE
    BEGIN PERFORM public.stats_finanzas_sucursal('2000-01-01','2999-12-31'); EXCEPTION WHEN others THEN a:=true; END;
    BEGIN PERFORM public.stats_recetas_sucursal('2000-01-01','2999-12-31'); EXCEPTION WHEN others THEN b:=true; END;
    IF a AND b THEN PERFORM set_config('probe.p185','BLOQUEADO (anon en ambas)',false);
    ELSE PERFORM set_config('probe.p185','FALLO (fin='||a||' rec='||b||')',false); END IF;
  END IF;
END $$;

-- P186 — S-NEG4 (no-regresión empresa↔empresa): stats de A NO incluyen empB (ni sucursal ni STATB)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE vf jsonb; vr jsonb; n_fb int; n_statb int; BEGIN
  IF current_setting('probe.st_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p186','N/A (pendiente 092)',false);
  ELSE
    vf := public.stats_finanzas_sucursal('2000-01-01','2999-12-31');
    vr := public.stats_recetas_sucursal('2000-01-01','2999-12-31');
    SELECT count(*) INTO n_fb FROM jsonb_array_elements(vf) e WHERE (e->>'sucursal_id')::int = NULLIF(current_setting('probe.cat_fB',true),'')::int;
    SELECT count(*) INTO n_statb FROM jsonb_array_elements(vr) e WHERE e->>'medicamento'='STATB';
    IF n_fb=0 AND n_statb=0 THEN PERFORM set_config('probe.p186','OK (empB excluida de finanzas y recetas)',false);
    ELSE PERFORM set_config('probe.p186','FALLO (fb='||n_fb||' statb='||n_statb||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p186','FALLO ('||SQLERRM||')',false); END $$;

-- P187 — S-NEG5 (PHI): payload de stats_recetas sin paciente/medico_id/receta
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.st_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p187','N/A (pendiente 092)',false);
  ELSE
    v := public.stats_recetas_sucursal('2000-01-01','2999-12-31');
    IF v::text NOT ILIKE '%paciente%' AND v::text NOT ILIKE '%medico_id%' AND v::text NOT ILIKE '%receta%'
      THEN PERFORM set_config('probe.p187','OK (sin paciente/medico_id/receta)',false);
      ELSE PERFORM set_config('probe.p187','FALLO (PHI en payload)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p187','FALLO ('||SQLERRM||')',false); END $$;

-- P188 — S-NEG5b: payload de stats_finanzas SIN clave 'medicamento' (separación a nivel payload)
DO $$ DECLARE v jsonb; BEGIN
  IF current_setting('probe.st_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p188','N/A (pendiente 092)',false);
  ELSE
    v := public.stats_finanzas_sucursal('2000-01-01','2999-12-31');
    IF v::text NOT ILIKE '%medicamento%' THEN PERFORM set_config('probe.p188','OK (finanzas sin clave medicamento)',false);
    ELSE PERFORM set_config('probe.p188','FALLO (medicamento en payload financiero)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p188','FALLO ('||SQLERRM||')',false); END $$;

-- P189 — S-NEG6 (celdas pequeñas): STATRARE (veces<k) NO aparece por nombre; STATPOP sí; '(otros)' presente
DO $$ DECLARE v jsonb; n_rare int; n_pop int; n_otros int; BEGIN
  IF current_setting('probe.st_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p189','N/A (pendiente 092)',false);
  ELSE
    v := public.stats_recetas_sucursal('2000-01-01','2999-12-31');
    SELECT count(*) INTO n_rare FROM jsonb_array_elements(v) e WHERE e->>'medicamento'='STATRARE';
    SELECT count(*) INTO n_pop FROM jsonb_array_elements(v) e WHERE e->>'medicamento'='STATPOP';
    SELECT count(*) INTO n_otros FROM jsonb_array_elements(v) e WHERE e->>'medicamento'='(otros)';
    IF n_rare=0 AND n_pop=1 AND n_otros>=1 THEN PERFORM set_config('probe.p189','OK (STATRARE suprimida→(otros); STATPOP visible)',false);
    ELSE PERFORM set_config('probe.p189','FALLO (rare='||n_rare||' pop='||n_pop||' otros='||n_otros||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p189','FALLO ('||SQLERRM||')',false); END $$;

-- P190 — S-SUC (sucursal-aware): usuario scoped a sucursal A solo ve A en stats (no la 2da sucursal empA)
SELECT set_config('role','none',true);
DO $$ DECLARE v jsonb; n_a int; n_a2 int; BEGIN
  IF current_setting('probe.st_ready',true)<>'1' OR current_setting('probe.st_rpc',true)<>'1' THEN PERFORM set_config('probe.p190','N/A (pendiente 092)',false);
  ELSE
    -- atar rx_norx (finanzas) a la sucursal A1; mi_sucursal() (DEFINER) lo lee vía auth.uid()
    UPDATE public.cuentas_proveedor SET sucursal_id = NULLIF(current_setting('probe.st_fa1',true),'')::int WHERE id = NULLIF(current_setting('probe.rx_norx',true),'')::uuid;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.rx_norx', true))::text, true);
    v := public.stats_finanzas_sucursal('2000-01-01','2999-12-31');
    SELECT count(*) INTO n_a  FROM jsonb_array_elements(v) e WHERE (e->>'sucursal_id')::int = NULLIF(current_setting('probe.st_fa1',true),'')::int;
    SELECT count(*) INTO n_a2 FROM jsonb_array_elements(v) e WHERE (e->>'sucursal_id')::int = NULLIF(current_setting('probe.st_fa2',true),'')::int;
    IF n_a=1 AND n_a2=0 THEN PERFORM set_config('probe.p190','OK (scoped a A1 ve solo A1, no la 2da sucursal)',false);
    ELSE PERFORM set_config('probe.p190','FALLO (a='||n_a||' a2='||n_a2||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p190','FALLO ('||SQLERRM||')',false); END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- PAÍS-0 · Helpers de país (P191–P194). Rojo-primero: pre-093 los helpers no existen → N/A.
-- Fixture: país GT (el del médico) + 2º país HN (existente ≠ GT) + farmacia/empresa GT y HN
-- frescas + un médico con pais_id NULL. El rojo/verde aquí es a NIVEL DEL BOOL del helper
-- (los NEG "médico no ve fila HN" por superficie son de los increments #2–#5).
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_gt uuid; v_hn uuid; v_fgt int; v_fhn int; v_lgt uuid; v_lhn uuid; v_mednull uuid; BEGIN
  SELECT pais_id INTO v_gt FROM public.perfiles WHERE id = NULLIF(current_setting('probe.medico',true),'')::uuid;
  SELECT id INTO v_hn FROM public.configuracion_pais WHERE id <> v_gt LIMIT 1;
  SELECT id INTO v_mednull FROM public.perfiles WHERE rol='medico' AND id <> NULLIF(current_setting('probe.medico',true),'')::uuid LIMIT 1;
  IF v_gt IS NULL OR v_hn IS NULL OR v_mednull IS NULL THEN PERFORM set_config('probe.p0_ready','0',false); RETURN; END IF;
  -- farmacias GT / HN
  INSERT INTO public.farmacias (nombre,tipo,pais_id) VALUES ('P0 FARM GT','farmacia',v_gt) RETURNING id INTO v_fgt;
  INSERT INTO public.farmacias (nombre,tipo,pais_id) VALUES ('P0 FARM HN','farmacia',v_hn) RETURNING id INTO v_fhn;
  -- empresas (lab) GT / HN
  INSERT INTO public.empresas_proveedoras (nombre_empresa,email_contacto,tipo,pais_id,estado) VALUES ('P0 LAB GT','plgt@p.test','laboratorio_clinico',v_gt,'activa') RETURNING id INTO v_lgt;
  INSERT INTO public.empresas_proveedoras (nombre_empresa,email_contacto,tipo,pais_id,estado) VALUES ('P0 LAB HN','plhn@p.test','laboratorio_clinico',v_hn,'activa') RETURNING id INTO v_lhn;
  -- médico con país NULL (rollback lo revierte)
  UPDATE public.perfiles SET pais_id = NULL WHERE id = v_mednull;
  PERFORM set_config('probe.p0_ready','1',false);
  PERFORM set_config('probe.p0_fgt',v_fgt::text,false); PERFORM set_config('probe.p0_fhn',v_fhn::text,false);
  PERFORM set_config('probe.p0_lgt',v_lgt::text,false); PERFORM set_config('probe.p0_lhn',v_lhn::text,false);
  PERFORM set_config('probe.p0_mednull',v_mednull::text,false);
  PERFORM set_config('probe.p0_gt',v_gt::text,false);   PERFORM set_config('probe.p0_hn',v_hn::text,false);
END $$;

DO $$ BEGIN
  PERFORM set_config('probe.p0_rpc', CASE WHEN to_regprocedure('private.farmacia_en_mi_pais(integer)') IS NOT NULL AND to_regprocedure('private.lab_en_mi_pais(uuid)') IS NOT NULL THEN '1' ELSE '0' END, false);
END $$;

-- P191 — POS: médico GT → helpers true para farmacia/lab GT
DO $$ DECLARE a boolean; b boolean; BEGIN
  IF current_setting('probe.p0_ready',true)<>'1' OR current_setting('probe.p0_rpc',true)<>'1' THEN PERFORM set_config('probe.p191','N/A (pendiente 093)',false);
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.medico',true))::text, true);
    SELECT private.farmacia_en_mi_pais(NULLIF(current_setting('probe.p0_fgt',true),'')::int) INTO a;
    SELECT private.lab_en_mi_pais(NULLIF(current_setting('probe.p0_lgt',true),'')::uuid) INTO b;
    IF a AND b THEN PERFORM set_config('probe.p191','OK (médico GT: farmacia_GT=true, lab_GT=true)',false);
    ELSE PERFORM set_config('probe.p191','FALLO (farm='||a||' lab='||b||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p191','FALLO ('||SQLERRM||')',false); END $$;

-- P192 — NEG: médico GT → helpers false para farmacia/lab HN
DO $$ DECLARE a boolean; b boolean; BEGIN
  IF current_setting('probe.p0_ready',true)<>'1' OR current_setting('probe.p0_rpc',true)<>'1' THEN PERFORM set_config('probe.p192','N/A (pendiente 093)',false);
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.medico',true))::text, true);
    SELECT private.farmacia_en_mi_pais(NULLIF(current_setting('probe.p0_fhn',true),'')::int) INTO a;
    SELECT private.lab_en_mi_pais(NULLIF(current_setting('probe.p0_lhn',true),'')::uuid) INTO b;
    IF (a IS FALSE) AND (b IS FALSE) THEN PERFORM set_config('probe.p192','OK (médico GT: farmacia_HN=false, lab_HN=false)',false);
    ELSE PERFORM set_config('probe.p192','FALLO (farm='||a||' lab='||b||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p192','FALLO ('||SQLERRM||')',false); END $$;

-- P193 — fail-closed: médico con pais_id NULL → ambos helpers false (sin error) para id GT
DO $$ DECLARE a boolean; b boolean; BEGIN
  IF current_setting('probe.p0_ready',true)<>'1' OR current_setting('probe.p0_rpc',true)<>'1' THEN PERFORM set_config('probe.p193','N/A (pendiente 093)',false);
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p0_mednull',true))::text, true);
    SELECT private.farmacia_en_mi_pais(NULLIF(current_setting('probe.p0_fgt',true),'')::int) INTO a;
    SELECT private.lab_en_mi_pais(NULLIF(current_setting('probe.p0_lgt',true),'')::uuid) INTO b;
    IF (a IS FALSE) AND (b IS FALSE) THEN PERFORM set_config('probe.p193','OK (país NULL → fail-closed false, sin error)',false);
    ELSE PERFORM set_config('probe.p193','FALLO (farm='||a||' lab='||b||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p193','FALLO ('||SQLERRM||')',false); END $$;

-- P194 — p_id NULL → false en ambos (médico GT)
DO $$ DECLARE a boolean; b boolean; BEGIN
  IF current_setting('probe.p0_ready',true)<>'1' OR current_setting('probe.p0_rpc',true)<>'1' THEN PERFORM set_config('probe.p194','N/A (pendiente 093)',false);
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.medico',true))::text, true);
    SELECT private.farmacia_en_mi_pais(NULL) INTO a;
    SELECT private.lab_en_mi_pais(NULL) INTO b;
    IF (a IS FALSE) AND (b IS FALSE) THEN PERFORM set_config('probe.p194','OK (p_id NULL → false en ambos)',false);
    ELSE PERFORM set_config('probe.p194','FALLO (farm='||a||' lab='||b||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p194','FALLO ('||SQLERRM||')',false); END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- PAÍS #1 (productos_empresa, P195–P198) + MONETIZACIÓN-0 (G1, P199–P202).
-- Red-first: P195/P197/P198 muestran ROJO (leak vivo) PRE-094 → OK post-094. P199–P202 N/A
-- pre-095 (tabla/helper ausentes). ROJO ≠ FALLO (es el rojo esperado del increment).
-- Reusa fixture país-0 (probe.p0_*). Médico GT = probe.medico; país-NULL = probe.p0_mednull.
-- ============================================================
SELECT set_config('role','none',true);
DO $$ BEGIN
  IF current_setting('probe.p0_ready',true)<>'1' THEN PERFORM set_config('probe.pe_ready','0',false); RETURN; END IF;
  INSERT INTO public.productos_empresa (nombre_producto,empresa_id,precio_unitario,moneda,stock_disponible,requiere_receta,estado,pais_id)
    VALUES ('PE GT', current_setting('probe.p0_lgt',true)::uuid, 10,'GTQ',5,false,'activo', current_setting('probe.p0_gt',true)::uuid);
  INSERT INTO public.productos_empresa (nombre_producto,empresa_id,precio_unitario,moneda,stock_disponible,requiere_receta,estado,pais_id)
    VALUES ('PE HN', current_setting('probe.p0_lhn',true)::uuid, 10,'HNL',5,false,'activo', current_setting('probe.p0_hn',true)::uuid);
  PERFORM set_config('probe.pe_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.pe_ready','0',false); END $$;

-- P195 — NEG (red-first): médico GT NO debe ver producto HN
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.medico',true))::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pe_ready',true)<>'1' THEN PERFORM set_config('probe.p195','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.productos_empresa WHERE empresa_id = current_setting('probe.p0_lhn',true)::uuid;
    IF n=0 THEN PERFORM set_config('probe.p195','OK (médico GT no ve producto HN)',false);
    ELSE PERFORM set_config('probe.p195','ROJO (médico GT ve producto HN — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p195','FALLO ('||SQLERRM||')',false); END $$;

-- P196 — POS no-regresión: médico GT SÍ ve producto GT
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pe_ready',true)<>'1' THEN PERFORM set_config('probe.p196','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.productos_empresa WHERE empresa_id = current_setting('probe.p0_lgt',true)::uuid;
    IF n>0 THEN PERFORM set_config('probe.p196','OK (médico GT ve su producto GT)',false);
    ELSE PERFORM set_config('probe.p196','FALLO (médico GT NO ve su producto GT)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p196','FALLO ('||SQLERRM||')',false); END $$;

-- P197 — fail-closed (red-first): médico país-NULL → 0 productos de la fixture
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p0_mednull',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pe_ready',true)<>'1' THEN PERFORM set_config('probe.p197','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.productos_empresa WHERE empresa_id IN (current_setting('probe.p0_lgt',true)::uuid, current_setting('probe.p0_lhn',true)::uuid);
    IF n=0 THEN PERFORM set_config('probe.p197','OK (país-NULL no ve productos)',false);
    ELSE PERFORM set_config('probe.p197','ROJO (país-NULL ve productos — fail-open, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p197','FALLO ('||SQLERRM||')',false); END $$;

-- P198 — backfill (red-first): productos_empresa con pais_id NULL = 0 (owner)
SELECT set_config('role','none',true);
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.productos_empresa WHERE pais_id IS NULL;
  IF n=0 THEN PERFORM set_config('probe.p198','OK (0 productos con país NULL)',false);
  ELSE PERFORM set_config('probe.p198','ROJO ('||n||' productos con país NULL — pendiente backfill 094)',false); END IF;
END $$;

-- P203 — trigger re-deriva país al cambiar empresa_id (sin tocar pais_id). Owner (role none);
-- el trigger es DEFINER. Pre-094 (sin trigger) el país NO cambia → ROJO; post-094 → HN.
SELECT set_config('role','none',true);
DO $$ DECLARE v_pais uuid; v_esperado uuid; v_old uuid; BEGIN
  IF current_setting('probe.pe_ready',true)<>'1' THEN PERFORM set_config('probe.p203','N/A',false);
  ELSE
    SELECT pais_id INTO v_old FROM public.productos_empresa WHERE nombre_producto='PE GT' LIMIT 1;  -- GT antes
    UPDATE public.productos_empresa SET empresa_id = current_setting('probe.p0_lhn',true)::uuid
      WHERE nombre_producto='PE GT' AND empresa_id = current_setting('probe.p0_lgt',true)::uuid;
    SELECT pais_id INTO v_pais FROM public.productos_empresa WHERE nombre_producto='PE GT' LIMIT 1;  -- ¿re-derivado?
    SELECT pais_id INTO v_esperado FROM public.empresas_proveedoras WHERE id = current_setting('probe.p0_lhn',true)::uuid;  -- país real de la nueva empresa
    IF v_pais = v_esperado AND v_pais <> v_old THEN PERFORM set_config('probe.p203','OK (re-asignar empresa re-deriva país = país de la nueva empresa, cambió desde GT)',false);
    ELSE PERFORM set_config('probe.p203','ROJO (país='||COALESCE(v_pais::text,'NULL')||' esperado='||COALESCE(v_esperado::text,'NULL')||' old='||COALESCE(v_old::text,'NULL')||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p203','FALLO ('||SQLERRM||')',false); END $$;

-- ===== MONETIZACIÓN-0 / G1 =====
DO $$ BEGIN
  IF current_setting('probe.p0_ready',true)<>'1' OR to_regclass('public.empresa_paises_operacion') IS NULL THEN PERFORM set_config('probe.g1_ready','0',false); RETURN; END IF;
  INSERT INTO public.empresa_paises_operacion (empresa_id,pais_id,activo)
    VALUES (current_setting('probe.p0_lgt',true)::uuid, current_setting('probe.p0_gt',true)::uuid, true) ON CONFLICT DO NOTHING;
  PERFORM set_config('probe.g1_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.g1_ready','0',false); PERFORM set_config('probe.g1_err', SQLERRM, false); END $$;

-- P199 — helper: opera-GT true / no-opera-HN false / inactivo false / NULL false
DO $$ DECLARE a boolean; b boolean; c boolean; d boolean; BEGIN
  IF current_setting('probe.g1_ready',true)<>'1' THEN PERFORM set_config('probe.p199','N/A (pendiente 095)',false);
  ELSE
    a := private.empresa_opera_en_pais(current_setting('probe.p0_lgt',true)::uuid, current_setting('probe.p0_gt',true)::uuid);
    b := private.empresa_opera_en_pais(current_setting('probe.p0_lgt',true)::uuid, current_setting('probe.p0_hn',true)::uuid);
    UPDATE public.empresa_paises_operacion SET activo=false WHERE empresa_id=current_setting('probe.p0_lgt',true)::uuid AND pais_id=current_setting('probe.p0_gt',true)::uuid;
    c := private.empresa_opera_en_pais(current_setting('probe.p0_lgt',true)::uuid, current_setting('probe.p0_gt',true)::uuid);
    d := private.empresa_opera_en_pais(NULL, current_setting('probe.p0_gt',true)::uuid);
    UPDATE public.empresa_paises_operacion SET activo=true WHERE empresa_id=current_setting('probe.p0_lgt',true)::uuid AND pais_id=current_setting('probe.p0_gt',true)::uuid;
    IF a AND (b IS FALSE) AND (c IS FALSE) AND (d IS FALSE) THEN PERFORM set_config('probe.p199','OK (opera-GT true; no-HN/inactivo/NULL false)',false);
    ELSE PERFORM set_config('probe.p199','FALLO (a='||a||' b='||b||' c='||c||' d='||d||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p199','FALLO ('||SQLERRM||')',false); END $$;

-- P200 — NEG: proveedor INSERT directo → BLOQ y SELECT directo → 0
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; ins text; BEGIN
  IF current_setting('probe.g1_ready',true)<>'1' THEN PERFORM set_config('probe.p200','N/A (pendiente 095)',false);
  ELSE
    BEGIN INSERT INTO public.empresa_paises_operacion (empresa_id,pais_id,activo) VALUES (current_setting('probe.p0_lgt',true)::uuid, current_setting('probe.p0_hn',true)::uuid, true); ins:='PERMITIDO';
    EXCEPTION WHEN others THEN ins:='BLOQ'; END;
    SELECT count(*) INTO n FROM public.empresa_paises_operacion;
    IF ins='BLOQ' AND n=0 THEN PERFORM set_config('probe.p200','BLOQUEADO (proveedor: insert BLOQ, select 0)',false);
    ELSE PERFORM set_config('probe.p200','FALLO (ins='||ins||' select='||n||')',false); END IF;
  END IF;
END $$;

-- P201 — POS: super_admin gestiona (ve filas)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id::text FROM public.perfiles WHERE rol='super_admin' LIMIT 1), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.g1_ready',true)<>'1' THEN PERFORM set_config('probe.p201','N/A (pendiente 095)',false);
  ELSE
    SELECT count(*) INTO n FROM public.empresa_paises_operacion;
    IF n>0 THEN PERFORM set_config('probe.p201','OK (super_admin ve '||n||' filas)',false);
    ELSE PERFORM set_config('probe.p201','FALLO (super_admin ve 0)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p201','FALLO ('||SQLERRM||')',false); END $$;

-- P202 — RESTRICT: borrar país con operación → BLOQ
SELECT set_config('role','none',true);
DO $$ BEGIN
  IF current_setting('probe.g1_ready',true)<>'1' THEN PERFORM set_config('probe.p202','N/A (pendiente 095)',false);
  ELSE
    INSERT INTO public.empresa_paises_operacion (empresa_id,pais_id,activo) VALUES (current_setting('probe.p0_lhn',true)::uuid, current_setting('probe.p0_hn',true)::uuid, true) ON CONFLICT DO NOTHING;
    BEGIN DELETE FROM public.configuracion_pais WHERE id=current_setting('probe.p0_hn',true)::uuid; PERFORM set_config('probe.p202','FALLO (borró país con operación)',false);
    EXCEPTION WHEN foreign_key_violation THEN PERFORM set_config('probe.p202','BLOQUEADO (FK RESTRICT)',false);
             WHEN others THEN PERFORM set_config('probe.p202','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- PAÍS #2 · farmacia_medicamentos (P204–P209). Red-first: P204/P206/P208 ROJO pre-096 → OK post.
-- Reusa fixture país-0 (p0_fgt/p0_fhn farmacias GT/HN; probe.medico GT; p0_mednull país-NULL;
-- cat_clinico clínico no-médico; cat_inv/cat_fA proveedor). ROJO ≠ FALLO.
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_medgt uuid; BEGIN
  -- médico-GT REAL (rol='medico', país no-NULL = GT; distinto del país-NULL p0_mednull)
  SELECT id INTO v_medgt FROM public.perfiles WHERE rol='medico' AND pais_id IS NOT NULL
    AND id <> current_setting('probe.p0_mednull',true)::uuid LIMIT 1;
  IF current_setting('probe.p0_ready',true)<>'1' OR NULLIF(current_setting('probe.cat_clinico',true),'') IS NULL OR v_medgt IS NULL THEN PERFORM set_config('probe.fm_ready','0',false); RETURN; END IF;
  INSERT INTO public.farmacia_medicamentos (farmacia_id,nombre_medicamento,stock_actual,stock_minimo,precio_unitario,activo)
    VALUES (current_setting('probe.p0_fgt',true)::int,'FM GT PAIS',10,1,5.0,true);
  INSERT INTO public.farmacia_medicamentos (farmacia_id,nombre_medicamento,stock_actual,stock_minimo,precio_unitario,activo)
    VALUES (current_setting('probe.p0_fhn',true)::int,'FM HN PAIS',10,1,5.0,true);
  UPDATE public.perfiles SET pais_id = current_setting('probe.p0_gt',true)::uuid WHERE id = current_setting('probe.cat_clinico',true)::uuid;  -- clínico GT
  PERFORM set_config('probe.fm_medgt', v_medgt::text, false);
  PERFORM set_config('probe.fm_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.fm_ready','0',false); END $$;

-- P204 — NEG (red-first): médico GT NO ve stock de farmacia HN
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p204','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id=current_setting('probe.p0_fhn',true)::int;
    IF n=0 THEN PERFORM set_config('probe.p204','OK (médico GT no ve stock HN)',false);
    ELSE PERFORM set_config('probe.p204','ROJO (médico GT ve stock HN — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p204','FALLO ('||SQLERRM||')',false); END $$;

-- P205 — POS no-regresión: médico GT SÍ ve stock de farmacia GT
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p205','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id=current_setting('probe.p0_fgt',true)::int;
    IF n>0 THEN PERFORM set_config('probe.p205','OK (médico GT ve stock GT)',false);
    ELSE PERFORM set_config('probe.p205','FALLO (médico GT NO ve stock GT)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p205','FALLO ('||SQLERRM||')',false); END $$;

-- P206 — NEG (red-first): clínico-no-médico GT NO ve stock de farmacia HN
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_clinico',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p206','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id=current_setting('probe.p0_fhn',true)::int;
    IF n=0 THEN PERFORM set_config('probe.p206','OK (clínico GT no ve stock HN)',false);
    ELSE PERFORM set_config('probe.p206','ROJO (clínico GT ve stock HN — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p206','FALLO ('||SQLERRM||')',false); END $$;

-- P207 — POS no-regresión: clínico GT SÍ ve stock de farmacia GT
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p207','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id=current_setting('probe.p0_fgt',true)::int;
    IF n>0 THEN PERFORM set_config('probe.p207','OK (clínico GT ve stock GT)',false);
    ELSE PERFORM set_config('probe.p207','FALLO (clínico GT NO ve stock GT)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p207','FALLO ('||SQLERRM||')',false); END $$;

-- P208 — fail-closed (red-first): médico país-NULL → 0 stock de la fixture
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p0_mednull',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p208','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id IN (current_setting('probe.p0_fgt',true)::int, current_setting('probe.p0_fhn',true)::int);
    IF n=0 THEN PERFORM set_config('probe.p208','OK (país-NULL no ve stock)',false);
    ELSE PERFORM set_config('probe.p208','ROJO (país-NULL ve stock — fail-open, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p208','FALLO ('||SQLERRM||')',false); END $$;

-- P209 — no-regresión proveedor: ve su empresa (sin país); anon → 0
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; an int; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p209','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id=current_setting('probe.cat_fA',true)::int;  -- proveedor ve su farmacia
    PERFORM set_config('role','none',true);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true); PERFORM set_config('role','anon',true);
    BEGIN SELECT count(*) INTO an FROM public.farmacia_medicamentos; EXCEPTION WHEN others THEN an:=-1; END;
    PERFORM set_config('role','none',true);
    IF n>0 AND an=0 THEN PERFORM set_config('probe.p209','OK (proveedor ve su empresa='||n||'; anon=0)',false);
    ELSE PERFORM set_config('probe.p209','FALLO (proveedor='||n||' anon='||an||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('role','none',true); PERFORM set_config('probe.p209','FALLO ('||SQLERRM||')',false); END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- PAÍS #3 · examenes_catalogo + laboratorios_para_medico (P210–P215). Red-first.
-- Reusa: p0_lgt/p0_lhn (empresas lab clínico GT/HN), fm_medgt (médico-GT real), p0_mednull.
-- ============================================================
SELECT set_config('role','none',true);
DO $$ BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.ex_ready','0',false); RETURN; END IF;
  INSERT INTO public.examenes_catalogo (laboratorio_id,nombre,categoria,activo)
    VALUES (current_setting('probe.p0_lgt',true)::uuid,'EX GT PAIS','cat',true);
  INSERT INTO public.examenes_catalogo (laboratorio_id,nombre,categoria,activo)
    VALUES (current_setting('probe.p0_lhn',true)::uuid,'EX HN PAIS','cat',true);
  PERFORM set_config('probe.ex_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.ex_ready','0',false); END $$;

-- P210 — NEG (red-first): médico-GT NO ve examen de lab HN
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.ex_ready',true)<>'1' THEN PERFORM set_config('probe.p210','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.examenes_catalogo WHERE laboratorio_id=current_setting('probe.p0_lhn',true)::uuid;
    IF n=0 THEN PERFORM set_config('probe.p210','OK (médico GT no ve examen lab HN)',false);
    ELSE PERFORM set_config('probe.p210','ROJO (médico GT ve examen lab HN — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p210','FALLO ('||SQLERRM||')',false); END $$;

-- P211 — POS: médico-GT SÍ ve examen de lab GT
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.ex_ready',true)<>'1' THEN PERFORM set_config('probe.p211','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.examenes_catalogo WHERE laboratorio_id=current_setting('probe.p0_lgt',true)::uuid;
    IF n>0 THEN PERFORM set_config('probe.p211','OK (médico GT ve examen lab GT)',false);
    ELSE PERFORM set_config('probe.p211','FALLO (médico GT NO ve examen lab GT)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p211','FALLO ('||SQLERRM||')',false); END $$;

-- P212 — fail-closed (red-first): médico país-NULL → 0 exámenes de la fixture
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p0_mednull',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.ex_ready',true)<>'1' THEN PERFORM set_config('probe.p212','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.examenes_catalogo WHERE laboratorio_id IN (current_setting('probe.p0_lgt',true)::uuid, current_setting('probe.p0_lhn',true)::uuid);
    IF n=0 THEN PERFORM set_config('probe.p212','OK (país-NULL no ve exámenes)',false);
    ELSE PERFORM set_config('probe.p212','ROJO (país-NULL ve exámenes — fail-open, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p212','FALLO ('||SQLERRM||')',false); END $$;

-- P213 — RPC POS/no-regresión: médico-GT obtiene lab GT, NO el lab HN
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
DO $$ DECLARE g int; h int; BEGIN
  IF current_setting('probe.ex_ready',true)<>'1' OR to_regprocedure('public.laboratorios_para_medico()') IS NULL THEN PERFORM set_config('probe.p213','N/A',false);
  ELSE
    SELECT count(*) INTO g FROM public.laboratorios_para_medico() WHERE id=current_setting('probe.p0_lgt',true)::uuid;
    SELECT count(*) INTO h FROM public.laboratorios_para_medico() WHERE id=current_setting('probe.p0_lhn',true)::uuid;
    IF g>0 AND h=0 THEN PERFORM set_config('probe.p213','OK (RPC médico GT: lab GT sí, lab HN no)',false);
    ELSE PERFORM set_config('probe.p213','FALLO (gt='||g||' hn='||h||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p213','FALLO ('||SQLERRM||')',false); END $$;

-- P214 — RPC fail-closed (red-first): médico país-NULL → 0 labs (pre: todos, incl HN)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p0_mednull',true))::text, true);
DO $$ DECLARE h int; tot int; BEGIN
  IF current_setting('probe.ex_ready',true)<>'1' OR to_regprocedure('public.laboratorios_para_medico()') IS NULL THEN PERFORM set_config('probe.p214','N/A',false);
  ELSE
    SELECT count(*) INTO tot FROM public.laboratorios_para_medico();
    SELECT count(*) INTO h FROM public.laboratorios_para_medico() WHERE id=current_setting('probe.p0_lhn',true)::uuid;
    IF tot=0 AND h=0 THEN PERFORM set_config('probe.p214','OK (país-NULL → 0 labs, fail-closed)',false);
    ELSE PERFORM set_config('probe.p214','ROJO (país-NULL obtiene labs — fail-open, tot='||tot||' hn='||h||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p214','FALLO ('||SQLERRM||')',false); END $$;

-- P215 — no-regresión: anon NO lee examenes_catalogo (post-097: TO authenticated → 0)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT set_config('role','anon',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.ex_ready',true)<>'1' THEN PERFORM set_config('probe.p215','N/A',false);
  ELSE
    BEGIN SELECT count(*) INTO n FROM public.examenes_catalogo; EXCEPTION WHEN others THEN n:=-1; END;
    IF n=0 THEN PERFORM set_config('probe.p215','OK (anon no lee examenes_catalogo)',false);
    ELSE PERFORM set_config('probe.p215','ROJO/INFO (anon lee '||n||' — pre-097 era public)',false); END IF;
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- PAÍS #4 · farmacias (P216–P223). Red-first. Reusa: cat_inv/cat_fA (proveedor empresa A),
-- cat_fB (farmacia empresa B, MISMO país GT), fm_medgt (médico GT), cat_clinico (clínico GT),
-- p0_mednull (país NULL), p0_fgt/p0_fhn (GT/HN). guard: cat_ready+p0_ready+fm_ready.
-- ============================================================
SELECT set_config('role','none',true);
-- P216 — NEG CLAVE (red-first): proveedor-GT NO ve farmacia de OTRA empresa del mismo país
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p216','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacias WHERE id=current_setting('probe.cat_fB',true)::int;
    IF n=0 THEN PERFORM set_config('probe.p216','OK (proveedor no ve farmacia de otra empresa del mismo país)',false);
    ELSE PERFORM set_config('probe.p216','ROJO (proveedor ve farmacia de otra empresa GT — leak cross-tenant, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p216','FALLO ('||SQLERRM||')',false); END $$;

-- P217 — POS no-regresión: proveedor-GT ve SU propia farmacia
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' THEN PERFORM set_config('probe.p217','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacias WHERE id=current_setting('probe.cat_fA',true)::int;
    IF n>0 THEN PERFORM set_config('probe.p217','OK (proveedor ve su empresa)',false);
    ELSE PERFORM set_config('probe.p217','FALLO (proveedor NO ve su empresa)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p217','FALLO ('||SQLERRM||')',false); END $$;

-- P218 — NEG (red-first): médico-GT NO ve farmacia HN
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p218','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacias WHERE id=current_setting('probe.p0_fhn',true)::int;
    IF n=0 THEN PERFORM set_config('probe.p218','OK (médico GT no ve farmacia HN)',false);
    ELSE PERFORM set_config('probe.p218','ROJO (médico GT ve farmacia HN — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p218','FALLO ('||SQLERRM||')',false); END $$;

-- P219 — POS: médico-GT ve farmacia GT
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p219','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacias WHERE id=current_setting('probe.p0_fgt',true)::int;
    IF n>0 THEN PERFORM set_config('probe.p219','OK (médico GT ve farmacia GT)',false);
    ELSE PERFORM set_config('probe.p219','FALLO (médico GT NO ve farmacia GT)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p219','FALLO ('||SQLERRM||')',false); END $$;

-- P220 — NEG (red-first): clínico-GT NO ve farmacia HN
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_clinico',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p220','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacias WHERE id=current_setting('probe.p0_fhn',true)::int;
    IF n=0 THEN PERFORM set_config('probe.p220','OK (clínico GT no ve farmacia HN)',false);
    ELSE PERFORM set_config('probe.p220','ROJO (clínico GT ve farmacia HN — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p220','FALLO ('||SQLERRM||')',false); END $$;

-- P221 — fail-closed (red-first): médico país-NULL → 0 farmacias de la fixture
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p0_mednull',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p221','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacias WHERE id IN (current_setting('probe.p0_fgt',true)::int, current_setting('probe.p0_fhn',true)::int, current_setting('probe.cat_fA',true)::int);
    IF n=0 THEN PERFORM set_config('probe.p221','OK (país-NULL no ve farmacias)',false);
    ELSE PERFORM set_config('probe.p221','ROJO (país-NULL ve farmacias — fail-open, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p221','FALLO ('||SQLERRM||')',false); END $$;

-- P222 — anon → 0 farmacias (red-first: hoy la policy anon=true muestra todo)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims','{"role":"anon"}',true); SELECT set_config('role','anon',true);
DO $$ DECLARE n int; BEGIN
  BEGIN SELECT count(*) INTO n FROM public.farmacias; EXCEPTION WHEN others THEN n:=-1; END;
  IF n=0 THEN PERFORM set_config('probe.p222','OK (anon no ve farmacias)',false);
  ELSE PERFORM set_config('probe.p222','ROJO (anon ve '||n||' farmacias — policy anon vestigial)',false); END IF;
END $$;

-- P223 — POS super_admin: ve TODAS (incl HN) vía farmacias_write_admin (ALL)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id::text FROM public.perfiles WHERE rol='super_admin' LIMIT 1), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.p223','N/A',false);
  ELSE
    SELECT count(*) INTO n FROM public.farmacias WHERE id=current_setting('probe.p0_fhn',true)::int;
    IF n>0 THEN PERFORM set_config('probe.p223','OK (super_admin ve farmacia HN — ve todas)',false);
    ELSE PERFORM set_config('probe.p223','FALLO (super_admin NO ve HN)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p223','FALLO ('||SQLERRM||')',false); END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- PUB-A · targeting país publicidad (P224–P228). Red-first.
-- Fixture: empresa A (de cat_fA) opera en GT (no en HN). proveedor cat_inv (admin A).
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_ea uuid; v_sid uuid; BEGIN
  IF current_setting('probe.cat_ready',true)<>'1' OR current_setting('probe.p0_ready',true)<>'1' OR to_regprocedure('private.empresa_opera_en_pais(uuid,uuid)') IS NULL THEN PERFORM set_config('probe.pa_ready','0',false); RETURN; END IF;
  SELECT empresa_id INTO v_ea FROM public.farmacias WHERE id=current_setting('probe.cat_fA',true)::int;
  INSERT INTO public.empresa_paises_operacion (empresa_id,pais_id,activo) VALUES (v_ea, current_setting('probe.p0_gt',true)::uuid, true) ON CONFLICT DO NOTHING;  -- A opera en GT
  -- solicitud HN sembrada como owner (para el probe de aprobar; bypass del WITH CHECK)
  INSERT INTO public.solicitudes_campana (empresa_id,cuenta_proveedor_id,titulo,tipo,fecha_inicio,fecha_fin,estado,pais_id)
    VALUES (v_ea, current_setting('probe.cat_inv',true)::uuid, 'PA SOL HN','banner',CURRENT_DATE,CURRENT_DATE+30,'enviada', current_setting('probe.p0_hn',true)::uuid) RETURNING id INTO v_sid;
  PERFORM set_config('probe.pa_ea', v_ea::text, false);
  PERFORM set_config('probe.pa_sol_hn', v_sid::text, false);
  PERFORM set_config('probe.pa_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.pa_ready','0',false); END $$;

-- P224 — NEG (red-first): proveedor crea solicitud en país NO operado (HN) → BLOQ
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' THEN PERFORM set_config('probe.p224','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.solicitudes_campana (empresa_id,cuenta_proveedor_id,titulo,tipo,fecha_inicio,fecha_fin,estado,pais_id)
        VALUES (current_setting('probe.pa_ea',true)::uuid, current_setting('probe.cat_inv',true)::uuid, 'PA CREA HN','banner',CURRENT_DATE,CURRENT_DATE+30,'borrador', current_setting('probe.p0_hn',true)::uuid);
      PERFORM set_config('probe.p224','ROJO (creó campaña en país NO operado — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p224','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P225 — POS: proveedor crea solicitud en país operado (GT) → OK
DO $$ BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' THEN PERFORM set_config('probe.p225','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.solicitudes_campana (empresa_id,cuenta_proveedor_id,titulo,tipo,fecha_inicio,fecha_fin,estado,pais_id)
        VALUES (current_setting('probe.pa_ea',true)::uuid, current_setting('probe.cat_inv',true)::uuid, 'PA CREA GT','banner',CURRENT_DATE,CURRENT_DATE+30,'borrador', current_setting('probe.p0_gt',true)::uuid);
      PERFORM set_config('probe.p225','OK (crea en país operado)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p225','FALLO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P226 — NEG aprobar (red-first): super_admin aprueba solicitud país ∉ operación → BLOQ
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id::text FROM public.perfiles WHERE rol='super_admin' LIMIT 1), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' OR to_regprocedure('public.aprobar_solicitud_campana(uuid,text)') IS NULL THEN PERFORM set_config('probe.p226','N/A',false);
  ELSE
    BEGIN PERFORM public.aprobar_solicitud_campana(current_setting('probe.pa_sol_hn',true)::uuid, NULL);
      PERFORM set_config('probe.p226','ROJO (aprobó campaña en país NO operado — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p226','BLOQUEADO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P227 — backfill (red-first): solicitudes + campanas con país NULL = 0 (owner)
SELECT set_config('role','none',true);
DO $$ DECLARE n1 int; n2 int; BEGIN
  SELECT count(*) INTO n1 FROM public.solicitudes_campana WHERE pais_id IS NULL;
  SELECT count(*) INTO n2 FROM public.campanas_publicitarias WHERE pais_id IS NULL;
  IF n1=0 AND n2=0 THEN PERFORM set_config('probe.p227','OK (0 país NULL en solicitudes y campanas)',false);
  ELSE PERFORM set_config('probe.p227','ROJO (solicitudes NULL='||n1||' campanas NULL='||n2||' — pendiente backfill 099)',false); END IF;
END $$;

-- P228 — anti-escalada (no-regresión): proveedor crea solicitud atribuida a empresa AJENA → BLOQ
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v_eb uuid; BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' THEN PERFORM set_config('probe.p228','N/A',false);
  ELSE
    SELECT empresa_id INTO v_eb FROM public.farmacias WHERE id=current_setting('probe.cat_fB',true)::int;
    BEGIN
      INSERT INTO public.solicitudes_campana (empresa_id,cuenta_proveedor_id,titulo,tipo,fecha_inicio,fecha_fin,estado,pais_id)
        VALUES (v_eb, current_setting('probe.cat_inv',true)::uuid, 'PA AJENA','banner',CURRENT_DATE,CURRENT_DATE+30,'borrador', current_setting('probe.p0_gt',true)::uuid);
      PERFORM set_config('probe.p228','ROJO (creó campaña atribuida a empresa ajena)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p228','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- PUB-B · display por país del viewer (P229–P236). Red-first.
-- Fixture: campañas 'PB GT'/'PB HN' (vigentes) + 'PB GT FUT' (inicio futuro); paciente GT,
-- admin_clinica GT, médico GT (fm_medgt), viewer sin país (p0_mednull).
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_pac uuid; v_clin uuid; BEGIN
  IF current_setting('probe.fm_ready',true)<>'1' THEN PERFORM set_config('probe.pb_ready','0',false); RETURN; END IF;
  SELECT auth_user_id INTO v_pac FROM public.pacientes WHERE auth_user_id IS NOT NULL AND pais_id = current_setting('probe.p0_gt',true)::uuid LIMIT 1;
  SELECT id INTO v_clin FROM public.perfiles WHERE rol='admin_clinica' AND pais_id = current_setting('probe.p0_gt',true)::uuid LIMIT 1;
  IF v_pac IS NULL OR v_clin IS NULL THEN PERFORM set_config('probe.pb_ready','0',false); RETURN; END IF;
  INSERT INTO public.campanas_publicitarias (titulo,tipo,fecha_inicio,fecha_fin,activa,peso,pais_id)
    VALUES ('PB GT','banner',CURRENT_DATE-1,CURRENT_DATE+30,true,1, current_setting('probe.p0_gt',true)::uuid);
  INSERT INTO public.campanas_publicitarias (titulo,tipo,fecha_inicio,fecha_fin,activa,peso,pais_id)
    VALUES ('PB HN','banner',CURRENT_DATE-1,CURRENT_DATE+30,true,1, current_setting('probe.p0_hn',true)::uuid);
  INSERT INTO public.campanas_publicitarias (titulo,tipo,fecha_inicio,fecha_fin,activa,peso,pais_id)
    VALUES ('PB GT FUT','banner',CURRENT_DATE+5,CURRENT_DATE+30,true,1, current_setting('probe.p0_gt',true)::uuid);
  PERFORM set_config('probe.pb_pac', v_pac::text, false);
  PERFORM set_config('probe.pb_clin', v_clin::text, false);
  PERFORM set_config('probe.pb_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.pb_ready','0',false); END $$;

-- P229 — POS audiencia#2 (red-first): médico-GT ve campaña GT (hoy ve 0)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p229','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo='PB GT';
    IF n>0 THEN PERFORM set_config('probe.p229','OK (médico GT ve ads de su país)',false);
    ELSE PERFORM set_config('probe.p229','ROJO (médico GT no ve ads de su país — audiencia no servida)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p229','FALLO ('||SQLERRM||')',false); END $$;

-- P230 — POS audiencia#2 (red-first): clínica (admin_clinica) GT ve campaña GT
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.pb_clin',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p230','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo='PB GT';
    IF n>0 THEN PERFORM set_config('probe.p230','OK (clínica GT ve ads de su país)',false);
    ELSE PERFORM set_config('probe.p230','ROJO (clínica GT no ve ads de su país)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p230','FALLO ('||SQLERRM||')',false); END $$;

-- P231 — NEG aislamiento: médico-GT NO ve campaña HN (OR-trap: super_admin ALL no re-abre)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p231','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo='PB HN';
    IF n=0 THEN PERFORM set_config('probe.p231','OK (médico GT no ve campaña HN)',false);
    ELSE PERFORM set_config('probe.p231','ROJO (médico GT ve campaña HN — leak, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p231','FALLO ('||SQLERRM||')',false); END $$;

-- P232 — POS no-regresión paciente: paciente-GT ve campaña GT
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.pb_pac',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p232','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo='PB GT';
    IF n>0 THEN PERFORM set_config('probe.p232','OK (paciente GT ve ads de su país — cobertura mi_pais_viewer)',false);
    ELSE PERFORM set_config('probe.p232','FALLO (paciente GT NO ve sus ads — helper no cubre paciente)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p232','FALLO ('||SQLERRM||')',false); END $$;

-- P233 — NEG paciente cross-país: paciente-GT NO ve campaña HN
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p233','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo='PB HN';
    IF n=0 THEN PERFORM set_config('probe.p233','OK (paciente GT no ve campaña HN)',false);
    ELSE PERFORM set_config('probe.p233','ROJO (paciente GT ve campaña HN, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p233','FALLO ('||SQLERRM||')',false); END $$;

-- P234 — vigencia (red-first): paciente-GT NO ve campaña con fecha_inicio FUTURA
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p234','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo='PB GT FUT';
    IF n=0 THEN PERFORM set_config('probe.p234','OK (campaña con inicio futuro NO se muestra)',false);
    ELSE PERFORM set_config('probe.p234','ROJO (campaña con inicio futuro se muestra — fail-open vigencia)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p234','FALLO ('||SQLERRM||')',false); END $$;

-- P235 — fail-closed: viewer sin país (médico país-NULL) → 0 campañas
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.p0_mednull',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p235','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo IN ('PB GT','PB HN','PB GT FUT');
    IF n=0 THEN PERFORM set_config('probe.p235','OK (viewer sin país no ve ads)',false);
    ELSE PERFORM set_config('probe.p235','ROJO (viewer sin país ve ads — fail-open, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p235','FALLO ('||SQLERRM||')',false); END $$;

-- P236 — anon: comportamiento definido (0, sin error)
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims','{"role":"anon"}',true); SELECT set_config('role','anon',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.p236','N/A',false);
  ELSE
    BEGIN SELECT count(*) INTO n FROM public.campanas_publicitarias WHERE titulo='PB GT'; EXCEPTION WHEN others THEN n:=-1; END;
    IF n=0 THEN PERFORM set_config('probe.p236','OK (anon no ve ads, sin error)',false);
    ELSE PERFORM set_config('probe.p236','ROJO (anon ve '||n||' o error)',false); END IF;
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- V-G3 · re-tipo pais_id de planes_visitador_contratados (P237–P240). Red-first: N/A pre-101.
-- Estructura/FK (como país-0/G1). Todo como owner (role none).
-- ============================================================
SELECT set_config('role','none',true);
DO $$ BEGIN
  PERFORM set_config('probe.vg3_ready',
    CASE WHEN (SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='planes_visitador_contratados' AND column_name='pais_id') = 'uuid' THEN '1' ELSE '0' END, false);
END $$;

-- P237 — estructura: pais_id = uuid + FK a configuracion_pais
DO $$ DECLARE v_fk boolean; BEGIN
  IF current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p237','N/A (pendiente 101)',false);
  ELSE
    SELECT count(*)>0 INTO v_fk FROM pg_constraint WHERE conrelid='public.planes_visitador_contratados'::regclass AND contype='f' AND confrelid='public.configuracion_pais'::regclass;
    IF v_fk THEN PERFORM set_config('probe.p237','OK (pais_id uuid + FK a configuracion_pais)',false);
    ELSE PERFORM set_config('probe.p237','FALLO (sin FK a configuracion_pais)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p237','FALLO ('||SQLERRM||')',false); END $$;

-- P238 — NEG: INSERT con país inexistente → violación FK (BLOQ)
DO $$ DECLARE v_e uuid; BEGIN
  IF current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p238','N/A (pendiente 101)',false);
  ELSE
    SELECT id INTO v_e FROM public.empresas_proveedoras WHERE pais_id IS NOT NULL LIMIT 1;
    BEGIN
      INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
        VALUES (v_e, 1, gen_random_uuid(), 10, 0, 100, CURRENT_DATE, CURRENT_DATE+30, 'activo');
      PERFORM set_config('probe.p238','FALLO (insertó país inexistente)',false);
    EXCEPTION WHEN foreign_key_violation THEN PERFORM set_config('probe.p238','BLOQUEADO (FK)',false);
             WHEN others THEN PERFORM set_config('probe.p238','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p238','FALLO ('||SQLERRM||')',false); END $$;

-- P239 — POS: INSERT con país válido → OK
DO $$ DECLARE v_e uuid; BEGIN
  IF current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p239','N/A (pendiente 101)',false);
  ELSE
    SELECT id INTO v_e FROM public.empresas_proveedoras WHERE pais_id IS NOT NULL LIMIT 1;
    BEGIN
      INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
        VALUES (v_e, 1, current_setting('probe.p0_gt',true)::uuid, 10, 0, 100, CURRENT_DATE, CURRENT_DATE+30, 'activo');
      PERFORM set_config('probe.p239','OK (país válido aceptado)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p239','FALLO ('||SQLERRM||')',false); END;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p239','FALLO ('||SQLERRM||')',false); END $$;

-- P240 — RESTRICT: borrar un país con plan asociado → BLOQ (eje fail-closed)
DO $$ DECLARE v_e uuid; v_p3 uuid; BEGIN
  IF current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p240','N/A (pendiente 101)',false);
  ELSE
    SELECT id INTO v_e FROM public.empresas_proveedoras WHERE pais_id IS NOT NULL LIMIT 1;
    SELECT id INTO v_p3 FROM public.configuracion_pais WHERE id NOT IN (current_setting('probe.p0_gt',true)::uuid, current_setting('probe.p0_hn',true)::uuid) LIMIT 1;  -- país fresco (solo lo referenciará el plan)
    INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
      VALUES (v_e, 1, v_p3, 10, 0, 100, CURRENT_DATE, CURRENT_DATE+30, 'activo');
    BEGIN DELETE FROM public.configuracion_pais WHERE id = v_p3; PERFORM set_config('probe.p240','FALLO (borró país con plan)',false);
    EXCEPTION WHEN foreign_key_violation THEN PERFORM set_config('probe.p240','BLOQUEADO (FK RESTRICT)',false);
             WHEN others THEN PERFORM set_config('probe.p240','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p240','FALLO ('||SQLERRM||')',false); END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- VIS-A · plan de visitas por país ∈ operación (P241–P245). Red-first.
-- Reusa pa_ea (empresa A, opera GT por fixture Pub-A) + super_admin + cat_inv (proveedor A).
-- guard: pa_ready (da operación eA-GT) + vg3_ready (pais_id uuid). Helper de inserción común.
-- ============================================================
SELECT set_config('role','none',true);
-- P241 — NEG (red-first): super_admin crea plan en país NO operado (HN) → BLOQ
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id::text FROM public.perfiles WHERE rol='super_admin' LIMIT 1), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' OR current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p241','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, 1, current_setting('probe.p0_hn',true)::uuid, 10,0,100,CURRENT_DATE,CURRENT_DATE+30,'activo');
      PERFORM set_config('probe.p241','ROJO (creó plan en país NO operado — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p241','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P242 — POS: super_admin crea plan en país operado (GT) → OK
DO $$ BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' OR current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p242','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, 1, current_setting('probe.p0_gt',true)::uuid, 10,0,100,CURRENT_DATE,CURRENT_DATE+30,'activo');
      PERFORM set_config('probe.p242','OK (plan en país operado)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p242','FALLO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P243 — fail-closed: país NULL → BLOQ (NOT NULL)
DO $$ BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' OR current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p243','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, 1, NULL, 10,0,100,CURRENT_DATE,CURRENT_DATE+30,'activo');
      PERFORM set_config('probe.p243','ROJO (aceptó país NULL)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p243','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P244 — anti-escalada (no-regresión): proveedor NO crea plan (su empresa, estado='activo') → BLOQ
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' OR current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p244','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, 1, current_setting('probe.p0_gt',true)::uuid, 10,0,100,CURRENT_DATE,CURRENT_DATE+30,'activo');
      PERFORM set_config('probe.p244','ROJO (proveedor creó/auto-activó plan)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p244','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P245 — anti-escalada empresa (no-regresión): proveedor NO crea plan atribuido a empresa ajena → BLOQ
DO $$ DECLARE v_eb uuid; BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' OR current_setting('probe.vg3_ready',true)<>'1' THEN PERFORM set_config('probe.p245','N/A',false);
  ELSE
    SELECT empresa_id INTO v_eb FROM public.farmacias WHERE id=current_setting('probe.cat_fB',true)::int;
    BEGIN
      INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
        VALUES (v_eb, 1, current_setting('probe.p0_gt',true)::uuid, 10,0,100,CURRENT_DATE,CURRENT_DATE+30,'activo');
      PERFORM set_config('probe.p245','ROJO (proveedor creó plan de empresa ajena)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p245','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- V-G1 · ver calendario gateado por plan activo+país (P246–P253). Red-first.
-- Fixture: médico GT (fm_medgt) con slots contexto visitador+paciente; médico HN (p0_mednull→
-- país HN) con slot visitador; visitador cat_inv (empresa A=pa_ea, opera GT). Plan: sin/activo/
-- vencido. guard: pa_ready + fm_ready + pb_ready (paciente).
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_medhn uuid; BEGIN
  IF current_setting('probe.pa_ready',true)<>'1' OR current_setting('probe.fm_ready',true)<>'1' OR current_setting('probe.pb_ready',true)<>'1' THEN PERFORM set_config('probe.vg1_ready','0',false); RETURN; END IF;
  v_medhn := current_setting('probe.p0_mednull',true)::uuid;
  DELETE FROM public.planes_visitador_contratados WHERE empresa_id = current_setting('probe.pa_ea',true)::uuid;  -- estado limpio (P242 de Vis-A dejó un plan)
  UPDATE public.perfiles SET pais_id = current_setting('probe.p0_hn',true)::uuid WHERE id = v_medhn;   -- médico HN
  -- slots: médico GT (visitador + paciente), médico HN (visitador)
  INSERT INTO public.disponibilidad_medico (medico_id,dia_semana,hora_inicio,hora_fin,duracion_slot,activo,contexto)
    VALUES (current_setting('probe.fm_medgt',true)::uuid, 1,'09:00','10:00',30,true,'visitador');
  INSERT INTO public.disponibilidad_medico (medico_id,dia_semana,hora_inicio,hora_fin,duracion_slot,activo,contexto)
    VALUES (current_setting('probe.fm_medgt',true)::uuid, 2,'09:00','10:00',30,true,'paciente');
  INSERT INTO public.disponibilidad_medico (medico_id,dia_semana,hora_inicio,hora_fin,duracion_slot,activo,contexto)
    VALUES (v_medhn, 1,'09:00','10:00',30,true,'visitador');
  PERFORM set_config('probe.vg1_medhn', v_medhn::text, false);
  PERFORM set_config('probe.vg1_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.vg1_ready','0',false); END $$;

-- P246 — NEG (red-first): visitador SIN plan → 0 calendario (hoy ve todo por activo=true)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p246','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.fm_medgt',true)::uuid AND contexto='visitador';
    IF n=0 THEN PERFORM set_config('probe.p246','OK (visitador sin plan no ve calendario)',false);
    ELSE PERFORM set_config('probe.p246','ROJO (visitador sin plan ve calendario — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p246','FALLO ('||SQLERRM||')',false); END $$;

-- insertar plan ACTIVO vigente para empresa A en GT (owner; bypass WITH CHECK de 102)
SELECT set_config('role','none',true);
DO $$ BEGIN
  IF current_setting('probe.vg1_ready',true)='1' THEN
    INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
      VALUES (current_setting('probe.pa_ea',true)::uuid, 1, current_setting('probe.p0_gt',true)::uuid, 10,0,100,CURRENT_DATE-1,CURRENT_DATE+30,'activo');
  END IF;
END $$;

-- P250 — POS: visitador con plan GT activo → ve slots contexto='visitador' del médico GT
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p250','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.fm_medgt',true)::uuid AND contexto='visitador';
    IF n>0 THEN PERFORM set_config('probe.p250','OK (visitador con plan ve calendario del médico de su país)',false);
    ELSE PERFORM set_config('probe.p250','FALLO (visitador con plan NO ve calendario)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p250','FALLO ('||SQLERRM||')',false); END $$;

-- P247 — NEG: plan país GT, médico HN → 0
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p247','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.vg1_medhn',true)::uuid AND contexto='visitador';
    IF n=0 THEN PERFORM set_config('probe.p247','OK (plan GT no cubre médico HN)',false);
    ELSE PERFORM set_config('probe.p247','ROJO (plan GT ve médico HN — leak, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p247','FALLO ('||SQLERRM||')',false); END $$;

-- P248 — NEG: visitador NO ve slots contexto='paciente'
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p248','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.fm_medgt',true)::uuid AND contexto='paciente';
    IF n=0 THEN PERFORM set_config('probe.p248','OK (visitador no ve slots de paciente)',false);
    ELSE PERFORM set_config('probe.p248','ROJO (visitador ve slots contexto=paciente — leak, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p248','FALLO ('||SQLERRM||')',false); END $$;

-- P249 — NEG: plan vencido (fecha_fin pasada) → 0
SELECT set_config('role','none',true);
DO $$ BEGIN IF current_setting('probe.vg1_ready',true)='1' THEN
  UPDATE public.planes_visitador_contratados SET fecha_fin = CURRENT_DATE-1 WHERE empresa_id=current_setting('probe.pa_ea',true)::uuid AND pais_id=current_setting('probe.p0_gt',true)::uuid;
END IF; END $$;
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p249','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.fm_medgt',true)::uuid AND contexto='visitador';
    IF n=0 THEN PERFORM set_config('probe.p249','OK (plan vencido no ve calendario)',false);
    ELSE PERFORM set_config('probe.p249','ROJO (plan vencido ve calendario — leak, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p249','FALLO ('||SQLERRM||')',false); END $$;

-- P251 — fail-closed: no-proveedor (médico, mi_empresa NULL) NO ve contexto='visitador'
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p251','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.vg1_medhn',true)::uuid AND contexto='visitador';
    IF n=0 THEN PERFORM set_config('probe.p251','OK (no-proveedor no ve calendario visitador — fail-closed)',false);
    ELSE PERFORM set_config('probe.p251','ROJO (no-proveedor ve calendario visitador, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p251','FALLO ('||SQLERRM||')',false); END $$;

-- P252 — NO-REGRESIÓN agendamiento: paciente SÍ ve slots contexto='paciente'
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.pb_pac',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p252','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.fm_medgt',true)::uuid AND contexto='paciente';
    IF n>0 THEN PERFORM set_config('probe.p252','OK (paciente ve slots para agendar — preservado)',false);
    ELSE PERFORM set_config('probe.p252','FALLO (paciente NO ve slots — agendamiento roto)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p252','FALLO ('||SQLERRM||')',false); END $$;

-- P253 — NO-REGRESIÓN: el médico gestiona/ve su propia disponibilidad
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true))::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.p253','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico WHERE medico_id=current_setting('probe.fm_medgt',true)::uuid;
    IF n>0 THEN PERFORM set_config('probe.p253','OK (médico ve su propia disponibilidad)',false);
    ELSE PERFORM set_config('probe.p253','FALLO (médico no ve su disponibilidad)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p253','FALLO ('||SQLERRM||')',false); END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- V-G2 · agendar gateado por plan+país (P254–P260). Red-first.
-- Fixture: planes_asignaciones activo eA (cuota pasa) + manejo de planes_visitador_contratados.
-- Reusa fm_medgt (médico GT), vg1_medhn (médico HN), cat_inv (visitador eA). guard vg1_ready.
-- ============================================================
SELECT set_config('role','none',true);
DO $$ BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.va2_ready','0',false); RETURN; END IF;
  DELETE FROM public.planes_visitador_contratados WHERE empresa_id = current_setting('probe.pa_ea',true)::uuid;
  DELETE FROM public.planes_asignaciones WHERE empresa_id = current_setting('probe.pa_ea',true)::uuid;
  -- planes_asignaciones activo (cuota: plan_config_id NULL → ilimitado → pasa trg_limite)
  INSERT INTO public.planes_asignaciones (empresa_id,fecha_inicio,tipo_ciclo,precio_aplicado,moneda,estado,visitas_usadas)
    VALUES (current_setting('probe.pa_ea',true)::uuid, CURRENT_DATE, 'mensual', 0, 'GTQ', 'activo', 0);
  PERFORM set_config('probe.va2_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.va2_ready','0',false); PERFORM set_config('probe.va2_err',SQLERRM,false); END $$;

-- P254 — NEG (red-first): visitador SIN plan-visitador agenda médico GT → BLOQ (hoy agenda)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.va2_ready',true)<>'1' THEN PERFORM set_config('probe.p254','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.visitas_agendadas (empresa_id,medico_id,cuenta_proveedor_id,fecha_visita,hora_inicio,hora_fin,tipo_visita,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, current_setting('probe.fm_medgt',true)::uuid, current_setting('probe.cat_inv',true)::uuid, CURRENT_DATE+7,'09:00','10:00','presencial','pendiente');
      PERFORM set_config('probe.p254','ROJO (agendó sin plan de visitas — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p254','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- insertar plan-visitador ACTIVO vigente GT (owner)
SELECT set_config('role','none',true);
DO $$ BEGIN IF current_setting('probe.va2_ready',true)='1' THEN
  INSERT INTO public.planes_visitador_contratados (empresa_id,plan_visitador_id,pais_id,cantidad_visitas_incluidas,visitas_usadas,precio_pagado,fecha_inicio,fecha_fin,estado)
    VALUES (current_setting('probe.pa_ea',true)::uuid, 1, current_setting('probe.p0_gt',true)::uuid, 10,0,100,CURRENT_DATE-1,CURRENT_DATE+30,'activo');
END IF; END $$;

-- P255 — POS: visitador con plan GT activo agenda médico GT → OK
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v_id uuid; BEGIN
  IF current_setting('probe.va2_ready',true)<>'1' THEN PERFORM set_config('probe.p255','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.visitas_agendadas (empresa_id,medico_id,cuenta_proveedor_id,fecha_visita,hora_inicio,hora_fin,tipo_visita,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, current_setting('probe.fm_medgt',true)::uuid, current_setting('probe.cat_inv',true)::uuid, CURRENT_DATE+8,'09:00','10:00','presencial','pendiente') RETURNING id INTO v_id;
      PERFORM set_config('probe.va2_visita', v_id::text, false);
      PERFORM set_config('probe.p255','OK (agenda con plan país-cubriente)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p255','FALLO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P256 — NEG: visitador (plan GT) agenda médico HN → BLOQ
DO $$ BEGIN
  IF current_setting('probe.va2_ready',true)<>'1' THEN PERFORM set_config('probe.p256','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.visitas_agendadas (empresa_id,medico_id,cuenta_proveedor_id,fecha_visita,hora_inicio,hora_fin,tipo_visita,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, current_setting('probe.vg1_medhn',true)::uuid, current_setting('probe.cat_inv',true)::uuid, CURRENT_DATE+9,'09:00','10:00','presencial','pendiente');
      PERFORM set_config('probe.p256','ROJO (agendó médico de otro país — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p256','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P257 — NEG: plan-visitador vencido → BLOQ
SELECT set_config('role','none',true);
DO $$ BEGIN IF current_setting('probe.va2_ready',true)='1' THEN
  UPDATE public.planes_visitador_contratados SET fecha_fin=CURRENT_DATE-1 WHERE empresa_id=current_setting('probe.pa_ea',true)::uuid;
END IF; END $$;
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.va2_ready',true)<>'1' THEN PERFORM set_config('probe.p257','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.visitas_agendadas (empresa_id,medico_id,cuenta_proveedor_id,fecha_visita,hora_inicio,hora_fin,tipo_visita,estado)
        VALUES (current_setting('probe.pa_ea',true)::uuid, current_setting('probe.fm_medgt',true)::uuid, current_setting('probe.cat_inv',true)::uuid, CURRENT_DATE+10,'09:00','10:00','presencial','pendiente');
      PERFORM set_config('probe.p257','ROJO (agendó con plan vencido — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p257','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P258 — re-targeting: UPDATE de medico_id a un médico no cubierto → BLOQ (restaura plan antes)
SELECT set_config('role','none',true);
DO $$ BEGIN IF current_setting('probe.va2_ready',true)='1' THEN
  UPDATE public.planes_visitador_contratados SET fecha_fin=CURRENT_DATE+30 WHERE empresa_id=current_setting('probe.pa_ea',true)::uuid;
END IF; END $$;
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cat_inv',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v_id uuid; BEGIN
  IF current_setting('probe.va2_ready',true)<>'1' THEN PERFORM set_config('probe.p258','N/A',false);
  ELSE
    -- visita propia de P258 (médico GT, plan activo) para no tocar va2_visita (usada por P259)
    INSERT INTO public.visitas_agendadas (empresa_id,medico_id,cuenta_proveedor_id,fecha_visita,hora_inicio,hora_fin,tipo_visita,estado)
      VALUES (current_setting('probe.pa_ea',true)::uuid, current_setting('probe.fm_medgt',true)::uuid, current_setting('probe.cat_inv',true)::uuid, CURRENT_DATE+11,'09:00','10:00','presencial','pendiente') RETURNING id INTO v_id;
    BEGIN
      UPDATE public.visitas_agendadas SET medico_id = current_setting('probe.vg1_medhn',true)::uuid WHERE id = v_id;
      PERFORM set_config('probe.p258','ROJO (re-targeteó a médico no cubierto — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p258','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p258','FALLO ('||SQLERRM||')',false); END $$;

-- P259 — NO-REGRESIÓN: médico aprueba/cancela (UPDATE de estado sin tocar medico_id) → OK
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.fm_medgt',true), 'role','authenticated')::text, true);
DO $$ DECLARE v_n int; BEGIN
  IF current_setting('probe.va2_ready',true)<>'1' OR NULLIF(current_setting('probe.va2_visita',true),'') IS NULL THEN PERFORM set_config('probe.p259','N/A',false);
  ELSE
    BEGIN
      UPDATE public.visitas_agendadas SET estado='confirmada' WHERE id = current_setting('probe.va2_visita',true)::uuid AND medico_id = current_setting('probe.fm_medgt',true)::uuid;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n=1 THEN PERFORM set_config('probe.p259','OK (médico aprueba/cancela sin disparar el gate país)',false);
      ELSE PERFORM set_config('probe.p259','FALLO (UPDATE de estado afectó '||v_n||' filas)',false); END IF;
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p259','FALLO (gate bloqueó UPDATE de estado: '||SQLERRM||')',false); END;
  END IF;
END $$;

-- P260 — NO-REGRESIÓN cuota: trg_limite_visitas sigue presente (no se tocó)
SELECT set_config('role','none',true);
DO $$ DECLARE v_ok boolean; BEGIN
  SELECT count(*)>0 INTO v_ok FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='visitas_agendadas' AND t.tgname='trg_limite_visitas' AND NOT t.tgisinternal;
  IF v_ok THEN PERFORM set_config('probe.p260','OK (trg_limite_visitas intacto)',false);
  ELSE PERFORM set_config('probe.p260','FALLO (trg_limite_visitas ausente)',false); END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- Deuda (d) · Endurecer search_path SECURITY DEFINER (P261–P262). Red-first.
-- P261: HIJACK behavioral — un schema con `medico_clinicas` falsa en el search_path del
--       caller secuestra obtener_clinica_principal_medico (pre-fix: lee la tabla del
--       atacante → ROJO; post-fix: search_path='' la ignora → OK).
-- P262: estructural — ambas funciones fijan search_path (no NULL, no 'public').
-- ============================================================
SELECT set_config('role','none',true);
DO $$
DECLARE v_clin uuid; v_old text;
BEGIN
  v_old := current_setting('search_path');
  DROP SCHEMA IF EXISTS probe_evil CASCADE;
  CREATE SCHEMA probe_evil;
  CREATE TABLE probe_evil.medico_clinicas (clinica_id uuid, es_principal boolean, medico_id uuid);
  INSERT INTO probe_evil.medico_clinicas
    VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', true, 'dddddddd-dddd-dddd-dddd-dddddddddddd');
  -- prepender el schema malicioso al search_path del caller
  PERFORM set_config('search_path','probe_evil, public, private', true);
  -- llamar la función DEFINER para un médico SIN clínica principal real
  SELECT clinica_id INTO v_clin
  FROM public.obtener_clinica_principal_medico('dddddddd-dddd-dddd-dddd-dddddddddddd') LIMIT 1;
  -- restaurar search_path y limpiar antes de los veredictos
  PERFORM set_config('search_path', v_old, true);
  DROP SCHEMA IF EXISTS probe_evil CASCADE;
  IF v_clin = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' THEN
    PERFORM set_config('probe.p261','ROJO (hijack: leyó medico_clinicas del atacante)',false);
  ELSE
    PERFORM set_config('probe.p261','OK (ignoró schema malicioso; search_path fijado)',false);
  END IF;
EXCEPTION WHEN others THEN
  PERFORM set_config('search_path', coalesce(v_old,'public, private'), true);
  PERFORM set_config('probe.p261','FALLO ('||SQLERRM||')',false);
END $$;
SELECT set_config('role','none',true);

-- P262 — estructural: ambas funciones fijan search_path (no NULL, no 'public')
DO $$
DECLARE v_obt text[]; v_lab text[]; v_ok boolean;
BEGIN
  SELECT proconfig INTO v_obt FROM pg_proc WHERE oid='public.obtener_clinica_principal_medico(uuid)'::regprocedure;
  SELECT proconfig INTO v_lab FROM pg_proc WHERE oid='public.laboratorios_para_medico()'::regprocedure;
  v_ok := EXISTS (SELECT 1 FROM unnest(coalesce(v_obt,'{}'::text[])) e WHERE e LIKE 'search_path=%' AND e <> 'search_path=public')
      AND EXISTS (SELECT 1 FROM unnest(coalesce(v_lab,'{}'::text[])) e WHERE e LIKE 'search_path=%' AND e <> 'search_path=public');
  IF v_ok THEN PERFORM set_config('probe.p262','OK (ambas fijan search_path vacío)',false);
  ELSE PERFORM set_config('probe.p262','ROJO (search_path sin endurecer: obt='||coalesce(array_to_string(v_obt,','),'NULL')||' lab='||coalesce(array_to_string(v_lab,','),'NULL')||')',false); END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- Deuda (c) · Aislamiento país agendamiento paciente↔médico (P263–P266). Red-first.
-- Reusa: fm_medgt (médico GT, slot contexto='paciente' dia2), vg1_medhn (médico HN),
-- p0_gt/p0_hn. Fixture: paciente real con país GT + slot contexto='paciente' del médico HN.
-- guard cc_ready (depende de vg1_ready).
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_pac bigint; v_pacu uuid; BEGIN
  IF current_setting('probe.vg1_ready',true)<>'1' THEN PERFORM set_config('probe.cc_ready','0',false); RETURN; END IF;
  SELECT id, auth_user_id INTO v_pac, v_pacu FROM public.pacientes WHERE auth_user_id IS NOT NULL ORDER BY id LIMIT 1;
  IF v_pac IS NULL THEN PERFORM set_config('probe.cc_ready','0',false); RETURN; END IF;
  UPDATE public.pacientes SET pais_id = current_setting('probe.p0_gt',true)::uuid WHERE id = v_pac;   -- paciente GT
  -- slot contexto='paciente' para el médico HN (vg1_medhn) — la "carnada" cross-país
  INSERT INTO public.disponibilidad_medico (medico_id,dia_semana,hora_inicio,hora_fin,duracion_slot,activo,contexto)
    VALUES (current_setting('probe.vg1_medhn',true)::uuid, 3,'09:00','10:00',30,true,'paciente');
  PERFORM set_config('probe.cc_pac', v_pac::text, false);
  PERFORM set_config('probe.cc_pacu', v_pacu::text, false);
  PERFORM set_config('probe.cc_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.cc_ready','0',false); PERFORM set_config('probe.cc_err',SQLERRM,false); END $$;

-- P263 — NEG (red-first): paciente GT NO debe VER disponibilidad de médico HN (hoy la ve)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cc_pacu',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.cc_ready',true)<>'1' THEN PERFORM set_config('probe.p263','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico
       WHERE medico_id=current_setting('probe.vg1_medhn',true)::uuid AND contexto='paciente';
    IF n=0 THEN PERFORM set_config('probe.p263','OK (paciente no ve disponibilidad de médico de otro país)',false);
    ELSE PERFORM set_config('probe.p263','ROJO (paciente ve médico de otro país — leak vivo, n='||n||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p263','FALLO ('||SQLERRM||')',false); END $$;

-- P264 — POS (no-regresión): paciente GT SÍ ve disponibilidad de médico GT
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.cc_ready',true)<>'1' THEN PERFORM set_config('probe.p264','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.disponibilidad_medico
       WHERE medico_id=current_setting('probe.fm_medgt',true)::uuid AND contexto='paciente';
    IF n>0 THEN PERFORM set_config('probe.p264','OK (paciente ve disponibilidad de médico de su país)',false);
    ELSE PERFORM set_config('probe.p264','FALLO (paciente no ve médico de su país — regresión)',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p264','FALLO ('||SQLERRM||')',false); END $$;

-- P265 — NEG write gate (red-first): paciente GT crear_cita con médico HN → BLOQ (hoy agenda)
DO $$ DECLARE v_id bigint; BEGIN
  IF current_setting('probe.cc_ready',true)<>'1' THEN PERFORM set_config('probe.p265','N/A',false);
  ELSE
    BEGIN
      SELECT public.crear_cita(
        p_paciente_id := current_setting('probe.cc_pac',true)::bigint,
        p_medico_id   := current_setting('probe.vg1_medhn',true)::uuid,   -- médico HN
        p_fecha       := CURRENT_DATE+7, p_hora_inicio := '09:00', p_hora_fin := '10:00',
        p_pais_id     := current_setting('probe.p0_hn',true)::uuid) INTO v_id;
      PERFORM set_config('probe.p265','ROJO (agendó con médico de otro país — leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p265','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P266 — POS write gate + DERIVACIÓN país (red-first / lección 8): paciente GT crea cita
-- con médico GT pasando p_pais_id BOGUS (HN) → país de la cita debe quedar = país del médico (GT)
DO $$ DECLARE v_id bigint; v_pais uuid; BEGIN
  IF current_setting('probe.cc_ready',true)<>'1' THEN PERFORM set_config('probe.p266','N/A',false);
  ELSE
    BEGIN
      SELECT public.crear_cita(
        p_paciente_id := current_setting('probe.cc_pac',true)::bigint,
        p_medico_id   := current_setting('probe.fm_medgt',true)::uuid,    -- médico GT
        p_fecha       := CURRENT_DATE+8, p_hora_inicio := '11:00', p_hora_fin := '12:00',
        p_pais_id     := current_setting('probe.p0_hn',true)::uuid) INTO v_id;   -- país BOGUS (HN)
      SELECT pais_id INTO v_pais FROM public.citas WHERE id = v_id;
      IF v_pais = current_setting('probe.p0_gt',true)::uuid THEN
        PERFORM set_config('probe.p266','OK (país derivado del médico, ignoró p_pais_id del cliente)',false);
      ELSE
        PERFORM set_config('probe.p266','ROJO (país de la cita='||coalesce(v_pais::text,'NULL')||' ≠ país del médico — p_pais_id del cliente)',false);
      END IF;
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p266','FALLO ('||SQLERRM||')',false); END;
  END IF;
END $$;

-- P267 — CHOKEPOINT: paciente INSERT DIRECTO a citas (sin pasar por crear_cita) → DENEGADO
-- (invariante: la única vía de escritura del paciente es el RPC; si no, el gate país se evade)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.cc_pacu',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.cc_ready',true)<>'1' THEN PERFORM set_config('probe.p267','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.citas (paciente_id, medico_id, fecha, hora_inicio, hora_fin, estado)
        VALUES (current_setting('probe.cc_pac',true)::bigint, current_setting('probe.vg1_medhn',true)::uuid,
                CURRENT_DATE+9,'13:00','14:00','solicitada');
      PERFORM set_config('probe.p267','ROJO (INSERT directo a citas permitido — evade crear_cita)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p267','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;
SELECT set_config('role','none',true);

-- P268 — estructural (red-first): mi_clinica_medico fija search_path '' (no 'public', no NULL)
DO $$ DECLARE v_cfg text[]; v_ok boolean; BEGIN
  SELECT proconfig INTO v_cfg FROM pg_proc WHERE oid='public.mi_clinica_medico()'::regprocedure;
  v_ok := EXISTS (SELECT 1 FROM unnest(coalesce(v_cfg,'{}'::text[])) e WHERE e LIKE 'search_path=%' AND e <> 'search_path=public');
  IF v_ok THEN PERFORM set_config('probe.p268','OK (mi_clinica_medico fija search_path vacío)',false);
  ELSE PERFORM set_config('probe.p268','ROJO (search_path sin endurecer: '||coalesce(array_to_string(v_cfg,','),'NULL')||')',false); END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- Ola 2 · admin_clinica/gerente ven el PHI de SU clínica (P269–P281). Red-first.
-- Fixture: clínica A (>=2 médicos), medA (autor del PHI), medA2 (colega, viewer anti-OR-trap),
-- adminA (perfil SIN membresía → rol admin_clinica + clinicas.doctor_id=A → clinicas_del_usuario={A}),
-- clínica B con medB (médico fuera de A) + PHI de B (guard). PHI autorado por medA en 8 tablas.
-- ============================================================
SELECT set_config('role','none',true);
DO $$
DECLARE v_clinA uuid; v_medA uuid; v_medA2 uuid; v_adminA uuid; v_clinB uuid; v_medB uuid;
        v_pacA bigint; v_pacB bigint; v_recA bigint; v_catC uuid; v_medA2_rol text;
BEGIN
  -- médicos que son USUARIOS reales (medicos.id == perfiles.id == auth.uid()): los que autoran PHI
  SELECT clinica_id INTO v_clinA FROM public.medico_clinicas mc
    WHERE mc.medico_id IN (SELECT id FROM public.perfiles)
    GROUP BY clinica_id HAVING count(*)>=2 ORDER BY count(*) DESC LIMIT 1;
  IF v_clinA IS NULL THEN PERFORM set_config('probe.acp_ready','0',false); PERFORM set_config('probe.acp_err','sin clínica con >=2 médicos en perfiles',false); RETURN; END IF;
  SELECT medico_id INTO v_medA  FROM public.medico_clinicas WHERE clinica_id=v_clinA AND medico_id IN (SELECT id FROM public.perfiles) ORDER BY medico_id LIMIT 1;
  -- colega viewer del anti-OR-trap: médico PURO (rol='medico', sin admin_clinica/gerente)
  SELECT medico_id INTO v_medA2 FROM public.medico_clinicas WHERE clinica_id=v_clinA AND medico_id IN (SELECT id FROM public.perfiles WHERE rol='medico') AND medico_id<>v_medA ORDER BY medico_id LIMIT 1;
  SELECT mc.clinica_id, mc.medico_id INTO v_clinB, v_medB FROM public.medico_clinicas mc
    WHERE mc.clinica_id<>v_clinA AND mc.medico_id IN (SELECT id FROM public.perfiles)
      AND mc.medico_id NOT IN (SELECT medico_id FROM public.medico_clinicas WHERE clinica_id=v_clinA) LIMIT 1;
  SELECT id INTO v_adminA FROM public.perfiles
    WHERE id NOT IN (SELECT medico_id FROM public.medico_clinicas)
      AND id <> COALESCE(v_medB,'00000000-0000-0000-0000-000000000000'::uuid)
    ORDER BY id LIMIT 1;
  IF v_medA2 IS NULL OR v_adminA IS NULL OR v_medB IS NULL THEN
    PERFORM set_config('probe.acp_ready','0',false); PERFORM set_config('probe.acp_err','fixture incompleto medA2/adminA/medB',false); RETURN; END IF;
  UPDATE public.perfiles SET rol='admin_clinica' WHERE id=v_adminA;
  UPDATE public.clinicas SET doctor_id=v_adminA WHERE id=v_clinA;
  INSERT INTO public.pacientes (nombre,apellido,activo,medico_id) VALUES ('PROBE','PacA',true,v_medA) RETURNING id INTO v_pacA;
  INSERT INTO public.pacientes (nombre,apellido,activo,medico_id) VALUES ('PROBE','PacB',true,v_medB) RETURNING id INTO v_pacB;
  INSERT INTO public.historial_medico (paciente_id,medico_id,tipo_evento,titulo) VALUES (v_pacA::text, v_medA::text, 'nota','probe A');
  INSERT INTO public.recetas (medico_id,paciente_id) VALUES (v_medA, v_pacA) RETURNING id INTO v_recA;
  INSERT INTO public.recetas_avanzadas (receta_base_id,paciente_id,medico_id) VALUES (v_recA, v_pacA::text, v_medA::text);
  INSERT INTO public.receta_items (receta_id,nombre_medicamento,dosis,frecuencia) VALUES (v_recA,'Probe med','1','c/8h');
  INSERT INTO public.expediente_notas (paciente_id,medico_id) VALUES (v_pacA::int, v_medA);
  INSERT INTO public.signos_vitales (paciente_id,medico_id) VALUES (v_pacA::int, v_medA);
  INSERT INTO public.examenes (tipo,medico_id,paciente_id) VALUES ('laboratorio', v_medA, v_pacA::int);
  INSERT INTO public.citas (paciente_id,medico_id,clinica_id,fecha,hora_inicio,hora_fin,estado)
    VALUES (v_pacA, v_medA, v_clinA, CURRENT_DATE+5,'09:00','10:00','agendada');
  INSERT INTO public.historial_medico (paciente_id,medico_id,tipo_evento,titulo) VALUES (v_pacB::text, v_medB::text, 'nota','probe B');  -- PHI clínica B (guard)
  -- DIVERGENCIA id-space (P282): médico de CATÁLOGO (medicos-only, NO en perfiles) DENTRO de la
  -- clínica A, + PHI (recetas) autorado por identidad perfiles (medB) que NO es miembro de A →
  -- el admin de A NO debe verlo (prueba que la divergencia de espacios no produce falso-positivo).
  SELECT id INTO v_catC FROM public.medicos WHERE id NOT IN (SELECT id FROM public.perfiles) LIMIT 1;
  IF v_catC IS NOT NULL THEN INSERT INTO public.medico_clinicas (medico_id, clinica_id) VALUES (v_catC, v_clinA); END IF;
  INSERT INTO public.recetas (medico_id, paciente_id) VALUES (v_medB, v_pacB);   -- PHI autorado por perfiles fuera de A
  SELECT rol INTO v_medA2_rol FROM public.perfiles WHERE id=v_medA2;
  PERFORM set_config('probe.acp_medA2_rol', COALESCE(v_medA2_rol,'?'), false);
  PERFORM set_config('probe.acp_medB',v_medB::text,false); PERFORM set_config('probe.acp_catC', COALESCE(v_catC::text,''), false);
  PERFORM set_config('probe.acp_clinA',v_clinA::text,false); PERFORM set_config('probe.acp_medA',v_medA::text,false);
  PERFORM set_config('probe.acp_medA2',v_medA2::text,false); PERFORM set_config('probe.acp_adminA',v_adminA::text,false);
  PERFORM set_config('probe.acp_medB',v_medB::text,false); PERFORM set_config('probe.acp_pacA',v_pacA::text,false);
  PERFORM set_config('probe.acp_recA',v_recA::text,false); PERFORM set_config('probe.acp_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.acp_ready','0',false); PERFORM set_config('probe.acp_err',SQLERRM,false); END $$;

-- Positivos (admin A): ROJO pre (sin policy) → OK post (≥1)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.acp_adminA',true),'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; r boolean; BEGIN
  IF current_setting('probe.acp_ready',true)<>'1' THEN
    FOR n IN 269..276 LOOP PERFORM set_config('probe.p'||n,'N/A ('||coalesce(current_setting('probe.acp_err',true),'')||')',false); END LOOP; RETURN; END IF;
  SELECT count(*) INTO n FROM public.historial_medico WHERE medico_id=current_setting('probe.acp_medA',true);
  PERFORM set_config('probe.p269', CASE WHEN n>=1 THEN 'OK (admin ve historial de su clínica: '||n||')' ELSE 'ROJO (admin no ve historial de su clínica — feature ausente)' END, false);
  SELECT count(*) INTO n FROM public.recetas WHERE medico_id=current_setting('probe.acp_medA',true)::uuid;
  PERFORM set_config('probe.p270', CASE WHEN n>=1 THEN 'OK (admin ve recetas: '||n||')' ELSE 'ROJO (admin no ve recetas — feature ausente)' END, false);
  SELECT count(*) INTO n FROM public.recetas_avanzadas WHERE medico_id=current_setting('probe.acp_medA',true);
  PERFORM set_config('probe.p271', CASE WHEN n>=1 THEN 'OK (admin ve recetas_avanzadas: '||n||')' ELSE 'ROJO (admin no ve recetas_avanzadas — feature ausente)' END, false);
  SELECT count(*) INTO n FROM public.receta_items WHERE receta_id=current_setting('probe.acp_recA',true)::bigint;
  PERFORM set_config('probe.p272', CASE WHEN n>=1 THEN 'OK (admin ve receta_items: '||n||')' ELSE 'ROJO (admin no ve receta_items — feature ausente)' END, false);
  SELECT count(*) INTO n FROM public.expediente_notas WHERE medico_id=current_setting('probe.acp_medA',true)::uuid;
  PERFORM set_config('probe.p273', CASE WHEN n>=1 THEN 'OK (admin ve expediente_notas: '||n||')' ELSE 'ROJO (admin no ve expediente_notas — feature ausente)' END, false);
  SELECT count(*) INTO n FROM public.signos_vitales WHERE medico_id=current_setting('probe.acp_medA',true)::uuid;
  PERFORM set_config('probe.p274', CASE WHEN n>=1 THEN 'OK (admin ve signos_vitales: '||n||')' ELSE 'ROJO (admin no ve signos_vitales — feature ausente)' END, false);
  SELECT count(*) INTO n FROM public.examenes WHERE medico_id=current_setting('probe.acp_medA',true)::uuid;
  PERFORM set_config('probe.p275', CASE WHEN n>=1 THEN 'OK (admin ve examenes: '||n||')' ELSE 'ROJO (admin no ve examenes — feature ausente)' END, false);
  SELECT count(*) INTO n FROM public.pacientes WHERE id=current_setting('probe.acp_pacA',true)::bigint;
  PERFORM set_config('probe.p276', CASE WHEN n>=1 THEN 'OK (admin ve pacientes de su clínica: '||n||')' ELSE 'ROJO (admin no ve pacientes — feature ausente)' END, false);
END $$;

-- P277 — GUARD cross-clínica (admin A NO ve PHI de B): 0 PRE y 0 POST (no es red→green)
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.acp_ready',true)<>'1' THEN PERFORM set_config('probe.p277','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.historial_medico WHERE medico_id=current_setting('probe.acp_medB',true);
    PERFORM set_config('probe.p277', CASE WHEN n=0 THEN 'OK (admin no ve PHI de otra clínica)' ELSE 'ROJO (admin ve PHI cross-clínica: '||n||')' END, false);
  END IF;
END $$;

-- P278 — ANTI-OR-TRAP (médico colega medA2, rol medico): NO ve PHI de medA vía policy admin
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.acp_medA2',true),'role','authenticated')::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.acp_ready',true)<>'1' THEN PERFORM set_config('probe.p278','N/A',false);
  ELSIF current_setting('probe.acp_medA2_rol',true)<>'medico' THEN
    PERFORM set_config('probe.p278','N/A (actor no es médico puro: rol='||current_setting('probe.acp_medA2_rol',true)||')',false);
  ELSE SELECT count(*) INTO n FROM public.historial_medico WHERE medico_id=current_setting('probe.acp_medA',true);
    PERFORM set_config('probe.p278', CASE WHEN n=0 THEN 'OK (médico PURO no ve PHI de colega vía policy admin)' ELSE 'PERMITIDO (médico vio PHI de colega: '||n||')' END, false);
  END IF;
END $$;

-- P279 — NO-REGRESIÓN paciente: paciente no ve recetas ajenas (las del fixture medA/pacA)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.paciente_u',true),'role','authenticated')::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.acp_ready',true)<>'1' OR NULLIF(current_setting('probe.paciente_u',true),'') IS NULL THEN PERFORM set_config('probe.p279','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.recetas WHERE paciente_id=current_setting('probe.acp_pacA',true)::bigint;  -- receta de PacA (ajena a paciente_u)
    PERFORM set_config('probe.p279', CASE WHEN n=0 THEN 'OK (paciente no ve receta de otro paciente)' ELSE 'PERMITIDO (paciente vio receta ajena: '||n||')' END, false);
  END IF;
END $$;

-- P280 — NO-REGRESIÓN citas: admin A sigue viendo citas de su clínica (policy de citas intacta)
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.acp_adminA',true),'role','authenticated')::text, true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.acp_ready',true)<>'1' THEN PERFORM set_config('probe.p280','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.citas WHERE clinica_id=current_setting('probe.acp_clinA',true)::uuid;
    PERFORM set_config('probe.p280', CASE WHEN n>=1 THEN 'OK (admin ve citas de su clínica: '||n||')' ELSE 'REGRESIÓN (admin no ve citas de su clínica)' END, false);
  END IF;
END $$;

-- P281 — anon cerrado en las tablas PHI nuevas
SELECT set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
SELECT set_config('role','anon',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.acp_ready',true)<>'1' THEN PERFORM set_config('probe.p281','N/A',false);
  ELSE SELECT (SELECT count(*) FROM public.historial_medico WHERE medico_id=current_setting('probe.acp_medA',true))
            + (SELECT count(*) FROM public.recetas WHERE medico_id=current_setting('probe.acp_medA',true)::uuid)
            + (SELECT count(*) FROM public.pacientes WHERE id=current_setting('probe.acp_pacA',true)::bigint) INTO n;
    PERFORM set_config('probe.p281', CASE WHEN n=0 THEN 'OK (anon cerrado)' ELSE 'PERMITIDO (anon vio '||n||' filas PHI)' END, false);
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p281','OK (anon error/cerrado: '||SQLSTATE||')',false); END $$;

-- P282 — GUARD DIVERGENCIA id-space: con un médico de catálogo (medicos-only) DENTRO de la
-- clínica A, el admin NO ve PHI autorado por una identidad perfiles que NO es miembro de A.
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.acp_adminA',true),'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.acp_ready',true)<>'1' THEN PERFORM set_config('probe.p282','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.recetas WHERE medico_id=current_setting('probe.acp_medB',true)::uuid;
    PERFORM set_config('probe.p282', CASE WHEN n=0
      THEN 'OK (divergencia id-space no produce falso-positivo; catálogo C en A no filtra PHI de perfiles fuera de A)'
      ELSE 'ROJO (leak por divergencia id-space: admin vio '||n||' recetas de perfiles fuera de su clínica)' END, false);
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- Ola 2 · LEAK-FIX métricas de campaña (P283–P290). Red-first.
-- Fixture: una campaña, un médico (authenticated no-admin), un super_admin, un paciente.
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_camp int; v_med uuid; v_sa uuid; v_pac int; BEGIN
  SELECT id INTO v_camp FROM public.campanas_publicitarias LIMIT 1;
  SELECT id INTO v_med FROM public.perfiles WHERE rol='medico' LIMIT 1;
  SELECT id INTO v_sa FROM public.perfiles WHERE rol='super_admin' LIMIT 1;
  SELECT id INTO v_pac FROM public.pacientes WHERE auth_user_id = NULLIF(current_setting('probe.paciente_u',true),'')::uuid LIMIT 1;
  PERFORM set_config('probe.cm_camp',COALESCE(v_camp::text,''),false);
  PERFORM set_config('probe.cm_med',COALESCE(v_med::text,''),false);
  PERFORM set_config('probe.cm_sa',COALESCE(v_sa::text,''),false);
  PERFORM set_config('probe.cm_pac',COALESCE(v_pac::text,''),false);
  PERFORM set_config('probe.cm_ready', CASE WHEN v_camp IS NOT NULL AND v_med IS NOT NULL AND v_sa IS NOT NULL THEN '1' ELSE '0' END, false);
END $$;

-- P283 — anon NO ve v_metricas_campana_resumen (PRE 🔴 leak, POST 0)
SELECT set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
SELECT set_config('role','anon',true);
DO $$ DECLARE n int; BEGIN
  BEGIN SELECT count(*) INTO n FROM public.v_metricas_campana_resumen;
    PERFORM set_config('probe.p283', CASE WHEN n=0 THEN 'OK (anon no ve resumen)' ELSE 'ROJO (anon ve métricas resumen de todas las empresas: '||n||')' END, false);
  EXCEPTION WHEN others THEN PERFORM set_config('probe.p283','OK (anon sin acceso: '||SQLSTATE||')',false); END;
END $$;

-- P284 — anon NO ve v_metricas_campana_pais (PRE 🔴, POST 0)
DO $$ DECLARE n int; BEGIN
  BEGIN SELECT count(*) INTO n FROM public.v_metricas_campana_pais;
    PERFORM set_config('probe.p284', CASE WHEN n=0 THEN 'OK (anon no ve pais)' ELSE 'ROJO (anon ve métricas pais: '||n||')' END, false);
  EXCEPTION WHEN others THEN PERFORM set_config('probe.p284','OK (anon sin acceso: '||SQLSTATE||')',false); END;
END $$;

-- P285 — authenticated no-admin NO ve v_resumen (PRE 🔴, POST 0)
SELECT set_config('request.jwt.claims', json_build_object('sub',current_setting('probe.cm_med',true),'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.cm_ready',true)<>'1' THEN PERFORM set_config('probe.p285','N/A',false);
  ELSE BEGIN SELECT count(*) INTO n FROM public.v_metricas_campana_resumen;
    PERFORM set_config('probe.p285', CASE WHEN n=0 THEN 'OK (no-admin no ve resumen)' ELSE 'ROJO (no-admin ve métricas resumen ajenas: '||n||')' END, false);
  EXCEPTION WHEN others THEN PERFORM set_config('probe.p285','OK (no-admin sin acceso: '||SQLSTATE||')',false); END; END IF;
END $$;

-- P286 — no-admin NO ve MÉTRICAS de rendimiento en v_pais (impr+clicks); residual conteo no-sensible
DO $$ DECLARE m bigint; BEGIN
  IF current_setting('probe.cm_ready',true)<>'1' THEN PERFORM set_config('probe.p286','N/A',false);
  ELSE BEGIN SELECT COALESCE(sum(impresiones_totales+clicks_totales),0) INTO m FROM public.v_metricas_campana_pais;
    PERFORM set_config('probe.p286', CASE WHEN m=0 THEN 'OK (no-admin ve 0 métricas de rendimiento)' ELSE 'ROJO (no-admin ve métricas de rendimiento ajenas: '||m||')' END, false);
  EXCEPTION WHEN others THEN PERFORM set_config('probe.p286','OK (no-admin sin acceso: '||SQLSTATE||')',false); END; END IF;
END $$;

-- P287 — NO-REGRESIÓN super_admin: sigue viendo las vistas completas (crítico para dashboard admin)
SELECT set_config('request.jwt.claims', json_build_object('sub',current_setting('probe.cm_sa',true),'role','authenticated')::text, true);
DO $$ DECLARE n int; m bigint; BEGIN
  IF current_setting('probe.cm_ready',true)<>'1' THEN PERFORM set_config('probe.p287','N/A',false);
  ELSE SELECT count(*) INTO n FROM public.v_metricas_campana_resumen;
       SELECT COALESCE(sum(impresiones_totales+clicks_totales),0) INTO m FROM public.v_metricas_campana_pais;
    IF n>0 AND m>0 THEN PERFORM set_config('probe.p287','OK (super_admin ve métricas completas: resumen='||n||', metricas_pais='||m||')',false);
    ELSE PERFORM set_config('probe.p287','REGRESIÓN (super_admin perdió acceso: resumen='||n||', metricas='||m||')',false); END IF;
  END IF;
EXCEPTION WHEN others THEN PERFORM set_config('probe.p287','REGRESIÓN (super_admin error: '||SQLERRM||')',false); END $$;

-- P288 — tabla base campana_metricas: no-admin = 0 (RLS intacta) — no-regresión
SELECT set_config('request.jwt.claims', json_build_object('sub',current_setting('probe.cm_med',true),'role','authenticated')::text, true);
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.campana_metricas;
  PERFORM set_config('probe.p288', CASE WHEN n=0 THEN 'OK (no-admin no ve tabla base)' ELSE 'PERMITIDO (no-admin ve '||n||' filas base)' END, false);
END $$;

-- P289 — WRITE-LEAK: authenticated NO debe poder INSERT directo en campana_metricas (PRE 🔴, POST bloqueado)
DO $$ BEGIN
  IF current_setting('probe.cm_ready',true)<>'1' THEN PERFORM set_config('probe.p289','N/A',false);
  ELSE
    BEGIN
      INSERT INTO public.campana_metricas (campana_id, clickeado, tipo_perfil, sesion_id)
        VALUES (current_setting('probe.cm_camp',true)::int, true, 'probe', 'probe-sesion');
      PERFORM set_config('probe.p289','ROJO (authenticated insertó métrica arbitraria — write-leak vivo)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p289','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P290 — NO-REGRESIÓN: el paciente SIGUE pudiendo registrar su vista de anuncio (campana_vistas)
SELECT set_config('request.jwt.claims', json_build_object('sub',current_setting('probe.paciente_u',true),'role','authenticated')::text, true);
DO $$ BEGIN
  IF NULLIF(current_setting('probe.cm_pac',true),'')='' OR current_setting('probe.cm_ready',true)<>'1' THEN PERFORM set_config('probe.p290','N/A (sin paciente)',false);
  ELSE
    BEGIN
      INSERT INTO public.campana_vistas (campana_id, paciente_id, clickeado)
        VALUES (current_setting('probe.cm_camp',true)::int, current_setting('probe.cm_pac',true)::int, false);
      PERFORM set_config('probe.p290','OK (paciente registra su vista de anuncio)',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p290','REGRESIÓN (paciente no puede registrar vista: '||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P291 — NO-REGRESIÓN logging legítimo: registrar_campana_metrica (DEFINER) sigue insertando
-- pese al revoke del grant + drop de la policy (camino real del frontend). Llama como
-- authenticated; verifica la fila como owner (role none, bypassa RLS).
SELECT set_config('request.jwt.claims', json_build_object('sub',current_setting('probe.cm_med',true),'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  IF current_setting('probe.cm_ready',true)<>'1' THEN PERFORM set_config('probe.p291_called','0',false);
  ELSE
    BEGIN
      PERFORM public.registrar_campana_metrica(   -- overload de 8 args (p_pais_id) = el del frontend
        p_campana_id := current_setting('probe.cm_camp',true)::int,
        p_tipo_perfil := 'probe', p_sesion_id := 'probe-logging-291', p_clickeado := false,
        p_pais_id := NULL::uuid);
      PERFORM set_config('probe.p291_called','1',false);
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p291','REGRESIÓN (RPC logging falló: '||SQLERRM||')',false); PERFORM set_config('probe.p291_called','0',false); END;
  END IF;
END $$;
SELECT set_config('role','none',true);
DO $$ DECLARE n int; BEGIN
  IF current_setting('probe.cm_ready',true)<>'1' THEN PERFORM set_config('probe.p291','N/A',false);
  ELSIF current_setting('probe.p291_called',true)<>'1' THEN NULL;  -- ya marcado REGRESIÓN por el call
  ELSE SELECT count(*) INTO n FROM public.campana_metricas WHERE sesion_id='probe-logging-291';
    PERFORM set_config('probe.p291', CASE WHEN n>=1 THEN 'OK (logging legítimo vivo: RPC DEFINER insertó '||n||')' ELSE 'REGRESIÓN (RPC no insertó la métrica)' END, false);
  END IF;
END $$;
SELECT set_config('role','none',true);

-- ============================================================
-- Ola 2 · Endurecer search_path registrar_campana_metrica (P292–P294). Red-first.
-- ============================================================
-- P292 — estructural: AMBOS overloads fijan search_path '' (no null, no 'public')
DO $$ DECLARE n_ok int; n_tot int; BEGIN
  SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}'::text[])) e WHERE e LIKE 'search_path=%' AND e<>'search_path=public')),
         count(*)
    INTO n_ok, n_tot
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='registrar_campana_metrica';
  IF n_tot=2 AND n_ok=2 THEN PERFORM set_config('probe.p292','OK (ambos overloads fijan search_path vacío)',false);
  ELSE PERFORM set_config('probe.p292','ROJO (search_path sin endurecer: '||n_ok||'/'||n_tot||' overloads)',false); END IF;
END $$;
SELECT set_config('role','none',true);

-- P293 — HIJACK conductual: schema malicioso con campana_metricas falso prependido al path NO
-- redirige el INSERT del DEFINER. PRE 🔴 (la fila no llega a public; va al evil), POST OK (a public).
DO $$ DECLARE v_camp int; v_old text; n int; BEGIN
  v_old := current_setting('search_path');
  SELECT id INTO v_camp FROM public.campanas_publicitarias LIMIT 1;
  IF v_camp IS NULL THEN PERFORM set_config('probe.p293','N/A (sin campaña)',false); RETURN; END IF;
  DROP SCHEMA IF EXISTS probe_evil_m CASCADE;
  CREATE SCHEMA probe_evil_m;
  CREATE TABLE probe_evil_m.campana_metricas (
    campana_id int, perfil_id uuid, paciente_id int, tipo_perfil text, sesion_id text,
    clickeado boolean, contexto text, pais_id uuid);
  PERFORM set_config('search_path','probe_evil_m, public, private', true);
  PERFORM public.registrar_campana_metrica(
    p_campana_id := v_camp, p_tipo_perfil := 'probe', p_sesion_id := 'probe-hijack-293',
    p_clickeado := false, p_pais_id := NULL::uuid);
  PERFORM set_config('search_path', v_old, true);
  SELECT count(*) INTO n FROM public.campana_metricas WHERE sesion_id='probe-hijack-293';
  DROP SCHEMA IF EXISTS probe_evil_m CASCADE;
  IF n>=1 THEN PERFORM set_config('probe.p293','OK (INSERT a public.campana_metricas pese al schema malicioso)',false);
  ELSE PERFORM set_config('probe.p293','ROJO (hijack: INSERT redirigido al schema malicioso; tabla real no recibió)',false); END IF;
EXCEPTION WHEN others THEN
  PERFORM set_config('search_path', coalesce(v_old,'public, private'), true);
  PERFORM set_config('probe.p293','FALLO ('||SQLERRM||')',false);
END $$;
SELECT set_config('role','none',true);

-- (overload 7-arg de registrar_campana_metrica omitido de probes: shadoweado por el de 8-arg
--  — toda llamada con ≤7 args es ambigua porque p_pais_id tiene DEFAULT → inalcanzable vía
--  PostgREST/SQL. La equivalencia del camino VIVO (8-arg, el del frontend) la cubre P291.)

-- ============================================================
-- Ola 2 · CHECK de dominio solicitudes_campana.estado (P294–P298). Red-first.
-- Fixture: solicitud propia de af_emp (proveedor af_mkt con permiso publicidad), estado borrador.
-- ============================================================
SELECT set_config('role','none',true);
DO $$ DECLARE v_sol uuid; v_pais uuid; BEGIN
  IF NULLIF(current_setting('probe.af_emp',true),'')='' OR NULLIF(current_setting('probe.af_mkt',true),'')='' THEN
    PERFORM set_config('probe.sec_ready','0',false); PERFORM set_config('probe.sec_err','sin af_emp/af_mkt',false); RETURN; END IF;
  SELECT pais_id INTO v_pais FROM public.empresas_proveedoras WHERE id=current_setting('probe.af_emp',true)::uuid;
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado, pais_id)
    VALUES (current_setting('probe.af_emp',true)::uuid, current_setting('probe.af_mkt',true)::uuid, 'Probe estado-check', now(), now()+interval '7 days', 'borrador', v_pais)
    RETURNING id INTO v_sol;
  PERFORM set_config('probe.sec_sol', v_sol::text, false);
  PERFORM set_config('probe.sec_pais', v_pais::text, false);
  PERFORM set_config('probe.sec_ready','1',false);
EXCEPTION WHEN others THEN PERFORM set_config('probe.sec_ready','0',false); PERFORM set_config('probe.sec_err',SQLERRM,false); END $$;

-- P294 — NEG (red-first): INSERT con estado inválido (owner; aísla el CHECK de la RLS)
DO $$ DECLARE v_id uuid; BEGIN
  IF current_setting('probe.sec_ready',true)<>'1' THEN PERFORM set_config('probe.p294','N/A ('||coalesce(current_setting('probe.sec_err',true),'')||')',false);
  ELSE
    BEGIN
      INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado, pais_id)
        VALUES (current_setting('probe.af_emp',true)::uuid, current_setting('probe.af_mkt',true)::uuid, 'Probe estado INVALIDO', now(), now()+interval '7 days', 'xxx_invalido', current_setting('probe.sec_pais',true)::uuid)
        RETURNING id INTO v_id;
      PERFORM set_config('probe.p294','ROJO (aceptó estado inválido — sin CHECK)',false);
      DELETE FROM public.solicitudes_campana WHERE id = v_id;  -- limpiar artefacto (no contaminar P298)
    EXCEPTION WHEN check_violation THEN PERFORM set_config('probe.p294','BLOQUEADO (23514)',false);
             WHEN others THEN PERFORM set_config('probe.p294','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P295 — NEG (red-first): UPDATE de fila existente a estado inválido (owner)
DO $$ BEGIN
  IF current_setting('probe.sec_ready',true)<>'1' THEN PERFORM set_config('probe.p295','N/A',false);
  ELSE
    BEGIN
      UPDATE public.solicitudes_campana SET estado='zzz_invalido' WHERE id=current_setting('probe.sec_sol',true)::uuid;
      PERFORM set_config('probe.p295','ROJO (aceptó UPDATE a estado inválido — sin CHECK)',false);
    EXCEPTION WHEN check_violation THEN PERFORM set_config('probe.p295','BLOQUEADO (23514)',false);
             WHEN others THEN PERFORM set_config('probe.p295','BLOQUEADO ('||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P296 — POS (no-regresión): los 4 estados válidos siguen aceptados (owner UPDATE)
DO $$ DECLARE st text; v_ok int := 0; BEGIN
  IF current_setting('probe.sec_ready',true)<>'1' THEN PERFORM set_config('probe.p296','N/A',false);
  ELSE
    FOREACH st IN ARRAY ARRAY['borrador','enviada','publicada','rechazada'] LOOP
      BEGIN UPDATE public.solicitudes_campana SET estado=st WHERE id=current_setting('probe.sec_sol',true)::uuid; v_ok:=v_ok+1;
      EXCEPTION WHEN others THEN NULL; END;
    END LOOP;
    IF v_ok=4 THEN PERFORM set_config('probe.p296','OK (4/4 estados válidos aceptados)',false);
    ELSE PERFORM set_config('probe.p296','REGRESIÓN (solo '||v_ok||'/4 estados válidos aceptados)',false); END IF;
  END IF;
END $$;

-- P297 — GUARD authz (lección 10): proveedor NO puede UPDATE su solicitud a 'publicada' (RLS),
-- independiente del CHECK ('publicada' SÍ está en dominio, pero la RLS lo rechaza primero).
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt',true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ DECLARE v_n int; BEGIN
  IF current_setting('probe.sec_ready',true)<>'1' THEN PERFORM set_config('probe.p297','N/A',false);
  ELSE
    BEGIN
      UPDATE public.solicitudes_campana SET estado='publicada' WHERE id=current_setting('probe.sec_sol',true)::uuid;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n=0 THEN PERFORM set_config('probe.p297','BLOQUEADO (RLS: 0 filas — proveedor no auto-publica)',false);
      ELSE PERFORM set_config('probe.p297','PERMITIDO (proveedor auto-publicó '||v_n||' — lección 10 rota)',false); END IF;
    EXCEPTION WHEN others THEN PERFORM set_config('probe.p297','BLOQUEADO (RLS: '||SQLSTATE||')',false); END;
  END IF;
END $$;

-- P298 — estructural: cero filas fuera de dominio (cero breakage), pre y post
SELECT set_config('role','none',true);
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.solicitudes_campana WHERE estado NOT IN ('borrador','enviada','publicada','rechazada');
  PERFORM set_config('probe.p298', CASE WHEN n=0 THEN 'OK (0 filas fuera de dominio)' ELSE 'ROJO ('||n||' filas fuera de dominio — breakage)' END, false);
END $$;
SELECT set_config('role','none',true);

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
UNION ALL SELECT 'P24_proveedor_ve_cuenta_su_pais',     current_setting('probe.p24', true), 'OK (>0)'
UNION ALL SELECT 'P26_anon_lee_resultado_examen',       current_setting('probe.p26', true), 'BLOQUEADO'
UNION ALL SELECT 'P27_medico_ajeno_lee_resultado',      current_setting('probe.p27', true), 'BLOQUEADO'
UNION ALL SELECT 'P28_paciente_dueno_lee_resultado',    current_setting('probe.p28', true), 'OK (>0)'
UNION ALL SELECT 'P29_medico_orden_lee_resultado',      current_setting('probe.p29', true), 'OK (>0)'
UNION ALL SELECT 'P30_anon_lee_comprobante',            current_setting('probe.p30', true), 'BLOQUEADO'
UNION ALL SELECT 'P31_proveedor_ajeno_lee_comprobante', current_setting('probe.p31', true), 'BLOQUEADO'
UNION ALL SELECT 'P32_proveedor_dueno_lee_comprobante', current_setting('probe.p32', true), 'OK (>0)'
UNION ALL SELECT 'P33_proveedor_ajeno_escribe_comprob',  current_setting('probe.p33', true), 'BLOQUEADO'
UNION ALL SELECT 'P34_proveedor_dueno_escribe_comprob',  current_setting('probe.p34', true), 'OK'
UNION ALL SELECT 'P35_ajeno_escribe_resultado_lab',      current_setting('probe.p35', true), 'BLOQUEADO'
UNION ALL SELECT 'P36_lab_dueno_escribe_resultado',      current_setting('probe.p36', true), 'OK'
UNION ALL SELECT 'P37_anon_broadcast_promo',             current_setting('probe.p37', true), 'BLOQUEADO'
UNION ALL SELECT 'P38_medico_broadcast_promo',           current_setting('probe.p38', true), 'BLOQUEADO'
UNION ALL SELECT 'P39_superadmin_broadcast_promo',       current_setting('probe.p39', true), 'OK (>0)'
UNION ALL SELECT 'P40_medico_ajeno_notifica_paciente',   current_setting('probe.p40', true), 'BLOQUEADO'
UNION ALL SELECT 'P41_medico_atiende_notifica_paciente', current_setting('probe.p41', true), 'OK'
UNION ALL SELECT 'P42_ajeno_notifica_laboratorio',       current_setting('probe.p42', true), 'BLOQUEADO'
UNION ALL SELECT 'P43_medico_orden_notifica_lab',        current_setting('probe.p43', true), 'OK'
UNION ALL SELECT 'P44_ajeno_administra_visita',          current_setting('probe.p44', true), 'BLOQUEADO'
UNION ALL SELECT 'P45_proveedor_visita_administra',      current_setting('probe.p45', true), 'OK'
UNION ALL SELECT 'P46_staff_clinica_notifica_paciente',  current_setting('probe.p46', true), 'OK'
UNION ALL SELECT 'P47_superadmin_ve_admin_gated',        current_setting('probe.p47', true), 'OK'
UNION ALL SELECT 'P48_rol_fuera_catalogo_rechazado',     current_setting('probe.p48', true), 'BLOQUEADO'
UNION ALL SELECT 'P49_rol_valido_asignado',              current_setting('probe.p49', true), 'OK'
UNION ALL SELECT 'P50_superadmin_edita_farmacia',        current_setting('probe.p50', true), 'OK'
UNION ALL SELECT 'P51_medico_no_edita_farmacia',         current_setting('probe.p51', true), 'BLOQUEADO'
UNION ALL SELECT 'P52_superadmin_crea_reporte',          current_setting('probe.p52', true), 'OK'
UNION ALL SELECT 'P53_medico_no_crea_reporte',           current_setting('probe.p53', true), 'BLOQUEADO'
UNION ALL SELECT 'P54_superadmin_ve_reportes',           current_setting('probe.p54', true), 'OK'
UNION ALL SELECT 'P55_ajeno_ve_asignacion',             current_setting('probe.p55', true), 'BLOQUEADO'
UNION ALL SELECT 'P56_ajeno_actualiza_asignacion',      current_setting('probe.p56', true), 'BLOQUEADO'
UNION ALL SELECT 'P57_nosuper_inserta_campana',         current_setting('probe.p57', true), 'BLOQUEADO'
UNION ALL SELECT 'P58_nosuper_borra_campana',           current_setting('probe.p58', true), 'BLOQUEADO'
UNION ALL SELECT 'P59_tipo_fuera_catalogo',             current_setting('probe.p59', true), 'BLOQUEADO'
UNION ALL SELECT 'P60_proveedor_gestiona_su_asig',      current_setting('probe.p60', true), 'OK'
UNION ALL SELECT 'P61_medico_gestiona_su_asig',         current_setting('probe.p61', true), 'OK'
UNION ALL SELECT 'P62_superadmin_publica_rpc',          current_setting('probe.p62', true), 'OK'
UNION ALL SELECT 'P63_nosuper_no_aprueba_rpc',          current_setting('probe.p63', true), 'BLOQUEADO'
UNION ALL SELECT 'P64_medico_no_forja_empresa',         current_setting('probe.p64', true), 'BLOQUEADO'
UNION ALL SELECT 'P65_otro_tenant_gestiona_farmacia',         current_setting('probe.p65', true), 'BLOQUEADO'
UNION ALL SELECT 'P66_otro_tenant_edita_inventario',          current_setting('probe.p66', true), 'BLOQUEADO'
UNION ALL SELECT 'P67_nosuper_no_promueve',             current_setting('probe.p67', true), 'BLOQUEADO'
UNION ALL SELECT 'P68_superadmin_promueve',             current_setting('probe.p68', true), 'OK'
UNION ALL SELECT 'P69_dueno_gestiona_tenant',           current_setting('probe.p69', true), 'OK'
UNION ALL SELECT 'P70_medico_ve_catalogo',              current_setting('probe.p70', true), 'OK'
UNION ALL SELECT 'P71_reapropiacion_rechazada',         current_setting('probe.p71', true), 'BLOQUEADO'
UNION ALL SELECT 'P72_sinpermiso_no_edita_inventario',  current_setting('probe.p72', true), 'BLOQUEADO'
UNION ALL SELECT 'P73_sinpermiso_no_edita_datos',       current_setting('probe.p73', true), 'BLOQUEADO'
UNION ALL SELECT 'P74_inventario_edita_inventario',     current_setting('probe.p74', true), 'OK'
UNION ALL SELECT 'P75_inventario_no_edita_datos',       current_setting('probe.p75', true), 'BLOQUEADO'
UNION ALL SELECT 'P76_gerente_no_asigna_admin',         current_setting('probe.p76', true), 'BLOQUEADO'
UNION ALL SELECT 'P77_gerente_no_modifica_admin',       current_setting('probe.p77', true), 'BLOQUEADO'
UNION ALL SELECT 'P78_gerente_no_asigna_gerente',       current_setting('probe.p78', true), 'BLOQUEADO'
UNION ALL SELECT 'P79_operativo_no_asigna',             current_setting('probe.p79', true), 'BLOQUEADO'
UNION ALL SELECT 'P80_no_asigna_empresa_ajena',         current_setting('probe.p80', true), 'BLOQUEADO'
UNION ALL SELECT 'P81_admin_asigna_cualquiera',         current_setting('probe.p81', true), 'OK'
UNION ALL SELECT 'P82_gerente_asigna_operativo',        current_setting('probe.p82', true), 'OK'
UNION ALL SELECT 'P83_no_admin_update_directo_ajeno',   current_setting('probe.p83', true), 'BLOQUEADO'
UNION ALL SELECT 'P84_auto_ascenso_update_directo',     current_setting('probe.p84', true), 'BLOQUEADO'
UNION ALL SELECT 'P85_rpc_legado_farmacia_cerrado',     current_setting('probe.p85', true), 'BLOQUEADO'
UNION ALL SELECT 'P86_ultimo_admin_protegido',          current_setting('probe.p86', true), 'BLOQUEADO'
UNION ALL SELECT 'P87_alta_gerente_cajero',             current_setting('probe.p87', true), 'OK'
UNION ALL SELECT 'P88_alta_gerente_admin_bloqueada',    current_setting('probe.p88', true), 'BLOQUEADO'
UNION ALL SELECT 'P89_alta_empresa_ajena_bloqueada',    current_setting('probe.p89', true), 'BLOQUEADO'
UNION ALL SELECT 'P90_alta_rol_inexistente_bloqueada',  current_setting('probe.p90', true), 'BLOQUEADO'
UNION ALL SELECT 'P91_gerente_invita_admin',            current_setting('probe.p91', true), 'BLOQUEADO'
UNION ALL SELECT 'P92_gerente_invita_gerente',          current_setting('probe.p92', true), 'BLOQUEADO'
UNION ALL SELECT 'P93_operativo_invita',                current_setting('probe.p93', true), 'BLOQUEADO'
UNION ALL SELECT 'P94_invita_rol_inexistente',          current_setting('probe.p94', true), 'BLOQUEADO'
UNION ALL SELECT 'P95_gerente_invita_cajero',           current_setting('probe.p95', true), 'OK'
UNION ALL SELECT 'P96_insert_directo_invitacion',       current_setting('probe.p96', true), 'BLOQUEADO'
UNION ALL SELECT 'P97_consume_rol_fijado',              current_setting('probe.p97', true), 'OK'
UNION ALL SELECT 'P98_reconsume_token_usado',           current_setting('probe.p98', true), 'BLOQUEADO'
UNION ALL SELECT 'P99_consume_token_expirado',          current_setting('probe.p99', true), 'BLOQUEADO'
UNION ALL SELECT 'P100_consume_email_distinto',         current_setting('probe.p100', true), 'BLOQUEADO'
UNION ALL SELECT 'P101_consume_visitador_lab_e2e',      current_setting('probe.p101', true), 'OK'
UNION ALL SELECT 'P102_camino_viejo_cerrado',           current_setting('probe.p102', true), 'BLOQUEADO'
UNION ALL SELECT 'P110_miembro_ve_su_equipo',           current_setting('probe.p110', true), 'OK'
UNION ALL SELECT 'P111_ajeno_no_ve_personal',           current_setting('probe.p111', true), 'BLOQUEADO'
UNION ALL SELECT 'P112_miembroA_no_ve_clinicaB',        current_setting('probe.p112', true), 'BLOQUEADO'
UNION ALL SELECT 'P113_personal_clinica_null',          current_setting('probe.p113', true), 'BLOQUEADO'
UNION ALL SELECT 'P114_medico_no_ve_producto_afin',     current_setting('probe.p114', true), 'OCULTO (0)'
UNION ALL SELECT 'P115_afin_ve_sus_productos',          current_setting('probe.p115', true), 'OK'
UNION ALL SELECT 'P116_marketing_crea_campana',         current_setting('probe.p116', true), 'OK'
UNION ALL SELECT 'P117_lectura_no_crea_campana',        current_setting('probe.p117', true), 'BLOQUEADO'
UNION ALL SELECT 'P118_admin_afin_alta_marketing',      current_setting('probe.p118', true), 'OK'
UNION ALL SELECT 'P119_gerente_afin_no_alta_admin',     current_setting('probe.p119', true), 'BLOQUEADO'
UNION ALL SELECT 'P120_rpc_legado_afin_cerrado',        current_setting('probe.p120', true), 'BLOQUEADO'
UNION ALL SELECT 'P121_gerente_afin_edita_productos',   current_setting('probe.p121', true), 'OK'
UNION ALL SELECT 'P122_afin_no_autoaprueba_publicidad', current_setting('probe.p122', true), 'BLOQUEADO'
UNION ALL SELECT 'P123_afin_edita_contenido_solicitud', current_setting('probe.p123', true), 'OK'
UNION ALL SELECT 'P124_afin_no_insert_empresa_ajena',   current_setting('probe.p124', true), 'BLOQUEADO'
UNION ALL SELECT 'P125_afin_solicitud_no_nace_publicada',current_setting('probe.p125', true), 'BLOQUEADO'
UNION ALL SELECT 'P126_afin_no_update_solicitud_ajena',  current_setting('probe.p126', true), 'BLOQUEADO'
UNION ALL SELECT 'P127_afinA_no_ve_productos_afinB',     current_setting('probe.p127', true), 'OCULTO (0)'
UNION ALL SELECT 'P128_afinA_no_edita_productos_afinB',  current_setting('probe.p128', true), 'BLOQUEADO'
UNION ALL SELECT 'P129_afinA_no_ve_solicitudes_afinB',   current_setting('probe.p129', true), 'OCULTO (0)'
UNION ALL SELECT 'P130_gerente_afin_no_asigna_admin',    current_setting('probe.p130', true), 'BLOQUEADO'
UNION ALL SELECT 'P131_adminA_no_toca_miembro_afinB',    current_setting('probe.p131', true), 'BLOQUEADO'
UNION ALL SELECT 'P132_afin_ultimo_admin_protegido',     current_setting('probe.p132', true), 'BLOQUEADO'
UNION ALL SELECT 'P133_afin_no_ve_lab_visitador',        current_setting('probe.p133', true), 'OCULTO (0)'
UNION ALL SELECT 'P134_medico_sigue_viendo_no_afin',     current_setting('probe.p134', true), 'OK'
UNION ALL SELECT 'P135_despacho_sin_permiso',            current_setting('probe.p135', true), 'BLOQUEADO'
UNION ALL SELECT 'P136_token_viejo_no_resuelve',         current_setting('probe.p136', true), 'BLOQUEADO'
UNION ALL SELECT 'P137_verificar_cross_farmacia',        current_setting('probe.p137', true), 'BLOQUEADO'
UNION ALL SELECT 'P138_despacho_rol_correcto_OK',        current_setting('probe.p138', true), 'OK'
UNION ALL SELECT 'P139_registrar_sin_permiso',           current_setting('probe.p139', true), 'BLOQUEADO'
UNION ALL SELECT 'P140_registrar_cross_farmacia',        current_setting('probe.p140', true), 'BLOQUEADO'
UNION ALL SELECT 'P141_re_despacho',                     current_setting('probe.p141', true), 'BLOQUEADO'
UNION ALL SELECT 'P142_medico_paciente_no_despacha',     current_setting('probe.p142', true), 'BLOQUEADO'
UNION ALL SELECT 'P143_token_null',                      current_setting('probe.p143', true), 'BLOQUEADO'
UNION ALL SELECT 'P144_phi_minima_sin_telefono',         current_setting('probe.p144', true), 'OK'
UNION ALL SELECT 'P145_token_expirado',                  current_setting('probe.p145', true), 'BLOQUEADO'
UNION ALL SELECT 'P146_aislamiento_por_item',            current_setting('probe.p146', true), 'OK'
UNION ALL SELECT 'P147_binding_token_receta',            current_setting('probe.p147', true), 'BLOQUEADO'
UNION ALL SELECT 'P148_array_mixto_solo_propio',         current_setting('probe.p148', true), 'OK'
UNION ALL SELECT 'P149_cat_sin_inventario_editar',       current_setting('probe.p149', true), 'BLOQUEADO'
UNION ALL SELECT 'P150_cat_escribe_ajeno',               current_setting('probe.p150', true), 'BLOQUEADO'
UNION ALL SELECT 'P151_cat_farmacia_lee_ajeno',          current_setting('probe.p151', true), 'OCULTO (0)'
UNION ALL SELECT 'P152_cat_medico_disponibilidad',       current_setting('probe.p152', true), 'OK'
UNION ALL SELECT 'P153_rpc_carga_sin_permiso',           current_setting('probe.p153', true), 'BLOQUEADO'
UNION ALL SELECT 'P154_rpc_carga_farmacia_ajena',        current_setting('probe.p154', true), 'BLOQUEADO'
UNION ALL SELECT 'P155_rpc_idempotente',                 current_setting('probe.p155', true), 'OK'
UNION ALL SELECT 'P156_rpc_reporte_por_fila',            current_setting('probe.p156', true), 'OK'
UNION ALL SELECT 'P157_rpc_stock_vacio_conserva',        current_setting('probe.p157', true), 'OK'
UNION ALL SELECT 'P158_rpc_carga_ok',                    current_setting('probe.p158', true), 'OK'
UNION ALL SELECT 'P159_anon_no_lee_catalogo',            current_setting('probe.p159', true), 'OCULTO (0)'
UNION ALL SELECT 'P160_clinico_no_medico_disponibilidad',current_setting('probe.p160', true), 'OK'
UNION ALL SELECT 'P161_rpc_dup_intra_archivo',           current_setting('probe.p161', true), 'OK'
UNION ALL SELECT 'P162_norm_500mg_eq_500MG',             current_setting('probe.p162', true), 'OK'
UNION ALL SELECT 'P163_bandeja_aislamiento',             current_setting('probe.p163', true), 'OK'
UNION ALL SELECT 'P164_listar_sin_permiso',              current_setting('probe.p164', true), 'BLOQUEADO'
UNION ALL SELECT 'P165_listar_anon',                     current_setting('probe.p165', true), 'BLOQUEADO'
UNION ALL SELECT 'P166_despacho_mixto_reduce',           current_setting('probe.p166', true), 'OK'
UNION ALL SELECT 'P167_redespacho_noop',                 current_setting('probe.p167', true), 'BLOQUEADO'
UNION ALL SELECT 'P168_phi_minima',                      current_setting('probe.p168', true), 'OK'
UNION ALL SELECT 'P169_despacho_dirigido_efectos',       current_setting('probe.p169', true), 'OK'
UNION ALL SELECT 'P170_lectura_directa_tabla_oculta',    current_setting('probe.p170', true), 'OCULTO'
UNION ALL SELECT 'P171_farmaceutico_requerido',          current_setting('probe.p171', true), 'BLOQUEADO'
UNION ALL SELECT 'P172_edge_sin_recetas_avanzadas',      current_setting('probe.p172', true), 'BLOQUEADO'
UNION ALL SELECT 'P173_auditoria_despachado_por',        current_setting('probe.p173', true), 'OK'
UNION ALL SELECT 'P174_token_no_filtrado',               current_setting('probe.p174', true), 'OK'
UNION ALL SELECT 'P175_C1_crear_sucursal_pos',           current_setting('probe.p175', true), 'OK'
UNION ALL SELECT 'P176_C1_crear_sin_permiso',            current_setting('probe.p176', true), 'BLOQUEADO'
UNION ALL SELECT 'P177_C1_empresa_forzada',              current_setting('probe.p177', true), 'OK'
UNION ALL SELECT 'P178_C1_mi_sucursal_null',             current_setting('probe.p178', true), 'OK'
UNION ALL SELECT 'P179_C1_no_proveedor_bloqueado',       current_setting('probe.p179', true), 'BLOQUEADO'
UNION ALL SELECT 'P180_C1_borrar_sucursal_scoped_restrict', current_setting('probe.p180', true), 'BLOQUEADO'
UNION ALL SELECT 'P181_S_finanzas_pos',                   current_setting('probe.p181', true), 'OK'
UNION ALL SELECT 'P182_S_recetas_pos',                    current_setting('probe.p182', true), 'OK'
UNION ALL SELECT 'P183_S_finanzas_sin_permiso',           current_setting('probe.p183', true), 'BLOQUEADO'
UNION ALL SELECT 'P184_S_recetas_separacion',             current_setting('probe.p184', true), 'BLOQUEADO'
UNION ALL SELECT 'P185_S_anon',                           current_setting('probe.p185', true), 'BLOQUEADO'
UNION ALL SELECT 'P186_S_empresa_isolation',              current_setting('probe.p186', true), 'OK'
UNION ALL SELECT 'P187_S_phi_minima',                     current_setting('probe.p187', true), 'OK'
UNION ALL SELECT 'P188_S_finanzas_sin_medicamento',       current_setting('probe.p188', true), 'OK'
UNION ALL SELECT 'P189_S_celdas_pequenas',                current_setting('probe.p189', true), 'OK'
UNION ALL SELECT 'P190_S_sucursal_aware',                 current_setting('probe.p190', true), 'OK'
UNION ALL SELECT 'P191_pais0_helper_pos_GT',             current_setting('probe.p191', true), 'OK'
UNION ALL SELECT 'P192_pais0_helper_neg_HN',             current_setting('probe.p192', true), 'OK'
UNION ALL SELECT 'P193_pais0_failclosed_paisnull',       current_setting('probe.p193', true), 'OK'
UNION ALL SELECT 'P194_pais0_pid_null',                  current_setting('probe.p194', true), 'OK'
UNION ALL SELECT 'P195_prodemp_neg_HN',                  current_setting('probe.p195', true), 'OK post-094 (ROJO pre)'
UNION ALL SELECT 'P196_prodemp_pos_GT',                  current_setting('probe.p196', true), 'OK'
UNION ALL SELECT 'P197_prodemp_failclosed',              current_setting('probe.p197', true), 'OK post-094 (ROJO pre)'
UNION ALL SELECT 'P198_prodemp_backfill',                current_setting('probe.p198', true), 'OK post-094 (ROJO pre)'
UNION ALL SELECT 'P203_prodemp_trigger_reasigna',        current_setting('probe.p203', true), 'OK post-094 (ROJO pre)'
UNION ALL SELECT 'P199_G1_helper_opera',                 current_setting('probe.p199', true), 'OK post-095'
UNION ALL SELECT 'P200_G1_proveedor_bloq',               current_setting('probe.p200', true), 'BLOQUEADO post-095'
UNION ALL SELECT 'P201_G1_superadmin',                   current_setting('probe.p201', true), 'OK post-095'
UNION ALL SELECT 'P202_G1_restrict_pais',                current_setting('probe.p202', true), 'BLOQUEADO post-095'
UNION ALL SELECT 'P204_farmed_medico_neg_HN',           current_setting('probe.p204', true), 'OK post-096 (ROJO pre)'
UNION ALL SELECT 'P205_farmed_medico_pos_GT',           current_setting('probe.p205', true), 'OK'
UNION ALL SELECT 'P206_farmed_clinico_neg_HN',          current_setting('probe.p206', true), 'OK post-096 (ROJO pre)'
UNION ALL SELECT 'P207_farmed_clinico_pos_GT',          current_setting('probe.p207', true), 'OK'
UNION ALL SELECT 'P208_farmed_failclosed',              current_setting('probe.p208', true), 'OK post-096 (ROJO pre)'
UNION ALL SELECT 'P209_farmed_proveedor_anon',          current_setting('probe.p209', true), 'OK'
UNION ALL SELECT 'P210_examenes_medico_neg_HN',         current_setting('probe.p210', true), 'OK post-097 (ROJO pre)'
UNION ALL SELECT 'P211_examenes_medico_pos_GT',         current_setting('probe.p211', true), 'OK'
UNION ALL SELECT 'P212_examenes_failclosed',            current_setting('probe.p212', true), 'OK post-097 (ROJO pre)'
UNION ALL SELECT 'P213_rpc_labs_medico_GT',             current_setting('probe.p213', true), 'OK'
UNION ALL SELECT 'P214_rpc_labs_failclosed',            current_setting('probe.p214', true), 'OK post-097 (ROJO pre)'
UNION ALL SELECT 'P215_examenes_anon',                  current_setting('probe.p215', true), 'OK post-097'
UNION ALL SELECT 'P216_farmacias_prov_cross_empresa',   current_setting('probe.p216', true), 'OK post-098 (ROJO pre)'
UNION ALL SELECT 'P217_farmacias_prov_pos',             current_setting('probe.p217', true), 'OK'
UNION ALL SELECT 'P218_farmacias_medico_neg_HN',        current_setting('probe.p218', true), 'OK post-098 (ROJO pre)'
UNION ALL SELECT 'P219_farmacias_medico_pos_GT',        current_setting('probe.p219', true), 'OK'
UNION ALL SELECT 'P220_farmacias_clinico_neg_HN',       current_setting('probe.p220', true), 'OK post-098 (ROJO pre)'
UNION ALL SELECT 'P221_farmacias_failclosed',           current_setting('probe.p221', true), 'OK post-098 (ROJO pre)'
UNION ALL SELECT 'P222_farmacias_anon',                 current_setting('probe.p222', true), 'OK post-098 (ROJO pre)'
UNION ALL SELECT 'P223_farmacias_superadmin_all',       current_setting('probe.p223', true), 'OK'
UNION ALL SELECT 'P224_puba_crea_pais_no_operado',      current_setting('probe.p224', true), 'BLOQUEADO post-099 (ROJO pre)'
UNION ALL SELECT 'P225_puba_crea_pais_operado',         current_setting('probe.p225', true), 'OK'
UNION ALL SELECT 'P226_puba_aprobar_no_operado',        current_setting('probe.p226', true), 'BLOQUEADO post-099 (ROJO pre)'
UNION ALL SELECT 'P227_puba_backfill_notnull',          current_setting('probe.p227', true), 'OK post-099 (ROJO pre)'
UNION ALL SELECT 'P228_puba_antiescalada_empresa',      current_setting('probe.p228', true), 'BLOQUEADO'
UNION ALL SELECT 'P229_pubb_medico_ve_GT',              current_setting('probe.p229', true), 'OK post-100 (ROJO pre)'
UNION ALL SELECT 'P230_pubb_clinica_ve_GT',             current_setting('probe.p230', true), 'OK post-100 (ROJO pre)'
UNION ALL SELECT 'P231_pubb_medico_no_HN',              current_setting('probe.p231', true), 'OK'
UNION ALL SELECT 'P232_pubb_paciente_ve_GT',            current_setting('probe.p232', true), 'OK'
UNION ALL SELECT 'P233_pubb_paciente_no_HN',            current_setting('probe.p233', true), 'OK'
UNION ALL SELECT 'P234_pubb_vigencia_inicio_futuro',    current_setting('probe.p234', true), 'OK post-100 (ROJO pre)'
UNION ALL SELECT 'P235_pubb_failclosed',                current_setting('probe.p235', true), 'OK'
UNION ALL SELECT 'P236_pubb_anon',                      current_setting('probe.p236', true), 'OK'
UNION ALL SELECT 'P237_vg3_estructura_fk',              current_setting('probe.p237', true), 'OK post-101'
UNION ALL SELECT 'P238_vg3_fk_pais_inexistente',        current_setting('probe.p238', true), 'BLOQUEADO post-101'
UNION ALL SELECT 'P239_vg3_pais_valido',                current_setting('probe.p239', true), 'OK post-101'
UNION ALL SELECT 'P240_vg3_restrict_pais',              current_setting('probe.p240', true), 'BLOQUEADO post-101'
UNION ALL SELECT 'P241_visa_plan_pais_no_operado',      current_setting('probe.p241', true), 'BLOQUEADO post-102 (ROJO pre)'
UNION ALL SELECT 'P242_visa_plan_pais_operado',         current_setting('probe.p242', true), 'OK post-102'
UNION ALL SELECT 'P243_visa_pais_null',                 current_setting('probe.p243', true), 'BLOQUEADO post-102 (ROJO pre)'
UNION ALL SELECT 'P244_visa_proveedor_no_crea',         current_setting('probe.p244', true), 'BLOQUEADO'
UNION ALL SELECT 'P245_visa_antiescalada_empresa',      current_setting('probe.p245', true), 'BLOQUEADO'
UNION ALL SELECT 'P246_vg1_sin_plan',                   current_setting('probe.p246', true), 'OK post-103 (ROJO pre)'
UNION ALL SELECT 'P247_vg1_plan_GT_medico_HN',          current_setting('probe.p247', true), 'OK'
UNION ALL SELECT 'P248_vg1_no_ve_paciente',             current_setting('probe.p248', true), 'OK post-103 (ROJO pre)'
UNION ALL SELECT 'P249_vg1_plan_vencido',               current_setting('probe.p249', true), 'OK post-103 (ROJO pre)'
UNION ALL SELECT 'P250_vg1_plan_activo_pos',            current_setting('probe.p250', true), 'OK'
UNION ALL SELECT 'P251_vg1_failclosed_noproveedor',     current_setting('probe.p251', true), 'OK'
UNION ALL SELECT 'P252_vg1_paciente_agenda',            current_setting('probe.p252', true), 'OK'
UNION ALL SELECT 'P253_vg1_medico_propia',              current_setting('probe.p253', true), 'OK'
UNION ALL SELECT 'P254_vg2_sin_plan',                   current_setting('probe.p254', true), 'BLOQUEADO post-104 (ROJO pre)'
UNION ALL SELECT 'P255_vg2_plan_pos',                   current_setting('probe.p255', true), 'OK post-104'
UNION ALL SELECT 'P256_vg2_medico_otro_pais',           current_setting('probe.p256', true), 'BLOQUEADO post-104 (ROJO pre)'
UNION ALL SELECT 'P257_vg2_plan_vencido',               current_setting('probe.p257', true), 'BLOQUEADO post-104 (ROJO pre)'
UNION ALL SELECT 'P258_vg2_retargeting',                current_setting('probe.p258', true), 'BLOQUEADO post-104 (ROJO pre)'
UNION ALL SELECT 'P259_vg2_medico_estado_noregresion',  current_setting('probe.p259', true), 'OK'
UNION ALL SELECT 'P260_vg2_cuota_intacta',              current_setting('probe.p260', true), 'OK'
UNION ALL SELECT 'P261_searchpath_hijack_obtener_clinica', current_setting('probe.p261', true), 'OK post-105 (ROJO pre)'
UNION ALL SELECT 'P262_searchpath_estructural',          current_setting('probe.p262', true), 'OK post-105 (ROJO pre)'
UNION ALL SELECT 'P263_citas_paciente_no_ve_otro_pais',  current_setting('probe.p263', true), 'OK post-106 (ROJO pre)'
UNION ALL SELECT 'P264_citas_paciente_ve_su_pais',       current_setting('probe.p264', true), 'OK'
UNION ALL SELECT 'P265_citas_paciente_no_agenda_otro_pais', current_setting('probe.p265', true), 'BLOQUEADO post-106 (ROJO pre)'
UNION ALL SELECT 'P266_citas_pais_derivado_medico',      current_setting('probe.p266', true), 'OK post-106 (ROJO pre)'
UNION ALL SELECT 'P267_citas_insert_directo_denegado',   current_setting('probe.p267', true), 'BLOQUEADO (invariante chokepoint)'
UNION ALL SELECT 'P268_mi_clinica_medico_searchpath',    current_setting('probe.p268', true), 'OK post-107 (ROJO pre)'
UNION ALL SELECT 'P269_adminclin_historial',            current_setting('probe.p269', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P270_adminclin_recetas',              current_setting('probe.p270', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P271_adminclin_recetas_avanzadas',    current_setting('probe.p271', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P272_adminclin_receta_items',         current_setting('probe.p272', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P273_adminclin_expediente_notas',     current_setting('probe.p273', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P274_adminclin_signos_vitales',       current_setting('probe.p274', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P275_adminclin_examenes',             current_setting('probe.p275', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P276_adminclin_pacientes',            current_setting('probe.p276', true), 'OK post-108 (ROJO pre)'
UNION ALL SELECT 'P277_guard_cross_clinica',            current_setting('probe.p277', true), 'OK (guard: 0 pre y post)'
UNION ALL SELECT 'P278_antiORtrap_medico_colega',       current_setting('probe.p278', true), 'OK (guard anti-OR-trap)'
UNION ALL SELECT 'P279_noregresion_paciente',           current_setting('probe.p279', true), 'OK'
UNION ALL SELECT 'P280_noregresion_citas_admin',        current_setting('probe.p280', true), 'OK'
UNION ALL SELECT 'P281_anon_cerrado_phi',               current_setting('probe.p281', true), 'OK'
UNION ALL SELECT 'P282_guard_divergencia_idspace',      current_setting('probe.p282', true), 'OK (guard: 0 pre y post)'
UNION ALL SELECT 'P283_anon_no_ve_resumen',             current_setting('probe.p283', true), 'OK post-109 (ROJO pre)'
UNION ALL SELECT 'P284_anon_no_ve_pais',                current_setting('probe.p284', true), 'OK post-109 (ROJO pre)'
UNION ALL SELECT 'P285_noadmin_no_ve_resumen',          current_setting('probe.p285', true), 'OK post-109 (ROJO pre)'
UNION ALL SELECT 'P286_noadmin_no_ve_metricas_pais',    current_setting('probe.p286', true), 'OK post-109 (ROJO pre)'
UNION ALL SELECT 'P287_noregresion_superadmin',         current_setting('probe.p287', true), 'OK (no-regresión crítica)'
UNION ALL SELECT 'P288_noadmin_tabla_base_0',           current_setting('probe.p288', true), 'OK'
UNION ALL SELECT 'P289_writeleak_authenticated',        current_setting('probe.p289', true), 'BLOQUEADO post-109 (ROJO pre)'
UNION ALL SELECT 'P290_noregresion_paciente_vistas',    current_setting('probe.p290', true), 'OK'
UNION ALL SELECT 'P291_logging_legitimo_rpc_definer',   current_setting('probe.p291', true), 'OK (no-regresión logging)'
UNION ALL SELECT 'P292_searchpath_metricas_estructural', current_setting('probe.p292', true), 'OK post-110 (ROJO pre)'
UNION ALL SELECT 'P293_searchpath_metricas_hijack',     current_setting('probe.p293', true), 'OK post-110 (ROJO pre)'
UNION ALL SELECT 'P294_estado_insert_invalido',         current_setting('probe.p294', true), 'BLOQUEADO post-111 (ROJO pre)'
UNION ALL SELECT 'P295_estado_update_invalido',         current_setting('probe.p295', true), 'BLOQUEADO post-111 (ROJO pre)'
UNION ALL SELECT 'P296_estados_validos_noregresion',    current_setting('probe.p296', true), 'OK'
UNION ALL SELECT 'P297_leccion10_proveedor_no_publica', current_setting('probe.p297', true), 'BLOQUEADO (guard authz, RLS)'
UNION ALL SELECT 'P298_cero_filas_fuera_dominio',       current_setting('probe.p298', true), 'OK (cero breakage)';

ROLLBACK;  -- nada de lo anterior se persiste
