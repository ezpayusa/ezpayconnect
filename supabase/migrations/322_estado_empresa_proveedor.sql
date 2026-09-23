-- ############################################################################################
-- 322 - gate de estado de empresa en la capa de policies + helpers de identidad de proveedor
-- ############################################################################################
-- Recon del frente A pto 2: mi_empresa_proveedor()/mi_rol_proveedor()/mi_equipo_proveedor() y
-- private.pais_de_proveedor() solo miraban cuentas_proveedor.activo, NUNCA empresas_proveedoras.estado.
-- Una empresa 'pendiente' (o 'suspendida'/'rechazada') con cuenta activa entraba a toda la superficie
-- operativa de proveedor (50 policies + funciones).
--
-- Decision (Oscar), opcion D:
--  * Los helpers de identidad OPERATIVA devuelven NULL si la empresa no esta 'activa' -> toda superficie
--    que pasa por el helper hereda el gate (fail-closed: `= NULL` es false).
--  * 'pendiente' y 'suspendida' conservan SOLO onboarding (ver cuenta/empresa, editar perfil, pagar y
--    subir comprobante). 'rechazada': nada salvo ver su cuenta/empresa (pantalla de estado).
--  * Las 8 policies operativas que resolvian la empresa por subquery directo a cuentas_proveedor se
--    REAPUNTAN al helper (no se les pega la condicion de estado aparte).
--  * Onboarding: 2 helpers nuevos que permiten activa|pendiente|suspendida.
-- Lote 2 (mig 323): las ~35 funciones con subquery directo + la edge invitar-visitador. registrar_proveedor = 2b.
-- ############################################################################################

-- ===== 1) CHECK de dominio de estado =====
DO $chk$
BEGIN
  IF EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE estado NOT IN ('pendiente','activa','suspendida','rechazada')) THEN
    RAISE EXCEPTION 'MIG322: hay empresas con estado fuera de dominio; no se puede agregar el CHECK';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.empresas_proveedoras'::regclass AND conname='empresas_proveedoras_estado_chk') THEN
    ALTER TABLE public.empresas_proveedoras
      ADD CONSTRAINT empresas_proveedoras_estado_chk CHECK (estado IN ('pendiente','activa','suspendida','rechazada'));
  END IF;
END $chk$;

-- ===== 2) Helpers de identidad operativa: gate estado='activa' (misma firma/secdef/owner, search_path='') =====
CREATE OR REPLACE FUNCTION public.mi_empresa_proveedor()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT cp.empresa_id
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa'
   WHERE cp.id = auth.uid() AND cp.activo = true
   LIMIT 1;
$f$;

CREATE OR REPLACE FUNCTION public.mi_rol_proveedor()
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT cp.rol_en_empresa
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa'
   WHERE cp.id = auth.uid() AND cp.activo = true
   LIMIT 1;
$f$;

CREATE OR REPLACE FUNCTION public.mi_equipo_proveedor()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT cp.equipo_id
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id AND e.estado = 'activa'
   WHERE cp.id = auth.uid() AND cp.activo = true
   LIMIT 1;
$f$;

CREATE OR REPLACE FUNCTION private.pais_de_proveedor()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT COALESCE(cp.pais_id, e.pais_id)
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo IS TRUE AND e.estado = 'activa'
   LIMIT 1;
$f$;

-- ===== 3) Helpers de ONBOARDING (activa|pendiente|suspendida). USO EXCLUSIVO de las 5 policies de onboarding =====
CREATE OR REPLACE FUNCTION private.mi_empresa_onboarding()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT cp.empresa_id
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo = true AND e.estado IN ('activa','pendiente','suspendida')
   LIMIT 1;
$f$;
COMMENT ON FUNCTION private.mi_empresa_onboarding() IS 'USO EXCLUSIVO de las 5 policies de onboarding (pagos_proveedor + comprobantes). Permite empresa activa|pendiente|suspendida.';
REVOKE ALL ON FUNCTION private.mi_empresa_onboarding() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mi_empresa_onboarding() TO authenticated;

CREATE OR REPLACE FUNCTION private.mi_rol_onboarding()
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $f$
  SELECT cp.rol_en_empresa
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
   WHERE cp.id = auth.uid() AND cp.activo = true AND e.estado IN ('activa','pendiente','suspendida')
   LIMIT 1;
$f$;
COMMENT ON FUNCTION private.mi_rol_onboarding() IS 'USO EXCLUSIVO de las policies de onboarding de pagos_proveedor. Permite empresa activa|pendiente|suspendida.';
REVOKE ALL ON FUNCTION private.mi_rol_onboarding() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mi_rol_onboarding() TO authenticated;

-- ===== 4) 5 policies de ONBOARDING -> helpers de onboarding (resto igual) =====
ALTER POLICY "Proveedor crea pagos" ON public.pagos_proveedor
  WITH CHECK ((empresa_id = private.mi_empresa_onboarding())
              AND (private.mi_rol_onboarding() = ANY (ARRAY['admin'::text,'editor'::text,'finanzas'::text,'marketing'::text,'supervisor'::text])));

ALTER POLICY "Proveedor ve pagos segun rol" ON public.pagos_proveedor
  USING ((empresa_id = private.mi_empresa_onboarding())
         AND (private.mi_rol_onboarding() = ANY (ARRAY['admin'::text,'editor'::text,'finanzas'::text,'marketing'::text,'supervisor'::text])));

ALTER POLICY "comprobantes_scoped_insert" ON storage.objects
  WITH CHECK ((bucket_id = 'comprobantes'::text)
              AND ((split_part(name,'/'::text,1) = (private.mi_empresa_onboarding())::text) OR private.tiene_rol(ARRAY['super_admin'::text])));

ALTER POLICY "comprobantes_scoped_select" ON storage.objects
  USING ((bucket_id = 'comprobantes'::text)
         AND ((split_part(name,'/'::text,1) = (private.mi_empresa_onboarding())::text) OR private.tiene_rol(ARRAY['super_admin'::text])));

ALTER POLICY "comprobantes_scoped_update" ON storage.objects
  USING ((bucket_id = 'comprobantes'::text)
         AND ((split_part(name,'/'::text,1) = (private.mi_empresa_onboarding())::text) OR private.tiene_rol(ARRAY['super_admin'::text])))
  WITH CHECK ((bucket_id = 'comprobantes'::text)
              AND ((split_part(name,'/'::text,1) = (private.mi_empresa_onboarding())::text) OR private.tiene_rol(ARRAY['super_admin'::text])));

-- ===== 5) 8 policies del alcance extra -> reapuntar el subquery directo al helper =====
-- (a) invitaciones_visitador: empresa via helper; rol via mi_rol_proveedor; filtro de tipo por lookup de empresa
ALTER POLICY "invitaciones_insert_admin" ON public.invitaciones_visitador
  WITH CHECK ((empresa_id = public.mi_empresa_proveedor())
              AND (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text,'editor'::text]))
              AND (EXISTS (SELECT 1 FROM public.empresas_proveedoras e
                            WHERE e.id = invitaciones_visitador.empresa_id
                              AND e.tipo <> ALL (ARRAY['farmacia'::text,'empresa_afin'::text]))));

-- (b) visitas_agendadas crea: empresa+rol via helper; conserva cuenta_en_empresa y la rama admin-por-otro
ALTER POLICY "Proveedor crea visitas de su empresa" ON public.visitas_agendadas
  WITH CHECK ((empresa_id = public.mi_empresa_proveedor())
              AND (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text,'editor'::text,'visitador_medico'::text]))
              AND private.cuenta_en_empresa(cuenta_proveedor_id, empresa_id)
              AND ((cuenta_proveedor_id = auth.uid()) OR (public.mi_rol_proveedor() = ANY (ARRAY['admin'::text,'editor'::text]))));

-- (c) visitas_agendadas cancela
ALTER POLICY "Proveedor cancela sus visitas" ON public.visitas_agendadas
  USING (empresa_id = public.mi_empresa_proveedor());

-- (d) productos_empresa ve
ALTER POLICY "Proveedor ve productos de su empresa" ON public.productos_empresa
  USING (empresa_id = public.mi_empresa_proveedor());

-- (e) planes_visitador_contratados ve
ALTER POLICY "Proveedor ve sus planes visitador" ON public.planes_visitador_contratados
  USING (empresa_id = public.mi_empresa_proveedor());

-- (f) solicitudes_campana ve
ALTER POLICY "Proveedor ve sus campañas" ON public.solicitudes_campana
  USING (empresa_id = public.mi_empresa_proveedor());

-- (g) ubicaciones_medico_proveedor select (el activo ya vive en el helper)
ALTER POLICY "ubicaciones_select" ON public.ubicaciones_medico_proveedor
  USING (empresa_id = public.mi_empresa_proveedor());

-- (h) medicos: SIN CAMBIO — ya usa private.pais_de_proveedor(), que ahora trae el gate de estado.

-- ===== 6) GUARD de columnas PRIVILEGIADAS de empresas_proveedoras (molde perfiles_guard_rol_update, mig 262) =====
-- Medido (B.2): un proveedor admin/editor podia UPDATE su propia empresa cambiando estado='activa'
-- (auto-activacion), pais_id y tipo. La policy "Proveedor actualiza su propia empresa" no tiene WITH CHECK.
-- Columnas privilegiadas (B.3): estado, tipo, pais_id, dias_ventaja_reserva, ventana_prioridad_visitas.
-- Quien las cambia hoy (B.4): SOLO super_admin (RLS "Admin ezpay actualiza empresas"; no hay policy de
-- admin_pais). El alcance de pais lo da la RLS; el guard NO lo re-decide.
-- NO SECURITY DEFINER, search_path ''. IS DISTINCT FROM (nunca <>). Cubre INSERT (fuerza 'pendiente'
-- para no privilegiados; registrar_proveedor corre como postgres -> exento).
CREATE OR REPLACE FUNCTION private.empresas_proveedoras_guard_update()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $g$
DECLARE v_exento boolean;
BEGIN
  v_exento := current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin')
              OR COALESCE(private.tiene_rol(ARRAY['super_admin'::text]), false);

  IF TG_OP = 'INSERT' THEN
    IF NOT v_exento AND NEW.estado IS DISTINCT FROM 'pendiente' THEN
      NEW.estado := 'pendiente';   -- toda empresa creada por un no-privilegiado nace pendiente
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF ( NEW.estado                     IS DISTINCT FROM OLD.estado
    OR NEW.tipo                       IS DISTINCT FROM OLD.tipo
    OR NEW.pais_id                    IS DISTINCT FROM OLD.pais_id
    OR NEW.dias_ventaja_reserva       IS DISTINCT FROM OLD.dias_ventaja_reserva
    OR NEW.ventana_prioridad_visitas  IS DISTINCT FROM OLD.ventana_prioridad_visitas )
  THEN
    IF NOT v_exento THEN
      RAISE EXCEPTION 'No autorizado a modificar estado/tipo/pais/plan de la empresa'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END $g$;

DROP TRIGGER IF EXISTS empresas_proveedoras_guard_update ON public.empresas_proveedoras;
CREATE TRIGGER empresas_proveedoras_guard_update
  BEFORE INSERT OR UPDATE ON public.empresas_proveedoras
  FOR EACH ROW EXECUTE FUNCTION private.empresas_proveedoras_guard_update();

-- ============================================================================================
-- AUTOCHEQUEO
-- ============================================================================================
DO $ac$
DECLARE
  v int; v_txt text;
BEGIN
  -- (1) el CHECK existe
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.empresas_proveedoras'::regclass AND conname='empresas_proveedoras_estado_chk') THEN
    RAISE EXCEPTION 'MIG322: falta el CHECK de estado';
  END IF;

  -- (2) los 4 helpers de identidad contienen 'estado' en su definicion
  SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE (n.nspname||'.'||p.proname) IN ('public.mi_empresa_proveedor','public.mi_rol_proveedor','public.mi_equipo_proveedor','private.pais_de_proveedor')
     AND p.prosrc ~* 'estado';
  IF v <> 4 THEN RAISE EXCEPTION 'MIG322: se esperaban 4 helpers con gate de estado, hay %', v; END IF;

  -- (3) mi_empresa_onboarding / mi_rol_onboarding usados en EXACTAMENTE las 5 policies de onboarding y en ninguna otra
  SELECT count(*) INTO v FROM pg_policies
   WHERE (COALESCE(qual,'')||' '||COALESCE(with_check,'')) ~* 'mi_(empresa|rol)_onboarding'
     AND NOT ( (schemaname='public' AND tablename='pagos_proveedor' AND policyname IN ('Proveedor crea pagos','Proveedor ve pagos segun rol'))
            OR (schemaname='storage' AND tablename='objects' AND policyname IN ('comprobantes_scoped_insert','comprobantes_scoped_select','comprobantes_scoped_update')) );
  IF v <> 0 THEN RAISE EXCEPTION 'MIG322: helper de onboarding usado en % policy(s) fuera del whitelist', v; END IF;
  SELECT count(*) INTO v FROM pg_policies
   WHERE ( (schemaname='public' AND tablename='pagos_proveedor' AND policyname IN ('Proveedor crea pagos','Proveedor ve pagos segun rol'))
        OR (schemaname='storage' AND tablename='objects' AND policyname IN ('comprobantes_scoped_insert','comprobantes_scoped_select','comprobantes_scoped_update')) )
     AND (COALESCE(qual,'')||' '||COALESCE(with_check,'')) ~* 'mi_empresa_onboarding';
  IF v <> 5 THEN RAISE EXCEPTION 'MIG322: mi_empresa_onboarding no esta en las 5 policies de onboarding (hay %)', v; END IF;
  -- y en ninguna FUNCION
  SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','private') AND p.prosrc ~* 'mi_(empresa|rol)_onboarding'
     AND p.proname NOT IN ('mi_empresa_onboarding','mi_rol_onboarding');
  IF v <> 0 THEN RAISE EXCEPTION 'MIG322: helper de onboarding referenciado por % funcion(es)', v; END IF;

  -- (4) las 8 policies del alcance extra ya no contienen 'cuentas_proveedor'
  SELECT count(*) INTO v FROM pg_policies
   WHERE (COALESCE(qual,'')||' '||COALESCE(with_check,'')) ILIKE '%cuentas_proveedor%'
     AND ( (tablename='invitaciones_visitador' AND policyname='invitaciones_insert_admin')
        OR (tablename='visitas_agendadas' AND policyname IN ('Proveedor crea visitas de su empresa','Proveedor cancela sus visitas'))
        OR (tablename='productos_empresa' AND policyname='Proveedor ve productos de su empresa')
        OR (tablename='planes_visitador_contratados' AND policyname='Proveedor ve sus planes visitador')
        OR (tablename='solicitudes_campana' AND policyname='Proveedor ve sus campañas')
        OR (tablename='ubicaciones_medico_proveedor' AND policyname='ubicaciones_select')
        OR (tablename='medicos' AND policyname='Proveedor ve medicos de su pais') );
  IF v <> 0 THEN RAISE EXCEPTION 'MIG322: quedan % policies del alcance extra con cuentas_proveedor', v; END IF;

  -- (5) las 3 de IDENTIDAD/PERFIL, byte a byte iguales al snapshot
  SELECT qual INTO v_txt FROM pg_policies WHERE schemaname='public' AND tablename='cuentas_proveedor' AND policyname='Proveedor admin ve cuentas de su empresa';
  IF v_txt IS DISTINCT FROM '(empresa_id = get_empresa_id_proveedor())' THEN RAISE EXCEPTION 'MIG322: cambio "Proveedor admin ve cuentas": [%]', v_txt; END IF;
  SELECT qual INTO v_txt FROM pg_policies WHERE schemaname='public' AND tablename='empresas_proveedoras' AND policyname='Proveedor ve su propia empresa';
  IF v_txt IS DISTINCT FROM '(id = get_empresa_id_session())' THEN RAISE EXCEPTION 'MIG322: cambio "Proveedor ve su propia empresa": [%]', v_txt; END IF;
  SELECT qual INTO v_txt FROM pg_policies WHERE schemaname='public' AND tablename='empresas_proveedoras' AND policyname='Proveedor actualiza su propia empresa';
  IF v_txt IS DISTINCT FROM E'((id = get_empresa_id_session()) AND (EXISTS ( SELECT 1\n   FROM cuentas_proveedor\n  WHERE ((cuentas_proveedor.id = auth.uid()) AND (cuentas_proveedor.rol_en_empresa = ANY (ARRAY[''admin''::text, ''editor''::text]))))))' THEN
    RAISE EXCEPTION 'MIG322: cambio "Proveedor actualiza su propia empresa": [%]', v_txt;
  END IF;

  -- (6) el guard existe y esta habilitado
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                  WHERE c.oid='public.empresas_proveedoras'::regclass AND t.tgname='empresas_proveedoras_guard_update'
                    AND t.tgenabled='O' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'MIG322: falta el trigger guard habilitado';
  END IF;

  RAISE NOTICE 'MIG322 OK: CHECK + 4 helpers gateados + 2 onboarding (5 policies) + 8 reapuntadas + guard; identidad/perfil intactas';
END $ac$;
