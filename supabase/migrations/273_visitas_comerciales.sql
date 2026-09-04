-- ############################################################################################
-- 273 — FRENTE VISITAS del modulo comercial: jornada, visita, config por pais y guards
-- ############################################################################################
-- Alcance: jornadas_comerciales, visitas_comerciales, el catalogo de estados, la config de
-- verificacion por pais, los guards PA015-PA017 y 5 RPCs. Los reportes, los adjuntos, el material
-- y los dos buckets van en la 274 — separadas a proposito: la 274 depende de que las visitas
-- existan, y un bucket con policy mal scopeada se descubre tarde. Asi el rollback de una no
-- arrastra la otra.
--
-- NO SE TOCA `visitas_agendadas`. El visitador medico vive en `cuentas_proveedor` y el asesor
-- comercial en `perfiles`: son dos espacios de identidad. De aquella tabla se reusa la FORMA de
-- checkin_visita (cargar fila -> ownership -> estado -> ventana -> anti-doble -> escribir), no
-- una sola fila ni una sola columna.
--
-- ERRCODES: PA015-PA017 guards, PA019-PA022 y PA024-PA025 en las RPCs. PA008 se REUSA para
-- "ficha inactiva" porque es exactamente lo que ya significa en la 272. PA018 y PA023 quedan
-- RESERVADOS para la 274 (reporte sin check-in, path de adjunto ajeno).
-- ############################################################################################

-- ============================================================================================
-- CATALOGO de estados de la visita
-- ============================================================================================
CREATE TABLE IF NOT EXISTS public.catalogo_estado_visita_comercial (
  codigo      text PRIMARY KEY,
  etiqueta    text NOT NULL,
  orden       int  NOT NULL DEFAULT 0,
  es_final    boolean NOT NULL DEFAULT false,
  activo      boolean NOT NULL DEFAULT true
);
INSERT INTO public.catalogo_estado_visita_comercial (codigo, etiqueta, orden, es_final) VALUES
  ('planificada','Planificada',10,false),
  ('en_curso','En curso',20,false),
  ('realizada','Realizada',30,true),
  ('no_realizada','No realizada',40,true),
  ('cancelada','Cancelada',50,true)
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================================================
-- CONFIG DE VERIFICACION POR PAIS — D5, y el fail-closed es el punto entero
-- ============================================================================================
-- La migracion NO siembra ninguna fila. La ausencia es el estado inicial normal y el default vive
-- en los dos helpers de abajo. Un radio NULL que valide todo seria el mismo fail-open trivaluado
-- que costo siete migraciones en PA-FAILOPEN, asi que:
--   * COALESCE cubre la fila ausente Y la columna NULL,
--   * y los CHECK impiden que alguien configure "sin limite" a mano.
CREATE TABLE IF NOT EXISTS public.config_visitas_pais (
  pais_id            uuid PRIMARY KEY REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT,
  radio_checkin_m    numeric NOT NULL DEFAULT 150,
  precision_max_m    numeric NOT NULL DEFAULT 100,
  activo             boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT config_visitas_radio_razonable     CHECK (radio_checkin_m  BETWEEN 10 AND 5000),
  CONSTRAINT config_visitas_precision_razonable CHECK (precision_max_m  BETWEEN 10 AND 1000)
);

CREATE OR REPLACE FUNCTION private.radio_checkin_m(p_pais_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT COALESCE(
    (SELECT c.radio_checkin_m FROM public.config_visitas_pais c
      WHERE c.pais_id = p_pais_id AND c.activo),
    150);
$function$;

CREATE OR REPLACE FUNCTION private.precision_max_checkin_m(p_pais_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT COALESCE(
    (SELECT c.precision_max_m FROM public.config_visitas_pais c
      WHERE c.pais_id = p_pais_id AND c.activo),
    100);
$function$;

COMMENT ON FUNCTION private.radio_checkin_m(uuid) IS
'D5 fail-closed. Sin fila de config, o con la columna NULL, o con la config desactivada, devuelve
150 m — NUNCA "sin limite". El COALESCE es el control, no una comodidad: un NULL que se propague
haria que `distancia <= radio` diera NULL y el IF no entrara, que es exactamente el fail-open
trivaluado de la mig 222. Los CHECK de la tabla impiden ademas configurar un radio absurdo.';

-- ============================================================================================
-- DISTANCIA — haversine. No hay PostGIS en el proyecto (verificado: 0 extensiones).
-- ============================================================================================
CREATE OR REPLACE FUNCTION private.distancia_m(
  p_lat1 numeric, p_lng1 numeric, p_lat2 numeric, p_lng2 numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = ''
AS $function$
  SELECT CASE
    WHEN p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN NULL
    ELSE (2 * 6371000 * asin(sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
      + cos(radians(p_lat1)) * cos(radians(p_lat2))
      * power(sin(radians(p_lng2 - p_lng1) / 2), 2))))::numeric
  END;
$function$;

COMMENT ON FUNCTION private.distancia_m(numeric,numeric,numeric,numeric) IS
'Distancia en metros entre dos puntos. Devuelve NULL si falta cualquier coordenada — y quien la
consume tiene que tratar ese NULL como "no verificable", nunca como "verificado".';

-- ============================================================================================
-- JORNADA
-- ============================================================================================
CREATE TABLE IF NOT EXISTS public.jornadas_comerciales (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asesor_id          uuid NOT NULL REFERENCES public.perfiles(id) ON DELETE RESTRICT,
  pais_id            uuid NOT NULL REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT,
  fecha              date NOT NULL DEFAULT CURRENT_DATE,
  inicio_at          timestamptz NOT NULL DEFAULT now(),
  inicio_lat         numeric,
  inicio_lng         numeric,
  inicio_precision_m numeric,
  fin_at             timestamptz,
  fin_lat            numeric,
  fin_lng            numeric,
  fin_precision_m    numeric,
  notas_cierre       text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT jornadas_una_por_dia UNIQUE (asesor_id, fecha),
  CONSTRAINT jornadas_fin_posterior CHECK (fin_at IS NULL OR fin_at >= inicio_at)
);

-- ============================================================================================
-- VISITA
-- ============================================================================================
-- Sobre los nombres: el booleano se llama `checkin_verificado`, no `presente` ni `confirmado`.
-- Significa "la coordenada REPORTADA es consistente con la del prospecto", no "estuvo ahi": un
-- GPS se falsea con una app de mock location. Un campo que promete mas de lo que el dato sostiene
-- es el mismo error que un `disabled` que se lee como proteccion.
CREATE TABLE IF NOT EXISTS public.visitas_comerciales (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prospecto_id        uuid NOT NULL REFERENCES public.prospectos(id) ON DELETE RESTRICT,
  asesor_id           uuid NOT NULL REFERENCES public.perfiles(id) ON DELETE RESTRICT,
  pais_id             uuid NOT NULL REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT,
  jornada_id          uuid REFERENCES public.jornadas_comerciales(id) ON DELETE SET NULL,
  fecha_planificada   date NOT NULL DEFAULT CURRENT_DATE,
  estado              text NOT NULL DEFAULT 'planificada'
                      REFERENCES public.catalogo_estado_visita_comercial(codigo) ON DELETE RESTRICT,
  -- check-in
  checkin_at          timestamptz,          -- SIEMPRE now() del servidor
  checkin_cliente_at  timestamptz,          -- reloj del dispositivo; solo en el camino diferido
  checkin_origen      text NOT NULL DEFAULT 'en_linea'
                      CHECK (checkin_origen IN ('en_linea','diferido')),
  checkin_lat         numeric,
  checkin_lng         numeric,
  checkin_precision_m numeric,
  checkin_distancia_m numeric,              -- la calcula la RPC; NUNCA llega por parametro
  checkin_verificado  boolean NOT NULL DEFAULT false,
  checkin_motivo      text,                 -- por que NO verifico, cuando no verifico
  -- check-out
  checkout_at         timestamptz,
  checkout_lat        numeric,
  checkout_lng        numeric,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT visitas_com_una_por_dia UNIQUE (prospecto_id, asesor_id, fecha_planificada),
  CONSTRAINT visitas_com_checkout_exige_checkin CHECK (checkout_at IS NULL OR checkin_at IS NOT NULL),
  CONSTRAINT visitas_com_diferido_nunca_verifica
    CHECK (NOT (checkin_origen = 'diferido' AND checkin_verificado))
);

COMMENT ON CONSTRAINT visitas_com_diferido_nunca_verifica ON public.visitas_comerciales IS
'Un check-in encolado offline NO puede quedar verificado, y esto lo garantiza la TABLA y no solo
la RPC. Cuando el registro llega diferido, now() del servidor es la hora de sincronizacion —
posterior al hecho— y checkin_cliente_at la controla el asesor: no hay reloj confiable, asi que no
hay verificacion posible. Con el CHECK, ningun camino futuro puede saltearse la regla.';

CREATE INDEX IF NOT EXISTS idx_visitas_com_asesor_fecha ON public.visitas_comerciales (asesor_id, fecha_planificada DESC);
CREATE INDEX IF NOT EXISTS idx_visitas_com_prospecto   ON public.visitas_comerciales (prospecto_id);
CREATE INDEX IF NOT EXISTS idx_jornadas_asesor_fecha   ON public.jornadas_comerciales (asesor_id, fecha DESC);

-- ============================================================================================
-- GUARDS
-- ============================================================================================
CREATE OR REPLACE FUNCTION private.guard_pais_visita_comercial()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais_prospecto uuid; v_pais_ficha uuid;
BEGIN
  SELECT pr.pais_id INTO v_pais_prospecto FROM public.prospectos pr WHERE pr.id = NEW.prospecto_id;
  SELECT ap.pais_id INTO v_pais_ficha     FROM public.asesores_perfil ap WHERE ap.id = NEW.asesor_id;

  -- IS DISTINCT FROM y no `<>`: con `<>` un NULL daria NULL, el IF no entraria y la validacion se
  -- saltearia. Es literalmente el bug de la mig 222.
  IF NEW.pais_id IS DISTINCT FROM v_pais_prospecto THEN
    RAISE EXCEPTION 'PA015: la visita se marca en el pais % pero el prospecto % es del pais %',
      COALESCE(NEW.pais_id::text,'(nulo)'), NEW.prospecto_id,
      COALESCE(v_pais_prospecto::text,'(prospecto inexistente)') USING ERRCODE = 'PA015';
  END IF;
  IF NEW.pais_id IS DISTINCT FROM v_pais_ficha THEN
    RAISE EXCEPTION 'PA015: la visita es del pais % pero la ficha del asesor % es del pais %',
      COALESCE(NEW.pais_id::text,'(nulo)'), NEW.asesor_id,
      COALESCE(v_pais_ficha::text,'(el asesor no tiene ficha)') USING ERRCODE = 'PA015';
  END IF;

  -- PA017: la visita no puede colgar de la jornada de otro asesor ni de otra fecha.
  IF NEW.jornada_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.jornadas_comerciales j
                    WHERE j.id = NEW.jornada_id
                      AND j.asesor_id = NEW.asesor_id
                      AND j.fecha = NEW.fecha_planificada) THEN
      RAISE EXCEPTION 'PA017: la jornada % no es del asesor % o no es de la fecha %',
        NEW.jornada_id, NEW.asesor_id, NEW.fecha_planificada USING ERRCODE = 'PA017';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS trg_visitas_com_guard_pais ON public.visitas_comerciales;
CREATE TRIGGER trg_visitas_com_guard_pais
  BEFORE INSERT OR UPDATE OF pais_id, prospecto_id, asesor_id, jornada_id, fecha_planificada
  ON public.visitas_comerciales
  FOR EACH ROW EXECUTE FUNCTION private.guard_pais_visita_comercial();

CREATE OR REPLACE FUNCTION private.guard_jornada_pais()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais_ficha uuid;
BEGIN
  SELECT ap.pais_id INTO v_pais_ficha FROM public.asesores_perfil ap WHERE ap.id = NEW.asesor_id;
  IF NEW.pais_id IS DISTINCT FROM v_pais_ficha THEN
    RAISE EXCEPTION 'PA016: la jornada se abre en el pais % pero la ficha de % es del pais %',
      COALESCE(NEW.pais_id::text,'(nulo)'), NEW.asesor_id,
      COALESCE(v_pais_ficha::text,'(el asesor no tiene ficha)') USING ERRCODE = 'PA016';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS trg_jornadas_guard_pais ON public.jornadas_comerciales;
CREATE TRIGGER trg_jornadas_guard_pais
  BEFORE INSERT OR UPDATE OF pais_id, asesor_id ON public.jornadas_comerciales
  FOR EACH ROW EXECUTE FUNCTION private.guard_jornada_pais();

-- ============================================================================================
-- RLS — SELECT solamente. La escritura es exclusiva de las RPCs, igual que en la 272.
-- ============================================================================================
ALTER TABLE public.catalogo_estado_visita_comercial ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.config_visitas_pais              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jornadas_comerciales             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitas_comerciales              ENABLE ROW LEVEL SECURITY;

-- Toda tabla nueva en public nace con ALL para `authenticated` por default privileges: hay que
-- revocar EXPLICITAMENTE o el gate de RLS es lo unico que queda entre el usuario y un UPDATE.
REVOKE ALL ON public.catalogo_estado_visita_comercial FROM authenticated, anon;
REVOKE ALL ON public.config_visitas_pais              FROM authenticated, anon;
REVOKE ALL ON public.jornadas_comerciales             FROM authenticated, anon;
REVOKE ALL ON public.visitas_comerciales              FROM authenticated, anon;
GRANT SELECT ON public.catalogo_estado_visita_comercial TO authenticated;
GRANT SELECT ON public.config_visitas_pais              TO authenticated;
GRANT SELECT ON public.jornadas_comerciales             TO authenticated;
GRANT SELECT ON public.visitas_comerciales              TO authenticated;

DROP POLICY IF EXISTS catalogo_estado_visita_select ON public.catalogo_estado_visita_comercial;
CREATE POLICY catalogo_estado_visita_select ON public.catalogo_estado_visita_comercial
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS config_visitas_pais_select ON public.config_visitas_pais;
CREATE POLICY config_visitas_pais_select ON public.config_visitas_pais
  FOR SELECT TO authenticated
  USING (COALESCE(private.puede_admin_pais(pais_id), false) OR pais_id = private.mi_pais());

-- Mismo molde que las policies de la 264: termino de pais CONJUNTIVO y la pertenencia SIEMPRE por
-- el chokepoint private.asesores_a_cargo(), nunca escrita a mano.
DROP POLICY IF EXISTS jornadas_comerciales_select ON public.jornadas_comerciales;
CREATE POLICY jornadas_comerciales_select ON public.jornadas_comerciales
  FOR SELECT TO authenticated
  USING (
    COALESCE(private.puede_admin_pais(pais_id), false)
    OR ( pais_id = private.mi_pais()
         AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a WHERE a = asesor_id) )
  );

DROP POLICY IF EXISTS visitas_comerciales_select ON public.visitas_comerciales;
CREATE POLICY visitas_comerciales_select ON public.visitas_comerciales
  FOR SELECT TO authenticated
  USING (
    COALESCE(private.puede_admin_pais(pais_id), false)
    OR ( pais_id = private.mi_pais()
         AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a WHERE a = asesor_id) )
  );

-- ============================================================================================
-- RPCs
-- ============================================================================================

-- 1. abrir_jornada — NO recibe asesor_id ni pais_id.
CREATE OR REPLACE FUNCTION public.abrir_jornada(
  p_lat numeric DEFAULT NULL, p_lng numeric DEFAULT NULL, p_precision_m numeric DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_activo boolean; v_id uuid;
BEGIN
  -- LA LINEA QUE ATA: el sujeto es auth.uid() y no hay ningun parametro con el que decir "la
  -- jornada de otro". El pais sale de la ficha, no se recibe.
  SELECT ap.pais_id, ap.activo INTO v_pais, v_activo
    FROM public.asesores_perfil ap WHERE ap.id = auth.uid();

  IF NOT COALESCE(private.tiene_rol(ARRAY['asesor_comercial','supervisor_comercial']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(v_activo, false) THEN
    RAISE EXCEPTION 'PA008: tu ficha de asesor no existe o esta inactiva' USING ERRCODE = 'PA008';
  END IF;
  IF EXISTS (SELECT 1 FROM public.jornadas_comerciales j
              WHERE j.asesor_id = auth.uid() AND j.fecha = CURRENT_DATE) THEN
    RAISE EXCEPTION 'PA020: ya abriste la jornada de hoy' USING ERRCODE = 'PA020';
  END IF;

  INSERT INTO public.jornadas_comerciales (asesor_id, pais_id, inicio_lat, inicio_lng, inicio_precision_m)
  VALUES (auth.uid(), v_pais, p_lat, p_lng, p_precision_m)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- 2. cerrar_jornada — tampoco recibe id: se busca la del llamante, de hoy, abierta.
CREATE OR REPLACE FUNCTION public.cerrar_jornada(
  p_lat numeric DEFAULT NULL, p_lng numeric DEFAULT NULL,
  p_precision_m numeric DEFAULT NULL, p_notas text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_id uuid;
BEGIN
  SELECT j.id INTO v_id FROM public.jornadas_comerciales j
   WHERE j.asesor_id = auth.uid() AND j.fecha = CURRENT_DATE AND j.fin_at IS NULL;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'PA021: no tenes una jornada abierta hoy' USING ERRCODE = 'PA021';
  END IF;
  UPDATE public.jornadas_comerciales
     SET fin_at = now(), fin_lat = p_lat, fin_lng = p_lng,
         fin_precision_m = p_precision_m, notas_cierre = p_notas, updated_at = now()
   WHERE id = v_id;
END
$function$;

-- 3. planificar_visita — el asesor sale del PROSPECTO, no del llamante.
CREATE OR REPLACE FUNCTION public.planificar_visita(
  p_prospecto_id uuid, p_fecha date DEFAULT CURRENT_DATE)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_asesor uuid; v_jornada uuid; v_id uuid;
BEGIN
  -- LA LINEA QUE ATA: reusa el predicado de la 272 — el supervisor entra por su CARTERA via el
  -- chokepoint, y no se escribe aca una segunda regla de "de quien es".
  IF NOT COALESCE(private.puede_gestionar_prospecto(p_prospecto_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- El asesor de la visita es el ASIGNADO al prospecto, NO auth.uid(): si saliera del llamante,
  -- un supervisor que planifica se apropiaria de la visita de su asesor.
  SELECT pr.pais_id, pr.asesor_id INTO v_pais, v_asesor
    FROM public.prospectos pr WHERE pr.id = p_prospecto_id;

  SELECT j.id INTO v_jornada FROM public.jornadas_comerciales j
   WHERE j.asesor_id = v_asesor AND j.fecha = p_fecha;

  INSERT INTO public.visitas_comerciales (prospecto_id, asesor_id, pais_id, jornada_id, fecha_planificada)
  VALUES (p_prospecto_id, v_asesor, v_pais, v_jornada, p_fecha)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- 4. checkin_visita_comercial — SOLO el asesor asignado hace su propio check-in.
CREATE OR REPLACE FUNCTION public.checkin_visita_comercial(
  p_visita_id uuid, p_lat numeric, p_lng numeric,
  p_precision_m numeric DEFAULT NULL, p_cliente_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v RECORD; v_jornada RECORD; v_plat numeric; v_plng numeric;
        v_dist numeric; v_radio numeric; v_prec_max numeric;
        v_origen text; v_verificado boolean; v_motivo text;
BEGIN
  SELECT * INTO v FROM public.visitas_comerciales WHERE id = p_visita_id;

  -- LA LINEA QUE ATA: el dueño sale de la FILA. Ni el supervisor ni el admin: un check-in hecho
  -- por otro no es un dato, es una falsificacion. Fila inexistente -> v.asesor_id NULL -> el
  -- COALESCE lo cierra, y "no existe" no se distingue de "no podes".
  IF NOT COALESCE(v.asesor_id = auth.uid(), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF v.checkin_at IS NOT NULL THEN
    RAISE EXCEPTION 'PA025: esta visita ya tiene check-in' USING ERRCODE = 'PA025';
  END IF;

  SELECT * INTO v_jornada FROM public.jornadas_comerciales j
   WHERE j.asesor_id = auth.uid() AND j.fecha = CURRENT_DATE AND j.fin_at IS NULL;
  IF v_jornada.id IS NULL THEN
    RAISE EXCEPTION 'PA022: no hay jornada abierta; abri la jornada antes de hacer check-in'
      USING ERRCODE = 'PA022';
  END IF;

  v_origen := CASE WHEN p_cliente_at IS NULL THEN 'en_linea' ELSE 'diferido' END;

  -- PA024: el diferido no es prueba, pero un dato groseramente inconsistente no entra.
  IF v_origen = 'diferido' THEN
    IF p_cliente_at > now()
       OR p_cliente_at::date <> CURRENT_DATE
       OR p_cliente_at < v_jornada.inicio_at THEN
      RAISE EXCEPTION 'PA024: la hora del dispositivo (%) no es consistente con la jornada abierta a las %',
        p_cliente_at, v_jornada.inicio_at USING ERRCODE = 'PA024';
    END IF;
  END IF;

  SELECT pr.lat, pr.lng INTO v_plat, v_plng FROM public.prospectos pr WHERE pr.id = v.prospecto_id;

  -- La distancia se CALCULA aca. Recibirla por parametro seria el mismo error que un filtro de
  -- cliente que se lee como control: el dato que decide lo pondria el que esta siendo medido.
  v_dist     := private.distancia_m(p_lat, p_lng, v_plat, v_plng);
  v_radio    := private.radio_checkin_m(v.pais_id);
  v_prec_max := private.precision_max_checkin_m(v.pais_id);

  -- Gate ENTERO dentro del COALESCE: cualquier NULL de por medio da false, nunca "pasa".
  v_verificado := COALESCE(
        v_origen = 'en_linea'
    AND v_dist IS NOT NULL AND v_dist <= v_radio
    AND p_precision_m IS NOT NULL AND p_precision_m <= v_prec_max
  , false);

  v_motivo := CASE
    WHEN v_verificado THEN NULL
    WHEN v_origen = 'diferido' THEN 'diferido: sin reloj de servidor confiable no hay verificacion'
    WHEN v_plat IS NULL OR v_plng IS NULL THEN 'el prospecto no tiene coordenada cargada'
    WHEN p_lat IS NULL OR p_lng IS NULL THEN 'el dispositivo no reporto coordenada'
    WHEN p_precision_m IS NULL THEN 'el dispositivo no reporto precision'
    WHEN p_precision_m > v_prec_max THEN 'precision de '||round(p_precision_m)||' m, el maximo es '||round(v_prec_max)||' m'
    WHEN v_dist > v_radio THEN 'a '||round(v_dist)||' m del prospecto, el radio es '||round(v_radio)||' m'
    ELSE 'no verificable' END;

  UPDATE public.visitas_comerciales
     SET checkin_at = now(),                 -- SIEMPRE el reloj del servidor
         checkin_cliente_at = p_cliente_at,  -- el del dispositivo, solo si vino diferido
         checkin_origen = v_origen,
         checkin_lat = p_lat, checkin_lng = p_lng, checkin_precision_m = p_precision_m,
         checkin_distancia_m = v_dist,
         checkin_verificado = v_verificado,
         checkin_motivo = v_motivo,
         jornada_id = v_jornada.id,
         estado = 'en_curso',
         updated_at = now()
   WHERE id = p_visita_id;

  RETURN jsonb_build_object('verificado', v_verificado, 'distancia_m', v_dist,
                            'origen', v_origen, 'motivo', v_motivo);
END
$function$;

-- 5. checkout_visita_comercial
CREATE OR REPLACE FUNCTION public.checkout_visita_comercial(
  p_visita_id uuid, p_lat numeric DEFAULT NULL, p_lng numeric DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v RECORD; v_jornada_cerrada boolean;
BEGIN
  SELECT * INTO v FROM public.visitas_comerciales WHERE id = p_visita_id;
  IF NOT COALESCE(v.asesor_id = auth.uid(), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF v.checkin_at IS NULL THEN
    RAISE EXCEPTION 'PA022: no hay check-in que cerrar' USING ERRCODE = 'PA022';
  END IF;

  SELECT COALESCE(j.fin_at IS NOT NULL, false) INTO v_jornada_cerrada
    FROM public.jornadas_comerciales j WHERE j.id = v.jornada_id;
  IF COALESCE(v_jornada_cerrada, false) THEN
    RAISE EXCEPTION 'PA019: la jornada de esa visita ya esta cerrada' USING ERRCODE = 'PA019';
  END IF;

  UPDATE public.visitas_comerciales
     SET checkout_at = now(), checkout_lat = p_lat, checkout_lng = p_lng,
         estado = 'realizada', updated_at = now()
   WHERE id = p_visita_id;
END
$function$;

-- ============================================================================================
-- PRIVILEGIOS. REVOKE primero y solo; GRANT despues; re-verificacion al final.
-- ============================================================================================
REVOKE ALL ON FUNCTION private.radio_checkin_m(uuid)                FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.precision_max_checkin_m(uuid)        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.distancia_m(numeric,numeric,numeric,numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.abrir_jornada(numeric,numeric,numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cerrar_jornada(numeric,numeric,numeric,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.planificar_visita(uuid,date)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.checkin_visita_comercial(uuid,numeric,numeric,numeric,timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.checkout_visita_comercial(uuid,numeric,numeric) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION private.radio_checkin_m(uuid)                TO authenticated;
GRANT EXECUTE ON FUNCTION private.precision_max_checkin_m(uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION private.distancia_m(numeric,numeric,numeric,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.abrir_jornada(numeric,numeric,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cerrar_jornada(numeric,numeric,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.planificar_visita(uuid,date)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.checkin_visita_comercial(uuid,numeric,numeric,numeric,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.checkout_visita_comercial(uuid,numeric,numeric) TO authenticated;

COMMENT ON FUNCTION public.checkin_visita_comercial(uuid,numeric,numeric,numeric,timestamptz) IS
'Check-in de una visita comercial. SOLO lo hace el asesor asignado (el dueño sale de la fila).
Lo que es verificable: checkin_at = now() del servidor, la distancia calculada CONTRA
prospectos.lat/lng dentro de esta funcion, y el booleano derivado de ambos.
Lo que NO es verificable y queda declarado: la coordenada en si (un GPS se falsea con una app de
mock location) y la precision reportada. Por eso el campo se llama checkin_verificado —
"la coordenada reportada es consistente"— y no `presente`.';

DO $$
DECLARE v_malas text;
BEGIN
  SELECT string_agg(f, ', ') INTO v_malas FROM (
    SELECT p.oid::regprocedure::text AS f
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname, p.proname) IN
           (('public','abrir_jornada'), ('public','cerrar_jornada'), ('public','planificar_visita'),
            ('public','checkin_visita_comercial'), ('public','checkout_visita_comercial'),
            ('private','radio_checkin_m'), ('private','precision_max_checkin_m'), ('private','distancia_m'))
       AND (has_function_privilege('anon', p.oid, 'EXECUTE')
            OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  ) s;
  IF v_malas IS NOT NULL THEN RAISE EXCEPTION 'privilegios mal en: %', v_malas; END IF;

  SELECT string_agg(t, ', ') INTO v_malas FROM (
    SELECT c.relname AS t FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public'
       AND c.relname IN ('jornadas_comerciales','visitas_comerciales','config_visitas_pais',
                         'catalogo_estado_visita_comercial')
       AND (NOT c.relrowsecurity
            OR has_table_privilege('authenticated', c.oid, 'INSERT')
            OR has_table_privilege('authenticated', c.oid, 'UPDATE')
            OR has_table_privilege('authenticated', c.oid, 'DELETE'))
  ) s;
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'tablas sin RLS o con escritura directa para authenticated: %', v_malas;
  END IF;
END $$;
