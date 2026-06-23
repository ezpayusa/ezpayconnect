-- ============================================================
-- 140 · Spine sucursales 3.2 — Asignación personal→sucursal (DORMANT, NO aplicar sin OK)
-- ------------------------------------------------------------
-- Mecanismo que ACTIVA C.2 desde el usuario: puebla cuentas_proveedor.sucursal_id (hoy 0/12 → todo
-- grandfather-inerte). 1:1 estricto (PK id=auth.uid). El término sucursal_visible de mig 114 (policies
-- de farmacia_medicamentos) deja de ser grandfather al primer sucursal_id no-NULL.
-- ALCANCE: SOLO mecanismo de asignación + activación de la confinación de INVENTARIO (ya cableada en 114).
-- NO confina el buzón de recetas (eso es 3.4), NO panel gerente-sucursal, NO cambia el routing post-login.
-- Empresa DERIVADA del actor (I3). DEFINER + search_path=''.
-- ============================================================

-- Helper único de validación de sucursal (no-NULL): pertenece a la empresa, no-global, activa.
-- Reusado por asignar_sucursal_a_miembro Y por vincular_membresia_proveedor (alta con sucursal).
CREATE OR REPLACE FUNCTION private.sucursal_de_empresa_activa(p_sucursal_id integer, p_empresa uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.farmacias f
    WHERE f.id = p_sucursal_id
      AND f.empresa_id = p_empresa
      AND f.empresa_id IS NOT NULL   -- nunca global
      AND f.activo = true            -- nunca inactiva
  );
$$;
REVOKE EXECUTE ON FUNCTION private.sucursal_de_empresa_activa(integer, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.sucursal_de_empresa_activa(integer, uuid) TO authenticated;

-- (A) RPC standalone: reasignar (o desasignar) la sucursal de un miembro existente.
--     Gate usuarios_roles (igual que asignar_rol_miembro). Empresa derivada. NULL = desasignar (grandfather).
--     EXENTO permitido (no se bloquea: sucursal_visible los exime igual; el dato es informativo).
--     Esta es la "reasigná N personas primero" que destraba desactivar_sucursal (3.1).
CREATE OR REPLACE FUNCTION public.asignar_sucursal_a_miembro(p_target_id uuid, p_sucursal_id integer)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_caller uuid := auth.uid(); v_emp uuid;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000'; END IF;
  SELECT cp.empresa_id INTO v_emp FROM public.cuentas_proveedor cp WHERE cp.id = v_caller AND cp.activo = true;
  IF v_emp IS NULL THEN RAISE EXCEPTION 'Sin cuenta de proveedor activa' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: requiere permiso usuarios_roles' USING ERRCODE = '42501';
  END IF;
  -- target ∈ mi empresa (no asignar a miembro de otra empresa)
  IF NOT EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = p_target_id AND empresa_id = v_emp) THEN
    RAISE EXCEPTION 'El miembro no pertenece a tu empresa' USING ERRCODE = '42501';
  END IF;
  -- sucursal (solo si no-NULL): propia, no-global, activa. NULL = desasignar → grandfather/empresa-wide.
  IF p_sucursal_id IS NOT NULL AND NOT COALESCE(private.sucursal_de_empresa_activa(p_sucursal_id, v_emp), false) THEN
    RAISE EXCEPTION 'La sucursal no pertenece a tu empresa, es global o está inactiva' USING ERRCODE = '42501';
  END IF;
  UPDATE public.cuentas_proveedor SET sucursal_id = p_sucursal_id WHERE id = p_target_id AND empresa_id = v_emp;
END $$;
REVOKE EXECUTE ON FUNCTION public.asignar_sucursal_a_miembro(uuid, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.asignar_sucursal_a_miembro(uuid, integer) TO authenticated;

-- (B) 138-extendido: vincular_membresia_proveedor + p_sucursal_id OPCIONAL (asignar al invitar).
--     Param ADITIVO (default NULL = comportamiento actual). NO relaja autorizar_invitacion_staff.
--     3 ramas intactas: (i) nuevo / (ii) vincular existente setean sucursal; (iii) 409 sin tocar.
--     Se reemplaza la firma de 4 args por la de 5 (DROP+CREATE; sin overload ambiguo).
DROP FUNCTION IF EXISTS public.vincular_membresia_proveedor(text, text, text, text);
CREATE OR REPLACE FUNCTION public.vincular_membresia_proveedor(
  p_email      text,
  p_rol        text,
  p_nombre     text DEFAULT NULL,
  p_telefono   text DEFAULT NULL,
  p_sucursal_id integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_gate jsonb; v_emp uuid; v_uid uuid; v_email text := lower(trim(p_email));
BEGIN
  -- (1) RE-GATE (138 invocable directo): misma autz; empresa DERIVADA.
  v_gate := public.autorizar_invitacion_staff(p_rol);
  v_emp  := (v_gate->>'empresa_id')::uuid;
  -- (1b) sucursal OPCIONAL: si viene, validar (mismo helper) ANTES de tocar nada.
  IF p_sucursal_id IS NOT NULL AND NOT COALESCE(private.sucursal_de_empresa_activa(p_sucursal_id, v_emp), false) THEN
    RAISE EXCEPTION 'La sucursal no pertenece a tu empresa, es global o está inactiva' USING ERRCODE = '42501';
  END IF;
  -- (2) IDENTIDAD: uid solo por email server-side.
  SELECT u.id INTO v_uid FROM auth.users u WHERE lower(u.email) = v_email;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No existe un usuario con ese email' USING ERRCODE = 'P0002'; END IF;
  -- (3) GUARD 1:1 → rama (iii) = 409.
  IF EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = v_uid) THEN
    RAISE EXCEPTION 'El usuario ya tiene una cuenta de proveedor' USING ERRCODE = '23505';
  END IF;
  -- (4) INSERT membresía (ramas i/ii) con sucursal opcional.
  INSERT INTO public.cuentas_proveedor (id, empresa_id, email, nombre_completo, telefono, rol_en_empresa, activo, sucursal_id)
  SELECT v_uid, v_emp, u.email, COALESCE(p_nombre, u.email), p_telefono, p_rol, true, p_sucursal_id
    FROM auth.users u WHERE u.id = v_uid;
  RETURN jsonb_build_object('empresa_id', v_emp, 'rol', p_rol, 'uid', v_uid, 'sucursal_id', p_sucursal_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.vincular_membresia_proveedor(text, text, text, text, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.vincular_membresia_proveedor(text, text, text, text, integer) TO authenticated;
