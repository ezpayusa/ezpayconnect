-- ############################################################################################
-- 285 — pendiente #3: endurecer check-in y check-out
-- ############################################################################################
-- DOS HUECOS, MEDIDOS CONTRA EL CUERPO VIVO ANTES DE ESCRIBIR ESTO:
--
--   1. `checkin_visita_comercial` NO exigia que la visita estuviera en estado 'planificada'.
--      Aceptaba hacer check-in sobre una visita CANCELADA o NO_REALIZADA: el unico chequeo previo
--      era `checkin_at IS NOT NULL` (PA025), que no dice nada sobre el estado. Una visita cancelada
--      volvia a 'en_curso' sin que nadie la hubiera reabierto. -> PA028.
--
--   2. `checkout_visita_comercial` NO chequeaba `checkout_at IS NULL`. La segunda llamada pasaba y
--      reescribia checkout_at: cerrar una visita dos veces es reescribir un hecho ya registrado.
--      Lo documentaba P625, sostenida como roja aceptada en la lista DEUDA del runner. -> PA029.
--
-- QUE **NO** CAMBIA: ningun otro chequeo, ni su orden. Los dos guards se insertan en el lugar
-- exacto donde la fila ya esta leida y todavia no se hizo trabajo: despues del chequeo de
-- idempotencia que ya existia y ANTES del de jornada. El orden importa porque define QUE errcode
-- ve el cliente cuando dos condiciones fallan a la vez.
--
-- CREATE OR REPLACE conserva el ACL de las funciones (REVOKE de anon + GRANT a authenticated de la
-- mig 273): no hace falta re-otorgar, y re-otorgar de mas seria peor que no hacerlo.
--
-- Errcodes nuevos: PA028 y PA029. Proximo libre: PA030.
-- Lo miden: P625 (deja de ser deuda: ahora exige PA029), P637 y P638 (PA028 desde 'cancelada' y
-- desde 'no_realizada').
-- ############################################################################################

CREATE OR REPLACE FUNCTION public.checkin_visita_comercial(p_visita_id uuid, p_lat numeric, p_lng numeric, p_precision_m numeric DEFAULT NULL::numeric, p_cliente_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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

  -- PA028 (mig 285): solo se hace check-in sobre una visita PLANIFICADA. Antes, una visita
  -- cancelada o no_realizada aceptaba check-in y volvia a 'en_curso' sin que nadie la reabriera.
  -- IS DISTINCT FROM y no <>: un estado NULL tiene que caer del lado del RECHAZO, no propagarse.
  IF v.estado IS DISTINCT FROM 'planificada' THEN
    RAISE EXCEPTION 'PA028: la visita no esta en estado planificada (estado actual: %)', v.estado
      USING ERRCODE = 'PA028';
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

CREATE OR REPLACE FUNCTION public.checkout_visita_comercial(p_visita_id uuid, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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

  -- PA029 (mig 285): un checkout ya registrado no se reescribe. Antes la segunda llamada pasaba y
  -- pisaba checkout_at con un now() posterior: la visita quedaba cerrada a una hora que no fue.
  IF v.checkout_at IS NOT NULL THEN
    RAISE EXCEPTION 'PA029: esta visita ya tiene checkout' USING ERRCODE = 'PA029';
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
