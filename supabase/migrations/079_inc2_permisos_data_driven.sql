-- ============================================================
-- INCREMENTO 2 (paneles) · FRENTE A — Modelo de permisos data-driven (backend)
-- ------------------------------------------------------------
-- Rama: paneles/farmacia-tenant. Salda la deuda de "rol interno" del Inc.1:
-- la edición del tenant ya NO es por mera membresía, sino por PERMISO del rol
-- (data-driven, por tipo de empresa). Incluye el RPC de asignación de roles con
-- jerarquía anti-escalada (el privilegio peligroso).
-- ============================================================

-- 1) Catálogo de roles por tipo de empresa (con NIVEL jerárquico + flag es_admin)
CREATE TABLE IF NOT EXISTS public.roles_empresa_catalogo (
  tipo_empresa text NOT NULL,
  rol          text NOT NULL,
  nivel        integer NOT NULL,        -- mayor nivel = más alto (Admin el máximo)
  es_admin     boolean NOT NULL DEFAULT false,
  label        text,
  PRIMARY KEY (tipo_empresa, rol)
);

-- 2) Catálogo de acciones permitidas por (tipo_empresa, rol)
CREATE TABLE IF NOT EXISTS public.permisos_empresa_rol (
  tipo_empresa text NOT NULL,
  rol          text NOT NULL,
  accion       text NOT NULL,
  PRIMARY KEY (tipo_empresa, rol, accion),
  FOREIGN KEY (tipo_empresa, rol) REFERENCES public.roles_empresa_catalogo(tipo_empresa, rol) ON DELETE CASCADE
);

-- RLS: lectura authenticated, escritura solo super_admin (referencia, como roles_catalogo)
ALTER TABLE public.roles_empresa_catalogo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permisos_empresa_rol  ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "roles_emp_read"   ON public.roles_empresa_catalogo;
DROP POLICY IF EXISTS "roles_emp_write"  ON public.roles_empresa_catalogo;
DROP POLICY IF EXISTS "perm_emp_read"    ON public.permisos_empresa_rol;
DROP POLICY IF EXISTS "perm_emp_write"   ON public.permisos_empresa_rol;
CREATE POLICY "roles_emp_read"  ON public.roles_empresa_catalogo FOR SELECT TO authenticated USING (true);
CREATE POLICY "roles_emp_write" ON public.roles_empresa_catalogo FOR ALL    TO authenticated USING (private.tiene_rol(ARRAY['super_admin'])) WITH CHECK (private.tiene_rol(ARRAY['super_admin']));
CREATE POLICY "perm_emp_read"   ON public.permisos_empresa_rol   FOR SELECT TO authenticated USING (true);
CREATE POLICY "perm_emp_write"  ON public.permisos_empresa_rol   FOR ALL    TO authenticated USING (private.tiene_rol(ARRAY['super_admin'])) WITH CHECK (private.tiene_rol(ARRAY['super_admin']));

-- 3) SEED tipo='farmacia' (matriz aprobada)
INSERT INTO public.roles_empresa_catalogo (tipo_empresa, rol, nivel, es_admin, label) VALUES
  ('farmacia','admin',            100, true,  'Administrador'),
  ('farmacia','gerente_farmacia',  80, false, 'Gerente de Farmacia'),
  ('farmacia','supervisor',        60, false, 'Supervisor'),
  ('farmacia','inventario',        40, false, 'Inventario'),
  ('farmacia','finanzas',          40, false, 'Finanzas'),
  ('farmacia','pagador',           40, false, 'Pagador'),
  ('farmacia','cajero',            20, false, 'Cajero'),
  ('farmacia','dependiente',       20, false, 'Dependiente'),
  ('farmacia','delivery',          20, false, 'Delivery')
ON CONFLICT (tipo_empresa, rol) DO NOTHING;

INSERT INTO public.permisos_empresa_rol (tipo_empresa, rol, accion)
SELECT 'farmacia','admin',            unnest(ARRAY['config_empresa','usuarios_roles','inventario_editar','ventas_caja','delivery','finanzas_reportes','pagos_ezpay'])
UNION ALL SELECT 'farmacia','gerente_farmacia', unnest(ARRAY['config_empresa','usuarios_roles','inventario_editar','ventas_caja','delivery','finanzas_reportes'])
UNION ALL SELECT 'farmacia','supervisor',       unnest(ARRAY['inventario_editar','ventas_caja','delivery','finanzas_reportes'])
UNION ALL SELECT 'farmacia','inventario',       unnest(ARRAY['inventario_editar'])
UNION ALL SELECT 'farmacia','finanzas',         unnest(ARRAY['finanzas_reportes'])
UNION ALL SELECT 'farmacia','pagador',          unnest(ARRAY['pagos_ezpay','finanzas_reportes'])
UNION ALL SELECT 'farmacia','cajero',           unnest(ARRAY['ventas_caja'])
UNION ALL SELECT 'farmacia','dependiente',      unnest(ARRAY['ventas_caja'])
UNION ALL SELECT 'farmacia','delivery',         unnest(ARRAY['delivery'])
ON CONFLICT (tipo_empresa, rol, accion) DO NOTHING;
-- Nota: "solo ver"/"LIMITADO" de la matriz son matices de UI (Inc.2 Frente B);
-- la jerarquía de usuarios_roles la impone el RPC (abajo).

-- 4) Helper private.tiene_permiso(accion): resuelve rol del usuario en su empresa
--    y consulta el catálogo. SECURITY DEFINER + search_path='' + COALESCE (NULL-safe).
CREATE OR REPLACE FUNCTION private.tiene_permiso(p_accion text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT COALESCE((
    SELECT true
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
    JOIN public.permisos_empresa_rol per
      ON per.tipo_empresa = e.tipo
     AND per.rol = cp.rol_en_empresa
     AND per.accion = p_accion
    WHERE cp.id = auth.uid() AND cp.activo = true
    LIMIT 1
  ), false);
$function$;
REVOKE EXECUTE ON FUNCTION private.tiene_permiso(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.tiene_permiso(text) TO authenticated, service_role;

-- 5) Inc.1 policies → ahora por PERMISO (no por mera membresía). Lectura pública intacta.
DROP POLICY IF EXISTS "farmacias_tenant_update" ON public.farmacias;
CREATE POLICY "farmacias_tenant_update" ON public.farmacias
  FOR UPDATE TO authenticated
  USING      (COALESCE(empresa_id = public.mi_empresa_proveedor(), false) AND COALESCE(private.tiene_permiso('config_empresa'), false))
  WITH CHECK (COALESCE(empresa_id = public.mi_empresa_proveedor(), false) AND COALESCE(private.tiene_permiso('config_empresa'), false));

DROP POLICY IF EXISTS "farm_med_tenant_all" ON public.farmacia_medicamentos;
CREATE POLICY "farm_med_tenant_all" ON public.farmacia_medicamentos
  FOR ALL TO authenticated
  USING (
    COALESCE(private.tiene_permiso('inventario_editar'), false)
    AND farmacia_id IN (SELECT f.id FROM public.farmacias f
                        WHERE f.empresa_id IS NOT NULL
                          AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false))
  )
  WITH CHECK (
    COALESCE(private.tiene_permiso('inventario_editar'), false)
    AND farmacia_id IN (SELECT f.id FROM public.farmacias f
                        WHERE f.empresa_id IS NOT NULL
                          AND COALESCE(f.empresa_id = public.mi_empresa_proveedor(), false))
  );

-- 6) RPC asignar_rol_miembro — PRIVILEGIO PELIGROSO (anti-escalada por jerarquía).
--    SECURITY DEFINER + search_path='' + COALESCE. Todo scoped por empresa.
CREATE OR REPLACE FUNCTION public.asignar_rol_miembro(p_target_id uuid, p_nuevo_rol text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_emp uuid; v_tipo text; v_asig_rol text;
  v_asig_nivel integer; v_asig_admin boolean;
  v_target_emp uuid; v_target_rol text; v_target_admin boolean;
  v_nuevo_nivel integer;
BEGIN
  -- (a) El asignador debe poder gestionar usuarios_roles
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes asignar roles';
  END IF;

  -- datos del asignador (su empresa, tipo y rol)
  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Asignador sin empresa activa'; END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_asig_rol;

  -- target: debe existir y ser de LA MISMA empresa (scope)
  SELECT cp.empresa_id, cp.rol_en_empresa INTO v_target_emp, v_target_rol
  FROM public.cuentas_proveedor cp WHERE cp.id = p_target_id;
  IF v_target_emp IS NULL THEN RAISE EXCEPTION 'Miembro destino no existe'; END IF;
  IF v_target_emp <> v_emp THEN
    RAISE EXCEPTION 'No autorizado: el miembro no pertenece a tu empresa';
  END IF;

  -- el rol nuevo debe existir en el catálogo de ese tipo de empresa
  SELECT nivel INTO v_nuevo_nivel
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para tipo %', p_nuevo_rol, v_tipo;
  END IF;

  -- es_admin del rol ACTUAL del target
  SELECT es_admin INTO v_target_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_target_rol;

  -- (b) Nadie modifica/degrada a un Admin salvo otro Admin
  IF COALESCE(v_target_admin, false) AND NOT COALESCE(v_asig_admin, false) THEN
    RAISE EXCEPTION 'No autorizado: solo un Admin puede modificar a otro Admin';
  END IF;

  -- (c) Admin asigna cualquier rol; un NO-admin solo roles de nivel ESTRICTAMENTE inferior
  --     (bloquea Gerente→Admin y Gerente→Gerente).
  IF NOT COALESCE(v_asig_admin, false) THEN
    IF v_nuevo_nivel IS NULL OR v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes asignar roles de nivel inferior al tuyo';
    END IF;
  END IF;

  UPDATE public.cuentas_proveedor SET rol_en_empresa = p_nuevo_rol WHERE id = p_target_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.asignar_rol_miembro(uuid,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.asignar_rol_miembro(uuid,text) TO authenticated, service_role;
