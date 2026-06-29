-- 172 permisos_pendientes_paciente
-- RPC reusable: permisos del catálogo activo que el paciente NUNCA respondió (ni concedió ni revocó).
-- "Pendiente" = codigo activo SIN ninguna fila en public.consentimientos para ese paciente.
-- Excluye siempre 'tratamiento_phi' (aviso informativo, no entra al nudge).
-- Gate de acceso: espejo EXACTO de estado_consentimiento_paciente (mig 170). No modifica tablas existentes.

CREATE OR REPLACE FUNCTION public.permisos_pendientes_paciente(p_paciente_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  IF NOT (
       COALESCE(private.paciente_es_mio(p_paciente_id), false)
    OR ( private.tiene_rol(ARRAY['medico','asistente_medico']) AND private.paciente_en_clinica_de(p_paciente_id::integer) )
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  ) THEN RAISE EXCEPTION 'No autorizado'; END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(
             jsonb_build_object('codigo', p.codigo, 'etiqueta', p.etiqueta)
             ORDER BY p.codigo
           )
    FROM (
      -- catálogo activo, una fila por código (versión activa más alta = espejo del resolver)
      SELECT DISTINCT ON (cp.codigo) cp.codigo, cp.etiqueta
      FROM public.consentimiento_permisos cp
      WHERE cp.activo = true
        AND cp.codigo <> 'tratamiento_phi'
      ORDER BY cp.codigo, cp.version DESC
    ) p
    WHERE p.codigo NOT IN (
      SELECT DISTINCT c.permiso_codigo
      FROM public.consentimientos c
      WHERE c.paciente_id = p_paciente_id
    )
  ), '[]'::jsonb);
END;
$function$;

REVOKE ALL     ON FUNCTION public.permisos_pendientes_paciente(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.permisos_pendientes_paciente(bigint) TO authenticated;
