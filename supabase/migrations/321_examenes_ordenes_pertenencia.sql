-- ############################################################################################
-- 321 - pertenencia en las policies del medico de examenes y ordenes_examen
-- ############################################################################################
-- Recon del frente A: la creacion de examenes/ordenes es INSERT directo por PostgREST (ConsultaPage),
-- sin trigger que resuelva medico_id/paciente_id y sin RPC DEFINER. El unico gate era la policy del
-- medico, que exigia SOLO medico_id = auth.uid() SIN relacion con el paciente:
--   examenes  : "Medico ve examenes de sus pacientes" (ALL, sin WITH CHECK -> el USING gatea el INSERT)
--   ordenes   : ordenes_medico_all (ALL, WITH CHECK medico_id = auth.uid())
-- Medido (R8): un medico podia INSERT ordenes y examenes para CUALQUIER paciente. La fila forjada es
-- visible al paciente (estado <> 'completado'), aunque no dispensable (storage y adjuntos cerrados).
--
-- FIX: se parte cada policy ALL del medico en SELECT/INSERT/UPDATE/DELETE explicitas. La visibilidad
-- (SELECT) y el borrado (DELETE) quedan IDENTICOS a hoy (medico_id = auth.uid()); el INSERT y el
-- UPDATE agregan el PREDICADO A -- el MISMO, textual, de recetas_insert (mig 320) y del gate PR009 de
-- emitir_receta (mig 316):
--   private.medico_atiende_paciente(paciente_id::bigint)
--   OR EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = <tabla>.paciente_id AND pa.medico_id = auth.uid())
-- examenes.paciente_id es integer -> cast explicito ::bigint para pegar el overload (bigint), no el (text).
--
-- El walk-in del lab (medico_id NULL) NO se ve afectado: entra por examenes_laboratorio_all /
-- ordenes_lab_all, que no se tocan. Tampoco se tocan super_admin, admin_clinica, paciente,
-- examen_adjuntos, storage ni las RPCs de liberacion/adjunto.
-- Idempotente: DROP POLICY IF EXISTS antes de cada CREATE.
-- ############################################################################################

-- ===== examenes: partir la ALL del medico =====
DROP POLICY IF EXISTS "Medico ve examenes de sus pacientes" ON public.examenes;
DROP POLICY IF EXISTS examenes_medico_select ON public.examenes;
DROP POLICY IF EXISTS examenes_medico_insert ON public.examenes;
DROP POLICY IF EXISTS examenes_medico_update ON public.examenes;
DROP POLICY IF EXISTS examenes_medico_delete ON public.examenes;

CREATE POLICY examenes_medico_select ON public.examenes
  FOR SELECT TO authenticated
  USING (medico_id = auth.uid());

CREATE POLICY examenes_medico_insert ON public.examenes
  FOR INSERT TO authenticated
  WITH CHECK (
    medico_id = auth.uid()
    AND ( private.medico_atiende_paciente(paciente_id::bigint)
          OR EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = examenes.paciente_id AND pa.medico_id = auth.uid()) )
  );

CREATE POLICY examenes_medico_update ON public.examenes
  FOR UPDATE TO authenticated
  USING (medico_id = auth.uid())
  WITH CHECK (
    medico_id = auth.uid()
    AND ( private.medico_atiende_paciente(paciente_id::bigint)
          OR EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = examenes.paciente_id AND pa.medico_id = auth.uid()) )
  );

CREATE POLICY examenes_medico_delete ON public.examenes
  FOR DELETE TO authenticated
  USING (medico_id = auth.uid());

-- ===== ordenes_examen: partir la ALL del medico =====
DROP POLICY IF EXISTS ordenes_medico_all ON public.ordenes_examen;
DROP POLICY IF EXISTS ordenes_medico_select ON public.ordenes_examen;
DROP POLICY IF EXISTS ordenes_medico_insert ON public.ordenes_examen;
DROP POLICY IF EXISTS ordenes_medico_update ON public.ordenes_examen;
DROP POLICY IF EXISTS ordenes_medico_delete ON public.ordenes_examen;

CREATE POLICY ordenes_medico_select ON public.ordenes_examen
  FOR SELECT TO authenticated
  USING (medico_id = auth.uid());

CREATE POLICY ordenes_medico_insert ON public.ordenes_examen
  FOR INSERT TO authenticated
  WITH CHECK (
    medico_id = auth.uid()
    AND ( private.medico_atiende_paciente(paciente_id::bigint)
          OR EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = ordenes_examen.paciente_id AND pa.medico_id = auth.uid()) )
  );

CREATE POLICY ordenes_medico_update ON public.ordenes_examen
  FOR UPDATE TO authenticated
  USING (medico_id = auth.uid())
  WITH CHECK (
    medico_id = auth.uid()
    AND ( private.medico_atiende_paciente(paciente_id::bigint)
          OR EXISTS (SELECT 1 FROM public.pacientes pa WHERE pa.id = ordenes_examen.paciente_id AND pa.medico_id = auth.uid()) )
  );

CREATE POLICY ordenes_medico_delete ON public.ordenes_examen
  FOR DELETE TO authenticated
  USING (medico_id = auth.uid());

-- ============================================================================================
-- AUTOCHEQUEO
-- ============================================================================================
DO $ac$
DECLARE
  v_ex text; v_or text; v_bad int; v_ins int; v_q text; v_c text;
BEGIN
  -- (1) set exacto de nombres por tabla
  SELECT string_agg(policyname, ',' ORDER BY policyname) INTO v_ex
    FROM pg_policies WHERE schemaname='public' AND tablename='examenes';
  IF v_ex <> 'Admin clinica ve examenes de su clinica,Paciente ve sus examenes,examenes_laboratorio_all,examenes_medico_delete,examenes_medico_insert,examenes_medico_select,examenes_medico_update,examenes_superadmin_all' THEN
    RAISE EXCEPTION 'MIG321: set de policies de examenes inesperado: %', v_ex;
  END IF;
  SELECT string_agg(policyname, ',' ORDER BY policyname) INTO v_or
    FROM pg_policies WHERE schemaname='public' AND tablename='ordenes_examen';
  IF v_or <> 'ordenes_lab_all,ordenes_medico_delete,ordenes_medico_insert,ordenes_medico_select,ordenes_medico_update' THEN
    RAISE EXCEPTION 'MIG321: set de policies de ordenes_examen inesperado: %', v_or;
  END IF;

  -- (2) ninguna policy de medico es cmd=ALL
  SELECT count(*) INTO v_bad FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
   WHERE c.relnamespace='public'::regnamespace AND c.relname IN ('examenes','ordenes_examen')
     AND pol.polname ~ '_medico_' AND pol.polcmd='*';
  IF v_bad <> 0 THEN RAISE EXCEPTION 'MIG321: quedaron % policies de medico cmd=ALL', v_bad; END IF;

  -- (3) insert/update de medico contienen medico_atiende_paciente en with_check
  SELECT count(*) INTO v_ins FROM pg_policies WHERE schemaname='public'
     AND tablename IN ('examenes','ordenes_examen')
     AND policyname ~ '_medico_(insert|update)$'
     AND with_check LIKE '%medico_atiende_paciente%';
  IF v_ins <> 4 THEN RAISE EXCEPTION 'MIG321: se esperaban 4 policies insert/update con pertenencia, hay %', v_ins; END IF;

  -- (4) las 5 policies NO tocadas, byte a byte contra el snapshot del recon
  -- examenes :: Admin clinica ve examenes de su clinica
  SELECT qual, with_check INTO v_q, v_c FROM pg_policies WHERE schemaname='public' AND tablename='examenes' AND policyname='Admin clinica ve examenes de su clinica';
  IF v_q IS DISTINCT FROM 'COALESCE(private.medico_es_de_mi_clinica(medico_id), false)' OR v_c IS DISTINCT FROM NULL THEN
    RAISE EXCEPTION 'MIG321: cambio "Admin clinica ve examenes de su clinica": q=[%] c=[%]', v_q, v_c;
  END IF;
  -- examenes :: Paciente ve sus examenes
  SELECT qual, with_check INTO v_q, v_c FROM pg_policies WHERE schemaname='public' AND tablename='examenes' AND policyname='Paciente ve sus examenes';
  IF v_q IS DISTINCT FROM E'((paciente_id IN ( SELECT pacientes.id\n   FROM pacientes\n  WHERE (pacientes.auth_user_id = auth.uid()))) AND (liberado_al_paciente OR (estado <> ''completado''::examen_estado)))' OR v_c IS DISTINCT FROM NULL THEN
    RAISE EXCEPTION 'MIG321: cambio "Paciente ve sus examenes": q=[%] c=[%]', v_q, v_c;
  END IF;
  -- examenes :: examenes_laboratorio_all
  SELECT qual, with_check INTO v_q, v_c FROM pg_policies WHERE schemaname='public' AND tablename='examenes' AND policyname='examenes_laboratorio_all';
  IF v_q IS DISTINCT FROM '(laboratorio_id = mi_empresa_proveedor())' OR v_c IS DISTINCT FROM '(laboratorio_id = mi_empresa_proveedor())' THEN
    RAISE EXCEPTION 'MIG321: cambio examenes_laboratorio_all: q=[%] c=[%]', v_q, v_c;
  END IF;
  -- examenes :: examenes_superadmin_all
  SELECT qual, with_check INTO v_q, v_c FROM pg_policies WHERE schemaname='public' AND tablename='examenes' AND policyname='examenes_superadmin_all';
  IF v_q IS DISTINCT FROM 'private.tiene_rol(ARRAY[''super_admin''::text])' OR v_c IS DISTINCT FROM 'private.tiene_rol(ARRAY[''super_admin''::text])' THEN
    RAISE EXCEPTION 'MIG321: cambio examenes_superadmin_all: q=[%] c=[%]', v_q, v_c;
  END IF;
  -- ordenes_examen :: ordenes_lab_all
  SELECT qual, with_check INTO v_q, v_c FROM pg_policies WHERE schemaname='public' AND tablename='ordenes_examen' AND policyname='ordenes_lab_all';
  IF v_q IS DISTINCT FROM '(laboratorio_id = mi_empresa_proveedor())' OR v_c IS DISTINCT FROM '(laboratorio_id = mi_empresa_proveedor())' THEN
    RAISE EXCEPTION 'MIG321: cambio ordenes_lab_all: q=[%] c=[%]', v_q, v_c;
  END IF;

  RAISE NOTICE 'MIG321 OK: examenes(8)/ordenes(5) policies; medico insert/update con pertenencia; 5 no tocadas intactas';
END $ac$;
