-- ============================================================
-- FASE 6 — Alinear políticas administrativas al catálogo de roles
-- ------------------------------------------------------------
-- ⚠️ ORDEN DE DESPLIEGUE (replicar en prod, función ANTES del FK):
--   1. supabase functions deploy crear-staff-clinica   (escribe 'gerente', válido c/o sin FK)
--   2. aplicar esta migración (políticas + FK + NOT NULL)
--   3. harness P1–P54
--   4. verificación HTTP de crear-staff
-- Si el FK se aplica ANTES de redeployar la función, la versión vieja inserta
-- 'secretaria'/'asistente' → FK 23503 → creación de staff ROTA.
-- ------------------------------------------------------------
-- Quita ramas de roles FANTASMA (admin, admin_pais, ezpay_admin,
-- admin_finanzas, admin_publicidad, admin_ventas, farmaceutico) de las
-- políticas del sistema perfiles.rol y las colapsa a roles REALES del
-- catálogo (super_admin como único admin de sistema; se conservan medico/
-- etc.). El back-office EzPay ya funcionaba SOLO para super_admin (los
-- roles granulares nunca existieron). Las políticas del sistema PROVEEDOR
-- (mi_rol_proveedor: 'admin' es rol real de empresa) y los falsos positivos
-- (planes_base/_configuracion: 'farmaceutico' es un VALOR de tipo) se dejan
-- intactos. Nota: en USING/WITH CHECK un predicado NULL → DENIEGA (fail-
-- closed), así que no hace falta COALESCE aquí.
-- ============================================================

DROP POLICY IF EXISTS "auditoria_select_admin" ON public.auditoria_logs;
CREATE POLICY "auditoria_select_admin" ON public.auditoria_logs AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

-- (nombre original con mojibake en BD: "Admin ve métricas" → DROP dinámico + nombre ASCII)
DO $$ DECLARE pn text; BEGIN
  FOR pn IN SELECT policyname FROM pg_policies
            WHERE schemaname='public' AND tablename='campana_metricas' AND policyname LIKE 'Admin ve m%tricas'
  LOOP EXECUTE format('DROP POLICY %I ON public.campana_metricas', pn); END LOOP;
END $$;
DROP POLICY IF EXISTS "campana_metricas admin select" ON public.campana_metricas;
CREATE POLICY "campana_metricas admin select" ON public.campana_metricas AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve campanas de su pais" ON public.campanas_publicitarias;
CREATE POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "Admin ve citas de su pais" ON public.citas;
CREATE POLICY "Admin ve citas de su pais" ON public.citas AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "Admin ve clinicas de su pais" ON public.clinicas;
CREATE POLICY "Admin ve clinicas de su pais" ON public.clinicas AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "Admin ezpay actualiza configuracion" ON public.configuracion_sistema;
CREATE POLICY "Admin ezpay actualiza configuracion" ON public.configuracion_sistema AS PERMISSIVE FOR ALL TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "editar_configuracion" ON public.configuracion_sistema;  -- redundante (super_admin cubre vía política hermana)

DROP POLICY IF EXISTS "cuentas_banco_admin" ON public.cuentas_bancarias_pais;
CREATE POLICY "cuentas_banco_admin" ON public.cuentas_bancarias_pais AS PERMISSIVE FOR ALL TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')))
  WITH CHECK ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ezpay ve cuentas proveedor" ON public.cuentas_proveedor;
CREATE POLICY "Admin ezpay ve cuentas proveedor" ON public.cuentas_proveedor AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ezpay ve toda disponibilidad" ON public.disponibilidad_medico;
CREATE POLICY "Admin ezpay ve toda disponibilidad" ON public.disponibilidad_medico AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ezpay actualiza empresas" ON public.empresas_proveedoras;
CREATE POLICY "Admin ezpay actualiza empresas" ON public.empresas_proveedoras AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ezpay ve todas las empresas" ON public.empresas_proveedoras;
CREATE POLICY "Admin ezpay ve todas las empresas" ON public.empresas_proveedoras AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve facturas de su pais" ON public.facturas;
CREATE POLICY "Admin ve facturas de su pais" ON public.facturas AS PERMISSIVE FOR SELECT TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "editar_medicamentos" ON public.farmacia_medicamentos;
CREATE POLICY "editar_medicamentos" ON public.farmacia_medicamentos AS PERMISSIVE FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')))
  WITH CHECK ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "ver_medicamentos" ON public.farmacia_medicamentos;
CREATE POLICY "ver_medicamentos" ON public.farmacia_medicamentos AS PERMISSIVE FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = ANY (ARRAY['medico', 'super_admin']::text[]))));

DROP POLICY IF EXISTS "invitaciones_clinica_admin_all" ON public.invitaciones_clinica;
CREATE POLICY "invitaciones_clinica_admin_all" ON public.invitaciones_clinica AS PERMISSIVE FOR ALL TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "invitaciones_medico_admin_all" ON public.invitaciones_medico;
CREATE POLICY "invitaciones_medico_admin_all" ON public.invitaciones_medico AS PERMISSIVE FOR ALL TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve medicos de su pais" ON public.medicos;
CREATE POLICY "Admin ve medicos de su pais" ON public.medicos AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "Admin ve notificaciones de su pais" ON public.notificaciones;
CREATE POLICY "Admin ve notificaciones de su pais" ON public.notificaciones AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "notificaciones_admin_all" ON public.notificaciones;  -- redundante (super_admin cubre vía política hermana)

DROP POLICY IF EXISTS "Admin ezpay ve notificaciones" ON public.notificaciones_email;
CREATE POLICY "Admin ezpay ve notificaciones" ON public.notificaciones_email AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve pacientes de su pais" ON public.pacientes;
CREATE POLICY "Admin ve pacientes de su pais" ON public.pacientes AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "Admin ezpay gestiona pagos" ON public.pagos_proveedor;
CREATE POLICY "Admin ezpay gestiona pagos" ON public.pagos_proveedor AS PERMISSIVE FOR ALL TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve perfiles de su pais" ON public.perfiles;
CREATE POLICY "Admin ve perfiles de su pais" ON public.perfiles AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "Admins pueden insertar perfiles" ON public.perfiles;
CREATE POLICY "Admins pueden insertar perfiles" ON public.perfiles AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin gestiona config" ON public.planes_publicidad_config;
CREATE POLICY "Admin gestiona config" ON public.planes_publicidad_config AS PERMISSIVE FOR ALL TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ezpay gestiona planes visitador" ON public.planes_visitador_contratados;
CREATE POLICY "Admin ezpay gestiona planes visitador" ON public.planes_visitador_contratados AS PERMISSIVE FOR ALL TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ezpay ve todos los productos" ON public.productos_empresa;
CREATE POLICY "Admin ezpay ve todos los productos" ON public.productos_empresa AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve recetas de su pais" ON public.recetas;
CREATE POLICY "Admin ve recetas de su pais" ON public.recetas AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "ver_recordatorios" ON public.recordatorios_citas;
CREATE POLICY "ver_recordatorios" ON public.recordatorios_citas AS PERMISSIVE FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = ANY (ARRAY['medico', 'super_admin']::text[]))));

DROP POLICY IF EXISTS "crear_recordatorios_prog" ON public.recordatorios_programados;
CREATE POLICY "crear_recordatorios_prog" ON public.recordatorios_programados AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = ANY (ARRAY['medico', 'super_admin']::text[]))));

DROP POLICY IF EXISTS "ver_recordatorios_prog" ON public.recordatorios_programados;
CREATE POLICY "ver_recordatorios_prog" ON public.recordatorios_programados AS PERMISSIVE FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = ANY (ARRAY['medico', 'super_admin']::text[]))));

DROP POLICY IF EXISTS "Admins crear reportes" ON public.reportes_guardados;
CREATE POLICY "Admins crear reportes" ON public.reportes_guardados AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admins ver reportes" ON public.reportes_guardados;
CREATE POLICY "Admins ver reportes" ON public.reportes_guardados AS PERMISSIVE FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve todo signos vitales" ON public.signos_vitales;
CREATE POLICY "Admin ve todo signos vitales" ON public.signos_vitales AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

-- (nombres originales con mojibake en BD: "...campañas" → DROP dinámico + nombre ASCII)
DO $$ DECLARE pn text; BEGIN
  FOR pn IN SELECT policyname FROM pg_policies
            WHERE schemaname='public' AND tablename='solicitudes_campana' AND policyname LIKE 'Admin ezpay actualiza campa%as'
  LOOP EXECUTE format('DROP POLICY %I ON public.solicitudes_campana', pn); END LOOP;
  FOR pn IN SELECT policyname FROM pg_policies
            WHERE schemaname='public' AND tablename='solicitudes_campana' AND policyname LIKE 'Admin ezpay ve todas las campa%as'
  LOOP EXECUTE format('DROP POLICY %I ON public.solicitudes_campana', pn); END LOOP;
END $$;
DROP POLICY IF EXISTS "solicitudes_campana admin update" ON public.solicitudes_campana;
CREATE POLICY "solicitudes_campana admin update" ON public.solicitudes_campana AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));
DROP POLICY IF EXISTS "solicitudes_campana admin select" ON public.solicitudes_campana;
CREATE POLICY "solicitudes_campana admin select" ON public.solicitudes_campana AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve solicitudes de su pais" ON public.solicitudes_campana;
CREATE POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

DROP POLICY IF EXISTS "Admins pueden actualizar usuario_roles" ON public.usuario_roles;
CREATE POLICY "Admins pueden actualizar usuario_roles" ON public.usuario_roles AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admins pueden insertar usuario_roles" ON public.usuario_roles;
CREATE POLICY "Admins pueden insertar usuario_roles" ON public.usuario_roles AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admins pueden leer usuario_roles" ON public.usuario_roles;
CREATE POLICY "Admins pueden leer usuario_roles" ON public.usuario_roles AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ezpay ve todas las visitas" ON public.visitas_agendadas;
CREATE POLICY "Admin ezpay ve todas las visitas" ON public.visitas_agendadas AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')));

DROP POLICY IF EXISTS "Admin ve visitas de su pais" ON public.visitas_agendadas;
CREATE POLICY "Admin ve visitas de su pais" ON public.visitas_agendadas AS PERMISSIVE FOR ALL TO public
  USING ((get_auth_user_rol() = 'super_admin'));

-- ============================================================
-- Cierre del fail-open: perfiles.rol no puede salir del catálogo
-- ============================================================
ALTER TABLE public.perfiles ALTER COLUMN rol SET NOT NULL;
ALTER TABLE public.perfiles
  ADD CONSTRAINT perfiles_rol_fkey FOREIGN KEY (rol)
  REFERENCES public.roles_catalogo(codigo);
