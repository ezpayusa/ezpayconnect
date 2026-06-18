-- ============================================================
-- Ola 2 · Endurecer search_path de registrar_campana_metrica (anti-hijack). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes red-first P292 (estructural) + P293 (hijack) + P294 (equiv).
--
-- registrar_campana_metrica (2 overloads, SECURITY DEFINER) NO fijaba search_path (proconfig
-- null) y usaba `campana_metricas` (y `campanas_publicitarias` en el de 8-arg) SIN calificar →
-- VECTOR DE HIJACK: un caller que prepende un schema con una tabla `campana_metricas` falsa
-- redirige el INSERT del DEFINER. Es el ÚNICO camino de escritura de métricas (Ola2 leak-fix
-- revocó el INSERT directo) → endurecer es ahora más relevante.
--
-- Patrón lección 097: SET search_path TO '' + calificar TODO al schema. NO llama funciones
-- anidadas (lección 39 N/A). NO se tocan grants (EXECUTE a authenticated/anon/PUBLIC se mantiene
-- por CREATE OR REPLACE). Comportamiento idéntico (mismos INSERT) — el logging legítimo sigue.
--
-- NOTA (shadowing, deuda menor aparte): el overload de 7-arg está SHADOWEADO por el de 8-arg —
-- toda llamada con ≤7 args es ambigua porque p_pais_id tiene DEFAULT → el 7-arg es INALCANZABLE
-- vía PostgREST/SQL; el frontend siempre llama el de 8-arg. Se endurece igual (defensa). Limpieza
-- futura: dropear el overload 7-arg muerto. Equivalencia del camino vivo (8-arg) probada por P291.
-- ============================================================

-- Overload 7-arg
CREATE OR REPLACE FUNCTION public.registrar_campana_metrica(
  p_campana_id integer, p_perfil_id uuid DEFAULT NULL::uuid, p_paciente_id integer DEFAULT NULL::integer,
  p_tipo_perfil text DEFAULT 'desconocido'::text, p_sesion_id text DEFAULT NULL::text,
  p_clickeado boolean DEFAULT false, p_contexto text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.campana_metricas (
    campana_id, perfil_id, paciente_id, tipo_perfil, sesion_id, clickeado, contexto
  ) VALUES (
    p_campana_id, p_perfil_id, p_paciente_id, p_tipo_perfil, p_sesion_id, p_clickeado, p_contexto
  );
END;
$function$;

-- Overload 8-arg (deriva país de campanas_publicitarias si p_pais_id es NULL)
CREATE OR REPLACE FUNCTION public.registrar_campana_metrica(
  p_campana_id integer, p_perfil_id uuid DEFAULT NULL::uuid, p_paciente_id integer DEFAULT NULL::integer,
  p_tipo_perfil text DEFAULT 'desconocido'::text, p_sesion_id text DEFAULT NULL::text,
  p_clickeado boolean DEFAULT false, p_contexto text DEFAULT NULL::text, p_pais_id uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_pais_id UUID;
BEGIN
  IF p_pais_id IS NULL THEN
    SELECT pais_id INTO v_pais_id FROM public.campanas_publicitarias WHERE id = p_campana_id;
  ELSE
    v_pais_id := p_pais_id;
  END IF;

  INSERT INTO public.campana_metricas (
    campana_id, perfil_id, paciente_id, tipo_perfil, sesion_id, clickeado, contexto, pais_id
  ) VALUES (
    p_campana_id, p_perfil_id, p_paciente_id, p_tipo_perfil, p_sesion_id, p_clickeado, p_contexto, v_pais_id
  );
END;
$function$;
