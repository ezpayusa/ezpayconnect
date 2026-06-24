-- ============================================================
-- 151 · DELIVERY Front F1 — mini-mig: listar_entregas_delivery (cola del repartidor). LECTURA PURA.
-- ------------------------------------------------------------
-- Cola de SUS entregas para la PWA del repartidor. STABLE DEFINER sp'', gate entregas_ver. Confinada al slice
-- del repartidor: deriva del helper private.entrega_visible (= término RLS de entregas) Y ADEMÁS delivery_id=auth.uid()
-- (estrictamente las propias, sea cual sea el rol). Superficie de columnas CONTROLADA (no SELECT *): solo lo que la
-- cola necesita. PII (direccion/telefono) sale acá porque es el flujo delivery confinado a la PROPIA entrega del
-- repartidor (necesita la dirección para entregar y el teléfono para coordinar). Idempotente.
-- ============================================================
CREATE OR REPLACE FUNCTION public.listar_entregas_delivery(
  p_estado text DEFAULT NULL, p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_ver'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT COALESCE(jsonb_agg(obj ORDER BY ord_estado, ord_fecha DESC), '[]'::jsonb) INTO v FROM (
    SELECT
      CASE e.estado WHEN 'en_camino' THEN 0 WHEN 'asignada' THEN 1 WHEN 'pendiente' THEN 2
                    WHEN 'entregada' THEN 3 WHEN 'fallida' THEN 4 ELSE 5 END AS ord_estado,
      e.created_at AS ord_fecha,
      jsonb_build_object(
        'entrega_id', e.id, 'estado', e.estado, 'receta_base_id', e.receta_base_id,
        'farmacia_id', e.farmacia_id, 'sucursal_nombre', f.nombre,
        'direccion_entrega', e.direccion_entrega, 'telefono_contacto', e.telefono_contacto,  -- PII: SU propia entrega (flujo delivery confinado)
        'lat', e.lat, 'lng', e.lng,
        'monto', e.monto, 'cobrado', e.cobrado, 'metodo_cobro', e.metodo_cobro,
        'intentos', e.intentos, 'motivo_fallo', e.motivo_fallo, 'evidencia_path', e.evidencia_path,
        'asignado_at', e.asignado_at, 'entregado_at', e.entregado_at,
        'created_at', e.created_at, 'updated_at', e.updated_at
      ) AS obj
    FROM public.entregas e
    JOIN public.farmacias f ON f.id = e.farmacia_id
    WHERE private.entrega_visible(e.empresa_id, e.farmacia_id, e.delivery_id)   -- confinamiento (helper = término RLS)
      AND e.delivery_id = auth.uid()                                           -- slice del repartidor: SOLO las suyas
      AND (p_estado IS NULL OR e.estado = p_estado)
      AND (p_desde IS NULL OR e.created_at::date >= p_desde)
      AND (p_hasta IS NULL OR e.created_at::date <= p_hasta)
  ) t;
  RETURN v;
END $$;
REVOKE EXECUTE ON FUNCTION public.listar_entregas_delivery(text,date,date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_entregas_delivery(text,date,date) TO authenticated;
