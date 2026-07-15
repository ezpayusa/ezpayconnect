-- 261: exponer citas.llegada_at (agregada por mig 260) en obtener_citas_clinica.
-- DROP+CREATE porque cambia el RETURNS TABLE (CREATE OR REPLACE no permite alterar columnas de retorno).
-- IDÉNTICA a la definición previa salvo 2 cambios: (1) llegada_at al FINAL del RETURNS TABLE,
-- (2) c.llegada_at al FINAL del SELECT. Gate/STABLE/DEFINER/search_path/WHERE/JOIN sin tocar.
-- Sin dependencias en BD (0 vistas/funciones). Callers del front mapean por nombre → compat hacia atrás.
BEGIN;

DROP FUNCTION public.obtener_citas_clinica(uuid);

CREATE FUNCTION public.obtener_citas_clinica(p_clinica_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(
   id bigint, medico_id uuid, paciente_id bigint, clinica_id uuid,
   fecha date, hora_inicio time without time zone, hora_fin time without time zone,
   motivo text, estado text, notas text, created_at timestamp with time zone,
   paciente_nombre text, paciente_email text, paciente_telefono text,
   paciente_apellido text, paciente_auth_user_id uuid,
   llegada_at timestamp with time zone
 )
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
         p.nombre, p.email, p.telefono, p.apellido, p.auth_user_id,
         c.llegada_at
  FROM public.citas c
  LEFT JOIN public.pacientes p ON p.id = c.paciente_id
  WHERE
    c.clinica_id = p_clinica_id
    OR c.medico_id IN (
      SELECT mc.medico_id FROM public.medico_clinicas mc WHERE mc.clinica_id = p_clinica_id
    );
END;
$function$;

-- Permisos explícitos (una función nueva nace con EXECUTE a PUBLIC): reponer el estado previo.
REVOKE ALL     ON FUNCTION public.obtener_citas_clinica(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obtener_citas_clinica(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.obtener_citas_clinica(uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.obtener_citas_clinica(uuid) TO service_role;

COMMIT;
