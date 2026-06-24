-- ============================================================
-- 149 · DELIVERY Fase 1 — OLA E: monitoreo + reconciliación de discrepancias. LECTURA PURA (0 escritura).
-- ------------------------------------------------------------
-- 3 RPCs STABLE DEFINER sp'' gate entregas_ver: listar_entregas_monitoreo (+flags disc_monto/disc_cobrada_fallida),
-- stats_entregas_sucursal (+conteos), reconciliar_entregas_faltantes (#2 estructural). El confinamiento NO se
-- reimplementa: helper private.entrega_visible = MISMO término que la RLS de entregas (empresa + sucursal_visible
-- + slice delivery + super_admin). Q1: gerente_farmacia es EXENTO → ve toda la empresa (NO se confina por sucursal).
-- NO toca despacho/cobro/emisión/141/143. Idempotente.
-- ============================================================

-- 0) Helper de visibilidad (término ÚNICO, espejo de la RLS de entregas; deriva de los mismos helpers) ----
CREATE OR REPLACE FUNCTION private.entrega_visible(p_empresa uuid, p_farmacia integer, p_delivery uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT ( COALESCE(public.mi_empresa_proveedor() = p_empresa, false)
           AND COALESCE(private.sucursal_visible(p_farmacia), false)
           AND ( public.mi_rol_proveedor() <> 'delivery' OR p_delivery = auth.uid() ) )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false);
$$;
REVOKE ALL ON FUNCTION private.entrega_visible(uuid,integer,uuid) FROM PUBLIC, anon;

-- 1) listar_entregas_monitoreo ---------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_entregas_monitoreo(
  p_estado text DEFAULT NULL, p_sucursal_id integer DEFAULT NULL, p_delivery_id uuid DEFAULT NULL,
  p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_ver'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT COALESCE(jsonb_agg(obj ORDER BY ord DESC), '[]'::jsonb) INTO v FROM (
    SELECT e.created_at AS ord, jsonb_build_object(
      'id', e.id, 'estado', e.estado, 'farmacia_id', e.farmacia_id, 'sucursal_nombre', f.nombre,
      'delivery_id', e.delivery_id, 'delivery_nombre', cp.nombre_completo,
      'monto', e.monto, 'cobrado', e.cobrado, 'cobrado_at', e.cobrado_at, 'cobrado_por', e.cobrado_por, 'metodo_cobro', e.metodo_cobro,
      'intentos', e.intentos, 'motivo_fallo', e.motivo_fallo, 'reabierta_at', e.reabierta_at,
      'asignado_at', e.asignado_at, 'entregado_at', e.entregado_at, 'created_at', e.created_at,
      'paciente_nombre', p.nombre || ' ' || COALESCE(p.apellido,''),
      'direccion_entrega', e.direccion_entrega, 'telefono_contacto', e.telefono_contacto,
      'evidencia_path', e.evidencia_path, 'lat', e.lat, 'lng', e.lng,                       -- evidencia_path = PATH, no URL firmada
      'disc_monto', (e.monto IS NOT NULL AND e.monto < COALESCE((
          SELECT SUM(d.total_dispensado) FROM public.dispensaciones d
          JOIN public.recetas_avanzadas ra ON ra.id=d.receta_avanzada_id
          WHERE ra.receta_base_id=e.receta_base_id AND d.farmacia_id=e.farmacia_id), 0)),    -- #1
      'disc_cobrada_fallida', (e.cobrado AND e.estado='fallida')                            -- #3
    ) AS obj
    FROM public.entregas e
    JOIN public.farmacias f ON f.id=e.farmacia_id
    LEFT JOIN public.cuentas_proveedor cp ON cp.id=e.delivery_id
    JOIN public.recetas   r ON r.id=e.receta_base_id
    JOIN public.pacientes p ON p.id=e.paciente_id
    WHERE private.entrega_visible(e.empresa_id, e.farmacia_id, e.delivery_id)                -- confinamiento (espejo RLS)
      AND (p_estado IS NULL     OR e.estado=p_estado)
      AND (p_sucursal_id IS NULL OR e.farmacia_id=p_sucursal_id)                             -- FILTRO conjuntivo (no relaja)
      AND (p_delivery_id IS NULL OR e.delivery_id=p_delivery_id)
      AND (p_desde IS NULL OR e.created_at::date >= p_desde)
      AND (p_hasta IS NULL OR e.created_at::date <= p_hasta)
  ) t;
  RETURN v;
END $$;
REVOKE EXECUTE ON FUNCTION public.listar_entregas_monitoreo(text,integer,uuid,date,date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_entregas_monitoreo(text,integer,uuid,date,date) TO authenticated;

-- 2) stats_entregas_sucursal ------------------------------------------------
CREATE OR REPLACE FUNCTION public.stats_entregas_sucursal(p_desde date, p_hasta date, p_sucursal_id integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_ver'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT COALESCE(jsonb_agg(obj ORDER BY (obj->>'farmacia_id')::int), '[]'::jsonb) INTO v FROM (
    SELECT jsonb_build_object(
      'farmacia_id', e.farmacia_id, 'sucursal_nombre', f.nombre,
      'total', count(*),
      'pendiente', count(*) FILTER (WHERE e.estado='pendiente'),
      'asignada',  count(*) FILTER (WHERE e.estado='asignada'),
      'en_camino', count(*) FILTER (WHERE e.estado='en_camino'),
      'entregada', count(*) FILTER (WHERE e.estado='entregada'),
      'fallida',   count(*) FILTER (WHERE e.estado='fallida'),
      'pct_exito', round(100.0 * count(*) FILTER (WHERE e.estado='entregada')
                   / NULLIF(count(*) FILTER (WHERE e.estado IN ('entregada','fallida')),0), 1),
      'monto_cobrado', COALESCE(SUM(e.monto) FILTER (WHERE e.cobrado), 0),
      'reintentos', COALESCE(SUM(e.intentos), 0),
      'disc_monto', count(*) FILTER (WHERE e.monto IS NOT NULL AND e.monto < COALESCE((
          SELECT SUM(d.total_dispensado) FROM public.dispensaciones d
          JOIN public.recetas_avanzadas ra ON ra.id=d.receta_avanzada_id
          WHERE ra.receta_base_id=e.receta_base_id AND d.farmacia_id=e.farmacia_id), 0)),
      'disc_cobrada_fallida', count(*) FILTER (WHERE e.cobrado AND e.estado='fallida')
    ) AS obj
    FROM public.entregas e JOIN public.farmacias f ON f.id=e.farmacia_id
    WHERE private.entrega_visible(e.empresa_id, e.farmacia_id, e.delivery_id)
      AND (p_sucursal_id IS NULL OR e.farmacia_id=p_sucursal_id)
      AND (p_desde IS NULL OR e.created_at::date >= p_desde)
      AND (p_hasta IS NULL OR e.created_at::date <= p_hasta)
    GROUP BY e.farmacia_id, f.nombre
  ) t;
  RETURN v;
END $$;
REVOKE EXECUTE ON FUNCTION public.stats_entregas_sucursal(date,date,integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.stats_entregas_sucursal(date,date,integer) TO authenticated;

-- 3) reconciliar_entregas_faltantes (#2 estructural: delivery despachado SIN entrega) ----
CREATE OR REPLACE FUNCTION public.reconciliar_entregas_faltantes(p_sucursal_id integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_ver'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT COALESCE(jsonb_agg(DISTINCT obj), '[]'::jsonb) INTO v FROM (
    SELECT jsonb_build_object(
      'receta_base_id', ri.receta_id, 'farmacia_id', ri.farmacia_id, 'sucursal_nombre', f.nombre,
      'fallo_log', EXISTS (SELECT 1 FROM private.delivery_autocreate_fallos lf WHERE lf.receta_base_id=ri.receta_id)
    ) AS obj
    FROM public.receta_items ri
    JOIN public.farmacias f ON f.id=ri.farmacia_id
    WHERE ri.modalidad='delivery'
      AND ri.farmacia_id IS NOT NULL
      AND private.entrega_visible(f.empresa_id, ri.farmacia_id, NULL)                        -- delivery (NULL) → no ve faltantes; exento/confinable sí
      AND (p_sucursal_id IS NULL OR ri.farmacia_id=p_sucursal_id)
      AND EXISTS (SELECT 1 FROM public.dispensaciones d
                  JOIN public.recetas_avanzadas ra ON ra.id=d.receta_avanzada_id
                  WHERE ra.receta_base_id=ri.receta_id AND d.farmacia_id=ri.farmacia_id)     -- despachado delivery
      AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.receta_base_id=ri.receta_id AND e.farmacia_id=ri.farmacia_id)  -- SIN entrega
  ) t;
  RETURN v;
END $$;
REVOKE EXECUTE ON FUNCTION public.reconciliar_entregas_faltantes(integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.reconciliar_entregas_faltantes(integer) TO authenticated;
