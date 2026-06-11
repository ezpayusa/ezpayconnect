-- ============================================================
-- 048: Roles del proveedor — helpers + RPC para asignar roles
-- ------------------------------------------------------------
-- Base para el sistema de roles del panel de proveedores (confidencialidad
-- y distribución de trabajo). Catálogo de roles (rol_en_empresa):
--   admin, supervisor, visitador_medico, catalogo, marketing, finanzas, lectura
-- (legacy tolerados: editor≈admin, viewer≈lectura)
-- ============================================================

-- Empresa del usuario actual (cualquier rol). Distinto de get_empresa_id_proveedor()
-- que solo devuelve valor para admin; este sirve para políticas de cualquier miembro.
CREATE OR REPLACE FUNCTION mi_empresa_proveedor()
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT empresa_id FROM cuentas_proveedor WHERE id = auth.uid() LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION mi_empresa_proveedor() TO authenticated;

-- Rol del usuario actual dentro de su empresa proveedora.
CREATE OR REPLACE FUNCTION mi_rol_proveedor()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT rol_en_empresa FROM cuentas_proveedor WHERE id = auth.uid() LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION mi_rol_proveedor() TO authenticated;

-- Cambiar el rol de un miembro de la empresa. Solo un admin de la MISMA empresa
-- puede hacerlo. SECURITY DEFINER porque cuentas_proveedor no tiene policy UPDATE
-- (y no queremos abrir UPDATE general, solo este cambio controlado).
CREATE OR REPLACE FUNCTION cambiar_rol_proveedor(p_cuenta_id uuid, p_rol text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_empresa uuid;
  v_caller_rol text;
  v_target_empresa uuid;
BEGIN
  SELECT empresa_id, rol_en_empresa INTO v_caller_empresa, v_caller_rol
  FROM cuentas_proveedor WHERE id = auth.uid();

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'No autorizado: solo un administrador puede cambiar roles';
  END IF;

  IF p_rol NOT IN ('admin','supervisor','visitador_medico','catalogo','marketing','finanzas','lectura') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_rol;
  END IF;

  SELECT empresa_id INTO v_target_empresa FROM cuentas_proveedor WHERE id = p_cuenta_id;
  IF v_target_empresa IS NULL THEN
    RAISE EXCEPTION 'La cuenta no existe';
  END IF;
  IF v_target_empresa IS DISTINCT FROM v_caller_empresa THEN
    RAISE EXCEPTION 'La cuenta no pertenece a tu empresa';
  END IF;

  -- Evitar que el admin se quite a sí mismo el último admin (se queda sin admin).
  IF p_cuenta_id = auth.uid() AND p_rol <> 'admin'
     AND (SELECT count(*) FROM cuentas_proveedor
          WHERE empresa_id = v_caller_empresa AND rol_en_empresa = 'admin' AND activo = true) <= 1 THEN
    RAISE EXCEPTION 'No puedes quitarte el rol de administrador: la empresa quedaría sin administradores';
  END IF;

  UPDATE cuentas_proveedor
  SET rol_en_empresa = p_rol, updated_at = now()
  WHERE id = p_cuenta_id;
END;
$$;
GRANT EXECUTE ON FUNCTION cambiar_rol_proveedor(uuid, text) TO authenticated;
