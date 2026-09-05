-- ############################################################################################
-- 280 — Agenda de visitas comerciales: hora, autoria, reprogramar, cancelar y adopcion
-- ############################################################################################
-- Contrato aprobado. Cinco piezas:
--   a) columnas hora_planificada / planificada_por / cancelacion_motivo + CHECK de motivo
--   b) planificar_visita recreada con hora y con autoria
--   c) reprogramar_visita_comercial
--   d) cancelar_visita_comercial
--   e) adopcion de visitas huerfanas al abrir la jornada
--
-- ERRCODES NUEVOS
--   PA026  la fecha esta en el pasado
--   PA027  la visita no esta en un estado (o una forma) que admita la operacion
--          — cubre "ya tiene check-in", "ya esta cancelada" y "falta el motivo": es la misma
--          regla dicha tres veces, no tres reglas.
--
-- OJO CON EL TRIGGER EXISTENTE: trg_visitas_com_guard_pais dispara en
-- BEFORE INSERT OR UPDATE OF pais_id, prospecto_id, asesor_id, jornada_id, fecha_planificada.
-- Reprogramar toca fecha_planificada y jornada_id, asi que PA015/PA017 se revalidan solos en ese
-- UPDATE. La jornada_id nueva se calcula del MISMO asesor en la MISMA fecha, asi que es
-- consistente por construccion. Cancelar toca estado y cancelacion_motivo, que no estan en esa
-- lista: no lo dispara.
-- ############################################################################################

-- ============================================================================================
-- (a) COLUMNAS
-- ============================================================================================
ALTER TABLE public.visitas_comerciales
  ADD COLUMN IF NOT EXISTS hora_planificada   time NULL,
  ADD COLUMN IF NOT EXISTS planificada_por    uuid NULL,
  ADD COLUMN IF NOT EXISTS cancelacion_motivo text NULL;

-- Backfill: las visitas que ya existen no guardaron quien las planifico. Se les asigna el asesor
-- asignado, que es la mejor aproximacion disponible y la unica que no inventa un dato: hasta hoy
-- planificar_visita descartaba auth.uid() a proposito, asi que ese rastro no existe en ningun lado.
UPDATE public.visitas_comerciales SET planificada_por = asesor_id WHERE planificada_por IS NULL;

ALTER TABLE public.visitas_comerciales ALTER COLUMN planificada_por SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.visitas_comerciales'::regclass
                    AND conname  = 'visitas_comerciales_planificada_por_fkey') THEN
    ALTER TABLE public.visitas_comerciales
      ADD CONSTRAINT visitas_comerciales_planificada_por_fkey
      FOREIGN KEY (planificada_por) REFERENCES public.perfiles(id) ON DELETE RESTRICT;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.visitas_comerciales'::regclass
                    AND conname  = 'visitas_com_cancelada_con_motivo') THEN
    ALTER TABLE public.visitas_comerciales
      ADD CONSTRAINT visitas_com_cancelada_con_motivo CHECK (
        (estado <> 'cancelada')
        OR (cancelacion_motivo IS NOT NULL AND length(btrim(cancelacion_motivo)) > 0));
  END IF;
END $$;

COMMENT ON COLUMN public.visitas_comerciales.planificada_por IS
'Quien LLAMO a planificar_visita. Distinto de asesor_id, que es el asesor ASIGNADO al prospecto y
sale del prospecto, no del llamante: cuando un supervisor planifica para su asesor, la visita
sigue siendo del asesor y esta columna es la unica que conserva que la agendo el supervisor.';

COMMENT ON CONSTRAINT visitas_com_cancelada_con_motivo ON public.visitas_comerciales IS
'Una cancelacion sin motivo no dice nada. Lo garantiza la TABLA y no solo la RPC, asi que ningun
camino futuro puede dejar una visita cancelada sin explicacion.';

-- ============================================================================================
-- (b) planificar_visita — con hora y con autoria
-- ============================================================================================
DROP FUNCTION IF EXISTS public.planificar_visita(uuid, date);

CREATE OR REPLACE FUNCTION public.planificar_visita(
  p_prospecto_id uuid, p_fecha date DEFAULT CURRENT_DATE, p_hora time DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_asesor uuid; v_jornada uuid; v_id uuid;
BEGIN
  -- LA LINEA QUE ATA, IDENTICA A LA ANTERIOR: reusa el predicado de la 272 — el supervisor entra
  -- por su CARTERA via el chokepoint, y no se escribe aca una segunda regla de "de quien es".
  IF NOT COALESCE(private.puede_gestionar_prospecto(p_prospecto_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  IF p_fecha < CURRENT_DATE THEN
    RAISE EXCEPTION 'fecha_pasada' USING ERRCODE = 'PA026';
  END IF;

  -- El asesor de la visita es el ASIGNADO al prospecto, NO auth.uid(): si saliera del llamante,
  -- un supervisor que planifica se apropiaria de la visita de su asesor. Quien la agendo queda
  -- registrado aparte, en planificada_por.
  SELECT pr.pais_id, pr.asesor_id INTO v_pais, v_asesor
    FROM public.prospectos pr WHERE pr.id = p_prospecto_id;

  SELECT j.id INTO v_jornada FROM public.jornadas_comerciales j
   WHERE j.asesor_id = v_asesor AND j.fecha = p_fecha;

  -- Sin ON CONFLICT: el 23505 de visitas_com_una_por_dia sube tal cual. "Ya hay una visita a ese
  -- prospecto ese dia" es informacion que el usuario tiene que ver, no algo que la RPC deba tapar.
  INSERT INTO public.visitas_comerciales
    (prospecto_id, asesor_id, pais_id, jornada_id, fecha_planificada, hora_planificada, planificada_por)
  VALUES (p_prospecto_id, v_asesor, v_pais, v_jornada, p_fecha, p_hora, auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END
$function$;

-- ============================================================================================
-- (c) reprogramar_visita_comercial
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.reprogramar_visita_comercial(
  p_visita_id uuid, p_fecha date, p_hora time DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_prospecto uuid; v_asesor uuid; v_estado text; v_jornada uuid;
BEGIN
  -- LA LINEA QUE ATA: el prospecto sale de la FILA y el gate es el mismo predicado de siempre.
  -- Fila inexistente -> v_prospecto NULL -> puede_gestionar_prospecto(NULL) da false dentro del
  -- COALESCE: "no existe" y "no podes" devuelven lo mismo, como en toda la 272/273/279.
  SELECT v.prospecto_id, v.asesor_id, v.estado INTO v_prospecto, v_asesor, v_estado
    FROM public.visitas_comerciales v WHERE v.id = p_visita_id;

  IF NOT COALESCE(private.puede_gestionar_prospecto(v_prospecto), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- Una visita con check-in ya ocurrio: moverle la fecha seria reescribir un hecho.
  IF v_estado IS DISTINCT FROM 'planificada' THEN
    RAISE EXCEPTION 'visita_no_planificada' USING ERRCODE = 'PA027';
  END IF;

  IF p_fecha < CURRENT_DATE THEN
    RAISE EXCEPTION 'fecha_pasada' USING ERRCODE = 'PA026';
  END IF;

  -- La jornada se RECALCULA para la fecha nueva: la vieja era de otro dia. Si el asesor todavia
  -- no abrio jornada ese dia queda NULL, y la adopta abrir_jornada cuando la abra.
  SELECT j.id INTO v_jornada FROM public.jornadas_comerciales j
   WHERE j.asesor_id = v_asesor AND j.fecha = p_fecha;

  UPDATE public.visitas_comerciales
     SET fecha_planificada = p_fecha,
         hora_planificada  = p_hora,
         jornada_id        = v_jornada,
         updated_at        = now()
   WHERE id = p_visita_id;
END
$function$;

-- ============================================================================================
-- (d) cancelar_visita_comercial
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.cancelar_visita_comercial(
  p_visita_id uuid, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_prospecto uuid; v_estado text;
BEGIN
  SELECT v.prospecto_id, v.estado INTO v_prospecto, v_estado
    FROM public.visitas_comerciales v WHERE v.id = p_visita_id;

  IF NOT COALESCE(private.puede_gestionar_prospecto(v_prospecto), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- Cubre tambien "ya esta cancelada": cancelada <> planificada.
  IF v_estado IS DISTINCT FROM 'planificada' THEN
    RAISE EXCEPTION 'visita_no_planificada' USING ERRCODE = 'PA027';
  END IF;

  -- Mismo errcode a proposito: es la misma regla —"no se puede en este estado o de esta forma"—
  -- y no una nueva. El CHECK de la tabla lo garantiza ademas por debajo.
  IF p_motivo IS NULL OR length(btrim(p_motivo)) = 0 THEN
    RAISE EXCEPTION 'motivo_requerido' USING ERRCODE = 'PA027';
  END IF;

  UPDATE public.visitas_comerciales
     SET estado             = 'cancelada',
         cancelacion_motivo = p_motivo,
         updated_at         = now()
   WHERE id = p_visita_id;
END
$function$;

-- ============================================================================================
-- (e) ADOPCION — abrir_jornada recoge las visitas huerfanas de ese dia
-- ============================================================================================
-- MISMA FIRMA y mismo cuerpo que la 273, con el UPDATE de adopcion agregado despues del INSERT.
-- Una visita planificada para un dia en que todavia no habia jornada nace con jornada_id NULL;
-- al abrir la jornada, deja de ser huerfana.
CREATE OR REPLACE FUNCTION public.abrir_jornada(
  p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric,
  p_precision_m numeric DEFAULT NULL::numeric)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_activo boolean; v_id uuid; v_asesor_j uuid; v_fecha_j date;
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
  RETURNING id, asesor_id, fecha INTO v_id, v_asesor_j, v_fecha_j;

  -- ADOPCION. La condicion usa los valores de la FILA RECIEN INSERTADA, no auth.uid() ni
  -- CURRENT_DATE: la jornada adopta las visitas de SU asesor en SU fecha, tal como quedaron
  -- escritas. Solo las huerfanas y solo las planificadas — una visita cancelada no vuelve a la
  -- jornada por abrirla.
  UPDATE public.visitas_comerciales
     SET jornada_id = v_id
   WHERE asesor_id = v_asesor_j
     AND fecha_planificada = v_fecha_j
     AND jornada_id IS NULL
     AND estado = 'planificada';

  RETURN v_id;
END
$function$;

-- ============================================================================================
-- (f) PRIVILEGIOS — REVOKE primero y solo, GRANT despues.
-- ============================================================================================
REVOKE ALL ON FUNCTION public.planificar_visita(uuid,date,time)            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reprogramar_visita_comercial(uuid,date,time) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancelar_visita_comercial(uuid,text)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.abrir_jornada(numeric,numeric,numeric)       FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.planificar_visita(uuid,date,time)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.reprogramar_visita_comercial(uuid,date,time) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancelar_visita_comercial(uuid,text)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.abrir_jornada(numeric,numeric,numeric)       TO authenticated;
