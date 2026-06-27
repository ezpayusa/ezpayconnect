-- 159 · Cierre P0 seguridad Clínica — gatear los 3 RPC SECURITY DEFINER abiertos a anon/PUBLIC.
-- Patrón (igual que obtener_personal_clinica, mig 082): lógica privada SIN gate (fuente de verdad de
-- pertenencia) + endpoint público GATEADO fail-closed + REVOKE anon/PUBLIC.
--
-- Funciones cerradas: public.obtener_clinica_usuario (identidad), public.obtener_citas_clinica y
-- public.obtener_medicos_clinica (pertenencia). Hoy las tres son SECURITY DEFINER con EXECUTE a
-- PUBLIC+anon+authenticated y filtran SOLO por su parámetro → IDOR/PII cross-clínica.
--
-- ROMPER RECURSIÓN: private.clinicas_del_usuario()/clinica_del_usuario() HOY llaman a la propia
-- public.obtener_clinica_usuario(auth.uid()). Si gateamos la pública, el gate (que usa el helper)
-- se llamaría a sí mismo. Se introduce private.clinicas_de(uid) como fuente de verdad SIN gate y se
-- reapuntan los helpers a ella. El conjunto devuelto es idéntico (medico_clinicas ∪ clinicas.doctor_id).
--
-- service_role (decisión 3a): crear-staff-clinica corre con service_role (auth.uid()=NULL) y pasa
-- p_user_id=solicitante.id explícito. El gate de obtener_clinica_usuario permite el branch
-- auth.uid() IS NULL (≡ service_role, porque anon/PUBLIC quedan REVOKE y authenticated siempre trae uid).
-- El edge NO se toca y sigue recibiendo {clinica_id} idéntico.

-- ============================================================
-- 1) FUENTE DE VERDAD DE PERTENENCIA — interna, SIN gate, SIN grant a anon/authenticated.
--    Solo la usan funciones DEFINER (corren como owner). REVOKE de PUBLIC (CREATE concede a PUBLIC por defecto).
-- ============================================================
CREATE OR REPLACE FUNCTION private.clinicas_de(p_user_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT mc.clinica_id FROM public.medico_clinicas mc WHERE mc.medico_id = p_user_id
  UNION
  SELECT c.id          FROM public.clinicas c         WHERE c.doctor_id = p_user_id;
$function$;
REVOKE ALL ON FUNCTION private.clinicas_de(uuid) FROM PUBLIC;

-- ============================================================
-- 2) REAPUNTAR HELPERS a private.clinicas_de(auth.uid()) — rompe el ciclo. Salida idéntica a hoy.
--    (CREATE OR REPLACE preserva los grants existentes: postgres, authenticated.)
-- ============================================================
CREATE OR REPLACE FUNCTION private.clinicas_del_usuario()
RETURNS SETOF uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT private.clinicas_de(auth.uid());
$function$;

CREATE OR REPLACE FUNCTION private.clinica_del_usuario()
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT c FROM private.clinicas_de(auth.uid()) AS c LIMIT 1;
$function$;

-- ============================================================
-- 2b) REAPUNTAR mi_clinica_id() (mig 062, RLS de laboratorio) a private.clinicas_de(auth.uid()).
--     Tercer helper que llamaba a la pública: desacople total. Cuerpo equivalente (1 uuid, LIMIT 1).
--     Firma/LANGUAGE sql/STABLE/SET search_path='public'/grants SIN cambios (CREATE OR REPLACE los preserva).
-- ============================================================
CREATE OR REPLACE FUNCTION public.mi_clinica_id()
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT c FROM private.clinicas_de(auth.uid()) AS c LIMIT 1
$function$;

-- ============================================================
-- 3) GATE IDENTIDAD — obtener_clinica_usuario. Reusa private.clinicas_de (no duplica query).
-- ============================================================
CREATE OR REPLACE FUNCTION public.obtener_clinica_usuario(p_user_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(clinica_id uuid, clinica_nombre text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- Gate fail-closed (PRIMERA sentencia, antes de tocar tablas): dueño del uid, super_admin,
  -- o contexto server (auth.uid() NULL ≡ service_role; ver decisión 3a).
  IF NOT (
       p_user_id = auth.uid()
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR auth.uid() IS NULL
  ) THEN
    RAISE EXCEPTION 'No autorizado: solo podés consultar tu propia clínica';
  END IF;

  RETURN QUERY
  SELECT c.id, c.nombre::text
  FROM private.clinicas_de(p_user_id) AS m(clinica_id)
  JOIN public.clinicas c ON c.id = m.clinica_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.obtener_clinica_usuario(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_clinica_usuario(uuid) TO authenticated, service_role;

-- ============================================================
-- 4a) GATE PERTENENCIA — obtener_citas_clinica.
-- ============================================================
CREATE OR REPLACE FUNCTION public.obtener_citas_clinica(p_clinica_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(id bigint, medico_id uuid, paciente_id bigint, clinica_id uuid, fecha date,
  hora_inicio time without time zone, hora_fin time without time zone, motivo text, estado text,
  notas text, created_at timestamp with time zone, paciente_nombre text, paciente_email text,
  paciente_telefono text, paciente_apellido text, paciente_auth_user_id uuid)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- Gate fail-closed (PRIMERA sentencia): super_admin o pertenencia a la clínica pedida.
  IF NOT (
       COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR p_clinica_id IN (SELECT private.clinicas_del_usuario())
  ) THEN
    RAISE EXCEPTION 'No autorizado para ver datos de esta clínica';
  END IF;

  RETURN QUERY
  SELECT c.id, c.medico_id, c.paciente_id, c.clinica_id, c.fecha, c.hora_inicio, c.hora_fin,
         c.motivo, c.estado::text, c.notas, c.created_at,
         p.nombre, p.email, p.telefono, p.apellido, p.auth_user_id
  FROM public.citas c
  LEFT JOIN public.pacientes p ON p.id = c.paciente_id
  WHERE
    c.clinica_id = p_clinica_id
    OR c.medico_id IN (
      SELECT mc.medico_id FROM public.medico_clinicas mc WHERE mc.clinica_id = p_clinica_id
    );
END;
$function$;
REVOKE ALL ON FUNCTION public.obtener_citas_clinica(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_citas_clinica(uuid) TO authenticated, service_role;

-- ============================================================
-- 4b) GATE PERTENENCIA — obtener_medicos_clinica (+ SET search_path='' que hoy le falta).
-- ============================================================
CREATE OR REPLACE FUNCTION public.obtener_medicos_clinica(p_clinica_id uuid)
RETURNS TABLE(medico_id uuid, es_principal boolean)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT (
       COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR p_clinica_id IN (SELECT private.clinicas_del_usuario())
  ) THEN
    RAISE EXCEPTION 'No autorizado para ver datos de esta clínica';
  END IF;

  RETURN QUERY
  SELECT mc.medico_id, mc.es_principal
  FROM public.medico_clinicas mc
  WHERE mc.clinica_id = p_clinica_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.obtener_medicos_clinica(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_medicos_clinica(uuid) TO authenticated, service_role;
