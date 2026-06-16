-- ============================================================
-- INCREMENTO 4 · Saneo QR de despacho (A-REFINADA) — SEGURIDAD / PHI
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — NO aplicar sin OK. Probes rojo-primero (P135–P146).
-- Decisiones (Oscar): 1a=A-refinada (recetas_avanzadas NO se retira; se endurece
-- en su sitio) · 1b=POR ÍTEM · 1c=TTL 30 días · 1d=recetas_dispensar a
-- admin/gerente_farmacia/supervisor/dependiente/cajero (delivery FUERA).
--
-- Modelo (del Paso 0): el médico crea recetas(id bigint)+receta_items(farmacia_id
-- int, por ítem); generar-pdf-receta crea recetas_avanzadas(receta_base_id text →
-- recetas.id) y hoy genera un codigo_qr DÉBIL. dispensaciones FK → recetas_avanzadas.
-- Aislamiento canónico: receta_items.farmacia_id → farmacias.empresa_id = mi_empresa_proveedor().
--
-- ⚠️ VALIDACIONES PRE-APLICACIÓN (correr y limpiar ANTES de aplicar):
--   V1: SELECT count(*) FROM receta_items ri LEFT JOIN farmacias f ON f.id=ri.farmacia_id
--        WHERE ri.farmacia_id IS NOT NULL AND f.id IS NULL;            -- huérfanos → 0
--   V2: SELECT count(*) FROM recetas_avanzadas WHERE receta_base_id !~ '^[0-9]+$';  -- no-numéricos → 0
--   V3: SELECT count(*) FROM recetas_avanzadas ra LEFT JOIN recetas r ON r.id = ra.receta_base_id::bigint
--        WHERE ra.receta_base_id ~ '^[0-9]+$' AND r.id IS NULL;        -- base huérfana → 0
-- Si V1/V2/V3 > 0 → DETENERSE y depurar; las FK fallarían.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Token FUERTE + TTL en recetas_avanzadas (en su sitio, no se retira)
--    DEFAULT volátil ⇒ cada fila existente recibe un token DISTINTO al reescribir.
-- ------------------------------------------------------------
ALTER TABLE public.recetas_avanzadas
  ADD COLUMN IF NOT EXISTS dispatch_token text NOT NULL DEFAULT encode(extensions.gen_random_bytes(32), 'hex'),
  ADD COLUMN IF NOT EXISTS dispatch_token_expira_at timestamptz NOT NULL DEFAULT (now() + interval '30 days');
-- TTL de filas existentes relativo a su emisión (no a la fecha de migración):
UPDATE public.recetas_avanzadas
   SET dispatch_token_expira_at = COALESCE(created_at, now()) + interval '30 days'
 WHERE dispatch_token_expira_at IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS recetas_avanzadas_dispatch_token_key
  ON public.recetas_avanzadas(dispatch_token);

-- ------------------------------------------------------------
-- 2) Estado de despacho POR ÍTEM (un solo uso por ítem)
-- ------------------------------------------------------------
ALTER TABLE public.receta_items
  ADD COLUMN IF NOT EXISTS dispensado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dispensado_at timestamptz;

-- ------------------------------------------------------------
-- 3) Puente per-ítem con FKs reales (tras validar V1–V3)
-- ------------------------------------------------------------
-- 3a) receta_items.farmacia_id → farmacias.id
ALTER TABLE public.receta_items
  ADD CONSTRAINT receta_items_farmacia_fk
  FOREIGN KEY (farmacia_id) REFERENCES public.farmacias(id);
-- 3b) recetas_avanzadas.receta_base_id (text) → recetas.id (bigint): normalizar tipo + FK
--     + NOT NULL (decisión 3) + UNIQUE (decisión 4: 1 recetas_avanzadas por receta →
--     un solo token vivo; generar-pdf-receta hará ON CONFLICT (receta_base_id) DO NOTHING).
ALTER TABLE public.recetas_avanzadas
  ALTER COLUMN receta_base_id TYPE bigint USING NULLIF(receta_base_id, '')::bigint;
ALTER TABLE public.recetas_avanzadas
  ALTER COLUMN receta_base_id SET NOT NULL;
ALTER TABLE public.recetas_avanzadas
  ADD CONSTRAINT recetas_avanzadas_receta_base_uniq UNIQUE (receta_base_id);
-- recetas tiene PK COMPUESTO (id, paciente_id); para FK a `id` SOLO se requiere una
-- constraint UNIQUE sobre id. Additivo y seguro: id es secuencial (recetas_id_seq), 0 dups.
ALTER TABLE public.recetas
  ADD CONSTRAINT recetas_id_uniq UNIQUE (id);
ALTER TABLE public.recetas_avanzadas
  ADD CONSTRAINT recetas_avanzadas_receta_base_fk
  FOREIGN KEY (receta_base_id) REFERENCES public.recetas(id);

-- ------------------------------------------------------------
-- 4) Permiso nuevo recetas_dispensar (matriz aprobada)
-- ------------------------------------------------------------
INSERT INTO public.permisos_empresa_rol (tipo_empresa, rol, accion)
SELECT 'farmacia', r, 'recetas_dispensar'
FROM unnest(ARRAY['admin','gerente_farmacia','supervisor','dependiente','cajero']) AS r
ON CONFLICT (tipo_empresa, rol, accion) DO NOTHING;

-- ------------------------------------------------------------
-- 5) dispensaciones: INSERT CERRADO para todos salvo el RPC definer.
--    Estado verificado (inventario): RLS ON; solo disp_superadmin_all + selects
--    de médico/paciente; NINGUNA policy INSERT de farmacia. Reforzamos defensa en
--    profundidad a nivel columna (las funciones definer corren como owner → no les
--    afecta este REVOKE).
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.dispensaciones FROM authenticated, anon;

-- ------------------------------------------------------------
-- 6) RPC verificar_receta_despacho(token) — POR ÍTEM, PHI mínima
--    Gate: auth.uid + tiene_permiso('recetas_dispensar') + farmacia del ítem ∈
--    mi_empresa_proveedor() + token válido y no expirado. Devuelve SOLO ítems del
--    actor; NUNCA teléfono/dirección/diagnóstico/firma/ítems de otra farmacia/select*.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verificar_receta_despacho(p_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_ra RECORD; v_receta_id bigint; v_pac_nombre text; v_items jsonb;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN RAISE EXCEPTION 'Token requerido'; END IF;

  SELECT ra.id, ra.receta_base_id, ra.estado_dispensacion, ra.dispatch_token
    INTO v_ra
  FROM public.recetas_avanzadas ra
  WHERE ra.dispatch_token = p_token
    AND COALESCE(ra.dispatch_token_expira_at > now(), false);   -- token NO expirado
  IF NOT FOUND THEN RAISE EXCEPTION 'Token inválido o expirado'; END IF;

  v_receta_id := v_ra.receta_base_id;

  SELECT p.nombre INTO v_pac_nombre
  FROM public.recetas r JOIN public.pacientes p ON p.id = r.paciente_id
  WHERE r.id = v_receta_id;

  -- Ítems SOLO de la(s) farmacia(s) de la empresa del actor (aislamiento per-ítem)
  SELECT jsonb_agg(jsonb_build_object(
           'item_id', ri.id,
           'nombre_medicamento', ri.nombre_medicamento,
           'dosis', ri.dosis,
           'frecuencia', ri.frecuencia,
           'cantidad', ri.cantidad,
           'instrucciones', ri.instrucciones,
           'dispensado', ri.dispensado))
    INTO v_items
  FROM public.receta_items ri
  JOIN public.farmacias f ON f.id = ri.farmacia_id
  WHERE ri.receta_id = v_receta_id
    AND COALESCE(f.empresa_id = v_emp, false);

  IF v_items IS NULL THEN
    RAISE EXCEPTION 'No autorizado: la receta no tiene ítems asignados a tu farmacia';
  END IF;

  RETURN jsonb_build_object(
    'receta_id', v_receta_id,
    'dispatch_token', v_ra.dispatch_token,
    'estado_dispensacion', v_ra.estado_dispensacion,
    'paciente_nombre', v_pac_nombre,   -- a lo sumo; sin teléfono/dirección
    'items', v_items                   -- solo los del actor
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.verificar_receta_despacho(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.verificar_receta_despacho(text) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 7) RPC registrar_dispensacion(token, item_ids[], farmaceutico) — POR ÍTEM, un solo uso
--    Mismo gate; escribe dispensaciones SOLO los ítems del actor no dispensados.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_dispensacion(
  p_token text, p_item_ids bigint[], p_farmaceutico text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid; v_emp uuid; v_ra RECORD; v_receta_id bigint; v_n int := 0; r RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_dispensar'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede despachar recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa farmacia'; END IF;
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN RAISE EXCEPTION 'Token requerido'; END IF;

  SELECT ra.id, ra.receta_base_id, ra.paciente_id, ra.medico_id, ra.dispatch_token
    INTO v_ra
  FROM public.recetas_avanzadas ra
  WHERE ra.dispatch_token = p_token
    AND COALESCE(ra.dispatch_token_expira_at > now(), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Token inválido o expirado'; END IF;
  v_receta_id := v_ra.receta_base_id;

  FOR r IN
    SELECT ri.id, ri.farmacia_id, ri.nombre_medicamento, ri.cantidad, ri.precio_unitario
    FROM public.receta_items ri
    JOIN public.farmacias f ON f.id = ri.farmacia_id
    WHERE ri.receta_id = v_receta_id
      AND COALESCE(f.empresa_id = v_emp, false)            -- aislamiento por farmacia
      AND ri.id = ANY (COALESCE(p_item_ids, ARRAY[]::bigint[]))
      AND ri.dispensado = false                            -- un solo uso
  LOOP
    UPDATE public.receta_items SET dispensado = true, dispensado_at = now() WHERE id = r.id;
    -- medicamentos_dispensados como ARRAY jsonb: el trigger trg_actualizar_stock
    -- itera con jsonb_array_elements (espera array; objeto → 22023).
    INSERT INTO public.dispensaciones
      (receta_avanzada_id, farmacia_id, paciente_id, medico_id, codigo_qr,
       medicamentos_dispensados, cantidad_items, total_dispensado, estado_dispensacion,
       farmaceutico_nombre, fecha_dispensacion)
    VALUES
      (v_ra.id, r.farmacia_id, v_ra.paciente_id, v_ra.medico_id, v_ra.dispatch_token,
       jsonb_build_array(jsonb_build_object('item_id', r.id, 'nombre', r.nombre_medicamento, 'cantidad', r.cantidad)),
       1, COALESCE(r.precio_unitario, 0) * r.cantidad, 'completada', p_farmaceutico, now());
    v_n := v_n + 1;
  END LOOP;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Sin ítems despachables (ya dispensados, no asignados a tu farmacia, o ids inválidos)';
  END IF;
  RETURN jsonb_build_object('despachados', v_n);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.registrar_dispensacion(text, bigint[], text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_dispensacion(text, bigint[], text) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 8) Arreglar/endurecer el trigger existente actualizar_stock_dispensacion. Tenía DOS
--    bugs latentes (rompían cualquier dispensación con medicamentos_dispensados):
--    (a) tablas SIN calificar y SIN SET search_path → desde un RPC definer con
--        search_path='' fallaba 42P01. Fijamos search_path='public' + calificamos.
--    (b) `item RECORD` + `SELECT * FROM jsonb_array_elements(...)` → `item` era un
--        RECORD (col `value`), así que `item->>'cantidad'` daba 42883. Lo correcto:
--        `item jsonb` + `SELECT value`.
--    (c) copiaba `NEW.estado_dispensacion` ('completada') a recetas_avanzadas, cuyo CHECK
--        solo admite {pendiente,dispensada,parcial,rechazada} → 23514. Mapeo per-ítem:
--        'dispensada' si NO quedan ítems pendientes de la receta, si no 'parcial'.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actualizar_stock_dispensacion()
RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE
    item jsonb;
BEGIN
    IF NEW.medicamentos_dispensados IS NOT NULL THEN
        FOR item IN SELECT value FROM jsonb_array_elements(NEW.medicamentos_dispensados)
        LOOP
            UPDATE public.farmacia_medicamentos
            SET stock_actual = GREATEST(stock_actual - COALESCE((item->>'cantidad')::INTEGER, 0), 0),
                updated_at = NOW()
            WHERE farmacia_id = NEW.farmacia_id
              AND nombre_medicamento = item->>'nombre'
              AND activo = true;
        END LOOP;
    END IF;

    UPDATE public.recetas_avanzadas ra
    SET estado_dispensacion = CASE
          WHEN NOT EXISTS (SELECT 1 FROM public.receta_items ri
                           WHERE ri.receta_id = ra.receta_base_id AND ri.dispensado = false)
            THEN 'dispensada' ELSE 'parcial' END,
        fecha_dispensacion = NEW.fecha_dispensacion,
        farmacia_id = NEW.farmacia_id::TEXT
    WHERE ra.id = NEW.receta_avanzada_id;

    RETURN NEW;
END;
$function$;

-- ============================================================
-- CAMBIOS DE CÓDIGO QUE ACOMPAÑAN (no en esta migración; van en el mismo paquete):
--  · BORRAR edge functions public/verificar-receta-qr y registrar-dispensacion
--    + sus bloques en supabase/config.toml. (Eran service_role sin check de rol.)
--  · generar-pdf-receta: dejar de emitir `EZP-…`; el QR del PDF usa el
--    `dispatch_token` FUERTE de la fila recetas_avanzadas recién creada (sigue
--    creando la fila + PDF; PacienteDetallePage sigue leyendo recetas_avanzadas).
--  · useRecetas.ts: dejar de generar `EZP-…` en cliente (recetas.codigo_qr ya no
--    participa del despacho).
--  · DispensarRecetaPage (o pantalla de farmacia): llamar supabase.rpc(
--    'verificar_receta_despacho'/'registrar_dispensacion') con el JWT del usuario.
-- CIERRE DE TOKEN DÉBIL: el despacho resuelve SOLO por `dispatch_token` (los RPC no
-- consultan `codigo_qr`); con las 2 edge functions borradas, NINGÚN camino resuelve
-- un `EZP-…`. Los codigo_qr viejos quedan inertes.
-- ============================================================
