-- ============================================================
-- INCREMENTO 2 (paneles) · Alta de personal de FARMACIA por INVITACIÓN (opción A)
-- ------------------------------------------------------------
-- Rama: paneles/farmacia-tenant. Reusa invitaciones_visitador (ya tiene empresa_id,
-- email, rol, token, estado, expires_at). Dos RPC:
--   - invitar_miembro_farmacia: CREA la invitación con empresa_id + rol FIJADOS,
--     imponiendo la MISMA jerarquía que alta_miembro_farmacia (anti-escalada).
--   - consumo: se REUSA registrar_visitador_desde_invitacion (token-based, sin
--     usuarios_roles, SIN param de rol/empresa → el invitado no manipula su rol ni
--     su empresa). Se endurece con search_path='' + tablas calificadas.
-- Escritura directa: cuentas_proveedor ya está cerrada (sin política INSERT). El
-- INSERT directo a invitaciones_visitador se CIERRA para tipo='farmacia' (solo el
-- RPC crea invitaciones de farmacia). NO aplicar sin OK.
-- ============================================================

-- 1) RPC invitar_miembro_farmacia — crea la invitación (jerarquía como el alta)
CREATE OR REPLACE FUNCTION public.invitar_miembro_farmacia(
  p_email text, p_nombre text, p_nuevo_rol text, p_telefono text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_emp uuid; v_tipo text; v_asig_rol text; v_asig_nivel integer; v_asig_admin boolean;
  v_nuevo_nivel integer; v_token uuid;
BEGIN
  -- (a) el que invita necesita usuarios_roles
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: no puedes invitar personal';
  END IF;

  SELECT cp.empresa_id, e.tipo, cp.rol_en_empresa
    INTO v_emp, v_tipo, v_asig_rol
  FROM public.cuentas_proveedor cp JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
  WHERE cp.id = auth.uid() AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Invitador sin empresa activa'; END IF;

  -- este flujo data-driven es para farmacia. (La empresa queda FIJADA a la del
  -- invitador: no hay parámetro de empresa → imposible invitar en empresa ajena.)
  IF v_tipo <> 'farmacia' THEN
    RAISE EXCEPTION 'Invitación data-driven disponible solo para empresas tipo farmacia';
  END IF;
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'El email es obligatorio';
  END IF;

  -- (b) nuevo_rol debe existir para farmacia
  SELECT nivel INTO v_nuevo_nivel
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = 'farmacia' AND rol = p_nuevo_rol;
  IF v_nuevo_nivel IS NULL THEN
    RAISE EXCEPTION 'Rol "%" no existe para farmacia', p_nuevo_rol;
  END IF;

  SELECT nivel, es_admin INTO v_asig_nivel, v_asig_admin
  FROM public.roles_empresa_catalogo WHERE tipo_empresa = 'farmacia' AND rol = v_asig_rol;

  -- (c) Admin invita cualquier rol; un NO-admin solo nivel ESTRICTAMENTE inferior
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

-- 2) CONSUMO — aceptar_invitacion_proveedor: AUTENTICADO, atado a auth.uid() y al
--    EMAIL VERIFICADO del usuario (auth.users). No recibe user_id ni email por
--    parámetro (el caller no puede impersonar ni declarar otro email). El rol y la
--    empresa salen del token (no manipulables). No exige usuarios_roles (el invitado
--    no lo tiene; la autorización ya ocurrió al crear la invitación). SIN anon.
--    Dependencia de seguridad: "Confirm email = ON" en Supabase Auth (verificado por
--    el equipo). El check email_confirmed_at es defensa en profundidad.
CREATE OR REPLACE FUNCTION public.aceptar_invitacion_proveedor(p_token uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_inv RECORD;
  v_uid uuid;
  v_email text;
  v_conf timestamptz;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Inicia sesión (con tu email verificado) para aceptar la invitación';
  END IF;

  SELECT email, email_confirmed_at INTO v_email, v_conf FROM auth.users WHERE id = v_uid;
  IF v_conf IS NULL THEN
    RAISE EXCEPTION 'Debes verificar tu email antes de aceptar la invitación';
  END IF;

  SELECT * INTO v_inv
  FROM public.invitaciones_visitador
  WHERE token = p_token AND estado = 'pendiente' AND expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitación no válida o expirada';
  END IF;

  -- Binding contra el email AUTENTICADO (no un parámetro): solo quien controla el
  -- buzón del invitado (verificado) puede consumir.
  IF lower(trim(v_email)) IS DISTINCT FROM lower(trim(v_inv.email)) THEN
    RAISE EXCEPTION 'La invitación no corresponde a tu cuenta';
  END IF;

  IF EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = v_uid) THEN
    RAISE EXCEPTION 'Ya tienes una cuenta de proveedor';
  END IF;

  INSERT INTO public.cuentas_proveedor (id, empresa_id, email, nombre_completo, telefono, rol_en_empresa, activo)
  VALUES (
    v_uid, v_inv.empresa_id, v_email,
    v_inv.nombre_completo, v_inv.telefono,
    COALESCE(v_inv.rol, 'visitador_medico'),   -- rol FIJADO por el token
    true
  );

  UPDATE public.invitaciones_visitador SET estado = 'usada' WHERE id = v_inv.id;
  RETURN v_inv.empresa_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.aceptar_invitacion_proveedor(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.aceptar_invitacion_proveedor(uuid) TO authenticated, service_role;

-- 2b) CERRAR EL CAMINO VIEJO: registrar_visitador_desde_invitacion aceptaba un
--     user_id arbitrario y corría como anon (sin sesión ni binding) → puerta lateral.
--     Tras reordenar el frontend a aceptar_invitacion_proveedor, nadie lo usa → DROP.
DROP FUNCTION IF EXISTS public.registrar_visitador_desde_invitacion(uuid, uuid, text, text, text);

-- 3) Cerrar el INSERT directo a invitaciones_visitador PARA FARMACIA.
--    (cuentas_proveedor ya está cerrada: sin política INSERT.) Para farmacia, las
--    invitaciones SOLO se crean por invitar_miembro_farmacia (definer/owner).
--    Laboratorio/visitador conservan su INSERT directo admin/editor (tipo<>farmacia).
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
        AND e.tipo <> 'farmacia'          -- farmacia: solo vía invitar_miembro_farmacia
    )
  );
-- (SELECT "invitaciones_select_admin" se mantiene: cada empresa ve solo las suyas.)
