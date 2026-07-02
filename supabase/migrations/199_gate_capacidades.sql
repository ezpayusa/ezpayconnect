-- 199 Gate de capacidades por empresa — la pieza central "¿empresa tiene capacidad activa y vigente?"
-- DENY BY DEFAULT: sin fila vigente = NO tiene la capacidad. SOLO crea las funciones; NO se engancha a
-- ninguna RPC de negocio todavía (enrolar_medico, gate de agenda, etc. NO se tocan). El enganche viene
-- después del backfill de capacidades a las empresas existentes.
--
-- Solo lectura sobre empresa_capacidades (+ mi_empresa_proveedor para la de sesión). No tocan agenda de
-- paciente ni visitas. SECURITY DEFINER porque empresa_capacidades está CERRADA a authenticated: la
-- función corre como owner y es la ÚNICA ventana; el cliente nunca lee la tabla directo.

-- ============================================================
-- 1) private.empresa_tiene_capacidad(empresa, capacidad) — plomería para RPCs (esquema private)
-- ============================================================
CREATE OR REPLACE FUNCTION private.empresa_tiene_capacidad(p_empresa_id uuid, p_capacidad_codigo text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.empresa_capacidades ec
    WHERE ec.empresa_id       = p_empresa_id
      AND ec.capacidad_codigo = p_capacidad_codigo
      AND ec.activa           = true
      AND (ec.hasta IS NULL OR ec.hasta > now())
  );
$function$;

REVOKE ALL     ON FUNCTION private.empresa_tiene_capacidad(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.empresa_tiene_capacidad(uuid, text) TO authenticated;

-- ============================================================
-- 2) public.mis_capacidades() — "¿qué capacidades tiene MI empresa?" (empresa derivada de la sesión)
-- ============================================================
CREATE OR REPLACE FUNCTION public.mis_capacidades()
RETURNS TABLE (capacidad_codigo text, hasta timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
  SELECT ec.capacidad_codigo, ec.hasta
  FROM public.empresa_capacidades ec
  WHERE ec.empresa_id = public.mi_empresa_proveedor()   -- NULL si no es proveedor activo → 0 filas
    AND ec.activa     = true
    AND (ec.hasta IS NULL OR ec.hasta > now());
$function$;

REVOKE ALL     ON FUNCTION public.mis_capacidades() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mis_capacidades() TO authenticated;
