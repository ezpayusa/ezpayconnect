-- 152 · F1.5 — Detalle del repartidor: meds despachados + cobrado_at + evidencias separadas.
-- ADITIVA / RETROCOMPATIBLE con la PWA F1 EN PROD:
--   * entregas.evidencia_path SE MANTIENE viva (la PWA en prod la lee). NO se dropea acá → cleanup FUTURO post-merge.
--   * registrar_evidencia_entrega gana p_tipo OPCIONAL (DEFAULT NULL): la llamada vieja (p_entrega_id, p_path) sigue
--     resolviendo a ESTA función (una sola función, sin ambigüedad) y SIGUE seteando evidencia_path.
--   * listar_entregas_delivery NO se toca (firma intacta). Los meds/cobrado_at/evidencias van por el RPC NUEVO
--     detalle_entrega_delivery, que el front viejo aún no llama → 0 impacto hasta el merge del pulido.
-- Idempotente.

-- ===== 1) Tabla entrega_evidencias (N por tipo + auditoría) =====
CREATE TABLE IF NOT EXISTS public.entrega_evidencias (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entrega_id  bigint NOT NULL REFERENCES public.entregas(id) ON DELETE CASCADE,
  tipo        text   NOT NULL CHECK (tipo IN ('foto','firma')),
  path        text   NOT NULL,
  subido_at   timestamptz NOT NULL DEFAULT now(),
  subido_por  uuid REFERENCES public.cuentas_proveedor(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_entrega_evidencias_entrega_tipo ON public.entrega_evidencias(entrega_id, tipo);

ALTER TABLE public.entrega_evidencias ENABLE ROW LEVEL SECURITY;

-- RLS espejo de entregas (vía la entrega padre): lectura confinada empresa + sucursal_visible + slice delivery.
DROP POLICY IF EXISTS entrega_evidencias_select ON public.entrega_evidencias;
CREATE POLICY entrega_evidencias_select ON public.entrega_evidencias FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.entregas e
  WHERE e.id = entrega_evidencias.entrega_id
    AND private.entrega_visible(e.empresa_id, e.farmacia_id, e.delivery_id)
));

-- Escritura SOLO vía RPC DEFINER → sin DML directo. (SELECT queda gobernado por la policy de arriba.)
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, TRIGGER, REFERENCES ON public.entrega_evidencias FROM anon, authenticated;

-- ===== 2) registrar_evidencia_entrega: + p_tipo OPCIONAL, escribe la tabla nueva, MANTIENE evidencia_path =====
-- Drop de ambas firmas (idempotencia) y CREATE con p_tipo DEFAULT NULL.
DROP FUNCTION IF EXISTS public.registrar_evidencia_entrega(bigint, text);
DROP FUNCTION IF EXISTS public.registrar_evidencia_entrega(bigint, text, text);
CREATE FUNCTION public.registrar_evidencia_entrega(p_entrega_id bigint, p_path text, p_tipo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_tipo text;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_actualizar_estado'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  IF v_e.delivery_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Solo el delivery asignado adjunta evidencia'; END IF;
  IF p_path NOT LIKE (public.mi_empresa_proveedor()::text || '/' || p_entrega_id::text || '/%') THEN
    RAISE EXCEPTION 'Path fuera de scope'; END IF;
  -- Tipo: explícito si viene; si no, se infiere del nombre del archivo (la PWA viva sube {tipo}_{ts}).
  v_tipo := COALESCE(
    p_tipo,
    CASE WHEN p_path ~ '/foto_'  THEN 'foto'
         WHEN p_path ~ '/firma_' THEN 'firma' END
  );
  IF v_tipo IS NOT NULL AND v_tipo NOT IN ('foto','firma') THEN RAISE EXCEPTION 'Tipo inválido'; END IF;
  -- COMPAT: SIGUE seteando evidencia_path (la PWA en prod lo lee). NO se dropea la columna en esta mig.
  UPDATE public.entregas SET evidencia_path=p_path, updated_at=now() WHERE id=p_entrega_id;
  -- ADITIVO: registra en la tabla nueva (si se pudo determinar el tipo).
  IF v_tipo IS NOT NULL THEN
    INSERT INTO public.entrega_evidencias(entrega_id, tipo, path, subido_por)
    VALUES (p_entrega_id, v_tipo, p_path, auth.uid());
  END IF;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE ALL ON FUNCTION public.registrar_evidencia_entrega(bigint, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.registrar_evidencia_entrega(bigint, text, text) TO authenticated;

-- ===== 3) detalle_entrega_delivery: meds despachados (SIN clínico) + cobrado_at + evidencias =====
-- Gate entregas_ver; confinado empresa + sucursal_visible + delivery_id=auth.uid(). Solo lectura (STABLE).
CREATE OR REPLACE FUNCTION public.detalle_entrega_delivery(p_entrega_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_ra_id uuid; v_items jsonb; v_evid jsonb; v_suc text;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_ver'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas
   WHERE id = p_entrega_id
     AND private.entrega_visible(empresa_id, farmacia_id, delivery_id)
     AND delivery_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;

  SELECT f.nombre INTO v_suc FROM public.farmacias f WHERE f.id = v_e.farmacia_id;
  SELECT ra.id   INTO v_ra_id FROM public.recetas_avanzadas ra WHERE ra.receta_base_id = v_e.receta_base_id;

  -- Ítems = lo DESPACHADO (dispensaciones.medicamentos_dispensados del grupo) → reconcilia con el monto.
  -- SOLO atributos de PRODUCTO: nombre + cantidad + presentación/concentración.
  -- PROHIBIDO exponer campos CLÍNICOS de la receta del médico (viven en receta_items y NO se seleccionan acá).
  SELECT jsonb_agg(jsonb_build_object(
           'nombre',        COALESCE(NULLIF(m.nombre_comercial, ''), it->>'nombre'),
           'cantidad',      (it->>'cantidad')::numeric,
           'presentacion',  m.presentacion,
           'concentracion', m.concentracion
         ))
    INTO v_items
    FROM public.dispensaciones d
    CROSS JOIN LATERAL jsonb_array_elements(d.medicamentos_dispensados) AS it
    LEFT JOIN public.receta_items ri ON ri.id = (it->>'item_id')::bigint
    LEFT JOIN public.medicamentos m  ON m.id  = ri.medicamento_id
   WHERE d.receta_avanzada_id = v_ra_id AND d.farmacia_id = v_e.farmacia_id;

  SELECT jsonb_agg(jsonb_build_object('tipo', ev.tipo, 'path', ev.path, 'subido_at', ev.subido_at)
                   ORDER BY ev.subido_at)
    INTO v_evid
    FROM public.entrega_evidencias ev WHERE ev.entrega_id = p_entrega_id;

  RETURN jsonb_build_object(
    'entrega_id', v_e.id, 'estado', v_e.estado, 'receta_base_id', v_e.receta_base_id,
    'farmacia_id', v_e.farmacia_id, 'sucursal_nombre', v_suc,
    'direccion_entrega', v_e.direccion_entrega, 'telefono_contacto', v_e.telefono_contacto,
    'lat', v_e.lat, 'lng', v_e.lng,
    'monto', v_e.monto, 'cobrado', v_e.cobrado, 'metodo_cobro', v_e.metodo_cobro,
    'cobrado_at', v_e.cobrado_at, 'cobrado_por', v_e.cobrado_por,
    'intentos', v_e.intentos, 'motivo_fallo', v_e.motivo_fallo,
    'asignado_at', v_e.asignado_at, 'entregado_at', v_e.entregado_at,
    'items',      COALESCE(v_items, '[]'::jsonb),
    'evidencias', COALESCE(v_evid,  '[]'::jsonb)
  );
END $$;
REVOKE ALL ON FUNCTION public.detalle_entrega_delivery(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.detalle_entrega_delivery(bigint) TO authenticated;
