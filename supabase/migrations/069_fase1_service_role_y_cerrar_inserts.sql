-- ============================================================
-- FASE 1 · Bloque C — service_all → service_role + cerrar INSERT abiertos
-- ------------------------------------------------------------
-- Objetivo: quitar el acceso de {public} (anon + authenticated) a tablas que
-- hoy quedan totalmente abiertas por políticas pensadas para el service role,
-- y cerrar los INSERT WITH CHECK(true) que dejan insertar a cualquiera.
--
-- Verificado ANTES de tocar (no rompe nada legítimo):
--  * medico_clinicas, recordatorios: SIN uso directo desde el frontend
--    (solo RPC SECURITY DEFINER / edge functions con service_role).
--  * invitaciones_clinica/medico: el frontend solo hace .select('*') en las
--    páginas admin-ezpay → cubierto por las políticas *_admin_all (super_admin);
--    creación/validación van por edge functions con service_role.
--  * push_subscriptions: el frontend hace insert/select/delete directo, PERO
--    ya existen políticas por-usuario (auth.uid()=user_id) que lo cubren → la
--    política service_all es redundante para el cliente.
--  * notificaciones/cuentas_proveedor/empresas_proveedoras: NINGÚN INSERT
--    directo desde el cliente; todo va por RPC definer (notificar_*,
--    registrar_proveedor) cuyo owner=postgres tiene rolbypassrls=true → siguen
--    funcionando sin la política pública.
--
-- Nota: service_role tiene BYPASSRLS, así que una política `TO service_role`
-- es documentativa (belt-and-suspenders); lo importante es retirar {public}.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Reasignar las 5 políticas "service_all" de {public} → service_role
-- ------------------------------------------------------------

-- invitaciones_clinica
DROP POLICY IF EXISTS "invitaciones_clinica_service_all" ON invitaciones_clinica;
CREATE POLICY "invitaciones_clinica_service_all" ON invitaciones_clinica
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- invitaciones_medico
DROP POLICY IF EXISTS "invitaciones_medico_service_all" ON invitaciones_medico;
CREATE POLICY "invitaciones_medico_service_all" ON invitaciones_medico
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- medico_clinicas
DROP POLICY IF EXISTS "Service role all medico_clinicas" ON medico_clinicas;
CREATE POLICY "Service role all medico_clinicas" ON medico_clinicas
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- push_subscriptions  (las políticas por-usuario auth.uid()=user_id se mantienen)
DROP POLICY IF EXISTS "Service role all push subscriptions" ON push_subscriptions;
CREATE POLICY "Service role all push subscriptions" ON push_subscriptions
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- recordatorios
DROP POLICY IF EXISTS "recordatorios_service_all" ON recordatorios;
CREATE POLICY "recordatorios_service_all" ON recordatorios
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ------------------------------------------------------------
-- 2. Cerrar los INSERT WITH CHECK(true) abiertos a {public}
--    (los inserts legítimos van por RPC definer con bypassrls)
-- ------------------------------------------------------------

-- notificaciones: se insertan SOLO vía notificar_* (SECURITY DEFINER)
DROP POLICY IF EXISTS "notificaciones_insert" ON notificaciones;
DROP POLICY IF EXISTS "notificaciones_service_insert" ON notificaciones;

-- cuentas_proveedor: se crea vía registrar_proveedor (SECURITY DEFINER)
DROP POLICY IF EXISTS "Cuenta proveedor se inserta publicamente" ON cuentas_proveedor;

-- empresas_proveedoras: se crea vía registrar_proveedor (SECURITY DEFINER)
DROP POLICY IF EXISTS "Cualquiera inserta empresas" ON empresas_proveedoras;
