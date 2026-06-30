-- 179 Ola 3 backend "canje de premios con aprobación"
-- RESERVA AL SOLICITAR: descuenta puntos (mov negativo) + baja stock al solicitar; super_admin aprueba/rechaza.
-- Rechazo = REVERSA (devuelve puntos + stock). Lock de fila del premio (FOR UPDATE) serializa concurrencia.

-- ============================================================
-- 1) TABLA canjes
-- ============================================================
CREATE TABLE IF NOT EXISTS public.canjes (
  id                    bigserial PRIMARY KEY,
  paciente_id           bigint NOT NULL REFERENCES public.pacientes(id),
  premio_id             bigint NOT NULL REFERENCES public.premios(id),
  costo_puntos          int    NOT NULL,                        -- snapshot del costo al solicitar
  estado                text   NOT NULL DEFAULT 'pendiente'
                          CHECK (estado IN ('pendiente','aprobado','rechazado','entregado')),
  movimiento_reserva_id bigint REFERENCES public.puntos_movimientos(id),  -- la fila negativa que reservó
  solicitado_at         timestamptz NOT NULL DEFAULT now(),
  resuelto_at           timestamptz,
  resuelto_por          uuid,
  nota_resolucion       text
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.canjes FROM authenticated;  -- escritura solo por RPC DEFINER
REVOKE ALL ON public.canjes FROM anon;

ALTER TABLE public.canjes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Paciente ve sus canjes" ON public.canjes;
CREATE POLICY "Paciente ve sus canjes" ON public.canjes
  FOR SELECT TO authenticated USING (private.paciente_es_mio(paciente_id));
DROP POLICY IF EXISTS "Super admin ve todos los canjes" ON public.canjes;
CREATE POLICY "Super admin ve todos los canjes" ON public.canjes
  FOR SELECT TO authenticated USING (private.tiene_rol(ARRAY['super_admin']));

-- ============================================================
-- 2) RPC solicitar_canje — reserva atómica (puntos + stock) bajo lock del premio
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
-- 3) RPC resolver_canje — super_admin aprueba/rechaza (rechazo = reversa)
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolver_canje(_canje_id bigint, _aprobar boolean, _nota text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_canje RECORD;
  v_estado text;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  -- LOCK + anti doble-resolución
  SELECT id, paciente_id, premio_id, costo_puntos, estado INTO v_canje
  FROM public.canjes WHERE id = _canje_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'canje_inexistente'; END IF;
  IF v_canje.estado <> 'pendiente' THEN RAISE EXCEPTION 'canje_ya_resuelto'; END IF;

  IF _aprobar THEN
    v_estado := 'aprobado';
    -- puntos y stock YA descontados al solicitar; aprobar no los toca.
  ELSE
    v_estado := 'rechazado';
    -- REVERSA: devolver puntos + stock reservados.
    INSERT INTO public.puntos_movimientos (paciente_id, puntos, tipo, motivo)
    VALUES (v_canje.paciente_id, v_canje.costo_puntos, 'canje_reversa', 'Reversa por rechazo de canje');
    UPDATE public.premios SET stock = stock + 1 WHERE id = v_canje.premio_id;
  END IF;

  UPDATE public.canjes
  SET estado = v_estado, resuelto_at = now(), resuelto_por = auth.uid(), nota_resolucion = _nota
  WHERE id = _canje_id;

  RETURN jsonb_build_object('ok', true, 'estado', v_estado);
END;
$function$;

REVOKE ALL     ON FUNCTION public.resolver_canje(bigint, boolean, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.resolver_canje(bigint, boolean, text) TO authenticated;  -- gate interno = super_admin

-- ============================================================
-- 4) RPC listar_canjes_pendientes — panel super_admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.listar_canjes_pendientes()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'canje_id', c.id, 'solicitado_at', c.solicitado_at, 'costo_puntos', c.costo_puntos,
             'paciente_id', c.paciente_id, 'paciente_nombre', p.nombre || ' ' || COALESCE(p.apellido, ''),
             'premio_id', c.premio_id, 'premio_nombre', pr.nombre, 'premio_tipo', pr.tipo
           ) ORDER BY c.solicitado_at)
    FROM public.canjes c
    JOIN public.pacientes p  ON p.id  = c.paciente_id
    JOIN public.premios   pr ON pr.id = c.premio_id
    WHERE c.estado = 'pendiente'
  ), '[]'::jsonb);
END;
$function$;

REVOKE ALL     ON FUNCTION public.listar_canjes_pendientes() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_canjes_pendientes() TO authenticated;  -- gate interno = super_admin

-- ============================================================
-- 5) RPC mis_canjes — el paciente ve SUS canjes
-- ============================================================
CREATE OR REPLACE FUNCTION public.mis_canjes()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid; v_pid bigint;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT id INTO v_pid FROM public.pacientes WHERE auth_user_id = v_uid;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'canje_id', c.id, 'estado', c.estado, 'costo_puntos', c.costo_puntos,
             'solicitado_at', c.solicitado_at, 'resuelto_at', c.resuelto_at,
             'premio_nombre', pr.nombre, 'premio_tipo', pr.tipo, 'nota_resolucion', c.nota_resolucion
           ) ORDER BY c.solicitado_at DESC)
    FROM public.canjes c JOIN public.premios pr ON pr.id = c.premio_id
    WHERE c.paciente_id = v_pid
  ), '[]'::jsonb);
END;
$function$;

REVOKE ALL     ON FUNCTION public.mis_canjes() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mis_canjes() TO authenticated;

-- ============================================================
-- 6) SEED premios GT de prueba (PERSISTEN, para QA del front). Guard NOT EXISTS por (nombre,pais) → re-apply seguro.
-- ============================================================
INSERT INTO public.premios (nombre, descripcion, costo_puntos, pais_id, tipo, stock, activo)
SELECT v.nombre, v.descripcion, v.costo_puntos, v.pais_id::uuid, v.tipo, v.stock, true
FROM (VALUES
  ('Descuento 10% consulta', '10% de descuento en tu proxima consulta', 20, 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909', 'descuento',  50),
  ('Termo SOFTMED',          'Termo de acero inoxidable',                50, 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909', 'fisico',     10),
  ('Sorteo mensual',         'Participa en el sorteo del mes',           10, 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909', 'sorteo',    100)
) AS v(nombre, descripcion, costo_puntos, pais_id, tipo, stock)
WHERE NOT EXISTS (
  SELECT 1 FROM public.premios pe WHERE pe.nombre = v.nombre AND pe.pais_id = v.pais_id::uuid
);
