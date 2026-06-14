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
UNION ALL SELECT 'P64_medico_no_forja_empresa',         current_setting('probe.p64', true), 'BLOQUEADO';

ROLLBACK;  -- nada de lo anterior se persiste
