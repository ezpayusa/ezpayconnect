-- ############################################################################################
-- 274 — Reportes de visita, adjuntos, material comercial y LOS DOS BUCKETS con sus policies
-- ############################################################################################
-- Segunda y ultima migracion del frente visitas. Va separada de la 273 a proposito: depende de que
-- las visitas existan, y un bucket con policy mal scopeada se descubre tarde. Separadas, el
-- rollback de una no arrastra la otra.
--
-- EL BUCKET Y SUS POLICIES VAN EN LA MISMA MIGRACION. La leccion de FASE 4 fue exactamente esa: el
-- circuito estaba entero y lo que faltaba era la policy. Un bucket sin policy no falla al crearse,
-- falla en produccion cuando alguien sube algo.
--
-- ERRCODES: PA018 (informe sin check-in) y PA023 (path que no corresponde), que quedaron
-- reservados en la 273. Proximo libre despues de esta migracion: PA026.
-- ############################################################################################

-- ============================================================================================
-- CATALOGO de resultados
-- ============================================================================================
CREATE TABLE IF NOT EXISTS public.catalogo_resultado_visita (
  codigo text PRIMARY KEY, etiqueta text NOT NULL, orden int NOT NULL DEFAULT 0,
  activo boolean NOT NULL DEFAULT true
);
INSERT INTO public.catalogo_resultado_visita (codigo, etiqueta, orden) VALUES
  ('interesado','Interesado',10), ('requiere_seguimiento','Requiere seguimiento',20),
  ('no_interesado','No interesado',30), ('cerro_acuerdo','Cerró acuerdo',40),
  ('no_estaba','No estaba',50)
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================================================
-- REPORTE — 1:1 con la visita
-- ============================================================================================
CREATE TABLE IF NOT EXISTS public.reportes_visita (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visita_id             uuid NOT NULL UNIQUE REFERENCES public.visitas_comerciales(id) ON DELETE RESTRICT,
  resultado             text NOT NULL REFERENCES public.catalogo_resultado_visita(codigo) ON DELETE RESTRICT,
  resumen               text NOT NULL,
  compromisos           text,                    -- "que cosas quedan pendientes"
  proxima_accion_fecha  date,
  creado_por            uuid NOT NULL REFERENCES public.perfiles(id) ON DELETE RESTRICT,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reportes_visita_resumen_no_vacio CHECK (length(btrim(resumen)) > 0)
);

-- ============================================================================================
-- ADJUNTOS — cuelgan de la VISITA, no del reporte: las fotos se suben DURANTE la visita, antes de
-- cerrar el informe. Si colgaran del reporte, no habria donde ponerlas hasta el final.
-- ============================================================================================
CREATE TABLE IF NOT EXISTS public.visita_adjuntos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visita_id    uuid NOT NULL REFERENCES public.visitas_comerciales(id) ON DELETE RESTRICT,
  storage_path text NOT NULL UNIQUE,
  mime         text,
  bytes        bigint,
  subido_por   uuid NOT NULL REFERENCES public.perfiles(id) ON DELETE RESTRICT,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ============================================================================================
-- MATERIAL — de la empresa y por pais, no del asesor. Lo sube el admin_pais, lo leen todos los
-- comerciales de ese pais.
-- ============================================================================================
CREATE TABLE IF NOT EXISTS public.material_comercial (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pais_id      uuid NOT NULL REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT,
  titulo       text NOT NULL,
  descripcion  text,
  storage_path text NOT NULL UNIQUE,
  mime         text,
  bytes        bigint,
  activo       boolean NOT NULL DEFAULT true,
  subido_por   uuid NOT NULL REFERENCES public.perfiles(id) ON DELETE RESTRICT,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT material_titulo_no_vacio CHECK (length(btrim(titulo)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_adjuntos_visita  ON public.visita_adjuntos (visita_id);
CREATE INDEX IF NOT EXISTS idx_material_pais    ON public.material_comercial (pais_id) WHERE activo;

-- ============================================================================================
-- GUARD PA018 — no hay informe sin check-in. Va en la TABLA y no en la RPC: asi ningun camino
-- futuro (otra RPC, una correccion manual del owner) puede saltearse la regla.
-- ============================================================================================
CREATE OR REPLACE FUNCTION private.guard_reporte_exige_checkin()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_checkin timestamptz; v_existe boolean;
BEGIN
  SELECT v.checkin_at, true INTO v_checkin, v_existe
    FROM public.visitas_comerciales v WHERE v.id = NEW.visita_id;
  IF NOT COALESCE(v_existe, false) OR v_checkin IS NULL THEN
    RAISE EXCEPTION 'PA018: no se puede reportar una visita sin check-in (visita %)', NEW.visita_id
      USING ERRCODE = 'PA018';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS trg_reportes_exige_checkin ON public.reportes_visita;
CREATE TRIGGER trg_reportes_exige_checkin
  BEFORE INSERT OR UPDATE OF visita_id ON public.reportes_visita
  FOR EACH ROW EXECUTE FUNCTION private.guard_reporte_exige_checkin();

-- ============================================================================================
-- RLS — SELECT solamente; la escritura es de las RPCs.
-- ============================================================================================
ALTER TABLE public.catalogo_resultado_visita ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reportes_visita           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visita_adjuntos           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.material_comercial        ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.catalogo_resultado_visita FROM authenticated, anon;
REVOKE ALL ON public.reportes_visita           FROM authenticated, anon;
REVOKE ALL ON public.visita_adjuntos           FROM authenticated, anon;
REVOKE ALL ON public.material_comercial        FROM authenticated, anon;
GRANT SELECT ON public.catalogo_resultado_visita TO authenticated;
GRANT SELECT ON public.reportes_visita           TO authenticated;
GRANT SELECT ON public.visita_adjuntos           TO authenticated;
GRANT SELECT ON public.material_comercial        TO authenticated;

-- Predicado unico de "puedo ver esta visita": mismo molde que la 264/273 — pais CONJUNTIVO y la
-- pertenencia por el chokepoint. D4 sale de aca: el supervisor LEE el informe de su asesor porque
-- asesores_a_cargo() lo incluye, y NO lo escribe porque la RPC lo excluye.
CREATE OR REPLACE FUNCTION private.puede_ver_visita(p_visita_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT COALESCE((
    SELECT COALESCE(private.puede_admin_pais(v.pais_id), false)
        OR ( v.pais_id = private.mi_pais()
             AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a WHERE a = v.asesor_id) )
      FROM public.visitas_comerciales v WHERE v.id = p_visita_id
  ), false);
$function$;

DROP POLICY IF EXISTS catalogo_resultado_visita_select ON public.catalogo_resultado_visita;
CREATE POLICY catalogo_resultado_visita_select ON public.catalogo_resultado_visita
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS reportes_visita_select ON public.reportes_visita;
CREATE POLICY reportes_visita_select ON public.reportes_visita
  FOR SELECT TO authenticated USING (COALESCE(private.puede_ver_visita(visita_id), false));

DROP POLICY IF EXISTS visita_adjuntos_select ON public.visita_adjuntos;
CREATE POLICY visita_adjuntos_select ON public.visita_adjuntos
  FOR SELECT TO authenticated USING (COALESCE(private.puede_ver_visita(visita_id), false));

DROP POLICY IF EXISTS material_comercial_select ON public.material_comercial;
CREATE POLICY material_comercial_select ON public.material_comercial
  FOR SELECT TO authenticated
  USING (COALESCE(private.puede_admin_pais(pais_id), false) OR pais_id = private.mi_pais());

-- ============================================================================================
-- BUCKETS — 50 MB (D6), privados, mime restringido. Con sus policies, ABAJO, en esta migracion.
-- ============================================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('visitas-comerciales','visitas-comerciales', false, 52428800,
   ARRAY['image/jpeg','image/png','image/webp','video/mp4','video/quicktime']),
  ('material-comercial','material-comercial', false, 52428800,
   ARRAY['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','application/pdf'])
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Convencion de path, la misma que evidencias-visitas de la 209/212:
--   visitas-comerciales : {pais_id}/{visita_id}/{archivo}
--   material-comercial  : {pais_id}/{lo que sea}/{archivo}
-- El segmento 1 es el scope y el 2 la fila, resuelto con private.safe_uuid (que devuelve NULL en
-- vez de reventar si el texto no es un uuid).
DROP POLICY IF EXISTS visitas_com_storage_insert ON storage.objects;
CREATE POLICY visitas_com_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'visitas-comerciales'
    AND EXISTS (
      SELECT 1 FROM public.visitas_comerciales v
       WHERE v.id = private.safe_uuid(split_part(name, '/', 2))
         AND v.asesor_id = auth.uid()
         AND v.pais_id::text = split_part(name, '/', 1))
  );

DROP POLICY IF EXISTS visitas_com_storage_select ON storage.objects;
CREATE POLICY visitas_com_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'visitas-comerciales'
    AND COALESCE(private.puede_ver_visita(private.safe_uuid(split_part(name, '/', 2))), false)
  );

DROP POLICY IF EXISTS visitas_com_storage_update ON storage.objects;
CREATE POLICY visitas_com_storage_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'visitas-comerciales'
    AND EXISTS (
      SELECT 1 FROM public.visitas_comerciales v
       WHERE v.id = private.safe_uuid(split_part(name, '/', 2))
         AND v.asesor_id = auth.uid())
  );

DROP POLICY IF EXISTS material_com_storage_insert ON storage.objects;
CREATE POLICY material_com_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'material-comercial'
    AND COALESCE(private.puede_admin_pais(private.safe_uuid(split_part(name, '/', 1))), false)
  );

DROP POLICY IF EXISTS material_com_storage_select ON storage.objects;
CREATE POLICY material_com_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'material-comercial'
    AND ( COALESCE(private.puede_admin_pais(private.safe_uuid(split_part(name, '/', 1))), false)
       OR private.safe_uuid(split_part(name, '/', 1)) = private.mi_pais() )
  );

-- ============================================================================================
-- RPCs
-- ============================================================================================

-- guardar_reporte_visita — D4: lo escribe QUIEN HIZO LA VISITA. El supervisor lo lee (la policy
-- de SELECT lo incluye por el chokepoint) pero no lo escribe ni lo comenta.
CREATE OR REPLACE FUNCTION public.guardar_reporte_visita(
  p_visita_id uuid, p_resultado text, p_resumen text,
  p_compromisos text DEFAULT NULL, p_proxima_accion_fecha date DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v RECORD; v_id uuid;
BEGIN
  SELECT * INTO v FROM public.visitas_comerciales WHERE id = p_visita_id;

  -- LA LINEA QUE ATA: el dueño sale de la fila y es el asesor ASIGNADO. Fila inexistente ->
  -- v.asesor_id NULL -> el COALESCE lo cierra y "no existe" no se distingue de "no podes".
  IF NOT COALESCE(v.asesor_id = auth.uid(), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.catalogo_resultado_visita c
                  WHERE c.codigo = p_resultado AND c.activo) THEN
    RAISE EXCEPTION 'PA010: el resultado % no existe o esta inactivo', COALESCE(p_resultado,'(nulo)')
      USING ERRCODE = 'PA010';
  END IF;

  -- "sin check-in no hay informe" NO se revalida aca: lo impone el trigger PA018 sobre la tabla.
  INSERT INTO public.reportes_visita
    (visita_id, resultado, resumen, compromisos, proxima_accion_fecha, creado_por)
  VALUES (p_visita_id, p_resultado, btrim(p_resumen), p_compromisos, p_proxima_accion_fecha, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- registrar_adjunto_visita — el path se RE-DERIVA contra la fila, igual que en checkin_visita de
-- la 209/212. Un path es texto que manda el cliente: sin esta validacion, un adjunto podria
-- quedar apuntando al directorio de otra visita o de otro pais.
CREATE OR REPLACE FUNCTION public.registrar_adjunto_visita(
  p_visita_id uuid, p_storage_path text, p_mime text DEFAULT NULL, p_bytes bigint DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v RECORD; v_id uuid;
BEGIN
  SELECT * INTO v FROM public.visitas_comerciales WHERE id = p_visita_id;
  IF NOT COALESCE(v.asesor_id = auth.uid(), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  IF split_part(p_storage_path, '/', 1) IS DISTINCT FROM v.pais_id::text
     OR private.safe_uuid(split_part(p_storage_path, '/', 2)) IS DISTINCT FROM v.id THEN
    RAISE EXCEPTION 'PA023: el path % no corresponde a la visita % del pais %',
      COALESCE(p_storage_path,'(nulo)'), v.id, v.pais_id USING ERRCODE = 'PA023';
  END IF;

  INSERT INTO public.visita_adjuntos (visita_id, storage_path, mime, bytes, subido_por)
  VALUES (p_visita_id, p_storage_path, p_mime, p_bytes, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- guardar_material_comercial — la unica de este frente con pais por parametro: no hay fila de
-- donde derivarlo. El gate entero dentro del COALESCE es todo el control, como en
-- guardar_asesor_perfil de la 272.
CREATE OR REPLACE FUNCTION public.guardar_material_comercial(
  p_titulo text, p_pais_id uuid, p_storage_path text,
  p_descripcion text DEFAULT NULL, p_mime text DEFAULT NULL, p_bytes bigint DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_id uuid;
BEGIN
  IF NOT COALESCE(private.puede_admin_pais(p_pais_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF split_part(p_storage_path, '/', 1) IS DISTINCT FROM p_pais_id::text THEN
    RAISE EXCEPTION 'PA023: el path % no empieza con el pais %', COALESCE(p_storage_path,'(nulo)'), p_pais_id
      USING ERRCODE = 'PA023';
  END IF;

  INSERT INTO public.material_comercial (pais_id, titulo, descripcion, storage_path, mime, bytes, subido_por)
  VALUES (p_pais_id, btrim(p_titulo), p_descripcion, p_storage_path, p_mime, p_bytes, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- ============================================================================================
-- PRIVILEGIOS
-- ============================================================================================
REVOKE ALL ON FUNCTION private.puede_ver_visita(uuid)                       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guardar_reporte_visita(uuid,text,text,text,date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.registrar_adjunto_visita(uuid,text,text,bigint)  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guardar_material_comercial(text,uuid,text,text,text,bigint) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION private.puede_ver_visita(uuid)                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.guardar_reporte_visita(uuid,text,text,text,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_adjunto_visita(uuid,text,text,bigint)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.guardar_material_comercial(text,uuid,text,text,text,bigint) TO authenticated;

COMMENT ON FUNCTION public.guardar_reporte_visita(uuid,text,text,text,date) IS
'D4: el informe lo escribe QUIEN HIZO LA VISITA. El supervisor lo LEE —la policy de SELECT lo
incluye por private.asesores_a_cargo()— pero no lo escribe ni lo comenta. "Sin check-in no hay
informe" esta delegado al trigger PA018 sobre la tabla, no revalidado aca.';

-- Re-verificacion: privilegios, RLS, y que los DOS buckets existan CON policy. Un bucket sin
-- policy es justo el modo de falla de FASE 4, asi que la migracion aborta si pasa.
DO $$
DECLARE v_malas text; v_n int;
BEGIN
  SELECT string_agg(f, ', ') INTO v_malas FROM (
    SELECT p.oid::regprocedure::text AS f FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE (n.nspname,p.proname) IN (('public','guardar_reporte_visita'),('public','registrar_adjunto_visita'),
            ('public','guardar_material_comercial'),('private','puede_ver_visita'))
       AND (has_function_privilege('anon', p.oid,'EXECUTE') OR NOT has_function_privilege('authenticated', p.oid,'EXECUTE'))
  ) s;
  IF v_malas IS NOT NULL THEN RAISE EXCEPTION 'privilegios mal en: %', v_malas; END IF;

  SELECT string_agg(t, ', ') INTO v_malas FROM (
    SELECT c.relname AS t FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public'
       AND c.relname IN ('reportes_visita','visita_adjuntos','material_comercial','catalogo_resultado_visita')
       AND (NOT c.relrowsecurity OR has_table_privilege('authenticated', c.oid,'INSERT')
            OR has_table_privilege('authenticated', c.oid,'UPDATE') OR has_table_privilege('authenticated', c.oid,'DELETE'))
  ) s;
  IF v_malas IS NOT NULL THEN RAISE EXCEPTION 'tablas sin RLS o con escritura directa: %', v_malas; END IF;

  SELECT count(*) INTO v_n FROM storage.buckets WHERE id IN ('visitas-comerciales','material-comercial');
  IF v_n <> 2 THEN RAISE EXCEPTION 'faltan buckets: se esperaban 2, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND policyname IN ('visitas_com_storage_insert','visitas_com_storage_select','visitas_com_storage_update',
                        'material_com_storage_insert','material_com_storage_select');
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'BUCKET SIN POLICY: se esperaban 5 policies de storage, hay % — es el modo de falla de FASE 4', v_n;
  END IF;
END $$;
