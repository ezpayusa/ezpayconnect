-- Cierra el origen server-side: aprobar_solicitud_campana ahora graba empresa_id + solicitud_campana_id
-- en la campana (antes los perdia, aunque v_s.empresa_id y p_solicitud_id estaban a mano). Verbatim de la
-- def viva (mig 222) salvo esas 2 columnas. Misma firma/authz/checks. Aplicar con -f.
CREATE OR REPLACE FUNCTION public.aprobar_solicitud_campana(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_s RECORD; v_campana_id integer;
BEGIN
  IF NOT (
    COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    OR (public.get_auth_user_rol() = 'admin_pais' AND EXISTS (
          SELECT 1 FROM public.solicitudes_campana WHERE id = p_solicitud_id AND pais_id = public.get_auth_user_pais_id()
        ))
  ) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin aprueba campañas';
  END IF;
  SELECT * INTO v_s FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada'; END IF;
  -- validación existente (que la empresa realmente opere en el país de la campaña): NO se toca.
  IF NOT COALESCE(private.empresa_opera_en_pais(v_s.empresa_id, v_s.pais_id), false) THEN
    RAISE EXCEPTION 'La empresa no opera en el país de la campaña';
  END IF;

  INSERT INTO public.campanas_publicitarias
    (titulo, descripcion, tipo, imagen_url, link_url, fecha_inicio, fecha_fin,
     activa, condicion_filtro, genero_filtro, edad_min, edad_max, pais_id,
     empresa_id, solicitud_campana_id)
  VALUES
    (v_s.titulo, v_s.descripcion, v_s.tipo, v_s.imagen_url, v_s.link_url,
     v_s.fecha_inicio, v_s.fecha_fin, true, v_s.condicion_filtro, v_s.genero_filtro,
     v_s.edad_min, v_s.edad_max, v_s.pais_id,
     v_s.empresa_id, p_solicitud_id)
  RETURNING id INTO v_campana_id;

  UPDATE public.solicitudes_campana
    SET estado = 'publicada', notas_admin = COALESCE(p_notas_admin, notas_admin)
    WHERE id = p_solicitud_id;

  RETURN v_campana_id;
END;
$function$;
