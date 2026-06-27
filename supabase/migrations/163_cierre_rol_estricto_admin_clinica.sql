-- 163 · Cierre por ROL ESTRICTO de 3 RPC administrativas de clínica.
-- Hoy gatean por PERTENENCIA sola (cualquier miembro de la clínica pasa) → un médico/asistente_medico
-- con pertenencia las pasa por URL/RPC directa (agujero; recon confirmó que NINGÚN flujo legítimo de
-- médico depende de ellas — no hay médico-dueño, y las páginas que las usan están detrás del gate de
-- front admin_clinica/admin/super_admin). Nuevo gate (patrón de crear-staff-clinica / mig 159):
--   super_admin  O  (private.tiene_rol(['admin_clinica','gerente']) AND pertenencia a la clínica objetivo).
-- Solo se reescribe el GATE de cada función; firma/RETURNS/volatilidad/search_path/grants intactos.
-- (El edge crear-invitacion-medico se cierra aparte, en el mismo paquete, replicando crear-staff-clinica.)

-- ============================================================
-- 1) actualizar_clinica — antes: membership OR super_admin → ahora: super_admin OR (rol admin AND membership)
-- ============================================================
CREATE OR REPLACE FUNCTION public.actualizar_clinica(
  p_clinica_id uuid, p_nombre text, p_direccion text DEFAULT NULL::text,
  p_telefono text DEFAULT NULL::text, p_email text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Gate ESTRICTO: super_admin O (admin_clinica/gerente AND pertenencia a esta clínica).
  IF NOT (
    EXISTS (SELECT 1 FROM perfiles p WHERE p.id = auth.uid() AND p.rol = 'super_admin')
    OR (
      private.tiene_rol(ARRAY['admin_clinica','gerente'])
      AND EXISTS (SELECT 1 FROM medico_clinicas mc WHERE mc.clinica_id = p_clinica_id AND mc.medico_id = auth.uid())
    )
  ) THEN
    RAISE EXCEPTION 'No autorizado para editar esta clínica';
  END IF;

  UPDATE clinicas SET nombre=p_nombre, direccion=p_direccion, telefono=p_telefono, email=p_email
  WHERE id = p_clinica_id;
END;
$function$;

-- ============================================================
-- 2) obtener_personal_clinica — antes: super_admin OR membership → ahora: super_admin OR (rol admin AND membership)
-- ============================================================
CREATE OR REPLACE FUNCTION public.obtener_personal_clinica(p_clinica_id uuid)
 RETURNS TABLE(medico_id uuid, nombre_completo text, email text, rol text, telefono text, especialidad text, es_principal boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Gate ESTRICTO: super_admin O (admin_clinica/gerente AND pertenencia). El branch super_admin se preserva.
  IF p_clinica_id IS NULL OR NOT (
       COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR ( COALESCE(private.tiene_rol(ARRAY['admin_clinica','gerente']), false)
         AND p_clinica_id IN (SELECT private.clinicas_del_usuario()) )
  ) THEN
    RAISE EXCEPTION 'No autorizado para ver el personal de esta clínica';
  END IF;

  RETURN QUERY
  SELECT mc.medico_id,
         p.nombre_completo,
         p.email,
         p.rol,
         p.telefono,
         m.especialidad,
         COALESCE(mc.es_principal, false)
  FROM public.medico_clinicas mc
  JOIN public.perfiles p ON p.id = mc.medico_id
  LEFT JOIN public.medicos m ON m.id = mc.medico_id
  WHERE mc.clinica_id = p_clinica_id;
END;
$function$;

-- ============================================================
-- 3) invitar_laboratorio — agrega check de rol ANTES de mi_clinica_id (que aporta la pertenencia).
--    Antes: pertenencia sola (mi_clinica_id NOT NULL). Ahora: rol admin/super_admin Y mi_clinica_id NOT NULL.
-- ============================================================
CREATE OR REPLACE FUNCTION public.invitar_laboratorio(p_email text, p_nombre text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clinica UUID;
  v_pais    UUID;
  v_lab     UUID;
  v_token   UUID;
BEGIN
  -- Gate ESTRICTO de rol ANTES de resolver la clínica (NO reemplaza mi_clinica_id; la pertenencia la
  -- sigue aportando mi_clinica_id justo debajo). super_admin/admin_clinica/gerente.
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin','admin_clinica','gerente']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo un administrador de clínica puede invitar laboratorios';
  END IF;

  v_clinica := mi_clinica_id();
  IF v_clinica IS NULL THEN
    RAISE EXCEPTION 'Solo el administrador de una clínica puede invitar laboratorios';
  END IF;

  SELECT pais_id INTO v_pais FROM clinicas WHERE id = v_clinica;

  -- ¿el lab ya existe como empresa?
  SELECT id INTO v_lab
  FROM empresas_proveedoras
  WHERE lower(email_contacto) = lower(p_email) AND tipo = 'laboratorio_clinico'
  LIMIT 1;

  IF v_lab IS NOT NULL AND EXISTS (
    SELECT 1 FROM laboratorio_clinicas
    WHERE laboratorio_id = v_lab AND clinica_id = v_clinica AND estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'Ese laboratorio ya está afiliado a tu clínica';
  END IF;

  -- ¿invitación pendiente duplicada?
  IF EXISTS (
    SELECT 1 FROM invitaciones_laboratorio
    WHERE clinica_id = v_clinica AND lower(email) = lower(p_email) AND estado = 'pendiente'
  ) THEN
    RAISE EXCEPTION 'Ya hay una invitación pendiente para ese email';
  END IF;

  INSERT INTO invitaciones_laboratorio (clinica_id, pais_id, email, nombre_laboratorio, laboratorio_id, created_by)
  VALUES (v_clinica, v_pais, lower(p_email), p_nombre, v_lab, auth.uid())
  RETURNING token INTO v_token;

  RETURN jsonb_build_object('token', v_token, 'laboratorio_existe', v_lab IS NOT NULL);
END $function$;

-- ============================================================
-- 4) Endurecer grants: quitar anon/PUBLIC de las 2 que lo tenían (higiene; el gate ya deniega a anon).
--    Quedan consistentes con obtener_personal_clinica (authenticated/service_role). NO toca authenticated.
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.actualizar_clinica(uuid, text, text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.invitar_laboratorio(text, text)                  FROM PUBLIC, anon;
