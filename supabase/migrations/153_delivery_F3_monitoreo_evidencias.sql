-- 153 · F3 — listar_entregas_monitoreo: + array de evidencias (foto+firma separadas, F1.5). ADITIVO.
-- Mantiene evidencia_path legacy (retrocompat). Mismo gate (entregas_ver) y MISMO confinamiento (entrega_visible =
-- empresa + sucursal_visible; NO delivery_id=auth.uid(), ese es el de la PWA). Sigue SIN exponer medicamentos.
-- CREATE OR REPLACE idempotente; re-declara DEFINER/sp''/grants.

CREATE OR REPLACE FUNCTION public.listar_entregas_monitoreo(p_estado text DEFAULT NULL::text, p_sucursal_id integer DEFAULT NULL::integer, p_delivery_id uuid DEFAULT NULL::uuid, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
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
      'evidencia_path', e.evidencia_path, 'lat', e.lat, 'lng', e.lng,                       -- evidencia_path = PATH legacy (retrocompat)
      -- F3: array de evidencias por tipo (foto+firma). Solo de la entrega ya confinada por el WHERE de abajo → sin fuga.
      'evidencias', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo', ev.tipo, 'path', ev.path, 'subido_at', ev.subido_at)
                        ORDER BY ev.subido_at), '[]'::jsonb)
        FROM public.entrega_evidencias ev WHERE ev.entrega_id = e.id),
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
END $function$;

REVOKE ALL ON FUNCTION public.listar_entregas_monitoreo(text,integer,uuid,date,date) FROM public;
GRANT EXECUTE ON FUNCTION public.listar_entregas_monitoreo(text,integer,uuid,date,date) TO authenticated;
