-- ============================================================
-- 138 · Invitación Opción B — pre-gate + vínculo de membresía (DORMANT, NO aplicar sin OK)
-- ------------------------------------------------------------
-- DOS funciones DEFINER (search_path='' + refs calificadas). auth.uid() evalúa SIEMPRE el caller (el
-- DEFINER cambia el rol, no el JWT) — y se preserva a través de la llamada anidada.
--
--  (A) autorizar_invitacion_staff(p_rol) — PRE-GATE SIN EFECTOS. La edge lo llama ANTES de createUser:
--      así un caller NO-admin se rechaza ANTES de crear cualquier auth user / enviar cualquier email
--      (cierra el fallo de orden + enumeración por timing). Valida invitador=usuarios_roles, deriva
--      empresa+tipo del invitador (I3), y exige rol ∈ catálogo del TIPO (lab sin catálogo → fail-closed).
--
--  (B) vincular_membresia_proveedor(p_email,…) — RE-GATEA (llama A; 138 es invocable directo) + resuelve
--      el uid SOLO por EMAIL server-side (sin uid caller-supplied: un llamador directo NO puede bindear
--      un uid arbitrario) + guard 1:1 (cuentas_proveedor.id PK) + insert. Unifica las 3 ramas D1:
--        (i) email nuevo: tras createUser de la edge, el email ya mapea al uid nuevo → inserta.
--        (ii) auth user existe sin membresía → vincula (no toca su credencial; este RPC no toca auth.users).
--        (iii) auth user con membresía → RAISE 23505 (la edge lo mapea a 409). Guard cross-empresa.
-- ============================================================

CREATE OR REPLACE FUNCTION public.autorizar_invitacion_staff(p_rol text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_caller uuid := auth.uid(); v_emp uuid; v_tipo text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000'; END IF;
  SELECT cp.empresa_id INTO v_emp FROM public.cuentas_proveedor cp WHERE cp.id = v_caller AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Invitador sin cuenta de proveedor activa' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: requiere permiso usuarios_roles' USING ERRCODE = '42501';
  END IF;
  SELECT e.tipo INTO v_tipo FROM public.empresas_proveedoras e WHERE e.id = v_emp;
  IF NOT EXISTS (SELECT 1 FROM public.roles_empresa_catalogo c WHERE c.tipo_empresa = v_tipo AND c.rol = p_rol) THEN
    RAISE EXCEPTION 'Rol % no concedible para tipo %', p_rol, COALESCE(v_tipo,'(desconocido)') USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('empresa_id', v_emp, 'tipo', v_tipo);
END $$;
REVOKE EXECUTE ON FUNCTION public.autorizar_invitacion_staff(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.autorizar_invitacion_staff(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.vincular_membresia_proveedor(
  p_email    text,
  p_rol      text,
  p_nombre   text DEFAULT NULL,
  p_telefono text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_gate jsonb; v_emp uuid; v_uid uuid; v_email text := lower(trim(p_email));
BEGIN
  -- (1) RE-GATE (138 es invocable directo): misma autz que el pre-gate de la edge. empresa DERIVADA aquí.
  v_gate := public.autorizar_invitacion_staff(p_rol);
  v_emp  := (v_gate->>'empresa_id')::uuid;

  -- (2) IDENTIDAD: uid resuelto SOLO por email server-side (sin uid caller-supplied).
  SELECT u.id INTO v_uid FROM auth.users u WHERE lower(u.email) = v_email;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No existe un usuario con ese email' USING ERRCODE = 'P0002'; END IF;

  -- (3) GUARD 1:1 (cross-empresa): una sola membresía de proveedor por auth user → rama (iii) = 409.
  IF EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = v_uid) THEN
    RAISE EXCEPTION 'El usuario ya tiene una cuenta de proveedor' USING ERRCODE = '23505';
  END IF;

  -- (4) INSERT membresía. empresa_id = la del invitador (NO hay parámetro de empresa → imposible cross-empresa).
  INSERT INTO public.cuentas_proveedor (id, empresa_id, email, nombre_completo, telefono, rol_en_empresa, activo)
  SELECT v_uid, v_emp, u.email, COALESCE(p_nombre, u.email), p_telefono, p_rol, true
    FROM auth.users u WHERE u.id = v_uid;

  RETURN jsonb_build_object('empresa_id', v_emp, 'rol', p_rol, 'uid', v_uid);
END $$;
REVOKE EXECUTE ON FUNCTION public.vincular_membresia_proveedor(text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.vincular_membresia_proveedor(text,text,text,text) TO authenticated;
