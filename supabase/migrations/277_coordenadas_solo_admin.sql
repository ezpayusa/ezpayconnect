-- ############################################################################################
-- 277 — Las COORDENADAS dejan de ser legibles por `authenticated`. Hallazgo, no ajuste de UI.
-- ############################################################################################
-- QUÉ ESTABA MAL
-- --------------
-- El diseño del frente visitas dijo: "el supervisor ve checkin_distancia_m y checkin_verificado,
-- NO lat/lng; las coordenadas crudas son sólo para admin_pais y super_admin". Nunca se implementó.
-- RLS es por FILA: la policy de SELECT de la 273 le da al supervisor la fila ENTERA, coordenadas
-- incluidas. Medido antes de escribir esto, impersonando al supervisor de QA:
--     "el SUPERVISOR ve 2 filas con checkin_lat, y el valor es 14.67982"
-- Que el front no las pinte no arregla nada: viajan en el payload y cualquiera las lee con las
-- devtools abiertas. Un control que vive en el cliente no es un control.
--
-- LA SOLUCIÓN
-- -----------
-- Privilegio por COLUMNA. `authenticated` pierde el SELECT de tabla completa y recibe SELECT
-- columna por columna, sin las de coordenada. Ojo con el orden: un GRANT de tabla entera GANA
-- sobre un REVOKE por columna, así que hay que revocar el de tabla primero.
--
-- Los admins conservan el acceso que el diseño les dio, por el camino de siempre en este repo:
-- una RPC SECURITY DEFINER con gate, no una RLS más ancha.
--
-- Y para que la UI pueda decir "sin ubicación registrada" sin ver la ubicación, se agregan
-- columnas GENERATED booleanas: el HECHO de que hubo coordenada no es la coordenada.
-- ############################################################################################

ALTER TABLE public.jornadas_comerciales
  ADD COLUMN IF NOT EXISTS inicio_con_ubicacion boolean
    GENERATED ALWAYS AS (inicio_lat IS NOT NULL AND inicio_lng IS NOT NULL) STORED,
  ADD COLUMN IF NOT EXISTS fin_con_ubicacion boolean
    GENERATED ALWAYS AS (fin_lat IS NOT NULL AND fin_lng IS NOT NULL) STORED;

ALTER TABLE public.visitas_comerciales
  ADD COLUMN IF NOT EXISTS checkin_con_ubicacion boolean
    GENERATED ALWAYS AS (checkin_lat IS NOT NULL AND checkin_lng IS NOT NULL) STORED,
  ADD COLUMN IF NOT EXISTS checkout_con_ubicacion boolean
    GENERATED ALWAYS AS (checkout_lat IS NOT NULL AND checkout_lng IS NOT NULL) STORED;

-- El REVOKE de tabla va PRIMERO: mientras exista, cualquier REVOKE por columna es decorativo.
REVOKE SELECT ON public.jornadas_comerciales FROM authenticated;
REVOKE SELECT ON public.visitas_comerciales  FROM authenticated;

GRANT SELECT (
  id, asesor_id, pais_id, fecha, inicio_at, inicio_precision_m, fin_at, fin_precision_m,
  notas_cierre, created_at, updated_at, inicio_con_ubicacion, fin_con_ubicacion
) ON public.jornadas_comerciales TO authenticated;

GRANT SELECT (
  id, prospecto_id, asesor_id, pais_id, jornada_id, fecha_planificada, estado,
  checkin_at, checkin_cliente_at, checkin_origen, checkin_precision_m, checkin_distancia_m,
  checkin_verificado, checkin_motivo, checkout_at, created_at, updated_at,
  checkin_con_ubicacion, checkout_con_ubicacion
) ON public.visitas_comerciales TO authenticated;

COMMENT ON COLUMN public.visitas_comerciales.checkin_con_ubicacion IS
'Si el dispositivo reportó coordenada. Existe para que la UI pueda decir "sin ubicación
registrada" sin leer la ubicación: el HECHO de que hubo coordenada no es la coordenada. Las
columnas checkin_lat/checkin_lng NO son legibles por `authenticated` (mig 277).';

-- Los admins conservan las coordenadas crudas — por RPC con gate, no ampliando RLS.
CREATE OR REPLACE FUNCTION public.coordenadas_visita(p_visita_id uuid)
RETURNS TABLE (checkin_lat numeric, checkin_lng numeric, checkout_lat numeric, checkout_lng numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v RECORD;
BEGIN
  SELECT * INTO v FROM public.visitas_comerciales WHERE id = p_visita_id;
  -- Gate ENTERO dentro del COALESCE. Fila inexistente -> v.pais_id NULL -> puede_admin_pais(NULL)
  -- da false: "no existe" y "no podés" no se distinguen, igual que en toda la 272/273.
  IF NOT COALESCE(private.puede_admin_pais(v.pais_id), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT v.checkin_lat, v.checkin_lng, v.checkout_lat, v.checkout_lng;
END
$function$;

COMMENT ON FUNCTION public.coordenadas_visita(uuid) IS
'Coordenadas crudas de una visita: SÓLO admin_pais de ese país y super_admin. El supervisor y el
asesor ven distancia, precisión y el veredicto — no el punto. Supervisar no necesita saber dónde
estuvo una persona, necesita saber si estuvo donde dijo.';

REVOKE ALL ON FUNCTION public.coordenadas_visita(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.coordenadas_visita(uuid) TO authenticated;

-- Re-verificación: que `authenticated` NO tenga SELECT sobre ninguna columna de coordenada.
DO $$
DECLARE v_malas text;
BEGIN
  SELECT string_agg(table_name||'.'||column_name, ', ') INTO v_malas
    FROM information_schema.column_privileges
   WHERE table_schema='public'
     AND table_name IN ('visitas_comerciales','jornadas_comerciales')
     AND grantee='authenticated' AND privilege_type='SELECT'
     AND column_name IN ('checkin_lat','checkin_lng','checkout_lat','checkout_lng',
                         'inicio_lat','inicio_lng','fin_lat','fin_lng');
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'authenticated TODAVIA lee coordenadas: %', v_malas;
  END IF;
  IF has_function_privilege('anon','public.coordenadas_visita(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'anon puede ejecutar coordenadas_visita';
  END IF;
END $$;
