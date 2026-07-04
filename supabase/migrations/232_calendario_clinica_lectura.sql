-- ============================================================================
-- Migración 232 (Mig B del calendario de clínica): lectura + auditoría de presencia.
-- Recon reveló que la RLS actual NO alcanza: medico_clinicas no es legible por staff
-- (solo service_role) y citas solo la leen admin_clinica/gerente/secretaria (NO
-- asistente_medico/enfermeria/admin). Por eso el calendario lee TODO por RPCs DEFINER
-- gateadas por un único predicado de staff (7 roles). visitas_agendadas no era legible
-- por ningún rol de clínica → RPC nueva.
-- ============================================================================

BEGIN;

-- (0) Columnas de auditoría "visitador presente" (registro PARALELO; no toca estado ni checkin/checkout).
ALTER TABLE public.visitas_agendadas
  ADD COLUMN IF NOT EXISTS confirmado_presente_clinica_at  timestamptz,
  ADD COLUMN IF NOT EXISTS confirmado_presente_clinica_por uuid REFERENCES public.perfiles(id);

-- (1) Gate único de LECTURA del calendario: los 7 roles del calendario sobre su clínica,
--     o super_admin sobre cualquiera. Reusa clinicas_del_usuario() (staff vía medico_clinicas).
CREATE OR REPLACE FUNCTION private.es_staff_calendario_clinica(p_clinica uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
  SELECT private.tiene_rol(ARRAY['super_admin'])
      OR ( private.tiene_rol(ARRAY['admin_clinica','admin','gerente','secretaria','asistente_medico','enfermeria'])
           AND p_clinica IN (SELECT private.clinicas_del_usuario()) );
$fn$;

-- (2) Columnas del calendario: médicos de la clínica (rol=medico), en tiempo real desde medico_clinicas.
CREATE OR REPLACE FUNCTION public.listar_medicos_clinica(p_clinica_id uuid)
RETURNS TABLE(medico_id uuid, nombre_completo text, es_principal boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
  IF NOT private.es_staff_calendario_clinica(p_clinica_id) THEN
    RAISE EXCEPTION 'No autorizado para ver los médicos de esta clínica';
  END IF;
  RETURN QUERY
    SELECT p.id, p.nombre_completo, mc.es_principal
    FROM public.medico_clinicas mc
    JOIN public.perfiles p ON p.id = mc.medico_id
    WHERE mc.clinica_id = p_clinica_id AND p.rol = 'medico'
    ORDER BY p.nombre_completo;
END; $fn$;

-- (3) Citas de la clínica en un rango (side "Citas de Pacientes").
CREATE OR REPLACE FUNCTION public.listar_citas_clinica(p_clinica_id uuid, p_desde date, p_hasta date)
RETURNS TABLE(cita_id bigint, medico_id uuid, paciente_id bigint, paciente_nombre text,
              paciente_apellido text, paciente_telefono text, foto_path text,
              fecha date, hora_inicio time, hora_fin time, estado text, motivo text, notas text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
  IF NOT private.es_staff_calendario_clinica(p_clinica_id) THEN
    RAISE EXCEPTION 'No autorizado para ver las citas de esta clínica';
  END IF;
  RETURN QUERY
    SELECT c.id, c.medico_id, c.paciente_id, pa.nombre, pa.apellido, pa.telefono, pa.foto_path,
           c.fecha, c.hora_inicio, c.hora_fin, c.estado, c.motivo, c.notas
    FROM public.citas c
    JOIN public.pacientes pa ON pa.id = c.paciente_id
    WHERE c.clinica_id = p_clinica_id AND c.fecha BETWEEN p_desde AND p_hasta;
END; $fn$;

-- (4) Visitas de visitador de la clínica en un rango — SOLO LECTURA. Opción B: solo médicos
--     cuya clínica PRINCIPAL (es_principal=true) es la consultada (nunca duplicar entre clínicas).
CREATE OR REPLACE FUNCTION public.listar_visitas_clinica(p_clinica_id uuid, p_desde date, p_hasta date)
RETURNS TABLE(visita_id uuid, medico_id uuid, medico_nombre text, empresa_id uuid, empresa_nombre text,
              fecha_visita date, hora_inicio time, hora_fin time, estado text,
              confirmado_presente_clinica_at timestamptz, confirmado_presente_clinica_por uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
  IF NOT private.es_staff_calendario_clinica(p_clinica_id) THEN
    RAISE EXCEPTION 'No autorizado para ver las visitas de esta clínica';
  END IF;
  RETURN QUERY
    SELECT v.id, v.medico_id, pm.nombre_completo, v.empresa_id, e.nombre_empresa,
           v.fecha_visita, v.hora_inicio, v.hora_fin, v.estado,
           v.confirmado_presente_clinica_at, v.confirmado_presente_clinica_por
    FROM public.visitas_agendadas v
    JOIN public.perfiles pm ON pm.id = v.medico_id
    LEFT JOIN public.empresas_proveedoras e ON e.id = v.empresa_id
    WHERE v.fecha_visita BETWEEN p_desde AND p_hasta
      AND EXISTS (SELECT 1 FROM public.medico_clinicas mc
                  WHERE mc.medico_id = v.medico_id
                    AND mc.clinica_id = p_clinica_id
                    AND mc.es_principal = true);
END; $fn$;

-- (5) Marcar/desmarcar "visitador presente" — registro paralelo de auditoría de la clínica.
--     NO toca estado ni checkin/checkout (esos son del visitador). Gate: staff que ACTÚA
--     (sin enfermería) sobre la clínica PRINCIPAL del médico de la visita, o super_admin.
CREATE OR REPLACE FUNCTION public.marcar_visitador_presente(p_visita_id uuid, p_presente boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_medico uuid; v_clinica uuid;
BEGIN
  SELECT medico_id INTO v_medico FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF v_medico IS NULL THEN RAISE EXCEPTION 'Visita inexistente'; END IF;

  SELECT clinica_id INTO v_clinica FROM public.medico_clinicas
    WHERE medico_id = v_medico AND es_principal = true LIMIT 1;

  -- Gate = mismo set completo de staff de calendario (6 roles, INCLUYE enfermería) + super_admin,
  -- sobre la clínica PRINCIPAL del médico de la visita.
  IF NOT private.es_staff_calendario_clinica(v_clinica) THEN
    RAISE EXCEPTION 'No autorizado para marcar la presencia del visitador en esta clínica';
  END IF;

  UPDATE public.visitas_agendadas
     SET confirmado_presente_clinica_at  = CASE WHEN p_presente THEN now() ELSE NULL END,
         confirmado_presente_clinica_por = CASE WHEN p_presente THEN auth.uid() ELSE NULL END
   WHERE id = p_visita_id;

  RETURN jsonb_build_object(
    'presente', p_presente,
    'at',  (SELECT confirmado_presente_clinica_at  FROM public.visitas_agendadas WHERE id = p_visita_id),
    'por', (SELECT confirmado_presente_clinica_por FROM public.visitas_agendadas WHERE id = p_visita_id));
END; $fn$;

-- (6) Hardening de EXECUTE: solo authenticated. Se revoca de PUBLIC **y de anon** (Supabase concede
--     EXECUTE a anon/authenticated por default privileges → REVOKE FROM PUBLIC solo no lo quita).
REVOKE EXECUTE ON FUNCTION public.listar_medicos_clinica(uuid)               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.listar_citas_clinica(uuid,date,date)       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.listar_visitas_clinica(uuid,date,date)     FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.marcar_visitador_presente(uuid,boolean)    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_medicos_clinica(uuid)               TO authenticated;
GRANT  EXECUTE ON FUNCTION public.listar_citas_clinica(uuid,date,date)       TO authenticated;
GRANT  EXECUTE ON FUNCTION public.listar_visitas_clinica(uuid,date,date)     TO authenticated;
GRANT  EXECUTE ON FUNCTION public.marcar_visitador_presente(uuid,boolean)    TO authenticated;

COMMIT;
