-- 154 · Ola R0 — gate "reveal-registrado" (MAQUINARIA INERTE).
-- Nada cambia de comportamiento: las 3 puertas (bandeja / walk-in QR / sin-QR) SIGUEN devolviendo el medicamento
-- como hoy. Solo se crea la maquinaria APAGADA: tabla de log, flags kill-switch en false, y un RPC DORMANT que
-- ninguna puerta llama aún (se cablean en R1/R2/R3; lección 51: RPC nuevo = inerte en main hasta su hook).
-- Decisiones: Q-R1 registro BLOQUEANTE (el reveal es condición de mostrar); Q-R2 N filas (sin UNIQUE), historial.
-- CORRECCIÓN al doc: reveal_log.empresa_id = UUID (mi_empresa_proveedor() devuelve uuid; el doc decía bigint).

-- ===== 1) Tabla private.reveal_log =====
CREATE TABLE IF NOT EXISTS private.reveal_log (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor          uuid   NOT NULL,
  receta_base_id bigint NOT NULL,
  puerta         text   NOT NULL CHECK (puerta IN ('bandeja','walkin_qr','sinqr')),
  empresa_id     uuid,                 -- denormalizado (uuid) para confinar el panel de detección futuro
  ocurrido_at    timestamptz NOT NULL DEFAULT now()
  -- Sin UNIQUE(actor, receta_base_id): historial completo, N filas (Q-R2).
);
ALTER TABLE private.reveal_log ENABLE ROW LEVEL SECURITY;
-- Sin policy de INSERT/SELECT: acceso SOLO por RPC DEFINER (corre como owner, no sujeto a RLS). Lectura futura por
-- otro RPC DEFINER (panel de detección). Lección 60: TRUNCATE no es RLS-gated → revocar explícito. Fail-closed.
REVOKE ALL ON private.reveal_log FROM anon, authenticated, public;

-- ===== 2) Flag kill-switch private.reveal_gate_flags (patrón fail-safe de delivery_flags) =====
CREATE TABLE IF NOT EXISTS private.reveal_gate_flags (
  puerta text PRIMARY KEY CHECK (puerta IN ('bandeja','walkin_qr','sinqr')),
  activo boolean NOT NULL DEFAULT false
);
ALTER TABLE private.reveal_gate_flags ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.reveal_gate_flags FROM anon, authenticated, public;
-- R0: las 3 puertas en false → INERTE. FAIL-SAFE (lo consumirá el cableado R1/R2/R3): fila ausente O activo=false
-- → comportamiento VIEJO (med en cabecera, sin gate). El gate solo actúa con activo=true explícito.
INSERT INTO private.reveal_gate_flags (puerta, activo) VALUES
  ('bandeja', false), ('walkin_qr', false), ('sinqr', false)
ON CONFLICT (puerta) DO NOTHING;

-- ===== 3) RPC revelar_items_receta (DORMANT en R0: existe pero ninguna puerta lo llama) =====
CREATE OR REPLACE FUNCTION public.revelar_items_receta(p_receta_base_id bigint, p_puerta text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_emp uuid; v_items jsonb;
BEGIN
  -- gate de permiso (mismo que listar_recetas_entrantes / verificar_receta_despacho / buscar_recetas_pendientes_paciente)
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  -- p_puerta validado contra el MISMO enum del CHECK de la tabla
  IF p_puerta NOT IN ('bandeja','walkin_qr','sinqr') THEN
    RAISE EXCEPTION 'Puerta inválida';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;

  -- confinamiento: ítems de la receta cuya farmacia ∈ empresa del caller Y sucursal_visible Y dispensado=false
  -- (mismo confinamiento que listar/verificar/buscar). Misma forma de ítems que devuelven hoy las puertas.
  SELECT jsonb_agg(jsonb_build_object(
           'item_id', ri.id,
           'nombre_medicamento', ri.nombre_medicamento,
           'dosis', ri.dosis,
           'frecuencia', ri.frecuencia,
           'cantidad', ri.cantidad,
           'instrucciones', ri.instrucciones,
           'farmacia_id', ri.farmacia_id) ORDER BY ri.id)
    INTO v_items
  FROM public.receta_items ri
  JOIN public.farmacias f ON f.id = ri.farmacia_id
  WHERE ri.receta_id = p_receta_base_id
    AND COALESCE(f.empresa_id = v_emp, false)
    AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)
    AND ri.dispensado = false;

  -- DECISIÓN confinamiento (no-leak): sin ítems visibles → RAISE ANTES de loguear. No es un reveal real → NO deja
  -- fila en reveal_log, y NUNCA expone ítems ajenos. (Espeja el `IF v_items IS NULL THEN RAISE` de listar/verificar.)
  IF v_items IS NULL THEN
    RAISE EXCEPTION 'No autorizado: la receta no tiene ítems asignados a tu farmacia';
  END IF;

  -- REGISTRO BLOQUEANTE (Q-R1): el reveal es CONDICIÓN de mostrar. INSERT antes del RETURN; si el INSERT falla,
  -- la función falla (sin EXCEPTION-swallow, sin best-effort). No hay forma de ver el med sin dejar el registro.
  -- Q-R1 BLOQUEANTE: NO envolver este INSERT en BEGIN/EXCEPTION. El registro del reveal es condición de mostrar;
  -- si se traga el error del log, se reabre la ventana "vio sin registro". El RETURN debe ser inalcanzable sin este INSERT.
  INSERT INTO private.reveal_log (actor, receta_base_id, puerta, empresa_id)
  VALUES (auth.uid(), p_receta_base_id, p_puerta, v_emp);

  RETURN v_items;
END;
$function$;
REVOKE ALL ON FUNCTION public.revelar_items_receta(bigint, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.revelar_items_receta(bigint, text) TO authenticated;
