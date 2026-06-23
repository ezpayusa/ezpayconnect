-- ============================================================
-- 139 · Spine sucursales 3.1 — Gestión de sucursales (DORMANT, NO aplicar sin OK)
-- ------------------------------------------------------------
-- farmacias ES la tabla de sucursales. CRUD del admin de farmacia (gate sucursales_gestionar = techo RBAC,
-- mig 117 → solo admin + gerente_farmacia, no concedible por override). Empresa DERIVADA del actor (I3);
-- los RPC con id de entrada (editar/desactivar) validan pertenencia (empresa_id = mi_empresa AND NOT NULL)
-- → cross-empresa estructuralmente imposible + las 6 globales (empresa_id NULL) quedan fuera de alcance.
-- v1 SIN geo (sin lat/lng; dirección texto libre). Fuente única: misma tabla farmacias, sin copia/sync.
-- crear_sucursal: 0 callers en src/ de origin/main (solo probes P176-P180) → el update de unicidad es
-- DORMANT-SAFE; preserva firma + gate + lógica existentes, solo añade el chequeo de unicidad.
-- ============================================================

-- (A) UPDATE crear_sucursal: + unicidad de nombre (case-insensitive, entre activas de la empresa).
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
  -- NUEVO: unicidad de nombre entre sucursales ACTIVAS de la misma empresa (case-insensitive).
  IF EXISTS (SELECT 1 FROM public.farmacias f
             WHERE f.empresa_id = v_emp AND f.activo = true
               AND lower(f.nombre) = lower(btrim(p_nombre))) THEN
    RAISE EXCEPTION 'Ya existe una sucursal activa con ese nombre' USING ERRCODE = '23505';
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

-- (B) listar_sucursales: SOLO las de mi empresa (NOT NULL → excluye globales). Contadores DERIVADOS al vuelo.
CREATE OR REPLACE FUNCTION public.listar_sucursales()
RETURNS TABLE(id integer, nombre text, direccion text, telefono text, encargado text,
              horario text, activo boolean, staff_count bigint, inventario_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_emp uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('sucursales_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede gestionar sucursales';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa proveedora'; END IF;
  RETURN QUERY
    SELECT f.id, f.nombre, f.direccion, f.telefono, f.encargado, f.horario, f.activo,
           (SELECT count(*) FROM public.cuentas_proveedor cp WHERE cp.sucursal_id = f.id AND cp.activo = true),
           (SELECT count(*) FROM public.farmacia_medicamentos fm WHERE fm.farmacia_id = f.id)
    FROM public.farmacias f
    WHERE f.empresa_id = v_emp AND f.empresa_id IS NOT NULL
    ORDER BY f.activo DESC, f.nombre;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.listar_sucursales() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_sucursales() TO authenticated;

-- (C) editar_sucursal: guard pertenencia (id input) + unicidad (excluye self). Sin param empresa.
CREATE OR REPLACE FUNCTION public.editar_sucursal(
  p_sucursal_id integer,
  p_nombre text,
  p_direccion text DEFAULT NULL,
  p_telefono text DEFAULT NULL,
  p_encargado text DEFAULT NULL,
  p_horario text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_emp uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('sucursales_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede gestionar sucursales';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa proveedora'; END IF;
  IF p_nombre IS NULL OR length(btrim(p_nombre)) = 0 THEN RAISE EXCEPTION 'Nombre de sucursal requerido'; END IF;
  -- pertenencia: id es input → guard cross-empresa; empresa_id NOT NULL excluye las globales.
  IF NOT EXISTS (SELECT 1 FROM public.farmacias f
                 WHERE f.id = p_sucursal_id AND f.empresa_id = v_emp AND f.empresa_id IS NOT NULL) THEN
    RAISE EXCEPTION 'No autorizado: la sucursal no pertenece a tu empresa' USING ERRCODE = '42501';
  END IF;
  -- unicidad: otra ACTIVA de la empresa con el mismo nombre (excluye self).
  IF EXISTS (SELECT 1 FROM public.farmacias f
             WHERE f.empresa_id = v_emp AND f.activo = true AND f.id <> p_sucursal_id
               AND lower(f.nombre) = lower(btrim(p_nombre))) THEN
    RAISE EXCEPTION 'Ya existe una sucursal activa con ese nombre' USING ERRCODE = '23505';
  END IF;
  UPDATE public.farmacias SET
    nombre    = btrim(p_nombre),
    direccion = NULLIF(btrim(COALESCE(p_direccion,'')),''),
    telefono  = NULLIF(btrim(COALESCE(p_telefono,'')),''),
    encargado = NULLIF(btrim(COALESCE(p_encargado,'')),''),
    horario   = NULLIF(btrim(COALESCE(p_horario,'')),'')
  WHERE id = p_sucursal_id AND empresa_id = v_emp;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.editar_sucursal(integer, text, text, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.editar_sucursal(integer, text, text, text, text, text) TO authenticated;

-- (D) desactivar_sucursal: soft-delete. Desactivar bloquea si hay staff activo asignado; reactivar valida unicidad.
CREATE OR REPLACE FUNCTION public.desactivar_sucursal(p_sucursal_id integer, p_activo boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_emp uuid; v_nombre text; v_staff integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('sucursales_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede gestionar sucursales';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa proveedora'; END IF;
  -- pertenencia (id input)
  SELECT f.nombre INTO v_nombre FROM public.farmacias f
   WHERE f.id = p_sucursal_id AND f.empresa_id = v_emp AND f.empresa_id IS NOT NULL;
  IF v_nombre IS NULL THEN
    RAISE EXCEPTION 'No autorizado: la sucursal no pertenece a tu empresa' USING ERRCODE = '42501';
  END IF;

  IF p_activo = false THEN
    -- bloquear desactivación si hay personal activo confinado a esta sucursal (protege C.2; sin huérfanos)
    SELECT count(*) INTO v_staff FROM public.cuentas_proveedor cp
     WHERE cp.sucursal_id = p_sucursal_id AND cp.activo = true;
    IF v_staff > 0 THEN
      RAISE EXCEPTION 'No se puede desactivar: % persona(s) activa(s) asignada(s). Reasignalas primero.', v_staff
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- reactivar: no chocar con otra activa del mismo nombre
    IF EXISTS (SELECT 1 FROM public.farmacias f
               WHERE f.empresa_id = v_emp AND f.activo = true AND f.id <> p_sucursal_id
                 AND lower(f.nombre) = lower(v_nombre)) THEN
      RAISE EXCEPTION 'Ya existe una sucursal activa con ese nombre; renombrá antes de reactivar' USING ERRCODE = '23505';
    END IF;
  END IF;

  UPDATE public.farmacias SET activo = p_activo WHERE id = p_sucursal_id AND empresa_id = v_emp;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.desactivar_sucursal(integer, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.desactivar_sucursal(integer, boolean) TO authenticated;
