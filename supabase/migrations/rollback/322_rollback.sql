-- ############################################################################################
-- ROLLBACK de la mig 322 - restaura helpers + 13 policies, dropea onboarding + CHECK
-- ############################################################################################

-- ===== helpers de identidad -> texto ORIGINAL (snapshot pg_get_functiondef) =====
CREATE OR REPLACE FUNCTION public.mi_empresa_proveedor()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$ SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true LIMIT 1; $f$;

CREATE OR REPLACE FUNCTION public.mi_rol_proveedor()
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT rol_en_empresa FROM public.cuentas_proveedor WHERE id = auth.uid() AND activo = true LIMIT 1;
$f$;

CREATE OR REPLACE FUNCTION public.mi_equipo_proveedor()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$ SELECT equipo_id FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true LIMIT 1; $f$;

CREATE OR REPLACE FUNCTION private.pais_de_proveedor()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT COALESCE(cp.pais_id, e.pais_id)
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo IS TRUE
   LIMIT 1;
$f$;

-- ===== 5 onboarding -> texto ORIGINAL (mi_empresa_proveedor / mi_rol_proveedor) =====
ALTER POLICY "Proveedor crea pagos" ON public.pagos_proveedor
  WITH CHECK ((empresa_id = mi_empresa_proveedor()) AND (mi_rol_proveedor() = ANY (ARRAY['admin'::text,'editor'::text,'finanzas'::text,'marketing'::text,'supervisor'::text])));
ALTER POLICY "Proveedor ve pagos segun rol" ON public.pagos_proveedor
  USING ((empresa_id = mi_empresa_proveedor()) AND (mi_rol_proveedor() = ANY (ARRAY['admin'::text,'editor'::text,'finanzas'::text,'marketing'::text,'supervisor'::text])));
ALTER POLICY "comprobantes_scoped_insert" ON storage.objects
  WITH CHECK ((bucket_id = 'comprobantes'::text) AND ((split_part(name,'/'::text,1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY['super_admin'::text])));
ALTER POLICY "comprobantes_scoped_select" ON storage.objects
  USING ((bucket_id = 'comprobantes'::text) AND ((split_part(name,'/'::text,1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY['super_admin'::text])));
ALTER POLICY "comprobantes_scoped_update" ON storage.objects
  USING ((bucket_id = 'comprobantes'::text) AND ((split_part(name,'/'::text,1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY['super_admin'::text])))
  WITH CHECK ((bucket_id = 'comprobantes'::text) AND ((split_part(name,'/'::text,1) = (mi_empresa_proveedor())::text) OR private.tiene_rol(ARRAY['super_admin'::text])));

-- ===== 7 reapuntadas -> texto ORIGINAL (subquery directo a cuentas_proveedor) =====
ALTER POLICY "invitaciones_insert_admin" ON public.invitaciones_visitador
  WITH CHECK (EXISTS ( SELECT 1 FROM (cuentas_proveedor cp JOIN empresas_proveedoras e ON ((e.id = cp.empresa_id)))
    WHERE ((cp.id = auth.uid()) AND (cp.empresa_id = invitaciones_visitador.empresa_id) AND (cp.activo = true)
      AND (cp.rol_en_empresa = ANY (ARRAY['admin'::text,'editor'::text])) AND (e.tipo <> ALL (ARRAY['farmacia'::text,'empresa_afin'::text])))));

ALTER POLICY "Proveedor crea visitas de su empresa" ON public.visitas_agendadas
  WITH CHECK ((empresa_id IN ( SELECT cuentas_proveedor.empresa_id FROM cuentas_proveedor
      WHERE ((cuentas_proveedor.id = auth.uid()) AND (cuentas_proveedor.activo = true)
        AND (cuentas_proveedor.rol_en_empresa = ANY (ARRAY['admin'::text,'editor'::text,'visitador_medico'::text])))))
    AND private.cuenta_en_empresa(cuenta_proveedor_id, empresa_id)
    AND ((cuenta_proveedor_id = auth.uid()) OR (EXISTS ( SELECT 1 FROM cuentas_proveedor
      WHERE ((cuentas_proveedor.id = auth.uid()) AND (cuentas_proveedor.rol_en_empresa = ANY (ARRAY['admin'::text,'editor'::text])))))));

ALTER POLICY "Proveedor cancela sus visitas" ON public.visitas_agendadas
  USING (empresa_id IN ( SELECT cuentas_proveedor.empresa_id FROM cuentas_proveedor WHERE (cuentas_proveedor.id = auth.uid())));

ALTER POLICY "Proveedor ve productos de su empresa" ON public.productos_empresa
  USING (empresa_id IN ( SELECT cuentas_proveedor.empresa_id FROM cuentas_proveedor WHERE (cuentas_proveedor.id = auth.uid())));

ALTER POLICY "Proveedor ve sus planes visitador" ON public.planes_visitador_contratados
  USING (empresa_id IN ( SELECT cuentas_proveedor.empresa_id FROM cuentas_proveedor WHERE (cuentas_proveedor.id = auth.uid())));

ALTER POLICY "Proveedor ve sus campañas" ON public.solicitudes_campana
  USING (empresa_id IN ( SELECT cuentas_proveedor.empresa_id FROM cuentas_proveedor WHERE (cuentas_proveedor.id = auth.uid())));

ALTER POLICY "ubicaciones_select" ON public.ubicaciones_medico_proveedor
  USING (empresa_id IN ( SELECT cuentas_proveedor.empresa_id FROM cuentas_proveedor WHERE ((cuentas_proveedor.id = auth.uid()) AND (cuentas_proveedor.activo = true))));

-- ===== drop guard + onboarding helpers + CHECK =====
DROP TRIGGER IF EXISTS empresas_proveedoras_guard_update ON public.empresas_proveedoras;
DROP FUNCTION IF EXISTS private.empresas_proveedoras_guard_update();
DROP FUNCTION IF EXISTS private.mi_empresa_onboarding();
DROP FUNCTION IF EXISTS private.mi_rol_onboarding();
ALTER TABLE public.empresas_proveedoras DROP CONSTRAINT IF EXISTS empresas_proveedoras_estado_chk;

-- ===== AUTOCHEQUEO del rollback: md5 vs snapshot del estado ORIGINAL =====
DO $ac$
DECLARE r record; v_now text; v_bad text := '';
  exp_helper CONSTANT text[][] := ARRAY[
    ['public.mi_empresa_proveedor','9c5da473e8be2d312092a222dbcaf7b9'],
    ['public.mi_rol_proveedor','8fbfad46ac66a1e68e125966717c2a3d'],
    ['public.mi_equipo_proveedor','42514e73054d99e4187fd16696d74176'],
    ['private.pais_de_proveedor','a16bcc62056031436e0c360d9503a34d']];
BEGIN
  FOR i IN 1..array_length(exp_helper,1) LOOP
    SELECT md5(pg_get_functiondef(p.oid)) INTO v_now FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE (n.nspname||'.'||p.proname)=exp_helper[i][1];
    IF v_now IS DISTINCT FROM exp_helper[i][2] THEN v_bad := v_bad||' helper:'||exp_helper[i][1]; END IF;
  END LOOP;
  FOR r IN
    SELECT * FROM (VALUES
      ('public','cuentas_proveedor','Proveedor admin ve cuentas de su empresa','783f3eafab36abed1fdc457849c4a710'),
      ('public','empresas_proveedoras','Proveedor actualiza su propia empresa','3dddee2233cf9caa387a8870c066d49b'),
      ('public','empresas_proveedoras','Proveedor ve su propia empresa','c190682ce355c2b9906f412e067bc0ca'),
      ('public','invitaciones_visitador','invitaciones_insert_admin','538e551fa8ed719f89a81b868fc0e4fd'),
      ('public','medicos','Proveedor ve medicos de su pais','658255d4ec42b16fd5579f92da21f218'),
      ('public','pagos_proveedor','Proveedor crea pagos','9c77519a515c88f80c881e0704416e29'),
      ('public','pagos_proveedor','Proveedor ve pagos segun rol','15e990f1d7e3de9dff8ceb23ceb71980'),
      ('public','planes_visitador_contratados','Proveedor ve sus planes visitador','d55ae589088935115811781b39de9936'),
      ('public','productos_empresa','Proveedor ve productos de su empresa','d55ae589088935115811781b39de9936'),
      ('public','solicitudes_campana','Proveedor ve sus campañas','d55ae589088935115811781b39de9936'),
      ('public','ubicaciones_medico_proveedor','ubicaciones_select','d621f5556323ce7017cfeb903b59d045'),
      ('public','visitas_agendadas','Proveedor cancela sus visitas','d55ae589088935115811781b39de9936'),
      ('public','visitas_agendadas','Proveedor crea visitas de su empresa','1f05cfa5aaf6fc3dc2c439dbf063b351'),
      ('storage','objects','comprobantes_scoped_insert','459f5c1e158a588c70e2d56351681479'),
      ('storage','objects','comprobantes_scoped_select','29dafd87fc5bf3a26e4451bae3071037'),
      ('storage','objects','comprobantes_scoped_update','b407ab815848a5f7612c5da01c560bd2')
    ) AS x(sch,tab,pol,md)
  LOOP
    SELECT md5(COALESCE(qual,'')||'|'||COALESCE(with_check,'')) INTO v_now FROM pg_policies
      WHERE schemaname=r.sch AND tablename=r.tab AND policyname=r.pol;
    IF v_now IS DISTINCT FROM r.md THEN v_bad := v_bad||' pol:'||r.tab||'::'||r.pol; END IF;
  END LOOP;
  IF v_bad <> '' THEN RAISE EXCEPTION 'ROLLBACK322: md5 no coincide en ->%', v_bad; END IF;

  IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.oid='public.empresas_proveedoras'::regclass AND t.tgname='empresas_proveedoras_guard_update' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'ROLLBACK322: quedo el trigger guard'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN ('mi_empresa_onboarding','mi_rol_onboarding','empresas_proveedoras_guard_update')) THEN
    RAISE EXCEPTION 'ROLLBACK322: quedaron funciones nuevas'; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.empresas_proveedoras'::regclass AND conname='empresas_proveedoras_estado_chk') THEN
    RAISE EXCEPTION 'ROLLBACK322: quedo el CHECK'; END IF;

  RAISE NOTICE 'ROLLBACK322 OK: md5 de 4 helpers + 16 policies == snapshot; sin guard/onboarding/CHECK';
END $ac$;
