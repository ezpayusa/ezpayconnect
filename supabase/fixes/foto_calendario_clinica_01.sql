-- Foto del medico en el calendario de clinica (frente foto-medico, superficie admin).
-- Agrega foto_url = COALESCE(medicos.foto_url, perfiles.avatar_url) a listar_medicos_clinica.
-- El RETURNS TABLE cambia de tipo -> NO basta CREATE OR REPLACE; se hace DROP + CREATE.
-- Preserva EXACTO: gate private.es_staff_calendario_clinica, plpgsql STABLE SECURITY DEFINER,
-- SET search_path TO '', y los REVOKE/GRANT de la mig 232.
-- Idempotente. Aplicar con: supabase db query --linked -f supabase/fixes/foto_calendario_clinica_01.sql

BEGIN;

DROP FUNCTION IF EXISTS public.listar_medicos_clinica(uuid);

CREATE FUNCTION public.listar_medicos_clinica(p_clinica_id uuid)
RETURNS TABLE(medico_id uuid, nombre_completo text, es_principal boolean, foto_url text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
  IF NOT private.es_staff_calendario_clinica(p_clinica_id) THEN
    RAISE EXCEPTION 'No autorizado para ver los medicos de esta clinica';
  END IF;
  RETURN QUERY
    SELECT p.id, p.nombre_completo, mc.es_principal,
           COALESCE(m.foto_url, p.avatar_url) AS foto_url
    FROM public.medico_clinicas mc
    JOIN public.perfiles p ON p.id = mc.medico_id
    LEFT JOIN public.medicos m ON m.id = mc.medico_id
    WHERE mc.clinica_id = p_clinica_id AND p.rol = 'medico'
    ORDER BY p.nombre_completo;
END; $fn$;

REVOKE EXECUTE ON FUNCTION public.listar_medicos_clinica(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_medicos_clinica(uuid) TO authenticated;

COMMIT;
