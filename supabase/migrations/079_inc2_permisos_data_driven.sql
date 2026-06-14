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
  v_target_emp uuid; v_target_rol text; v_target_admin boolean; v_target_tipo text;
  v_nuevo_nivel integer; v_nuevo_admin boolean;
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

  -- target: debe existir y ser de LA MISMA empresa (scope). Resolvemos su TIPO
  -- explícitamente para validar el rol nuevo contra el tipo del TARGET (ajuste b).
  SELECT cp.empresa_id, cp.rol_en_empresa, e.tipo INTO v_target_emp, v_target_rol, v_target_tipo
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = p_target_id;
  IF v_target_emp IS NULL THEN RAISE EXCEPTION 'Miembro destino no existe'; END IF;
  IF v_target_emp <> v_emp THEN
    RAISE EXCEPTION 'No autorizado: el miembro no pertenece a tu empresa';
  END IF;

  -- (b) el rol nuevo debe existir en el catálogo para el TIPO DEL TARGET
  SELECT nivel, es_admin INTO v_nuevo_nivel, v_nuevo_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_target_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para el tipo de empresa del miembro (%)', p_nuevo_rol, v_target_tipo;
  END IF;

  -- es_admin del rol ACTUAL del target (en su propio tipo)
  SELECT es_admin INTO v_target_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_target_tipo AND rol = v_target_rol;

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

  -- (d) Protección del ÚLTIMO Admin: la operación no puede dejar a la empresa sin Admin activo.
  IF COALESCE(v_target_admin, false) AND NOT COALESCE(v_nuevo_admin, false)
     AND (SELECT count(*) FROM public.cuentas_proveedor cp2
          JOIN public.roles_empresa_catalogo rc
            ON rc.tipo_empresa = v_target_tipo AND rc.rol = cp2.rol_en_empresa
          WHERE cp2.empresa_id = v_emp AND cp2.activo = true AND rc.es_admin) <= 1
  THEN
    RAISE EXCEPTION 'No autorizado: la empresa quedaría sin ningún Admin activo';
  END IF;

  UPDATE public.cuentas_proveedor SET rol_en_empresa = p_nuevo_rol WHERE id = p_target_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.asignar_rol_miembro(uuid,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.asignar_rol_miembro(uuid,text) TO authenticated, service_role;

-- 6b) RPC alta_miembro_farmacia — ÚNICO camino para CREAR un miembro de farmacia
--     (INSERT en cuentas_proveedor con rol). Misma jerarquía que asignar_rol_miembro.
--     El INSERT directo a cuentas_proveedor ya está cerrado (sin política INSERT + RLS),
--     así que este RPC SECURITY DEFINER (owner) es la única vía. p_user_id debe ser un
--     auth.users existente sin cuenta de proveedor (el alta NO reduce admins → sin guard
--     de último-admin). El alta NO puede reducir admins, por eso no lleva ese guard.
CREATE OR REPLACE FUNCTION public.alta_miembro_farmacia(
  p_user_id uuid, p_empresa_id uuid, p_nombre text, p_email text,
  p_nuevo_rol text, p_telefono text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_emp uuid; v_tipo text; v_asig_rol text; v_asig_nivel integer; v_asig_admin boolean;
  v_nuevo_nivel integer;
BEGIN
  -- (a) el que da de alta necesita usuarios_roles
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes dar de alta miembros';
  END IF;

  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Asignador sin empresa activa'; END IF;

  -- (b) alta SOLO en su misma empresa
  IF p_empresa_id IS DISTINCT FROM v_emp THEN
    RAISE EXCEPTION 'No autorizado: solo puedes dar de alta en tu propia empresa';
  END IF;

  -- este camino data-driven es para farmacia (otros tipos usan su flujo legado)
  IF v_tipo <> 'farmacia' THEN
    RAISE EXCEPTION 'Alta data-driven disponible solo para empresas tipo farmacia';
  END IF;

  -- (c) nuevo_rol debe existir para el tipo de la empresa
  SELECT nivel INTO v_nuevo_nivel
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para tipo %', p_nuevo_rol, v_tipo;
  END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_asig_rol;

  -- (d) Admin da de alta cualquier rol; un NO-admin solo nivel ESTRICTAMENTE inferior
  IF NOT COALESCE(v_asig_admin, false) THEN
    IF v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes dar de alta roles de nivel inferior al tuyo';
    END IF;
  END IF;

  -- (e) el usuario no debe tener ya una cuenta de proveedor
  IF EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'El usuario ya tiene una cuenta de proveedor';
  END IF;

  INSERT INTO public.cuentas_proveedor (id, empresa_id, nombre_completo, email, telefono, rol_en_empresa, activo)
  VALUES (p_user_id, v_emp, p_nombre, p_email, p_telefono, p_nuevo_rol, true);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.alta_miembro_farmacia(uuid,uuid,text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.alta_miembro_farmacia(uuid,uuid,text,text,text,text) TO authenticated, service_role;

-- ============================================================
-- 7) AJUSTE (a) — asignar_rol_miembro como ÚNICO camino para tocar rol_en_empresa
-- ------------------------------------------------------------
-- Estado verificado: cuentas_proveedor tiene RLS activo y NINGUNA política
-- UPDATE/INSERT → la escritura directa por authenticated/anon ya está denegada.
-- (a.1) Defensa en profundidad a nivel COLUMNA: aunque algún día se añada una
-- política UPDATE, la columna del rol no podrá escribirse por el cliente. Las
-- funciones SECURITY DEFINER corren como owner → no les afecta este REVOKE.
REVOKE UPDATE (rol_en_empresa) ON public.cuentas_proveedor FROM authenticated, anon;

-- (a.2) Cerrar la PUERTA LATERAL de los RPC legados para FARMACIA: ambos son
-- admin-only y usan una lista de roles hardcodeada (no-farmacia), pero un admin
-- de farmacia podría usarlos para fijar roles saltándose la jerarquía data-driven.
-- Para tipo='farmacia' obligan a usar asignar_rol_miembro. Laboratorio/visitador
-- (su catálogo vive en permisos.ts) quedan INTACTOS.
CREATE OR REPLACE FUNCTION public.cambiar_rol_proveedor(p_cuenta_id uuid, p_rol text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_empresa uuid; v_caller_rol text; v_caller_tipo text; v_target_empresa uuid;
BEGIN
  SELECT cp.empresa_id, cp.rol_en_empresa, e.tipo
    INTO v_caller_empresa, v_caller_rol, v_caller_tipo
  FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid();

  -- Camino único para farmacia: la jerarquía data-driven la impone asignar_rol_miembro
  IF v_caller_tipo = 'farmacia' THEN
    RAISE EXCEPTION 'En farmacia los roles se cambian con asignar_rol_miembro (jerarquía data-driven)';
  END IF;

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'No autorizado: solo un administrador puede cambiar roles';
  END IF;
  IF p_rol NOT IN ('admin','supervisor','visitador_medico','catalogo','marketing','finanzas','lectura') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_rol;
  END IF;
  SELECT empresa_id INTO v_target_empresa FROM cuentas_proveedor WHERE id = p_cuenta_id;
  IF v_target_empresa IS NULL THEN RAISE EXCEPTION 'La cuenta no existe'; END IF;
  IF v_target_empresa IS DISTINCT FROM v_caller_empresa THEN
    RAISE EXCEPTION 'La cuenta no pertenece a tu empresa';
  END IF;
  IF p_cuenta_id = auth.uid() AND p_rol <> 'admin'
     AND (SELECT count(*) FROM cuentas_proveedor
          WHERE empresa_id = v_caller_empresa AND rol_en_empresa = 'admin' AND activo = true) <= 1 THEN
    RAISE EXCEPTION 'No puedes quitarte el rol de administrador: la empresa quedaría sin administradores';
  END IF;
  UPDATE cuentas_proveedor SET rol_en_empresa = p_rol, updated_at = now() WHERE id = p_cuenta_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.invitar_miembro_proveedor(p_email text, p_nombre text, p_rol text, p_telefono text DEFAULT NULL::text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa_id uuid; v_caller_rol text; v_caller_tipo text; v_token uuid;
BEGIN
  SELECT cp.empresa_id, cp.rol_en_empresa, e.tipo
    INTO v_empresa_id, v_caller_rol, v_caller_tipo
  FROM cuentas_proveedor cp JOIN empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid();

  -- Farmacia: el alta/rol pasa por el flujo data-driven, no por esta invitación legada
  IF v_caller_tipo = 'farmacia' THEN
    RAISE EXCEPTION 'En farmacia el alta de personal usa el flujo data-driven (no esta invitación legada)';
  END IF;

  IF v_caller_rol IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'No autorizado: solo un administrador puede invitar miembros';
  END IF;
  IF p_rol NOT IN ('admin','supervisor','visitador_medico','catalogo','marketing','finanzas','lectura') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_rol;
  END IF;
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'El email es obligatorio';
  END IF;
  INSERT INTO invitaciones_visitador (empresa_id, email, nombre_completo, telefono, rol, estado, expires_at)
  VALUES (v_empresa_id, lower(trim(p_email)), p_nombre, p_telefono, p_rol, 'pendiente', now() + interval '7 days')
  RETURNING token INTO v_token;
  RETURN v_token;
END;
$function$;

-- Nota (Frente B): el alta de personal de FARMACIA (invitación + registro con rol
-- data-driven) se construirá en el portal /farmacia/*; la edge function
-- invitar-visitador y registrar_visitador_desde_invitacion siguen sirviendo al
-- flujo de visitadores (no fijan roles de farmacia; visitador_medico no tiene
-- permisos de farmacia). Pendiente anotado, no es vía de escalada.
