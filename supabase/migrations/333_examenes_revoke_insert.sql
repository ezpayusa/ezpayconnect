-- ############################################################################################
-- 333 - P3 fase 2 de 2: las ordenes de examen se crean SOLO por RPC (cierre del INSERT directo)
-- ############################################################################################
-- La 332 (aditiva) creo crear_orden_examen_medico / crear_orden_examen_walkin y dejo vivo el INSERT
-- directo para no romper el front viejo. El front nuevo (main 4477dd6) ya no inserta directo: 0
-- .insert/.upsert sobre examenes u ordenes_examen en src/ ni en supabase/functions (grep 25-sep), y
-- Oscar lo probo en el navegador el 25-sep. Las RPCs son SECURITY DEFINER con owner postgres: no
-- dependen de los grants ni de las policies de authenticated.
--
-- Esta migracion:
--   (a) REVOKE INSERT en examenes y ordenes_examen a authenticated, anon y PUBLIC.
--   (b) DROP examenes_medico_insert y ordenes_medico_insert.
--   (c) Split de las policies ALL de esas dos tablas en policies por comando, con el MISMO USING /
--       WITH CHECK y los MISMOS roles, sin INSERT:
--         examenes_laboratorio_all (public)       -> _select / _update / _delete
--         examenes_superadmin_all  (authenticated) -> _select / _update / _delete
--         ordenes_lab_all          (public)       -> _select / _delete
--       ordenes_lab_all NO lleva _update: desde la 332 authenticated no tiene UPDATE en
--       ordenes_examen, asi que esa policy seria letra muerta (mismo criterio que (d)). El acceso
--       efectivo no cambia.
--   (d) DROP ordenes_medico_update (sin grant de UPDATE no tiene efecto).
--   (e) M.8: REVOKE TRUNCATE, TRIGGER, REFERENCES de authenticated y anon en examenes,
--       ordenes_examen y examenes_catalogo.
-- NO toca: el INSERT de examenes_catalogo (alta legitima del laboratorio, catalogo_lab_all), los
-- grants por columna de la 332, las RPCs, ni las demas policies (medico/paciente/admin clinica).
-- Leccion mig 284: no se revoca SELECT; las policies que leen estas tablas en su USING no cambian.
--
-- Probes P879-P884 (+ P878 actualizada al estado post-333). Rollback: 333_rollback.sql.
-- ############################################################################################

BEGIN;

-- (a) sin INSERT directo
REVOKE INSERT ON public.examenes, public.ordenes_examen FROM authenticated, anon, PUBLIC;

-- (b) policies de INSERT del medico
DROP POLICY examenes_medico_insert ON public.examenes;
DROP POLICY ordenes_medico_insert ON public.ordenes_examen;

-- (c) split de las ALL
DROP POLICY examenes_laboratorio_all ON public.examenes;
CREATE POLICY examenes_laboratorio_select ON public.examenes
  AS PERMISSIVE FOR SELECT TO public
  USING (laboratorio_id = public.mi_empresa_proveedor());
CREATE POLICY examenes_laboratorio_update ON public.examenes
  AS PERMISSIVE FOR UPDATE TO public
  USING (laboratorio_id = public.mi_empresa_proveedor())
  WITH CHECK (laboratorio_id = public.mi_empresa_proveedor());
CREATE POLICY examenes_laboratorio_delete ON public.examenes
  AS PERMISSIVE FOR DELETE TO public
  USING (laboratorio_id = public.mi_empresa_proveedor());

DROP POLICY examenes_superadmin_all ON public.examenes;
CREATE POLICY examenes_superadmin_select ON public.examenes
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY examenes_superadmin_update ON public.examenes
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin'::text]));
CREATE POLICY examenes_superadmin_delete ON public.examenes
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin'::text]));

DROP POLICY ordenes_lab_all ON public.ordenes_examen;
CREATE POLICY ordenes_lab_select ON public.ordenes_examen
  AS PERMISSIVE FOR SELECT TO public
  USING (laboratorio_id = public.mi_empresa_proveedor());
CREATE POLICY ordenes_lab_delete ON public.ordenes_examen
  AS PERMISSIVE FOR DELETE TO public
  USING (laboratorio_id = public.mi_empresa_proveedor());

-- (d) UPDATE del medico sobre ordenes_examen: sin grant desde la 332
DROP POLICY ordenes_medico_update ON public.ordenes_examen;

-- (e) M.8
REVOKE TRUNCATE, TRIGGER, REFERENCES ON public.examenes, public.ordenes_examen, public.examenes_catalogo FROM authenticated, anon;

-- ---------------------------------------------------------------------------- autochequeo
DO $chk$
DECLARE bad text := ''; x text; n int; r record; v_lab text;
BEGIN
  -- privilegios de tabla
  FOR r IN SELECT t, rol, p FROM unnest(ARRAY['public.examenes','public.ordenes_examen']) t,
                                 unnest(ARRAY['authenticated','anon']) rol,
                                 unnest(ARRAY['INSERT','TRUNCATE','TRIGGER','REFERENCES']) p LOOP
    IF has_table_privilege(r.rol, r.t, r.p) THEN bad := bad||r.rol||' '||r.p||' en '||r.t||'; '; END IF;
  END LOOP;
  FOR r IN SELECT rol, p FROM unnest(ARRAY['authenticated','anon']) rol, unnest(ARRAY['TRUNCATE','TRIGGER','REFERENCES']) p LOOP
    IF has_table_privilege(r.rol, 'public.examenes_catalogo', r.p) THEN bad := bad||r.rol||' '||r.p||' en examenes_catalogo; '; END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated', 'public.examenes_catalogo', 'INSERT') THEN bad := bad||'se perdio el INSERT del catalogo; '; END IF;
  SELECT count(*) INTO n FROM pg_class c, aclexplode(c.relacl) a
   WHERE c.oid IN ('public.examenes'::regclass, 'public.ordenes_examen'::regclass, 'public.examenes_catalogo'::regclass) AND a.grantee = 0;
  IF n <> 0 THEN bad := bad||'PUBLIC con '||n||' privilegio(s); '; END IF;
  -- policies: ninguna INSERT/ALL en examenes u ordenes_examen; conjunto exacto por tabla
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('examenes','ordenes_examen') AND cmd IN ('INSERT','ALL');
  IF n <> 0 THEN bad := bad||n||' policy(s) INSERT/ALL en examenes/ordenes_examen; '; END IF;
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname) INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename = 'examenes';
  IF x IS DISTINCT FROM 'Admin clinica ve examenes de su clinica:SELECT,Paciente ve sus examenes:SELECT,examenes_laboratorio_delete:DELETE,examenes_laboratorio_select:SELECT,examenes_laboratorio_update:UPDATE,examenes_medico_delete:DELETE,examenes_medico_select:SELECT,examenes_superadmin_delete:DELETE,examenes_superadmin_select:SELECT,examenes_superadmin_update:UPDATE' THEN
    bad := bad||'policies de examenes: '||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(policyname||':'||cmd, ',' ORDER BY policyname) INTO x FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ordenes_examen';
  IF x IS DISTINCT FROM 'ordenes_lab_delete:DELETE,ordenes_lab_select:SELECT,ordenes_medico_delete:DELETE,ordenes_medico_select:SELECT' THEN
    bad := bad||'policies de ordenes_examen: '||COALESCE(x,'-')||'; '; END IF;
  -- expresiones de las nuevas: iguales a las de las ALL que reemplazan
  v_lab := '(laboratorio_id = mi_empresa_proveedor())';   -- forma deparseada de la USING de las ALL reemplazadas
  FOR r IN SELECT policyname, tablename, cmd, roles::text AS roles, qual, with_check FROM pg_policies
            WHERE schemaname = 'public' AND policyname IN ('examenes_laboratorio_select','examenes_laboratorio_update','examenes_laboratorio_delete',
              'ordenes_lab_select','ordenes_lab_delete') LOOP
    IF r.roles <> '{public}' OR r.qual IS DISTINCT FROM v_lab
       OR (r.cmd = 'UPDATE' AND r.with_check IS DISTINCT FROM v_lab) OR (r.cmd <> 'UPDATE' AND r.with_check IS NOT NULL) THEN
      bad := bad||r.policyname||' ('||r.roles||' '||COALESCE(r.qual,'-')||' / '||COALESCE(r.with_check,'-')||'); '; END IF;
  END LOOP;
  FOR r IN SELECT policyname, cmd, roles::text AS roles, qual, with_check FROM pg_policies
            WHERE schemaname = 'public' AND policyname IN ('examenes_superadmin_select','examenes_superadmin_update','examenes_superadmin_delete') LOOP
    IF r.roles <> '{authenticated}' OR r.qual IS DISTINCT FROM 'private.tiene_rol(ARRAY[''super_admin''::text])'
       OR (r.cmd = 'UPDATE' AND r.with_check IS DISTINCT FROM r.qual) OR (r.cmd <> 'UPDATE' AND r.with_check IS NOT NULL) THEN
      bad := bad||r.policyname||' ('||r.roles||' '||COALESCE(r.qual,'-')||' / '||COALESCE(r.with_check,'-')||'); '; END IF;
  END LOOP;
  -- grants por columna de la 332, intactos
  SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO x FROM pg_attribute a WHERE a.attrelid = 'public.examenes'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('authenticated', 'public.examenes', a.attname, 'UPDATE');
  IF x IS DISTINCT FROM 'archivo_url,estado,fecha_resultado,resultados' THEN bad := bad||'UPDATE por columna examenes='||COALESCE(x,'-')||'; '; END IF;
  SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO x FROM pg_attribute a WHERE a.attrelid = 'public.examenes_catalogo'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('authenticated', 'public.examenes_catalogo', a.attname, 'UPDATE');
  IF x IS DISTINCT FROM 'activo,categoria' THEN bad := bad||'UPDATE por columna catalogo='||COALESCE(x,'-')||'; '; END IF;
  SELECT count(*) INTO n FROM pg_attribute a WHERE a.attrelid = 'public.ordenes_examen'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('authenticated', 'public.ordenes_examen', a.attname, 'UPDATE');
  IF n <> 0 THEN bad := bad||'UPDATE en ordenes_examen='||n||'; '; END IF;
  -- las 4 funciones de la 332 y las 9 previas, sin cambios
  FOR r IN SELECT * FROM (VALUES
      ('public.crear_orden_examen_medico(bigint,uuid,jsonb,text)', '79a994588ab2b4458135272efb59b867'),
      ('public.crear_orden_examen_walkin(jsonb,text,text,text,text,text)', '434d122370e340d895c8540a290379f3'),
      ('private.armar_items_orden_examen(uuid,jsonb)', '36823df5ac3f7347a30275c07b4c39f9'),
      ('private.examenes_congelar_identidad()', 'f0ff903d5c5af6e137ba6b6aed0bad9a'),
      ('public.liberar_examen_al_paciente(integer)', '7c980b20f713d0cf49e7235da30838e1'),
      ('public.liberar_orden_al_paciente(uuid)', '96a54d314911a439af77e426ebe46611'),
      ('public.revertir_liberacion_examen(integer)', '4a7f4912f3330543d2d7a47b2a06fbc6'),
      ('public.notificar_orden_lab(uuid)', '59fafc8572840548c27ad39a759cba47'),
      ('public.notificar_resultado_examen(integer)', '33a7a110c39574c5a40f7ca1495d2686'),
      ('public.paciente_examenes()', 'a14ea485045b28883d81a0dd9fe7cd83'),
      ('public.contexto_ia_paciente(bigint)', '1eaf84a3475dfdfc3845d68ce2406fbb'),
      ('private.puede_ver_examen(integer)', '2b8150875b99dfb5df9fdb3d8af62ae0'),
      ('public.registrar_examen_adjunto(integer,text,text)', '245fb6669aa3fb22f8e62ca40a8b3467')) v(f, m) LOOP
    SELECT md5(prosrc) INTO x FROM pg_proc WHERE oid = to_regprocedure(r.f);
    IF x IS DISTINCT FROM r.m THEN bad := bad||r.f||' md5 '||COALESCE(x,'NO EXISTE')||'; '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'MIG333 AUTOCHEQUEO FALLA:%', bad; END IF;
END $chk$;

COMMIT;
