-- ============================================================
-- Push promocional masivo · v1 AMBAS audiencias (PACIENTES + STAFF/CLÍNICAS). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — maquinaria INERTE (l.32). La publicación SÓLO congela la cola; NADA se
-- entrega (ni in-app ni web-push) hasta que la edge enviar-push-campana DRENE (único camino, l.7).
-- Probes P345–P358.
--
-- SEAM (Paso 0, confirmado): enviar-push transaccional acepta usuario_ids ARBITRARIOS sin autz (deuda
-- preexistente, increment aparte). El push promocional usa RUTA NUEVA Y SEPARADA (enviar-push-campana)
-- que recibe SÓLO solicitud_id e ignora cualquier lista; entrega in-app + web-push leyendo la audiencia
-- de una solicitud APROBADA. Cola con audiencia CONGELADA al aprobar + opt-out RE-EVALUADO al drenar
-- para AMBOS canales. La entrega ocurre SÓLO al drenar.
--
-- DECISIONES (Oscar): D2 ambas audiencias; añadir 'promocion' al CHECK de notificaciones_pacientes
-- (widening verificado: ningún consumidor DB keyea por tipo). Staff notificaciones no tiene CHECK.
-- D3 ambos flujos (super_admin directo es_plataforma + empresa→aprobación; solicitante NUNCA auto-
-- publica, l.10). D5 super_admin=gratis; empresa=plan (gancho plan_publicidad_id). D6 consent por
-- AUDIENCIA: STAFF default opt-IN COALESCE(acepta,true)=true; PACIENTES default opt-OUT FAIL-CLOSED
-- COALESCE(acepta,false)=true (NULL/ausente EXCLUYE; el fail-closed de consentimiento es EXCLUIR,
-- opuesto al de país; NO grandfather).
-- ============================================================

-- 0) CHECK widening de notificaciones_pacientes: admitir 'promocion' (D2). Pura ampliación, sin romper.
DO $$ DECLARE v_con text; BEGIN
  SELECT conname INTO v_con FROM pg_constraint
   WHERE conrelid='public.notificaciones_pacientes'::regclass AND contype='c'
     AND pg_get_constraintdef(oid) ILIKE '%tipo%';
  IF v_con IS NOT NULL THEN EXECUTE 'ALTER TABLE public.notificaciones_pacientes DROP CONSTRAINT '||quote_ident(v_con); END IF;
END $$;
ALTER TABLE public.notificaciones_pacientes
  ADD CONSTRAINT notificaciones_pacientes_tipo_check
  CHECK (tipo = ANY (ARRAY['cita','receta','examen','mensaje','general','promocion']));

-- 1) Preferencias de notificación (AMBOS id-spaces: staff uuid + paciente int). Consent D6.
CREATE TABLE IF NOT EXISTS public.preferencias_notificacion (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id   uuid    REFERENCES public.perfiles(id)  ON DELETE CASCADE,  -- staff
  paciente_id  integer REFERENCES public.pacientes(id) ON DELETE CASCADE,  -- paciente
  acepta_promociones boolean,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT prefnotif_un_solo_sujeto CHECK (
    (usuario_id IS NOT NULL AND paciente_id IS NULL) OR
    (usuario_id IS NULL AND paciente_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS prefnotif_usuario_uq  ON public.preferencias_notificacion(usuario_id)  WHERE usuario_id  IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS prefnotif_paciente_uq ON public.preferencias_notificacion(paciente_id) WHERE paciente_id IS NOT NULL;
ALTER TABLE public.preferencias_notificacion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS prefnotif_select_own ON public.preferencias_notificacion;
CREATE POLICY prefnotif_select_own ON public.preferencias_notificacion FOR SELECT TO authenticated USING (
  COALESCE(usuario_id = auth.uid(), false)
  OR COALESCE(paciente_id IN (SELECT p.id FROM public.pacientes p WHERE p.auth_user_id = auth.uid()), false)
  OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false));
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.preferencias_notificacion FROM PUBLIC, anon, authenticated;  -- write SÓLO vía RPC
REVOKE ALL  ON public.preferencias_notificacion FROM anon;
GRANT  SELECT ON public.preferencias_notificacion TO authenticated;

-- 2) Solicitud de push (tabla NUEVA, no se cuelga de solicitudes_campana — ver justificación).
--    solicitudes_campana es flujo ADS (aprobar_solicitud_campana CREA un banner en campanas_publicitarias,
--    tiene imagen/link/fecha-rango + plan; su CHECK de estado ya está cerrado). El push es otro artefacto
--    (mensaje/url/audiencia, one-shot). Reusar entrelazaría dos máquinas de estado + dos RPC de aprobación.
--    Tabla separada = sin blast radius en ads. (l.41: una sola policy permisiva por tabla, sin OR-trap.)
CREATE TABLE IF NOT EXISTS public.solicitudes_push (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid REFERENCES public.empresas_proveedoras(id) ON DELETE CASCADE,  -- NULL = plataforma (super_admin)
  creada_por    uuid,
  titulo        text NOT NULL,
  mensaje       text NOT NULL,
  url           text,
  audiencia     text NOT NULL DEFAULT 'staff'
                CHECK (audiencia = ANY (ARRAY['paciente','staff','ambas'])),
  audiencia_rol text,                                  -- sólo staff: NULL = todos los roles staff
  pais_id       uuid,                                  -- target; NULL sólo válido con es_plataforma (l.35)
  es_plataforma boolean NOT NULL DEFAULT false,        -- "todos plataforma": deliberado, SÓLO super_admin
  plan_publicidad_id integer REFERENCES public.planes_publicidad(id),  -- gancho D5
  estado        text NOT NULL DEFAULT 'borrador'
                CHECK (estado = ANY (ARRAY['borrador','enviada','aprobada','rechazada'])),
  aprobada_por  uuid,                                  -- publicador REAL (l.27)
  aprobada_at   timestamptz,
  conteo_audiencia integer,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.solicitudes_push ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS solpush_select_own ON public.solicitudes_push;
CREATE POLICY solpush_select_own ON public.solicitudes_push FOR SELECT TO authenticated USING (
  COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
  OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false));
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.solicitudes_push FROM PUBLIC, anon, authenticated;
REVOKE ALL  ON public.solicitudes_push FROM anon;
GRANT  SELECT ON public.solicitudes_push TO authenticated;

-- 3) Cola de envío (audiencia CONGELADA; carga las claves de entrega de AMBOS id-spaces).
--    audiencia='staff'    → usuario_id (notificaciones in-app) ; push_user_id = usuario_id (web-push)
--    audiencia='paciente' → paciente_id (notificaciones_pacientes in-app) ; push_user_id = pacientes.auth_user_id (web-push, NULL si no tiene auth)
CREATE TABLE IF NOT EXISTS public.envios_push_cola (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  solicitud_id uuid NOT NULL REFERENCES public.solicitudes_push(id) ON DELETE CASCADE,
  audiencia    text NOT NULL CHECK (audiencia = ANY (ARRAY['paciente','staff'])),
  paciente_id  integer,                                -- in-app pacientes
  usuario_id   uuid,                                   -- in-app staff
  push_user_id uuid,                                   -- web-push (push_subscriptions.user_id)
  estado       text NOT NULL DEFAULT 'pendiente'
               CHECK (estado = ANY (ARRAY['pendiente','enviando','enviado','fallido','omitido_optout'])),
  created_at   timestamptz NOT NULL DEFAULT now(),
  sent_at      timestamptz,
  CONSTRAINT colapush_sujeto_por_audiencia CHECK (
    (audiencia='staff'    AND usuario_id  IS NOT NULL AND paciente_id IS NULL) OR
    (audiencia='paciente' AND paciente_id IS NOT NULL AND usuario_id  IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS colapush_staff_uq    ON public.envios_push_cola(solicitud_id, usuario_id)  WHERE usuario_id  IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS colapush_paciente_uq ON public.envios_push_cola(solicitud_id, paciente_id) WHERE paciente_id IS NOT NULL;
ALTER TABLE public.envios_push_cola ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS colapush_select_sa ON public.envios_push_cola;
CREATE POLICY colapush_select_sa ON public.envios_push_cola FOR SELECT TO authenticated USING (
  COALESCE(private.tiene_rol(ARRAY['super_admin']), false));
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.envios_push_cola FROM PUBLIC, anon, authenticated;  -- escribe el RPC (owner) / drena la edge (service_role)
REVOKE ALL  ON public.envios_push_cola FROM anon;
GRANT  SELECT ON public.envios_push_cola TO authenticated;

-- 4) RPC: fijar la PROPIA preferencia (write path único de preferencias_notificacion).
CREATE OR REPLACE FUNCTION public.set_preferencia_notificacion(p_acepta boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_pac integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = 'PP001'; END IF;
  IF EXISTS (SELECT 1 FROM public.perfiles WHERE id = v_uid) THEN          -- staff
    INSERT INTO public.preferencias_notificacion (usuario_id, acepta_promociones)
      VALUES (v_uid, p_acepta)
      ON CONFLICT (usuario_id) WHERE usuario_id IS NOT NULL
      DO UPDATE SET acepta_promociones = EXCLUDED.acepta_promociones, updated_at = now();
    RETURN p_acepta;
  END IF;
  v_pac := (SELECT id FROM public.pacientes WHERE auth_user_id = v_uid LIMIT 1);  -- paciente
  IF v_pac IS NOT NULL THEN
    INSERT INTO public.preferencias_notificacion (paciente_id, acepta_promociones)
      VALUES (v_pac, p_acepta)
      ON CONFLICT (paciente_id) WHERE paciente_id IS NOT NULL
      DO UPDATE SET acepta_promociones = EXCLUDED.acepta_promociones, updated_at = now();
    RETURN p_acepta;
  END IF;
  RAISE EXCEPTION 'Sujeto no reconocido (ni staff ni paciente)' USING ERRCODE = 'PP001';
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.set_preferencia_notificacion(boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_preferencia_notificacion(boolean) TO authenticated;

-- 5) RPC: crear solicitud (empresa con permiso, o super_admin). estado='enviada'. NUNCA publica (l.10).
CREATE OR REPLACE FUNCTION public.crear_solicitud_push(
  p_titulo text, p_mensaje text, p_url text DEFAULT NULL, p_audiencia text DEFAULT 'staff',
  p_audiencia_rol text DEFAULT NULL, p_pais_id uuid DEFAULT NULL, p_es_plataforma boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_sa boolean; v_emp uuid; v_id uuid;
BEGIN
  IF p_audiencia NOT IN ('paciente','staff','ambas') THEN RAISE EXCEPTION 'audiencia inválida' USING ERRCODE='PP003'; END IF;
  v_sa  := COALESCE(private.tiene_rol(ARRAY['super_admin']), false);
  v_emp := public.mi_empresa_proveedor();
  IF p_es_plataforma AND NOT v_sa THEN RAISE EXCEPTION 'es_plataforma sólo super_admin' USING ERRCODE = 'PP002'; END IF;  -- l.35
  IF NOT v_sa THEN
    IF v_emp IS NULL THEN RAISE EXCEPTION 'Sin empresa proveedora' USING ERRCODE = 'PP001'; END IF;
    IF NOT COALESCE(private.tiene_permiso('publicidad_gestionar'), false) THEN
      RAISE EXCEPTION 'Requiere publicidad_gestionar' USING ERRCODE = 'PP001'; END IF;
    -- cross-país FAIL-CLOSED EN LA CREACIÓN (l.35): la empresa NO puede ni crear solicitud para un país en el que no opera
    IF p_pais_id IS NULL THEN RAISE EXCEPTION 'País requerido' USING ERRCODE = 'PP003'; END IF;
    IF NOT COALESCE(private.empresa_opera_en_pais(v_emp, p_pais_id), false) THEN
      RAISE EXCEPTION 'La empresa no opera en el país solicitado' USING ERRCODE = 'PP003'; END IF;
  END IF;
  IF NOT p_es_plataforma AND p_pais_id IS NULL THEN RAISE EXCEPTION 'País requerido (no plataforma)' USING ERRCODE = 'PP003'; END IF;
  INSERT INTO public.solicitudes_push (empresa_id, creada_por, titulo, mensaje, url, audiencia, audiencia_rol, pais_id, es_plataforma, estado)
    VALUES (CASE WHEN v_sa AND p_es_plataforma THEN NULL ELSE v_emp END,
            v_uid, p_titulo, p_mensaje, p_url, p_audiencia, p_audiencia_rol, p_pais_id, (p_es_plataforma AND v_sa), 'enviada')
    RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.crear_solicitud_push(text,text,text,text,text,uuid,boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.crear_solicitud_push(text,text,text,text,text,uuid,boolean) TO authenticated;

-- 6) RPC: PUBLICAR (sólo super_admin, l.10). Gateado por estado='enviada'. CONGELA cola por audiencia.
--    NO entrega nada (ni in-app ni web-push). Consent aplicado al congelar (D6 por audiencia).
CREATE OR REPLACE FUNCTION public.publicar_push(p_solicitud_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_s RECORD; v_n integer;
  c_staff_roles text[] := ARRAY['admin_clinica','medico','gerente','soporte','vendedor'];
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'No autorizado: sólo super_admin publica push' USING ERRCODE = 'PP010'; END IF;
  SELECT * INTO v_s FROM public.solicitudes_push WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no encontrada' USING ERRCODE = 'PP011'; END IF;
  IF v_s.estado <> 'enviada' THEN
    RAISE EXCEPTION 'Solicitud no está en estado enviada (%)', v_s.estado USING ERRCODE = 'PP012'; END IF;
  IF NOT v_s.es_plataforma THEN                                                          -- país fail-closed l.35
    IF v_s.pais_id IS NULL THEN RAISE EXCEPTION 'País requerido' USING ERRCODE = 'PP013'; END IF;
    IF v_s.empresa_id IS NOT NULL AND NOT COALESCE(private.empresa_opera_en_pais(v_s.empresa_id, v_s.pais_id), false) THEN
      RAISE EXCEPTION 'La empresa no opera en el país' USING ERRCODE = 'PP013'; END IF;
  END IF;

  IF v_s.audiencia IN ('staff','ambas') THEN          -- STAFF: default opt-IN, scope por perfiles.pais_id
    INSERT INTO public.envios_push_cola (solicitud_id, audiencia, usuario_id, push_user_id, estado)
    SELECT p_solicitud_id, 'staff', pf.id, pf.id, 'pendiente'
    FROM public.perfiles pf
    LEFT JOIN public.preferencias_notificacion pn ON pn.usuario_id = pf.id
    WHERE pf.activo = true AND pf.rol = ANY (c_staff_roles)
      AND (v_s.audiencia_rol IS NULL OR pf.rol = v_s.audiencia_rol)
      AND (v_s.es_plataforma OR pf.pais_id = v_s.pais_id)
      AND COALESCE(pn.acepta_promociones, true) = true
    ON CONFLICT DO NOTHING;
  END IF;

  IF v_s.audiencia IN ('paciente','ambas') THEN       -- PACIENTES: default opt-OUT FAIL-CLOSED, scope por pacientes.pais_id
    INSERT INTO public.envios_push_cola (solicitud_id, audiencia, paciente_id, push_user_id, estado)
    SELECT p_solicitud_id, 'paciente', pac.id, pac.auth_user_id, 'pendiente'
    FROM public.pacientes pac
    LEFT JOIN public.preferencias_notificacion pn ON pn.paciente_id = pac.id
    WHERE (v_s.es_plataforma OR pac.pais_id = v_s.pais_id)
      AND COALESCE(pn.acepta_promociones, false) = true       -- fail-closed: NULL/ausente EXCLUYE
    ON CONFLICT DO NOTHING;
  END IF;

  SELECT count(*) INTO v_n FROM public.envios_push_cola WHERE solicitud_id = p_solicitud_id;
  UPDATE public.solicitudes_push
    SET estado = 'aprobada', aprobada_por = auth.uid(), aprobada_at = now(),
        conteo_audiencia = v_n, updated_at = now()
    WHERE id = p_solicitud_id;
  RETURN v_n;   -- INERTE: cola congelada; CERO entrega (la edge drena: in-app + web-push)
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.publicar_push(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.publicar_push(uuid) TO authenticated;   -- gate real = tiene_rol(super_admin) dentro

-- 7) RPC: targets vigentes (ÚNICA fuente para la edge; opt-out RE-EVALUADO por audiencia al drenar). SÓLO service_role.
CREATE OR REPLACE FUNCTION public.targets_push_vigentes(p_solicitud_id uuid)
RETURNS TABLE(cola_id uuid, audiencia text, paciente_id integer, usuario_id uuid, push_user_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT c.id, c.audiencia, c.paciente_id, c.usuario_id, c.push_user_id
  FROM public.envios_push_cola c
  LEFT JOIN public.preferencias_notificacion ps ON c.audiencia='staff'    AND ps.usuario_id  = c.usuario_id
  LEFT JOIN public.preferencias_notificacion pp ON c.audiencia='paciente' AND pp.paciente_id = c.paciente_id
  WHERE c.solicitud_id = p_solicitud_id AND c.estado = 'pendiente'
    AND (CASE c.audiencia
           WHEN 'staff'    THEN COALESCE(ps.acepta_promociones, true)     -- staff opt-IN
           WHEN 'paciente' THEN COALESCE(pp.acepta_promociones, false)    -- paciente opt-OUT fail-closed
           ELSE false END);
$function$;
REVOKE EXECUTE ON FUNCTION public.targets_push_vigentes(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.targets_push_vigentes(uuid) TO service_role;  -- sólo la edge (no enumerable por usuarios)

-- 8) RPC: DRENAR (claim atómico anti-TOCTOU, l.47). Marca opted-out → omitido; reclama vigentes pendientes
--    → 'enviando' con FOR UPDATE SKIP LOCKED (dos invocaciones concurrentes NO entregan dos veces). SÓLO service_role.
-- DEUDA RELIABILITY (diferida, aceptable v1 inerte/volumen chico): si la edge crashea tras reclamar
-- (pendiente→enviando) antes de confirmar, el target queda VARADO en 'enviando' y un reintento no lo
-- re-reclama (sólo toma 'pendiente'). Mitigación futura: reclaim por TTL de 'enviando' viejos (p.ej.
-- WHERE estado='enviando' AND sent_at < now()-interval). Anotar en roadmap.
CREATE OR REPLACE FUNCTION public.drenar_targets_push(p_solicitud_id uuid)
RETURNS TABLE(cola_id uuid, audiencia text, paciente_id integer, usuario_id uuid, push_user_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  -- (1) opted-out pendientes → omitido_optout (idempotente; mismo predicado que targets_push_vigentes)
  UPDATE public.envios_push_cola c SET estado='omitido_optout'
  WHERE c.solicitud_id = p_solicitud_id AND c.estado='pendiente'
    AND NOT (CASE c.audiencia
      WHEN 'staff'    THEN COALESCE((SELECT pn.acepta_promociones FROM public.preferencias_notificacion pn WHERE pn.usuario_id  = c.usuario_id),  true)
      WHEN 'paciente' THEN COALESCE((SELECT pn.acepta_promociones FROM public.preferencias_notificacion pn WHERE pn.paciente_id = c.paciente_id), false)
      ELSE false END);
  -- (2) claim atómico de los pendientes vigentes restantes (anti doble-envío concurrente)
  RETURN QUERY
  UPDATE public.envios_push_cola u SET estado='enviando', sent_at = now()
  WHERE u.id IN (
    SELECT c.id FROM public.envios_push_cola c
    WHERE c.solicitud_id = p_solicitud_id AND c.estado = 'pendiente'
    FOR UPDATE SKIP LOCKED
  )
  RETURNING u.id, u.audiencia, u.paciente_id, u.usuario_id, u.push_user_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.drenar_targets_push(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.drenar_targets_push(uuid) TO service_role;  -- sólo la edge
