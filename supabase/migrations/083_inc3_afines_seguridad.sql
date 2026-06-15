-- ============================================================
-- INCREMENTO 3 (paneles) · Empresas Afines — SEGURIDAD (Inc.3.A)
-- ------------------------------------------------------------
-- Rama: paneles/empresas-afines.  ⚠️ PAQUETE DE REVISIÓN — NO aplicar sin OK.
-- Modelo confirmado: el afín COMPRA PUBLICIDAD a EzPay (no marketplace). Reusa
-- solicitudes_campana → aprobar_solicitud_campana → campanas_publicitarias +
-- pagos_proveedor. Catálogo del afín = productos_empresa. (Ver docs §6.)
--
-- Contenido:
--  1) Seed roles_empresa_catalogo + permisos_empresa_rol para tipo='empresa_afin'
--     (matriz aprobada). Patrón data-driven idéntico a farmacia (079).
--  2) Generalizar alta_miembro_farmacia + invitar_miembro_farmacia a
--     tipo IN ('farmacia','empresa_afin') (mismo nombre legado; misma jerarquía
--     anti-escalada + último-admin; sin nuevos privilegios).
--  3) Cerrar la PUERTA LATERAL legada (cambiar_rol_proveedor / invitar_miembro_proveedor)
--     también para empresa_afin → camino único = data-driven (como farmacia).
--  4) BARRERA: los productos de empresa_afin NO aparecen en la búsqueda del médico.
--  5) Gestión de productos del afín por permiso data-driven 'productos_editar'
--     (además del string-list legado) → honra la matriz (gerente/catálogo).
--  6) Publicidad data-driven: solicitudes_campana INSERT/UPDATE por
--     tiene_permiso('publicidad_gestionar') (además del legado admin/editor).
--  7) Seed de productos ficticios del afín (datos de prueba).
--
-- Invariantes de seguridad reutilizados: SECURITY DEFINER + search_path=''
-- (helpers), COALESCE(...,false) NULL-safe en predicados RLS, aislamiento por
-- empresa vía mi_empresa_proveedor(). No se relaja ninguna política existente:
-- solo se AÑADE el camino data-driven y se RESTRINGE la lectura del médico.
-- ============================================================

-- ------------------------------------------------------------
-- 1) SEED roles + permisos para empresa_afin (matriz aprobada)
-- ------------------------------------------------------------
INSERT INTO public.roles_empresa_catalogo (tipo_empresa, rol, nivel, es_admin, label) VALUES
  ('empresa_afin','admin',      100, true,  'Administrador'),
  ('empresa_afin','gerente',     80, false, 'Gerente'),
  ('empresa_afin','catalogo',    40, false, 'Catálogo'),
  ('empresa_afin','marketing',   40, false, 'Marketing'),
  ('empresa_afin','finanzas',    40, false, 'Finanzas'),
  ('empresa_afin','lectura',     10, false, 'Solo lectura')
ON CONFLICT (tipo_empresa, rol) DO NOTHING;

INSERT INTO public.permisos_empresa_rol (tipo_empresa, rol, accion)
SELECT 'empresa_afin','admin',     unnest(ARRAY['config_empresa','usuarios_roles','productos_editar','publicidad_gestionar','pagos_ezpay','finanzas_reportes'])
UNION ALL SELECT 'empresa_afin','gerente',   unnest(ARRAY['config_empresa','usuarios_roles','productos_editar','publicidad_gestionar','finanzas_reportes'])
UNION ALL SELECT 'empresa_afin','catalogo',  unnest(ARRAY['productos_editar'])
UNION ALL SELECT 'empresa_afin','marketing', unnest(ARRAY['publicidad_gestionar'])
UNION ALL SELECT 'empresa_afin','finanzas',  unnest(ARRAY['pagos_ezpay','finanzas_reportes'])
ON CONFLICT (tipo_empresa, rol, accion) DO NOTHING;
-- 'lectura' no recibe acciones de escritura (solo SELECT por las políticas de lectura).

-- ------------------------------------------------------------
-- 2) Generalizar el ALTA data-driven a farmacia + empresa_afin
--    (idéntico a 079 salvo el guard de tipo; toda la lógica ya usa v_tipo)
-- ------------------------------------------------------------
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
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes dar de alta miembros';
  END IF;

  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Asignador sin empresa activa'; END IF;

  IF p_empresa_id IS DISTINCT FROM v_emp THEN
    RAISE EXCEPTION 'No autorizado: solo puedes dar de alta en tu propia empresa';
  END IF;

  -- Alta data-driven: tipos con seed en roles_empresa_catalogo (farmacia + afín).
  IF v_tipo NOT IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'Alta data-driven no disponible para empresas tipo %', v_tipo;
  END IF;

  SELECT nivel INTO v_nuevo_nivel
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para tipo %', p_nuevo_rol, v_tipo;
  END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_asig_rol;

  IF NOT COALESCE(v_asig_admin, false) THEN
    IF v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes dar de alta roles de nivel inferior al tuyo';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'El usuario ya tiene una cuenta de proveedor';
  END IF;

  INSERT INTO public.cuentas_proveedor (id, empresa_id, nombre_completo, email, telefono, rol_en_empresa, activo)
  VALUES (p_user_id, v_emp, p_nombre, p_email, p_telefono, p_nuevo_rol, true);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.alta_miembro_farmacia(uuid,uuid,text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.alta_miembro_farmacia(uuid,uuid,text,text,text,text) TO authenticated, service_role;

-- 2b) Generalizar la INVITACIÓN data-driven (usa v_tipo en lugar del literal 'farmacia')
CREATE OR REPLACE FUNCTION public.invitar_miembro_farmacia(
  p_email text, p_nombre text, p_nuevo_rol text, p_telefono text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_emp uuid; v_tipo text; v_asig_rol text; v_asig_nivel integer; v_asig_admin boolean;
  v_nuevo_nivel integer; v_token uuid;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes invitar personal';
  END IF;

  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Invitador sin empresa activa'; END IF;

  IF v_tipo NOT IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'Invitación data-driven no disponible para empresas tipo %', v_tipo;
  END IF;
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'El email es obligatorio';
  END IF;

  SELECT nivel INTO v_nuevo_nivel
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para tipo %', p_nuevo_rol, v_tipo;
  END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = v_tipo AND rol = v_asig_rol;

  IF NOT COALESCE(v_asig_admin, false) THEN
    IF v_asig_nivel IS NULL OR NOT (v_nuevo_nivel < v_asig_nivel) THEN
      RAISE EXCEPTION 'No autorizado: solo puedes invitar roles de nivel inferior al tuyo';
    END IF;
  END IF;

  -- empresa_id y rol quedan FIJADOS en la invitación (el invitado no los elige).
  INSERT INTO public.invitaciones_visitador (empresa_id, email, nombre_completo, telefono, rol, estado, expires_at)
  VALUES (v_emp, lower(trim(p_email)), p_nombre, p_telefono, p_nuevo_rol, 'pendiente', now() + interval '7 days')
  RETURNING token INTO v_token;

  RETURN v_token;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.invitar_miembro_farmacia(text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.invitar_miembro_farmacia(text,text,text,text) TO authenticated, service_role;

-- 2c) El INSERT directo a invitaciones_visitador: cerrar también para empresa_afin
--     (igual que farmacia: solo el RPC definer crea invitaciones data-driven).
DROP POLICY IF EXISTS "invitaciones_insert_admin" ON public.invitaciones_visitador;
CREATE POLICY "invitaciones_insert_admin" ON public.invitaciones_visitador
  FOR INSERT TO public
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.cuentas_proveedor cp
      JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
      WHERE cp.id = auth.uid()
        AND cp.empresa_id = invitaciones_visitador.empresa_id
        AND cp.activo = true
        AND cp.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text])
        AND e.tipo NOT IN ('farmacia','empresa_afin')   -- data-driven: solo vía RPC
    )
  );

-- ------------------------------------------------------------
-- 3) Cerrar la PUERTA LATERAL legada también para empresa_afin
--    (camino único = asignar_rol_miembro / invitar_miembro_farmacia)
-- ------------------------------------------------------------
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

  -- Tipos data-driven: la jerarquía la impone asignar_rol_miembro
  IF v_caller_tipo IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'En este tipo de empresa los roles se cambian con asignar_rol_miembro (jerarquía data-driven)';
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

  -- Tipos data-driven: el alta/rol pasa por el flujo data-driven (no esta invitación legada)
  IF v_caller_tipo IN ('farmacia','empresa_afin') THEN
    RAISE EXCEPTION 'En este tipo de empresa el alta de personal usa el flujo data-driven (no esta invitación legada)';
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

-- ------------------------------------------------------------
-- 4) BARRERA: el médico NO ve productos de empresa_afin en su búsqueda.
--    (Antes: USING (estado='activo') → cualquier producto activo era visible.)
--    ⚠️ Un subquery directo a empresas_proveedoras dentro de la policy se evalúa
--    BAJO LA RLS DEL QUE LLAMA: el médico no ve filas de empresas_proveedoras
--    (solo super_admin/dueño) → el NOT EXISTS daría TRUE y NO filtraría nada.
--    Por eso usamos un helper SECURITY DEFINER (search_path='') que resuelve el
--    tipo saltándose la RLS. COALESCE NULL-safe: solo excluye si ES afín.
--    El afín sigue viendo SUS productos por "Proveedor ve productos de su empresa";
--    super_admin por "Admin ezpay ve todos los productos".
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.empresa_es_afin(p_empresa_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT COALESCE(
    (SELECT e.tipo = 'empresa_afin' FROM public.empresas_proveedoras e WHERE e.id = p_empresa_id),
    false);
$function$;
REVOKE EXECUTE ON FUNCTION private.empresa_es_afin(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION private.empresa_es_afin(uuid) TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "Médico ve productos activos" ON public.productos_empresa;
CREATE POLICY "Médico ve productos activos" ON public.productos_empresa
  FOR SELECT USING (
    estado = 'activo'
    AND NOT COALESCE(private.empresa_es_afin(empresa_id), false)
  );

-- ------------------------------------------------------------
-- 5) Gestión de productos del afín por permiso data-driven 'productos_editar'
--    (ADEMÁS del string-list legado admin/editor/catalogo, que conserva el
--    comportamiento de laboratorio/proveedor). Honra la matriz: gerente del afín
--    tiene productos_editar pero su rol no está en el string-list legado.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Proveedor gestiona productos segun rol" ON public.productos_empresa;
CREATE POLICY "Proveedor gestiona productos segun rol" ON public.productos_empresa
  FOR ALL TO authenticated                                                     -- gestión: nunca anon (evita evaluar tiene_permiso como anon)
  USING (
    COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
    AND (
      public.mi_rol_proveedor() = ANY (ARRAY['admin','editor','catalogo'])
      OR COALESCE(private.tiene_permiso('productos_editar'), false)
    )
  )
  WITH CHECK (
    COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
    AND (
      public.mi_rol_proveedor() = ANY (ARRAY['admin','editor','catalogo'])
      OR COALESCE(private.tiene_permiso('productos_editar'), false)
    )
  );

-- ------------------------------------------------------------
-- 6) Publicidad data-driven + ANTI-AUTO-APROBACIÓN.
--    Se AÑADE la rama tiene_permiso('publicidad_gestionar') manteniendo el legado
--    admin/editor (lab/proveedor/farmacia). super_admin conserva sus políticas y
--    sigue siendo el ÚNICO que aprueba (vía aprobar_solicitud_campana, definer).
--    ⚠️ 'estado' NO tiene CHECK en BD (texto libre) → la RLS es el único guard de
--    transición. Por eso fijamos el estado por whitelist:
--      · INSERT: empresa forzada (= mi_empresa_proveedor()) + estado inicial NO
--        aprobado (solo 'borrador' | 'enviada'); nunca 'publicada'.
--      · UPDATE: el afín edita el CONTENIDO de SU solicitud no-publicada, pero el
--        NUEVO estado queda atado a ('borrador'|'enviada'|'rechazada') → NO puede
--        pasar a 'publicada' ni a ningún estado de aprobación. Aprobar/publicar =
--        EXCLUSIVO de super_admin. Tampoco puede mover la fila a otra empresa.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Proveedor crea campañas" ON public.solicitudes_campana;
CREATE POLICY "Proveedor crea campañas" ON public.solicitudes_campana
  FOR INSERT TO authenticated
  WITH CHECK (
    COALESCE(empresa_id = public.mi_empresa_proveedor(), false)                 -- empresa forzada
    AND (
      COALESCE(private.tiene_permiso('publicidad_gestionar'), false)
      OR EXISTS (
        SELECT 1 FROM public.cuentas_proveedor cp
        WHERE cp.id = auth.uid()
          AND cp.empresa_id = solicitudes_campana.empresa_id
          AND cp.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text])
      )
    )
    AND estado = ANY (ARRAY['borrador'::text, 'enviada'::text])                  -- nunca nace aprobada
  );

DROP POLICY IF EXISTS "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana;
CREATE POLICY "Proveedor actualiza sus campañas borrador" ON public.solicitudes_campana
  FOR UPDATE TO authenticated
  USING (
    COALESCE(empresa_id = public.mi_empresa_proveedor(), false)                  -- solo filas de su empresa
    AND (
      COALESCE(private.tiene_permiso('publicidad_gestionar'), false)
      OR EXISTS (
        SELECT 1 FROM public.cuentas_proveedor cp
        WHERE cp.id = auth.uid()
          AND cp.empresa_id = solicitudes_campana.empresa_id
          AND cp.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text])
      )
    )
    AND estado = ANY (ARRAY['borrador'::text, 'enviada'::text, 'rechazada'::text]) -- no toca 'publicada'
  )
  WITH CHECK (
    COALESCE(empresa_id = public.mi_empresa_proveedor(), false)                  -- no la mueve a otra empresa
    AND (
      COALESCE(private.tiene_permiso('publicidad_gestionar'), false)
      OR EXISTS (
        SELECT 1 FROM public.cuentas_proveedor cp
        WHERE cp.id = auth.uid()
          AND cp.empresa_id = solicitudes_campana.empresa_id
          AND cp.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text])
      )
    )
    AND estado = ANY (ARRAY['borrador'::text, 'enviada'::text, 'rechazada'::text]) -- NUEVO estado: jamás 'publicada'
  );

-- ------------------------------------------------------------
-- 7) Seed de productos ficticios del afín (datos de prueba). Idempotente.
-- ------------------------------------------------------------
INSERT INTO public.productos_empresa
  (empresa_id, nombre_producto, presentacion, categoria, precio_unitario, moneda, stock_disponible, requiere_receta, estado, pais_id)
SELECT e.id, p.nombre, p.presentacion, p.categoria, p.precio, 'GTQ', 100, false, 'activo', e.pais_id
FROM public.empresas_proveedoras e
CROSS JOIN (VALUES
  ('Multivitamínico Afín Plus',     'Frasco 60 cápsulas', 'Suplementos',     120.00),
  ('Crema Hidratante Dermo Afín',   'Tubo 100 ml',        'Dermocosmética',   85.50),
  ('Gel Antibacterial Afín',        'Botella 250 ml',     'Higiene',          35.00),
  ('Termómetro Digital Afín',       'Unidad',             'Dispositivos',     75.00),
  ('Tiras Reactivas Glucosa Afín',  'Caja 50 u',          'Dispositivos',    210.00)
) AS p(nombre, presentacion, categoria, precio)
WHERE e.tipo = 'empresa_afin'
  AND NOT EXISTS (
    SELECT 1 FROM public.productos_empresa pe2
    WHERE pe2.empresa_id = e.id AND pe2.nombre_producto = p.nombre
  );
