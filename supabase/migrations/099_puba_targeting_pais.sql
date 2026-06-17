-- ============================================================
-- PUB-A · Publicidad: enforcement de targeting por país (operación M:N) + NOT NULL
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes red-first (P224–P228). Backfill mostrado en PREVIEW
-- (6/6 campanas matchean por título+fecha a su solicitud → país cbbbbe6d; 0 sin match).
--
-- El país de una campaña/solicitud debe ∈ empresa_opera_en_pais(empresa, país) (helper
-- DEFINER de G1). Server-side, no param libre (lección 8). Gate en AMBOS caminos:
--   · CREAR: INSERT directo a solicitudes_campana (WITH CHECK de "Proveedor crea campañas")
--            — se MANTIENE empresa_id = mi_empresa_proveedor() (lección 8) y se AÑADE el país.
--   · APROBAR: aprobar_solicitud_campana re-valida antes de crear la campaña.
-- ============================================================

-- 1) BACKFILL solicitudes (NULL → país de su empresa) y campanas (NULL → match título+fecha)
UPDATE public.solicitudes_campana s
   SET pais_id = e.pais_id
  FROM public.empresas_proveedoras e
 WHERE s.empresa_id = e.id AND s.pais_id IS NULL;

UPDATE public.campanas_publicitarias c
   SET pais_id = sub.pais_eff
  FROM (
    SELECT s.titulo, s.fecha_inicio, s.fecha_fin, COALESCE(s.pais_id, e.pais_id) AS pais_eff
    FROM public.solicitudes_campana s JOIN public.empresas_proveedoras e ON e.id = s.empresa_id
  ) sub
 WHERE c.pais_id IS NULL
   AND c.titulo = sub.titulo AND c.fecha_inicio = sub.fecha_inicio AND c.fecha_fin = sub.fecha_fin;

DO $$ DECLARE n1 int; n2 int; BEGIN
  SELECT count(*) INTO n1 FROM public.solicitudes_campana WHERE pais_id IS NULL;
  SELECT count(*) INTO n2 FROM public.campanas_publicitarias WHERE pais_id IS NULL;
  IF n1 > 0 OR n2 > 0 THEN RAISE EXCEPTION 'backfill incompleto: solicitudes NULL=%, campanas NULL=%', n1, n2; END IF;
END $$;

ALTER TABLE public.solicitudes_campana   ALTER COLUMN pais_id SET NOT NULL;
ALTER TABLE public.campanas_publicitarias ALTER COLUMN pais_id SET NOT NULL;

-- 2) CREAR: WITH CHECK += país ∈ operación (mantiene empresa_id binding + permiso + estado)
DROP POLICY IF EXISTS "Proveedor crea campañas" ON public.solicitudes_campana;
CREATE POLICY "Proveedor crea campañas" ON public.solicitudes_campana
  FOR INSERT TO authenticated
  WITH CHECK (
    COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
    AND (
      COALESCE(private.tiene_permiso('publicidad_gestionar'), false)
      OR EXISTS (SELECT 1 FROM public.cuentas_proveedor cp
                 WHERE cp.id = auth.uid() AND cp.empresa_id = solicitudes_campana.empresa_id
                   AND cp.rol_en_empresa = ANY (ARRAY['admin','editor']))
    )
    AND estado = ANY (ARRAY['borrador','enviada'])
    AND COALESCE(private.empresa_opera_en_pais(empresa_id, pais_id), false)   -- NUEVO: país ∈ operación
  );

-- 3) APROBAR: re-validar país ∈ operación antes de crear la campaña
CREATE OR REPLACE FUNCTION public.aprobar_solicitud_campana(p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_s RECORD; v_campana_id integer;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin aprueba campañas';
  END IF;
  SELECT * INTO v_s FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada'; END IF;
  IF NOT COALESCE(private.empresa_opera_en_pais(v_s.empresa_id, v_s.pais_id), false) THEN
    RAISE EXCEPTION 'La empresa no opera en el país de la campaña';
  END IF;

  INSERT INTO public.campanas_publicitarias
    (titulo, descripcion, tipo, imagen_url, link_url, fecha_inicio, fecha_fin,
     activa, condicion_filtro, genero_filtro, edad_min, edad_max, pais_id)
  VALUES
    (v_s.titulo, v_s.descripcion, v_s.tipo, v_s.imagen_url, v_s.link_url,
     v_s.fecha_inicio, v_s.fecha_fin, true, v_s.condicion_filtro, v_s.genero_filtro,
     v_s.edad_min, v_s.edad_max, v_s.pais_id)
  RETURNING id INTO v_campana_id;

  UPDATE public.solicitudes_campana
    SET estado = 'publicada', notas_admin = COALESCE(p_notas_admin, notas_admin)
    WHERE id = p_solicitud_id;

  RETURN v_campana_id;
END;
$function$;
