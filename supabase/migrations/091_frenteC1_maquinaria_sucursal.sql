-- ============================================================
-- FRENTE C.1 · Maquinaria de sucursal (INERTE) — SIN tocar ninguna policy/RPC viva
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes rojo-primero (P175–P179). Aditivo/reversible.
-- Alcance v1: SOLO farmacia (farmacias = tabla de sucursales). Labs/visitadores fuera.
--
-- Esta migración NO refina ninguna policy ni RPC existente (eso es C.2/092). Aquí solo
-- se añade la maquinaria: columna usuario→sucursal, helper, permiso y RPC de creación.
-- Es INERTE para el comportamiento actual: todos los usuarios quedan sucursal_id=NULL
-- (grandfather = empresa-wide), y el término de sucursal aún no se ANDea en ningún lado.
--
-- Default DENEGAR del eje (se activa en C.2): el término sucursal será CONJUNTIVO
-- (AND) sobre el check de empresa ya vivo → solo restringe, nunca otorga.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Usuario → sucursal (opt-in; NULL = empresa-wide grandfather = comportamiento actual)
-- ------------------------------------------------------------
ALTER TABLE public.cuentas_proveedor
  ADD COLUMN IF NOT EXISTS sucursal_id integer;
-- FK ON DELETE RESTRICT = FAIL-CLOSED: no se puede borrar una sucursal con staff atado;
-- hay que reasignar/remover primero. SET NULL sería FAIL-OPEN (un usuario scoped a X pasaría
-- en silencio a NULL = empresa-wide al borrarse X). Un eje de aislamiento no se disuelve en
-- acceso más amplio → RESTRICT, coherente con default DENEGAR. (Constraint nombrado para
-- drop+re-add idempotente.) No hay path de borrado de sucursal en v1; el FK queda correcto ya.
ALTER TABLE public.cuentas_proveedor DROP CONSTRAINT IF EXISTS cuentas_proveedor_sucursal_id_fkey;
ALTER TABLE public.cuentas_proveedor
  ADD CONSTRAINT cuentas_proveedor_sucursal_id_fkey
  FOREIGN KEY (sucursal_id) REFERENCES public.farmacias(id) ON DELETE RESTRICT;
COMMENT ON COLUMN public.cuentas_proveedor.sucursal_id IS
  'Sucursal (farmacias.id) a la que el usuario está atado. NULL = alcance empresa (ve todas las sucursales de su empresa; grandfather de no-regresión). FK ON DELETE RESTRICT (fail-closed). La asignación va en C.2 (asignar_sucursal_a_miembro, con guardas anti-escalada).';

-- ------------------------------------------------------------
-- 2) Helper private.mi_sucursal() — null-safe + robusto a cardinalidad (LIMIT 1).
--    Devuelve NULL tanto para empresa-wide (sucursal_id NULL) COMO para no-proveedor
--    (sin fila en cuentas_proveedor). IMPORTANTE: quien gatea al no-proveedor es el
--    término de EMPRESA (mi_empresa_proveedor() match), NO el de sucursal; el término
--    sucursal "NULL → permisivo" SOLO se alcanza DESPUÉS de pasar el match de empresa.
--    Por eso un no-proveedor (mi_sucursal()=NULL) nunca entra: lo frena el término empresa.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.mi_sucursal()
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT cp.sucursal_id
  FROM public.cuentas_proveedor cp
  WHERE cp.id = auth.uid()
  LIMIT 1;   -- PK garantiza ≤1 fila; LIMIT 1 evita "more than one row" ante cualquier anomalía
$function$;
REVOKE EXECUTE ON FUNCTION private.mi_sucursal() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.mi_sucursal() TO authenticated;

-- ------------------------------------------------------------
-- 3) Permiso nuevo sucursales_gestionar — default DENY (solo admin + gerente_farmacia).
--    El catálogo de permisos solo lo escribe super_admin (esta migración corre como owner).
-- ------------------------------------------------------------
INSERT INTO public.permisos_empresa_rol (tipo_empresa, rol, accion)
SELECT 'farmacia', r, 'sucursales_gestionar'
FROM unnest(ARRAY['admin','gerente_farmacia']) AS r
ON CONFLICT (tipo_empresa, rol, accion) DO NOTHING;

-- ------------------------------------------------------------
-- 4) RPC crear_sucursal — empresa FORZADA (jamás del input). Patrón cargar_catalogo_farmacia.
--    DEFINER + search_path='' + schema-calificado. Gate: tiene_permiso('sucursales_gestionar').
--    pais_id derivado de la empresa. GUARD: sin empresa → RAISE limpio. (farmacias no tiene
--    triggers → no hay función de trigger sin search_path antes del INSERT, nota 18.)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_sucursal(
  p_nombre text,
  p_direccion text DEFAULT NULL,
  p_telefono text DEFAULT NULL,
  p_encargado text DEFAULT NULL,
  p_horario text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_emp uuid; v_pais uuid; v_id integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicia sesión';
  END IF;
  IF NOT COALESCE(private.tiene_permiso('sucursales_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede gestionar sucursales';
  END IF;
  v_emp := public.mi_empresa_proveedor();   -- empresa FORZADA del actor; NUNCA de un parámetro
  IF v_emp IS NULL THEN
    RAISE EXCEPTION 'No autorizado: sin empresa proveedora';
  END IF;
  IF p_nombre IS NULL OR length(btrim(p_nombre)) = 0 THEN
    RAISE EXCEPTION 'Nombre de sucursal requerido';
  END IF;

  SELECT e.pais_id INTO v_pais FROM public.empresas_proveedoras e WHERE e.id = v_emp;

  INSERT INTO public.farmacias
    (nombre, empresa_id, tipo, pais_id, direccion, telefono, encargado, horario, activo)
  VALUES
    (btrim(p_nombre), v_emp, 'farmacia', v_pais,
     NULLIF(btrim(COALESCE(p_direccion,'')),''),
     NULLIF(btrim(COALESCE(p_telefono,'')),''),
     NULLIF(btrim(COALESCE(p_encargado,'')),''),
     NULLIF(btrim(COALESCE(p_horario,'')),''),
     true)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.crear_sucursal(text, text, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_sucursal(text, text, text, text, text) TO authenticated, service_role;
