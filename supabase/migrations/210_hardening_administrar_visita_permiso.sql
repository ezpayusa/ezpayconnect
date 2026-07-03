-- ============================================================================
-- Migración 210: HARDENING RPC — administrar_visita exige poder aprobar visitas
-- ============================================================================
-- GAP QUE CIERRA:
-- administrar_visita (mig 075, versión vigente) autorizaba con:
--     private.tiene_rol(ARRAY['super_admin'])
--     OR COALESCE(mi_empresa_proveedor() = v_visita.empresa_id, false)
-- => CUALQUIER miembro de la empresa proveedora (aunque su rol no deba aprobar visitas)
--    podía aprobar/rechazar/modificar. El permiso fino 'visitas.aprobar' solo se chequeaba
--    en el front (permisos.ts, UI gate), no server-side.
--
-- POR QUÉ UN HELPER Y NO private.tiene_permiso():
-- El catálogo data-driven (permisos_empresa_rol → FK roles_empresa_catalogo, mig 083) modela
-- SOLO el dominio farmacia/empresa_afin (entregas, recetas, caja…). NO incluye el tipo
-- 'laboratorio_farmaceutico' ni el flujo visitador, y su FK impide sembrar 'visitas_aprobar'
-- para laboratorios. Como hay aprobadores reales de laboratorio (admin/supervisor), engancharlo
-- a tiene_permiso (fail-closed) los habría bloqueado. Portar labs al catálogo es otro alcance.
-- En su lugar, un helper acotado replica EXACTAMENTE la regla del front, tipo-agnóstico:
-- roles con visitas.aprobar en permisos.ts = admin, supervisor, editor(legacy).
-- ============================================================================


-- ============================================================================
-- PASO 1 — Helper server-side: ¿la cuenta activa puede aprobar visitas?
-- ============================================================================
-- Réplica exacta de puede('visitas.aprobar') del front (permisos.ts): rol_en_empresa en
-- {admin, supervisor, editor}. Tipo-agnóstico (igual que el front, que solo mira el rol).
-- Fail-closed: EXISTS falso si no hay cuenta activa que matchee. SECURITY DEFINER + search_path ''
-- (patrón de private.mi_empresa_proveedor / private.tiene_rol).
CREATE OR REPLACE FUNCTION private.puede_aprobar_visitas()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cuentas_proveedor cp
    WHERE cp.id = auth.uid()
      AND cp.activo = true
      AND cp.rol_en_empresa IN ('admin', 'supervisor', 'editor')
  );
$$;

GRANT EXECUTE ON FUNCTION private.puede_aprobar_visitas() TO authenticated;


-- ============================================================================
-- PASO 2 — Enganchar administrar_visita al helper
-- ============================================================================
-- Precede: mig 075 (versión vigente de administrar_visita). MISMA firma exacta (no rompe el
-- grant existente). Único cambio funcional: la autorización de la rama proveedora ahora exige
-- además private.puede_aprobar_visitas(). Todo lo demás se preserva idéntico (las 3 acciones,
-- COALESCE de comentario_admin, manejo de acción inválida, SET search_path TO '').
CREATE OR REPLACE FUNCTION public.administrar_visita(p_visita_id uuid, p_accion text, p_nueva_fecha date DEFAULT NULL::date, p_nueva_hora_inicio text DEFAULT NULL::text, p_nueva_hora_fin text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_visita RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  -- Revalidación del caller: aprobada_por referencia cuentas_proveedor → quien
  -- administra es la empresa proveedora (supervisor) o super_admin. El médico es
  -- la parte VISITADA, no el aprobador. COALESCE evita el fail-open trivaluado
  -- (mi_empresa_proveedor() NULL ⇒ 'false OR NULL' = NULL ⇒ RAISE saltado).
  -- HARDENING (mig 210): la rama de empresa proveedora ahora exige, además de pertenecer a la
  -- empresa de la visita, poder aprobar visitas (private.puede_aprobar_visitas, fail-closed).
  -- Antes cualquier miembro de la empresa podía administrar; ahora solo roles admin/supervisor/editor.
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR (
         COALESCE(public.mi_empresa_proveedor() = v_visita.empresa_id, false)
         AND private.puede_aprobar_visitas()
       )
  ) THEN
    RAISE EXCEPTION 'No autorizado para administrar esta visita';
  END IF;

  -- aprobada_por solo si el caller es proveedor (su uid ∈ cuentas_proveedor);
  -- para super_admin se preserva el valor previo (no viola la FK).
  IF p_accion = 'aprobar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada');
  ELSIF p_accion = 'rechazar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'rechazada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'rechazada');
  ELSIF p_accion = 'modificar' THEN
    UPDATE public.visitas_agendadas
    SET fecha_visita = COALESCE(p_nueva_fecha, fecha_visita),
        hora_inicio = COALESCE(p_nueva_hora_inicio, hora_inicio),
        hora_fin = COALESCE(p_nueva_hora_fin, hora_fin),
        estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada', 'modificado', true);
  ELSE
    RETURN jsonb_build_object('error', 'Acción no válida');
  END IF;

  RETURN v_result;
END;
$function$;
