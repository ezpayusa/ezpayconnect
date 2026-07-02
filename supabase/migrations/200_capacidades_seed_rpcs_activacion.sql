-- 200 Capacidades por empresa — seed de catálogo + RPCs de activación (super_admin) + activación masiva QA
-- Muro ético: solo tocan empresa_capacidades y leen catálogos/roles. No tocan visitas_agendadas,
-- disponibilidad_medico, ni agenda de paciente.
-- ERRCODEs (familia PC): PC001 no_autorizado · PC002 empresa_no_existe · PC003 capacidad_no_existe · PC004 tier_no_existe.

-- ============================================================
-- PARTE 1 — Sembrar el catálogo de capacidades (códigos estables)
-- ============================================================
INSERT INTO public.capacidades_catalogo (codigo, nombre, descripcion, activo, orden) VALUES
  ('productos',    'Productos',               'Gestión de catálogo de productos de la empresa',          true, 1),
  ('visitadores',  'Visitadores médicos',     'Módulo de visitadores y agenda de visitas',               true, 2),
  ('enrolamiento', 'Enrolamiento de médicos', 'Add-on: enrolar médicos y obtener prioridad de agenda',   true, 3),
  ('publicidad',   'Publicidad',              'Campañas publicitarias en la plataforma',                 true, 4)
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================
-- PARTE 2 — RPCs de activación (gate interno super_admin)
-- ============================================================

-- (a) activar_capacidad_suelta — UPSERT de una capacidad individual
CREATE OR REPLACE FUNCTION public.activar_capacidad_suelta(
  p_empresa_id uuid, p_capacidad_codigo text, p_hasta timestamptz DEFAULT NULL)
RETURNS SETOF public.empresa_capacidades
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE id = p_empresa_id) THEN
    RAISE EXCEPTION 'empresa_no_existe' USING ERRCODE = 'PC002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.capacidades_catalogo WHERE codigo = p_capacidad_codigo) THEN
    RAISE EXCEPTION 'capacidad_no_existe' USING ERRCODE = 'PC003';
  END IF;

  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  VALUES (p_empresa_id, p_capacidad_codigo, true, 'suelta', NULL, now(), p_hasta, auth.uid())
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = EXCLUDED.hasta, activada_por = EXCLUDED.activada_por;
    -- NO se toca origen/tier_id: si venía de un tier, se queda como estaba (solo re-activa). updated_at por trigger.

  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND capacidad_codigo = p_capacidad_codigo;
END;
$function$;
REVOKE ALL     ON FUNCTION public.activar_capacidad_suelta(uuid, text, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.activar_capacidad_suelta(uuid, text, timestamptz) TO authenticated;

-- (b) desactivar_capacidad — desactiva sin borrar (idempotente, no-op si no existe)
CREATE OR REPLACE FUNCTION public.desactivar_capacidad(p_empresa_id uuid, p_capacidad_codigo text)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  UPDATE public.empresa_capacidades
    SET activa = false
    WHERE empresa_id = p_empresa_id AND capacidad_codigo = p_capacidad_codigo;
  -- no-op idempotente si no existe la fila. updated_at por trigger.
END;
$function$;
REVOKE ALL     ON FUNCTION public.desactivar_capacidad(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.desactivar_capacidad(uuid, text) TO authenticated;

-- (c) asignar_tier — política SUMAR: activa las capacidades del tier, adopta las existentes, no toca las ajenas
CREATE OR REPLACE FUNCTION public.asignar_tier(
  p_empresa_id uuid, p_tier_id uuid, p_hasta timestamptz DEFAULT NULL)
RETURNS SETOF public.empresa_capacidades
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.empresas_proveedoras WHERE id = p_empresa_id) THEN
    RAISE EXCEPTION 'empresa_no_existe' USING ERRCODE = 'PC002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tiers_catalogo WHERE id = p_tier_id) THEN
    RAISE EXCEPTION 'tier_no_existe' USING ERRCODE = 'PC004';
  END IF;

  INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
  SELECT p_empresa_id, tc.capacidad_codigo, true, 'tier', p_tier_id, now(), p_hasta, auth.uid()
  FROM public.tier_capacidades tc
  WHERE tc.tier_id = p_tier_id
  ON CONFLICT (empresa_id, capacidad_codigo) DO UPDATE
    SET activa = true, hasta = EXCLUDED.hasta, activada_por = EXCLUDED.activada_por,
        origen = 'tier', tier_id = EXCLUDED.tier_id;  -- el tier adopta la capacidad. updated_at por trigger.

  -- set resultante: capacidades activas vigentes de la empresa (las sueltas ajenas al tier se mantienen)
  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND activa = true AND (hasta IS NULL OR hasta > now());
END;
$function$;
REVOKE ALL     ON FUNCTION public.asignar_tier(uuid, uuid, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.asignar_tier(uuid, uuid, timestamptz) TO authenticated;

-- (d) quitar_tier — desactiva SOLO las capacidades origen='tier' de ese tier; las sueltas se mantienen
CREATE OR REPLACE FUNCTION public.quitar_tier(p_empresa_id uuid, p_tier_id uuid)
RETURNS SETOF public.empresa_capacidades
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  UPDATE public.empresa_capacidades
    SET activa = false
    WHERE empresa_id = p_empresa_id AND origen = 'tier' AND tier_id = p_tier_id;
  -- updated_at por trigger.

  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id AND activa = true AND (hasta IS NULL OR hasta > now());
END;
$function$;
REVOKE ALL     ON FUNCTION public.quitar_tier(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.quitar_tier(uuid, uuid) TO authenticated;

-- (e) listar_capacidades_empresa — estado completo (activas/inactivas) para el panel admin
CREATE OR REPLACE FUNCTION public.listar_capacidades_empresa(p_empresa_id uuid)
RETURNS SETOF public.empresa_capacidades
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = 'PC001';
  END IF;
  RETURN QUERY SELECT * FROM public.empresa_capacidades
    WHERE empresa_id = p_empresa_id
    ORDER BY capacidad_codigo;
END;
$function$;
REVOKE ALL     ON FUNCTION public.listar_capacidades_empresa(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_capacidades_empresa(uuid) TO authenticated;

-- ============================================================
-- PARTE 3 — Activación masiva de prueba (PERSISTE; todas las empresas son fixtures QA)
-- Cada empresa × las 4 capacidades, origen='suelta', activa=true, hasta=NULL. Idempotente.
-- ============================================================
INSERT INTO public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, tier_id, desde, hasta, activada_por)
SELECT e.id, c.codigo, true, 'suelta', NULL, now(), NULL, NULL
FROM public.empresas_proveedoras e
CROSS JOIN (VALUES ('productos'),('visitadores'),('enrolamiento'),('publicidad')) AS c(codigo)
ON CONFLICT (empresa_id, capacidad_codigo) DO NOTHING;
