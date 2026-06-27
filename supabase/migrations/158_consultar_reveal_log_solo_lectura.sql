-- 158 · RPC de SOLO LECTURA public.consultar_reveal_log — diagnóstico/validación del gate reveal-registrado.
-- private.reveal_log (mig 154) tiene REVOKE ALL + sin policy SELECT: acceso únicamente por RPC DEFINER. La 154 dejó
-- la lectura ("panel de detección") como trabajo futuro; este RPC la cubre SOLO para validar las puertas (R1/R2/R3).
-- Gate fail-closed: super_admin al tope con el predicado canónico private.tiene_rol(ARRAY['super_admin']) (el mismo
-- de aprobar_solicitud_campana / registrar_*_farmacia). SOLO SELECT: cero escrituras, no toca reveal_gate_flags.
-- RETURNS TABLE calza 1:1 con el esquema real de private.reveal_log (actor uuid, receta_base_id bigint, puerta text,
-- empresa_id uuid, ocurrido_at timestamptz). LIMIT acotado [1..1000]. NO activa nada; lectura pura.

CREATE OR REPLACE FUNCTION public.consultar_reveal_log(
  p_receta_base_id bigint DEFAULT NULL,
  p_puerta         text   DEFAULT NULL,
  p_limit          int    DEFAULT 200
)
RETURNS TABLE (
  actor          uuid,
  receta_base_id bigint,
  puerta         text,
  empresa_id     uuid,
  ocurrido_at    timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- 1) Gate super_admin (predicado YA EXISTENTE: private.tiene_rol, mig 067). Fail-closed.
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin';
  END IF;

  -- 2) Validar puerta si viene informada (mismo enum que el CHECK de private.reveal_log).
  IF p_puerta IS NOT NULL AND p_puerta NOT IN ('bandeja','walkin_qr','sinqr') THEN
    RAISE EXCEPTION 'Puerta inválida';
  END IF;

  -- 3/4) SOLO SELECT, filtros opcionales, ORDER BY ocurrido_at DESC, LIMIT acotado.
  RETURN QUERY
  SELECT rl.actor, rl.receta_base_id, rl.puerta, rl.empresa_id, rl.ocurrido_at
  FROM private.reveal_log rl
  WHERE (p_receta_base_id IS NULL OR rl.receta_base_id = p_receta_base_id)
    AND (p_puerta IS NULL OR rl.puerta = p_puerta)
  ORDER BY rl.ocurrido_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 1000);
END;
$function$;

-- 6) Cierre de permisos. El gate real es el check interno super_admin; el GRANT solo permite intentar (no a anon).
REVOKE ALL ON FUNCTION public.consultar_reveal_log(bigint, text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_reveal_log(bigint, text, int) TO authenticated;
