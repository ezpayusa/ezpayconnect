-- ============================================================
-- 052: Dar de baja / reactivar miembros del proveedor (despido)
-- ------------------------------------------------------------
-- Una cuenta inactiva (activo=false) pierde TODO acceso a datos de la empresa
-- a nivel de BD: los helpers de RLS devuelven NULL para inactivos, así que
-- todas las políticas por empresa/rol fallan. Reversible (reactivar).
-- ============================================================

-- Los helpers de RLS ahora ignoran a las cuentas inactivas.
CREATE OR REPLACE FUNCTION mi_empresa_proveedor()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true LIMIT 1; $$;

CREATE OR REPLACE FUNCTION mi_rol_proveedor()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT rol_en_empresa FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true LIMIT 1; $$;

-- RPC: admin da de baja / reactiva a un miembro de su empresa.
CREATE OR REPLACE FUNCTION cambiar_estado_miembro_proveedor(p_id uuid, p_activo boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller_rol text;
  v_caller_empresa uuid;
  v_target_empresa uuid;
BEGIN
  SELECT rol_en_empresa, empresa_id INTO v_caller_rol, v_caller_empresa
  FROM cuentas_proveedor WHERE id = auth.uid();

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Solo un administrador puede dar de baja o reactivar miembros';
  END IF;
  IF p_id = auth.uid() THEN
    RAISE EXCEPTION 'No puedes cambiar tu propio estado';
  END IF;

  SELECT empresa_id INTO v_target_empresa FROM cuentas_proveedor WHERE id = p_id;
  IF v_target_empresa IS NULL OR v_target_empresa IS DISTINCT FROM v_caller_empresa THEN
    RAISE EXCEPTION 'Ese usuario no pertenece a tu empresa';
  END IF;

  UPDATE cuentas_proveedor SET activo = p_activo, updated_at = now() WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION cambiar_estado_miembro_proveedor(uuid, boolean) TO authenticated;
