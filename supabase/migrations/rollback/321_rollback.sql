-- ############################################################################################
-- ROLLBACK de la mig 321 - restaura las 2 policies ALL originales del medico
-- ############################################################################################
-- Estado original (snapshot del recon, pg_policies):
--   examenes :: "Medico ve examenes de sus pacientes" : ALL, roles=public, USING (medico_id = auth.uid()), sin WITH CHECK
--   ordenes_examen :: ordenes_medico_all              : ALL, roles=public, USING/WITH CHECK (medico_id = auth.uid())
-- Este rollback dropea las 8 policies nuevas y recrea esas 2.
-- ############################################################################################

DROP POLICY IF EXISTS examenes_medico_select ON public.examenes;
DROP POLICY IF EXISTS examenes_medico_insert ON public.examenes;
DROP POLICY IF EXISTS examenes_medico_update ON public.examenes;
DROP POLICY IF EXISTS examenes_medico_delete ON public.examenes;
DROP POLICY IF EXISTS ordenes_medico_select ON public.ordenes_examen;
DROP POLICY IF EXISTS ordenes_medico_insert ON public.ordenes_examen;
DROP POLICY IF EXISTS ordenes_medico_update ON public.ordenes_examen;
DROP POLICY IF EXISTS ordenes_medico_delete ON public.ordenes_examen;

DROP POLICY IF EXISTS "Medico ve examenes de sus pacientes" ON public.examenes;
CREATE POLICY "Medico ve examenes de sus pacientes" ON public.examenes
  FOR ALL TO public
  USING (medico_id = auth.uid());

DROP POLICY IF EXISTS ordenes_medico_all ON public.ordenes_examen;
CREATE POLICY ordenes_medico_all ON public.ordenes_examen
  FOR ALL TO public
  USING (medico_id = auth.uid())
  WITH CHECK (medico_id = auth.uid());

-- ============================================================================================
-- AUTOCHEQUEO del rollback: estado original exacto
-- ============================================================================================
DO $ac$
DECLARE
  v_ex text; v_or text; v_cmd text; v_q text; v_c text; v_roles text;
BEGIN
  -- sets originales
  SELECT string_agg(policyname, ',' ORDER BY policyname) INTO v_ex
    FROM pg_policies WHERE schemaname='public' AND tablename='examenes';
  IF v_ex <> 'Admin clinica ve examenes de su clinica,Medico ve examenes de sus pacientes,Paciente ve sus examenes,examenes_laboratorio_all,examenes_superadmin_all' THEN
    RAISE EXCEPTION 'ROLLBACK321: set examenes inesperado: %', v_ex;
  END IF;
  SELECT string_agg(policyname, ',' ORDER BY policyname) INTO v_or
    FROM pg_policies WHERE schemaname='public' AND tablename='ordenes_examen';
  IF v_or <> 'ordenes_lab_all,ordenes_medico_all' THEN
    RAISE EXCEPTION 'ROLLBACK321: set ordenes inesperado: %', v_or;
  END IF;

  -- "Medico ve examenes de sus pacientes": ALL, public, USING (medico_id = auth.uid()), CHECK null
  SELECT cmd, qual, with_check, array_to_string(roles,',') INTO v_cmd, v_q, v_c, v_roles
    FROM pg_policies WHERE schemaname='public' AND tablename='examenes' AND policyname='Medico ve examenes de sus pacientes';
  IF v_cmd <> 'ALL' OR v_roles <> 'public' OR v_q IS DISTINCT FROM '(medico_id = auth.uid())' OR v_c IS DISTINCT FROM NULL THEN
    RAISE EXCEPTION 'ROLLBACK321: examenes medico no restaurada: cmd=% roles=% q=[%] c=[%]', v_cmd, v_roles, v_q, v_c;
  END IF;

  -- ordenes_medico_all: ALL, public, USING/CHECK (medico_id = auth.uid())
  SELECT cmd, qual, with_check, array_to_string(roles,',') INTO v_cmd, v_q, v_c, v_roles
    FROM pg_policies WHERE schemaname='public' AND tablename='ordenes_examen' AND policyname='ordenes_medico_all';
  IF v_cmd <> 'ALL' OR v_roles <> 'public' OR v_q IS DISTINCT FROM '(medico_id = auth.uid())' OR v_c IS DISTINCT FROM '(medico_id = auth.uid())' THEN
    RAISE EXCEPTION 'ROLLBACK321: ordenes medico no restaurada: cmd=% roles=% q=[%] c=[%]', v_cmd, v_roles, v_q, v_c;
  END IF;

  RAISE NOTICE 'ROLLBACK321 OK: 2 policies ALL originales restauradas, 8 nuevas eliminadas';
END $ac$;
