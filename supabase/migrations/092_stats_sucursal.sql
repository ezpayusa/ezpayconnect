-- ============================================================
-- STATS por sucursal — 2 RPC DEFINER de LECTURA (aditivas). NO toca policy/RPC viva.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes rojo-primero (P181–P190).
-- Separación financiero↔clínico por permiso. PHI mínima (solo GROUP BY; nunca paciente/
-- medico/receta ni fila individual). Scope empresa + sucursal-aware vía private.mi_sucursal()
-- (inerte hoy con todos NULL; correcto cuando C.2 confine). Montos/clínico SOLO 'completada'.
--
-- Nota PHI: dispensaciones NO es legible fila-a-fila por admin/gerente (RLS = médico/paciente/
-- superadmin). Estas RPC DEFINER dan visibilidad AGREGADA. Por eso stats_recetas_sucursal
-- SUPRIME celdas pequeñas: medicamento con veces < k → se colapsa en '(otros)' (k-anon: una
-- cuenta-de-1 con nombre de medicamento re-identifica de facto al paciente). k es server-side,
-- NO un parámetro (el caller no puede bajarlo).
-- ============================================================

-- ------------------------------------------------------------
-- 1) Permiso nuevo recetas_reportes — default DENY (solo admin + gerente_farmacia).
--    finanzas_reportes ya existe (admin/gerente/supervisor/finanzas/pagador) y NO da
--    acceso al desglose clínico → separación real.
-- ------------------------------------------------------------
INSERT INTO public.permisos_empresa_rol (tipo_empresa, rol, accion)
SELECT 'farmacia', r, 'recetas_reportes'
FROM unnest(ARRAY['admin','gerente_farmacia']) AS r
ON CONFLICT (tipo_empresa, rol, accion) DO NOTHING;

-- ------------------------------------------------------------
-- 2) RPC financiero — montos + volumen por sucursal. SIN medicamento, SIN paciente.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stats_finanzas_sucursal(
  p_desde date, p_hasta date, p_sucursal_id integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_emp uuid; v_out jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('finanzas_reportes'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede ver reportes financieros';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa proveedora'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'sucursal_id', fid, 'sucursal', fnombre,
           'dispensaciones', n, 'total_dispensado', tot, 'items', items) ORDER BY fnombre), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT f.id AS fid, f.nombre AS fnombre,
           count(*) AS n,
           COALESCE(sum(d.total_dispensado), 0) AS tot,
           COALESCE(sum(d.cantidad_items), 0) AS items
    FROM public.dispensaciones d
    JOIN public.farmacias f ON f.id = d.farmacia_id
    WHERE COALESCE(f.empresa_id = v_emp, false)                                  -- aislamiento EMPRESA (intacto)
      AND (private.mi_sucursal() IS NULL OR f.id = private.mi_sucursal())        -- sucursal-aware (C.1)
      AND (p_sucursal_id IS NULL OR f.id = p_sucursal_id)
      AND d.estado_dispensacion = 'completada'                                   -- montos reales
      AND d.fecha_dispensacion::date BETWEEN p_desde AND p_hasta
    GROUP BY f.id, f.nombre
  ) s;

  RETURN v_out;   -- agregado por sucursal; nunca fila individual / paciente / medicamento
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.stats_finanzas_sucursal(date, date, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.stats_finanzas_sucursal(date, date, integer) TO authenticated, service_role;

-- ------------------------------------------------------------
-- 3) RPC clínico — desglose por medicamento (agregado). PHI mínima + supresión de celdas < k.
--    Extrae SOLO nombre + cantidad del jsonb (nada ligado a paciente que pudiera venir embebido).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stats_recetas_sucursal(
  p_desde date, p_hasta date, p_sucursal_id integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_emp uuid; v_out jsonb; v_k constant integer := 5;  -- umbral k-anon (server-side; NO parámetro)
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF NOT COALESCE(private.tiene_permiso('recetas_reportes'), false) THEN
    RAISE EXCEPTION 'No autorizado: tu rol no puede ver reportes de recetas';
  END IF;
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa proveedora'; END IF;

  WITH base AS (
    SELECT f.id AS fid, f.nombre AS fnombre,
           btrim(e.elem->>'nombre') AS med,                          -- SOLO nombre
           count(*) AS veces,
           COALESCE(sum((e.elem->>'cantidad')::numeric), 0) AS cant  -- SOLO cantidad
    FROM public.dispensaciones d
    JOIN public.farmacias f ON f.id = d.farmacia_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(d.medicamentos_dispensados, '[]'::jsonb)) AS e(elem)
    WHERE COALESCE(f.empresa_id = v_emp, false)
      AND (private.mi_sucursal() IS NULL OR f.id = private.mi_sucursal())
      AND (p_sucursal_id IS NULL OR f.id = p_sucursal_id)
      AND d.estado_dispensacion = 'completada'
      AND d.fecha_dispensacion::date BETWEEN p_desde AND p_hasta
    GROUP BY f.id, f.nombre, btrim(e.elem->>'nombre')
  ),
  supp AS (   -- celdas con veces < k se colapsan en '(otros)' por sucursal (anti re-identificación)
    SELECT fid, fnombre,
           CASE WHEN veces >= v_k THEN med ELSE '(otros)' END AS medicamento,
           sum(veces) AS veces, sum(cant) AS cant
    FROM base
    GROUP BY fid, fnombre, CASE WHEN veces >= v_k THEN med ELSE '(otros)' END
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'sucursal_id', fid, 'sucursal', fnombre,
           'medicamento', medicamento, 'veces_dispensado', veces, 'cantidad_total', cant)
           ORDER BY fnombre, medicamento), '[]'::jsonb)
    INTO v_out
  FROM supp;

  RETURN v_out;   -- agregado por medicamento; nunca paciente/medico/receta ni fila individual
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.stats_recetas_sucursal(date, date, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.stats_recetas_sucursal(date, date, integer) TO authenticated, service_role;
