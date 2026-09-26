-- ############################################################################################
-- 333 ROLLBACK - vuelve examenes / ordenes_examen / examenes_catalogo al estado post-332 (pre-333)
-- ############################################################################################
-- Restaura: INSERT, TRUNCATE, TRIGGER y REFERENCES de authenticated en examenes y ordenes_examen;
-- TRUNCATE, TRIGGER y REFERENCES de authenticated en examenes_catalogo (anon no tenia ninguno);
-- las policies examenes_laboratorio_all, examenes_superadmin_all, ordenes_lab_all,
-- examenes_medico_insert, ordenes_medico_insert y ordenes_medico_update con su definicion previa; y
-- quita las policies por comando que las reemplazaron. No toca la 332 (columna, RPCs, grants por
-- columna, trigger), que sigue vigente.
-- ############################################################################################

BEGIN;

DROP POLICY examenes_laboratorio_select ON public.examenes;
DROP POLICY examenes_laboratorio_update ON public.examenes;
DROP POLICY examenes_laboratorio_delete ON public.examenes;
DROP POLICY examenes_superadmin_select ON public.examenes;
DROP POLICY examenes_superadmin_update ON public.examenes;
DROP POLICY examenes_superadmin_delete ON public.examenes;
DROP POLICY ordenes_lab_select ON public.ordenes_examen;
DROP POLICY ordenes_lab_delete ON public.ordenes_examen;

CREATE POLICY examenes_laboratorio_all ON public.examenes
  AS PERMISSIVE FOR ALL TO public
  USING (laboratorio_id = public.mi_empresa_proveedor())
  WITH CHECK (laboratorio_id = public.mi_empresa_proveedor());
CREATE POLICY examenes_superadmin_all ON public.examenes
  AS PERMISSIVE FOR ALL TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY ordenes_lab_all ON public.ordenes_examen
  AS PERMISSIVE FOR ALL TO public
  USING (laboratorio_id = public.mi_empresa_proveedor())
  WITH CHECK (laboratorio_id = public.mi_empresa_proveedor());
CREATE POLICY examenes_medico_insert ON public.examenes
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((medico_id = auth.uid()) AND (private.medico_atiende_paciente((paciente_id)::bigint) OR (EXISTS (
    SELECT 1 FROM public.pacientes pa WHERE ((pa.id = examenes.paciente_id) AND (pa.medico_id = auth.uid()))))));
CREATE POLICY ordenes_medico_insert ON public.ordenes_examen
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((medico_id = auth.uid()) AND (private.medico_atiende_paciente(paciente_id) OR (EXISTS (
    SELECT 1 FROM public.pacientes pa WHERE ((pa.id = ordenes_examen.paciente_id) AND (pa.medico_id = auth.uid()))))));
CREATE POLICY ordenes_medico_update ON public.ordenes_examen
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (medico_id = auth.uid())
  WITH CHECK ((medico_id = auth.uid()) AND (private.medico_atiende_paciente(paciente_id) OR (EXISTS (
    SELECT 1 FROM public.pacientes pa WHERE ((pa.id = ordenes_examen.paciente_id) AND (pa.medico_id = auth.uid()))))));

GRANT INSERT, TRUNCATE, TRIGGER, REFERENCES ON public.examenes, public.ordenes_examen TO authenticated;
GRANT TRUNCATE, TRIGGER, REFERENCES ON public.examenes_catalogo TO authenticated;

DO $chk$
DECLARE bad text := ''; x text; r record;
BEGIN
  FOR r IN SELECT t, p FROM unnest(ARRAY['public.examenes','public.ordenes_examen']) t, unnest(ARRAY['INSERT','TRUNCATE','TRIGGER','REFERENCES']) p LOOP
    IF NOT has_table_privilege('authenticated', r.t, r.p) THEN bad := bad||'falta '||r.p||' en '||r.t||'; '; END IF;
  END LOOP;
  FOR r IN SELECT p FROM unnest(ARRAY['INSERT','TRUNCATE','TRIGGER','REFERENCES']) p LOOP
    IF NOT has_table_privilege('authenticated', 'public.examenes_catalogo', r.p) THEN bad := bad||'falta '||r.p||' en examenes_catalogo; '; END IF;
  END LOOP;
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname) INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename = 'examenes';
  IF x IS DISTINCT FROM 'Admin clinica ve examenes de su clinica:SELECT,Paciente ve sus examenes:SELECT,examenes_laboratorio_all:ALL,examenes_medico_delete:DELETE,examenes_medico_insert:INSERT,examenes_medico_select:SELECT,examenes_superadmin_all:ALL' THEN
    bad := bad||'policies de examenes: '||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname) INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ordenes_examen';
  IF x IS DISTINCT FROM 'ordenes_lab_all:ALL,ordenes_medico_delete:DELETE,ordenes_medico_insert:INSERT,ordenes_medico_select:SELECT,ordenes_medico_update:UPDATE' THEN
    bad := bad||'policies de ordenes_examen: '||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO x FROM pg_attribute a WHERE a.attrelid = 'public.examenes'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('authenticated', 'public.examenes', a.attname, 'UPDATE');
  IF x IS DISTINCT FROM 'archivo_url,estado,fecha_resultado,resultados' THEN bad := bad||'UPDATE por columna examenes='||COALESCE(x,'-')||'; '; END IF;
  IF bad <> '' THEN RAISE EXCEPTION 'ROLLBACK333 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
