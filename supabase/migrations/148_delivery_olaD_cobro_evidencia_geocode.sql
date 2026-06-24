-- ============================================================
-- 148 · DELIVERY Fase 1 — OLA D: cobro + bucket evidencia (privado) + geocodificación. Aditiva sobre entregas (C).
-- ------------------------------------------------------------
-- NO toca el path de despacho / pickup / 141/143 / emisión. Toca DINERO (registrar_cobro_entrega, monto re-derivado
-- server-side) y STORAGE (bucket privado + signed URLs; lecciones R6/R9: NUNCA público, NUNCA getPublicUrl).
-- Cobro desde {en_camino, entregada} (Oscar); recobro→RAISE. Evidencia: subida scoped + asociación solo por RPC.
-- Idempotente.
-- ============================================================

-- 1) RPC registrar_cobro_entrega (gate entregas_cobrar TECHO; monto autoritativo del servidor) ----
CREATE OR REPLACE FUNCTION public.registrar_cobro_entrega(p_entrega_id bigint, p_metodo_cobro text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_ra_id uuid; v_monto numeric; v_es_delivery boolean;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_cobrar'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF p_metodo_cobro NOT IN ('efectivo','tarjeta','transferencia','sin_cobro') THEN RAISE EXCEPTION 'Método inválido'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  v_es_delivery := (v_e.delivery_id = auth.uid());
  IF private.mi_sucursal() IS NOT NULL AND NOT v_es_delivery
     AND NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado: no es tu entrega'; END IF;
  IF v_e.cobrado THEN RAISE EXCEPTION 'Entrega ya cobrada'; END IF;
  IF v_e.estado NOT IN ('en_camino','entregada') THEN
    RAISE EXCEPTION 'Solo se cobra desde en_camino/entregada (estado=%)', v_e.estado; END IF;
  SELECT ra.id INTO v_ra_id FROM public.recetas_avanzadas ra WHERE ra.receta_base_id=v_e.receta_base_id;
  SELECT SUM(d.total_dispensado) INTO v_monto FROM public.dispensaciones d
    WHERE d.receta_avanzada_id=v_ra_id AND d.farmacia_id=v_e.farmacia_id;   -- monto RE-DERIVADO (no del cliente)
  UPDATE public.entregas SET cobrado=true, cobrado_at=now(), cobrado_por=auth.uid(),
    metodo_cobro=p_metodo_cobro, monto=COALESCE(v_monto, monto), updated_at=now()
  WHERE id=p_entrega_id;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.registrar_cobro_entrega(bigint,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_cobro_entrega(bigint,text) TO authenticated;

-- 2) RPC registrar_evidencia_entrega (solo el delivery asignado; valida path scope) ----
CREATE OR REPLACE FUNCTION public.registrar_evidencia_entrega(p_entrega_id bigint, p_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_actualizar_estado'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  IF v_e.delivery_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Solo el delivery asignado adjunta evidencia'; END IF;
  IF p_path NOT LIKE (public.mi_empresa_proveedor()::text || '/' || p_entrega_id::text || '/%') THEN
    RAISE EXCEPTION 'Path fuera de scope'; END IF;
  UPDATE public.entregas SET evidencia_path=p_path, updated_at=now() WHERE id=p_entrega_id;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.registrar_evidencia_entrega(bigint,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_evidencia_entrega(bigint,text) TO authenticated;

-- 3) RPC actualizar_direccion_entrega (gestor o delivery asignado; best-effort para lat/lng) ----
CREATE OR REPLACE FUNCTION public.actualizar_direccion_entrega(p_entrega_id bigint, p_direccion text,
  p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_es_delivery boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  v_es_delivery := (v_e.delivery_id = auth.uid());
  IF NOT (COALESCE(private.tiene_permiso('entregas_gestionar'), false) OR v_es_delivery) THEN
    RAISE EXCEPTION 'No autorizado'; END IF;
  UPDATE public.entregas SET direccion_entrega=p_direccion, lat=p_lat, lng=p_lng, updated_at=now() WHERE id=p_entrega_id;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.actualizar_direccion_entrega(bigint,text,double precision,double precision) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.actualizar_direccion_entrega(bigint,text,double precision,double precision) TO authenticated;

-- 4) Bucket privado entregas-evidencia + storage policies (path {empresa_id}/{entrega_id}/...) ----
INSERT INTO storage.buckets (id, name, public) VALUES ('entregas-evidencia','entregas-evidencia', false)
  ON CONFLICT (id) DO UPDATE SET public=false;   -- garantiza privado

-- INSERT (subida): 1er segmento=su empresa + permiso + ES SU entrega asignada (evita R9 laxo)
DROP POLICY IF EXISTS entregas_evidencia_insert ON storage.objects;
CREATE POLICY entregas_evidencia_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (
  bucket_id='entregas-evidencia'
  AND split_part(name,'/',1) = public.mi_empresa_proveedor()::text
  AND COALESCE(private.tiene_permiso('entregas_actualizar_estado'), false)
  AND EXISTS (SELECT 1 FROM public.entregas e
              WHERE e.id = NULLIF(split_part(name,'/',2),'')::bigint
                AND e.empresa_id = public.mi_empresa_proveedor()
                AND e.delivery_id = auth.uid())
);

-- SELECT (para createSignedUrl): espejo de la RLS de entregas (empresa + sucursal_visible + slice delivery)
DROP POLICY IF EXISTS entregas_evidencia_select ON storage.objects;
CREATE POLICY entregas_evidencia_select ON storage.objects FOR SELECT TO authenticated USING (
  bucket_id='entregas-evidencia' AND (
    EXISTS (SELECT 1 FROM public.entregas e
            WHERE e.id = NULLIF(split_part(name,'/',2),'')::bigint
              AND e.empresa_id = public.mi_empresa_proveedor()
              AND COALESCE(private.sucursal_visible(e.farmacia_id), false)
              AND (public.mi_rol_proveedor() <> 'delivery' OR e.delivery_id = auth.uid()))
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  )
);
-- Sin policy de UPDATE/DELETE para este bucket → inmutable salvo owner/service_role. anon sin policy → sin acceso.
