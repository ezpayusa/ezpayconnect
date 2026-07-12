-- 251: Pieza 2a — RPC confirmar_recepcion_receta (backend de la confirmación; la invoca la edge 2b).
-- Credencial = confirmacion_token (256 bits) que viaja en el link del email; NO usa auth.uid().
-- El país se DERIVA server-side (recetas.pais_id vía receta_base_id), nunca del cliente → cierra forja.
-- No devuelve NADA de PHI: solo un estado string.

CREATE OR REPLACE FUNCTION public.confirmar_recepcion_receta(
  p_token text, p_ip inet DEFAULT NULL, p_user_agent text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_ra_id uuid; v_pais uuid; v_n int;
BEGIN
  -- 1. Resolver la avanzada por token (respetando expiración); país derivado de la base.
  SELECT ra.id, r.pais_id INTO v_ra_id, v_pais
  FROM public.recetas_avanzadas ra
  JOIN public.recetas r ON r.id = ra.receta_base_id
  WHERE ra.confirmacion_token = p_token
    AND ra.confirmacion_token_expira_at > now();

  -- 2. Token inexistente o expirado → MISMO estado hacia afuera (no dar pistas a enumeración).
  IF NOT FOUND THEN
    RETURN 'token_invalido';
  END IF;

  -- 3. Caso límite: receta sin país (hoy inalcanzable) → no intentar el INSERT (evita not-null).
  IF v_pais IS NULL THEN
    RAISE WARNING 'confirmar_recepcion_receta: avanzada % sin pais_id, no se registra', v_ra_id;
    RETURN 'sin_pais';
  END IF;

  -- 4. Insert idempotente: 1 confirmación por receta (unique receta_avanzada_id).
  INSERT INTO public.confirmaciones_receta
    (receta_avanzada_id, pais_id, confirmada_ip, confirmada_user_agent)
  VALUES (v_ra_id, v_pais, p_ip, p_user_agent)
  ON CONFLICT ON CONSTRAINT confirmaciones_receta_avanzada_uniq DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 1 THEN
    RETURN 'confirmada';       -- primer click: registrada
  ELSE
    RETURN 'ya_confirmada';    -- token válido pero ya existía (idempotente)
  END IF;
END;
$function$;

-- Solo la edge (service_role) la invoca; no se expone por PostgREST.
REVOKE ALL ON FUNCTION public.confirmar_recepcion_receta(text, inet, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirmar_recepcion_receta(text, inet, text) FROM anon;          -- default-priv Supabase
REVOKE EXECUTE ON FUNCTION public.confirmar_recepcion_receta(text, inet, text) FROM authenticated; -- default-priv Supabase
GRANT EXECUTE ON FUNCTION public.confirmar_recepcion_receta(text, inet, text) TO service_role;
