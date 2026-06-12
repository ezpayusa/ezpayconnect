-- ============================================================
-- Fixture QA reutilizable (datos ficticios) — paciente con cita + receta + items
-- ------------------------------------------------------------
-- Sirve para validar P14 (el paciente ve los items de SUS recetas) y, en
-- general, para tener un paciente registrado (auth_user_id) con PHI propio.
-- Idempotente: se puede correr varias veces sin duplicar.
--   Paciente: pacientes.auth_user_id = 'ad81ba6f-...' (paciente.qa), id=13.
--   Marca: motivo/diagnostico = 'QA_FIXTURE_P14'.
-- Correr: npx supabase db query --linked -f tests/rls/fixtures/qa_paciente_recetas.sql
-- ============================================================
DO $$
DECLARE
  v_pac    BIGINT := (SELECT id FROM public.pacientes
                      WHERE auth_user_id = 'ad81ba6f-e350-4660-8f80-02342bbb3747' ORDER BY id LIMIT 1);
  v_med    UUID   := (SELECT id FROM public.perfiles WHERE rol='medico' ORDER BY id LIMIT 1);
  v_receta BIGINT;
BEGIN
  IF v_pac IS NULL OR v_med IS NULL THEN
    RAISE NOTICE 'Fixture P14: falta paciente.qa o un médico; no se sembró.';
    RETURN;
  END IF;

  -- Cita (para que el médico "atienda por cita" al paciente). Best-effort:
  -- si choca con algún índice de agenda, no aborta el resto del fixture.
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.citas
                   WHERE paciente_id=v_pac AND medico_id=v_med AND motivo='QA_FIXTURE_P14') THEN
      INSERT INTO public.citas (medico_id, paciente_id, fecha, hora_inicio, hora_fin, estado, motivo)
      VALUES (v_med, v_pac, CURRENT_DATE, '07:30', '07:45', 'confirmada', 'QA_FIXTURE_P14');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Fixture P14: cita no sembrada (%); se continúa con receta/items.', SQLERRM;
  END;

  -- Receta marcada
  SELECT id INTO v_receta FROM public.recetas
   WHERE paciente_id=v_pac AND diagnostico='QA_FIXTURE_P14' ORDER BY id LIMIT 1;
  IF v_receta IS NULL THEN
    INSERT INTO public.recetas (medico_id, paciente_id, diagnostico)
    VALUES (v_med, v_pac, 'QA_FIXTURE_P14')
    RETURNING id INTO v_receta;
  END IF;

  -- Items de la receta
  IF NOT EXISTS (SELECT 1 FROM public.receta_items WHERE receta_id=v_receta) THEN
    INSERT INTO public.receta_items (receta_id, nombre_medicamento, dosis, frecuencia) VALUES
      (v_receta, 'Amoxicilina 500mg', '1 tableta', 'cada 8h'),
      (v_receta, 'Ibuprofeno 400mg',  '1 tableta', 'cada 12h');
  END IF;

  RAISE NOTICE 'Fixture P14 listo: paciente=% receta=%', v_pac, v_receta;
END $$;
