-- 188 Trabajo B Parte 3 (backend) — RPC para que el super_admin liste las propuestas de especialidad
-- Complementa resolver_propuesta_especialidad (mig 186). Patrón panel super_admin = listar_canjes_pendientes.
-- Orden elegido: PENDIENTES primero, luego created_at DESC (las más nuevas arriba).

CREATE OR REPLACE FUNCTION public.listar_propuestas_especialidad(p_estado text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  -- Gate exacto de super_admin (mismo chequeo que resolver_propuesta_especialidad / resolver_canje).
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id',                 ep.id,
             'nombre_propuesto',   ep.nombre_propuesto,
             'estado',             ep.estado,
             'created_at',         ep.created_at,
             'resolved_at',        ep.resolved_at,
             'resolved_by',        ep.resolved_by,
             'medico_id',          ep.medico_id,
             'medico_nombre',      m.nombre_completo,
             'resolved_by_nombre', rp.nombre_completo
           )
           ORDER BY (ep.estado = 'pendiente') DESC, ep.created_at DESC)
    FROM public.especialidades_propuestas ep
    LEFT JOIN public.medicos  m  ON m.id  = ep.medico_id
    LEFT JOIN public.perfiles rp ON rp.id = ep.resolved_by       -- super_admin que resolvió (si aplica)
    WHERE p_estado IS NULL OR ep.estado = p_estado
  ), '[]'::jsonb);
END;
$function$;

REVOKE ALL     ON FUNCTION public.listar_propuestas_especialidad(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_propuestas_especialidad(text) TO authenticated;  -- gate interno = super_admin
