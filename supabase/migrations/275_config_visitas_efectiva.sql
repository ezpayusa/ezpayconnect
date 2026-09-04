-- ############################################################################################
-- 275 — config_visitas_efectiva(): el umbral EFECTIVO, para que el front no lo duplique
-- ############################################################################################
-- POR QUE EXISTE
-- --------------
-- El front tiene que avisarle al asesor, ANTES del check-in, que su GPS está reportando una
-- precisión que va a dejar el registro sin verificar. Para eso necesita el umbral del país.
--
-- Leerlo de `config_visitas_pais` no alcanza: la 273 NO siembra filas a propósito — el default
-- fail-closed (150 m / 100 m) vive en private.radio_checkin_m y private.precision_max_checkin_m.
-- Sin fila, el front no leería nada y tendría que hardcodear 150/100, que es exactamente una
-- SEGUNDA FUENTE DE VERDAD de la regla: el día que un país configure otro valor, el aviso previo
-- diría una cosa y la RPC decidiría otra.
--
-- Esta función devuelve lo que los helpers devuelven, sin recalcular nada. Es lectura pura.
-- ############################################################################################
CREATE OR REPLACE FUNCTION public.config_visitas_efectiva()
RETURNS TABLE (pais_id uuid, radio_checkin_m numeric, precision_max_m numeric, hay_fila boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT p.pais_id,
         private.radio_checkin_m(p.pais_id),
         private.precision_max_checkin_m(p.pais_id),
         EXISTS (SELECT 1 FROM public.config_visitas_pais c WHERE c.pais_id = p.pais_id AND c.activo)
    FROM (SELECT private.mi_pais() AS pais_id) p;
$function$;

COMMENT ON FUNCTION public.config_visitas_efectiva() IS
'Umbrales EFECTIVOS de verificación de check-in para el país del llamante — los mismos que aplica
checkin_visita_comercial, no una copia. `hay_fila` distingue "configurado" de "default", que es
información útil para un admin y ruido para un asesor. Sin sesión, mi_pais() es NULL y los helpers
devuelven igual los defaults: la función no revela nada de nadie.';

REVOKE ALL ON FUNCTION public.config_visitas_efectiva() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.config_visitas_efectiva() TO authenticated;

DO $$
BEGIN
  IF has_function_privilege('anon','public.config_visitas_efectiva()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.config_visitas_efectiva()','EXECUTE') THEN
    RAISE EXCEPTION 'privilegios mal en config_visitas_efectiva';
  END IF;
END $$;
