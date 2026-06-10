-- ============================================================
-- 047: RPCs para resolver destinatarios de notificaciones
-- ------------------------------------------------------------
-- Con RLS, el cliente no puede leer usuarios de otros (perfiles/cuentas).
-- Estos RPCs SECURITY DEFINER devuelven los ids para notificar:
--  - obtener_admins_ezpay(): admins de EzPay (para avisos de solicitudes nuevas)
--  - obtener_usuarios_empresa(): usuarios de una empresa proveedora (para
--    avisarle de aprobación/rechazo de su campaña)
-- ============================================================

CREATE OR REPLACE FUNCTION obtener_admins_ezpay()
RETURNS TABLE (user_id UUID)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM perfiles WHERE rol IN ('ezpay_admin', 'super_admin', 'admin_finanzas');
$$;

GRANT EXECUTE ON FUNCTION obtener_admins_ezpay() TO authenticated;

CREATE OR REPLACE FUNCTION obtener_usuarios_empresa(p_empresa_id UUID)
RETURNS TABLE (user_id UUID)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM cuentas_proveedor WHERE empresa_id = p_empresa_id AND activo = true;
$$;

GRANT EXECUTE ON FUNCTION obtener_usuarios_empresa(UUID) TO authenticated;
