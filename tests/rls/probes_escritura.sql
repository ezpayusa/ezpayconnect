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

-- P70 — POS: la búsqueda pública del médico sigue viendo el catálogo/inventario
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('probe.np_medico', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ DECLARE n INT; BEGIN
  SELECT count(*) INTO n FROM public.farmacia_medicamentos WHERE farmacia_id = current_setting('probe.farm', true)::int;
  IF n > 0 THEN PERFORM set_config('probe.p70','OK (médico ve inventario: '||n||')',false);
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
    INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado)
      VALUES (current_setting('probe.af_emp_b',true)::uuid, current_setting('probe.af_b_member',true)::uuid, 'Solic Afin B', now(), now()+interval '7 days', 'borrador')
      RETURNING id INTO v_id;
    PERFORM set_config('probe.af_b_solic', v_id::text, false);
  END IF;
END $$;
-- solicitud PROPIA de afín A (de af_mkt) para tests de auto-aprobación/edición de contenido
DO $$ DECLARE v_id uuid; BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado)
    VALUES (current_setting('probe.af_emp',true)::uuid, current_setting('probe.af_mkt',true)::uuid, 'Solic Afin A', now(), now()+interval '7 days', 'borrador')
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
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin)
    VALUES (NULLIF(current_setting('probe.af_emp',true),'')::uuid, NULLIF(current_setting('probe.af_mkt',true),'')::uuid,
            'Probe Campaña Afín', now(), now() + interval '7 days');
  PERFORM set_config('probe.p116','OK (marketing creó campaña)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p116','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p116','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P117 — NEG: el rol LECTURA del afín NO crea campañas
SELECT set_config('role', 'none', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_lectura', true), 'role','authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
DO $$ BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin)
    VALUES (NULLIF(current_setting('probe.af_emp',true),'')::uuid, NULLIF(current_setting('probe.af_lectura',true),'')::uuid,
            'Probe Campaña Lectura', now(), now() + interval '7 days');
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
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin)
    VALUES (NULLIF(current_setting('probe.af_emp_b',true),'')::uuid, NULLIF(current_setting('probe.af_mkt',true),'')::uuid, 'Cross empresa', now(), now()+interval '7 days');
  PERFORM set_config('probe.p124','PERMITIDO (insertó en empresa ajena!)',false);
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.p124','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.p124','BLOQUEADO ('||SQLSTATE||')',false);
END $$;

-- P125 — NEG: marketing del afín INSERT solicitud PROPIA que NACE 'publicada' → BLOQUEADO
SELECT set_config('role','none',true);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('probe.af_mkt', true), 'role','authenticated')::text, true);
SELECT set_config('role','authenticated',true);
DO $$ BEGIN
  INSERT INTO public.solicitudes_campana (empresa_id, cuenta_proveedor_id, titulo, fecha_inicio, fecha_fin, estado)
    VALUES (NULLIF(current_setting('probe.af_emp',true),'')::uuid, NULLIF(current_setting('probe.af_mkt',true),'')::uuid, 'Nace publicada', now(), now()+interval '7 days', 'publicada');
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
UNION ALL SELECT 'P148_array_mixto_solo_propio',         current_setting('probe.p148', true), 'OK';

ROLLBACK;  -- nada de lo anterior se persiste
