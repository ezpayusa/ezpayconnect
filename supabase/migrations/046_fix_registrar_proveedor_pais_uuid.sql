-- ============================================================
-- 046: Corregir registrar_proveedor — p_pais_id INTEGER -> UUID
-- ------------------------------------------------------------
-- empresas_proveedoras.pais_id es uuid (FK configuracion_pais), pero el RPC
-- declaraba p_pais_id INTEGER -> error 42804 al registrar proveedor.
-- Se hace DROP + CREATE porque CREATE OR REPLACE no puede cambiar el tipo
-- de un parámetro. El cuerpo es idéntico al de producción.
-- ============================================================

DROP FUNCTION IF EXISTS registrar_proveedor(text, text, text, integer, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.registrar_proveedor(
  p_nombre_empresa text,
  p_tipo text,
  p_ruc_nit text,
  p_pais_id uuid,
  p_ciudad text,
  p_direccion text,
  p_email_contacto text,
  p_telefono text,
  p_nombre_completo text,
  p_email text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_empresa_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  INSERT INTO empresas_proveedoras (
    nombre_empresa, tipo, ruc_nit, pais_id, ciudad, direccion, email_contacto, telefono, estado
  ) VALUES (
    p_nombre_empresa, p_tipo, p_ruc_nit, p_pais_id, p_ciudad, p_direccion, p_email_contacto, p_telefono, 'pendiente'
  ) RETURNING id INTO v_empresa_id;

  INSERT INTO cuentas_proveedor (
    id, empresa_id, nombre_completo, email, rol_en_empresa, activo
  ) VALUES (
    v_user_id, v_empresa_id, p_nombre_completo, p_email, 'admin', true
  );

  RETURN v_empresa_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION registrar_proveedor(text, text, text, uuid, text, text, text, text, text, text) TO authenticated;
