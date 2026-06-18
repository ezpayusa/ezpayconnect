-- ============================================================
-- Deuda (d) · Endurecer search_path de funciones SECURITY DEFINER (anti-hijack)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probe red-first P261 (hijack) + P262 (estructural).
--
-- 097 dejó laboratorios_para_medico en search_path='public' (NO '') porque llama a
-- obtener_clinica_principal_medico, que NO tiene search_path propio (proconfig=null →
-- hereda el del caller) y usa `medico_clinicas` SIN calificar → VECTOR DE HIJACK: un
-- caller que prepende al search_path un schema con una tabla `medico_clinicas` falsa
-- secuestra el resultado de la función SECURITY DEFINER.
--
-- Orden (IMPORTA): 1) endurecer obtener_clinica_principal_medico (SET '' + calificar
-- public.medico_clinicas) → auto-contenida sin importar el search_path del caller;
-- 2) recién entonces laboratorios_para_medico pasa a '' con seguridad (la llamada
-- anidada ya no depende del path heredado).
--
-- Patrón (lección 097): toda función endurecida a '' debe (a) fijar search_path y
-- (b) calificar TODO al schema; y sus funciones llamadas deben tener su PROPIO search_path.
-- Comportamiento idéntico (mismos datos). Callers en DB: laboratorios_para_medico,
-- mi_clinica_medico (ambos se benefician; aditivo, sin regresión). `medico_clinicas`
-- existe solo en public (sin schema sombra hoy — el fix cierra el vector a futuro).
-- ============================================================

-- 1) obtener_clinica_principal_medico → auto-contenida (SET '' + calificar)
CREATE OR REPLACE FUNCTION public.obtener_clinica_principal_medico(p_medico_id uuid)
RETURNS TABLE(clinica_id uuid, es_principal boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RETURN QUERY
  SELECT mc.clinica_id, mc.es_principal
  FROM public.medico_clinicas mc
  WHERE mc.medico_id = p_medico_id AND mc.es_principal = true
  LIMIT 1;
END;
$function$;

-- 2) laboratorios_para_medico → '' (ya estaba todo calificado public.* + auth.uid())
CREATE OR REPLACE FUNCTION public.laboratorios_para_medico()
RETURNS TABLE(id uuid, nombre_empresa text, ciudad text, afiliado boolean, es_preferido boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_pais    uuid;
  v_clinica uuid;
  v_pref    uuid;
BEGIN
  SELECT p.pais_id, p.laboratorio_preferido_id INTO v_pais, v_pref
  FROM public.perfiles p WHERE p.id = auth.uid();

  SELECT m.clinica_id INTO v_clinica
  FROM public.obtener_clinica_principal_medico(auth.uid()) m LIMIT 1;

  RETURN QUERY
  SELECT e.id, e.nombre_empresa, e.ciudad,
         EXISTS (
           SELECT 1 FROM public.laboratorio_clinicas lc
           WHERE lc.laboratorio_id = e.id AND lc.clinica_id = v_clinica AND lc.estado = 'activa'
         ) AS afiliado,
         (e.id = v_pref) AS es_preferido
  FROM public.empresas_proveedoras e
  WHERE e.tipo = 'laboratorio_clinico'
    AND e.estado = 'activa'
    AND e.pais_id = v_pais          -- fail-closed: v_pais NULL → '= NULL' → 0 labs
  ORDER BY afiliado DESC, es_preferido DESC, e.nombre_empresa;
END;
$function$;
