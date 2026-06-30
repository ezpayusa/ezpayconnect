-- 180 ajuste "no recanjear el mismo premio"
-- Regla: un paciente NO puede volver a canjear un premio del que ya tiene un canje en
-- 'pendiente' | 'aprobado' | 'entregado'. SÍ puede si su único previo de ese premio fue 'rechazado'.
-- Modifica 2 RPCs: solicitar_canje (guard server-side) + listar_premios_disponibles (flag ya_canjeado).

-- ============================================================
-- 1) solicitar_canje — agrega GUARD anti re-canje (dentro del lock, antes de reservar)
-- ============================================================
CREATE OR REPLACE FUNCTION public.solicitar_canje(_premio_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid    uuid;
  v_pid    bigint;
  v_pais   uuid;
  v_premio RECORD;
  v_saldo  int;
  v_mov_id bigint;
  v_canje  bigint;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT id, pais_id INTO v_pid, v_pais FROM public.pacientes WHERE auth_user_id = v_uid;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;

  -- LOCK de la fila del premio: serializa solicitudes concurrentes del mismo premio (anti oversell).
  SELECT id, costo_puntos, pais_id, stock, activo INTO v_premio
  FROM public.premios WHERE id = _premio_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'premio_no_disponible'; END IF;
  IF (NOT v_premio.activo) OR v_premio.stock <= 0 THEN RAISE EXCEPTION 'premio_no_disponible'; END IF;
  IF v_premio.pais_id IS DISTINCT FROM v_pais THEN RAISE EXCEPTION 'premio_otro_pais'; END IF;

  v_saldo := COALESCE((SELECT sum(puntos) FROM public.puntos_movimientos WHERE paciente_id = v_pid), 0);
  IF v_saldo < v_premio.costo_puntos THEN RAISE EXCEPTION 'saldo_insuficiente'; END IF;

  -- GUARD anti re-canje: bloquear si ya hay un canje VIGENTE (no rechazado) del mismo premio.
  IF EXISTS (
    SELECT 1 FROM public.canjes
    WHERE paciente_id = v_pid AND premio_id = _premio_id
      AND estado IN ('pendiente','aprobado','entregado')
  ) THEN
    RAISE EXCEPTION 'canje_duplicado';
  END IF;

  -- a) reserva de puntos (negativo)
  INSERT INTO public.puntos_movimientos (paciente_id, puntos, tipo, motivo)
  VALUES (v_pid, - v_premio.costo_puntos, 'canje_reserva', 'Reserva por canje de premio')
  RETURNING id INTO v_mov_id;

  -- b) baja stock (seguro bajo el lock)
  UPDATE public.premios SET stock = stock - 1 WHERE id = _premio_id;

  -- c) canje pendiente con snapshot del costo
  INSERT INTO public.canjes (paciente_id, premio_id, costo_puntos, estado, movimiento_reserva_id)
  VALUES (v_pid, _premio_id, v_premio.costo_puntos, 'pendiente', v_mov_id)
  RETURNING id INTO v_canje;

  RETURN jsonb_build_object('ok', true, 'canje_id', v_canje, 'saldo_restante', v_saldo - v_premio.costo_puntos);
END;
$function$;

REVOKE ALL     ON FUNCTION public.solicitar_canje(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.solicitar_canje(bigint) TO authenticated;

-- ============================================================
-- 2) listar_premios_disponibles — agrega flag ya_canjeado por premio
-- ============================================================
CREATE OR REPLACE FUNCTION public.listar_premios_disponibles()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid   uuid;
  v_pid   bigint;
  v_pais  uuid;
  v_saldo int;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT id, pais_id INTO v_pid, v_pais FROM public.pacientes WHERE auth_user_id = v_uid;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;

  v_saldo := COALESCE((SELECT sum(puntos) FROM public.puntos_movimientos WHERE paciente_id = v_pid), 0);

  RETURN jsonb_build_object(
    'saldo', v_saldo,
    'premios', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', p.id, 'nombre', p.nombre, 'descripcion', p.descripcion,
               'costo_puntos', p.costo_puntos, 'tipo', p.tipo, 'stock', p.stock,
               'imagen_path', p.imagen_path,
               -- true si el paciente ya tiene un canje vigente (no rechazado) de este premio.
               'ya_canjeado', EXISTS (
                 SELECT 1 FROM public.canjes cc
                 WHERE cc.paciente_id = v_pid AND cc.premio_id = p.id
                   AND cc.estado IN ('pendiente','aprobado','entregado')
               )
             ) ORDER BY p.costo_puntos)
      FROM public.premios p
      WHERE p.activo = true AND p.stock > 0 AND p.pais_id = v_pais
    ), '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL     ON FUNCTION public.listar_premios_disponibles() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_premios_disponibles() TO authenticated;
