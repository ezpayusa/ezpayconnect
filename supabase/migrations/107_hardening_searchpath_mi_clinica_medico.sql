-- ============================================================
-- Trivial · Endurecer search_path de mi_clinica_medico a '' (consistencia anti-hijack)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probe estructural P268 (red-first) + equivalencia conductual.
--
-- mi_clinica_medico está pineada a 'public' y usa `obtener_clinica_principal_medico` y
-- `clinicas` SIN calificar. NO es directamente explotable (el pin 'public' bloquea el
-- prepend-hijack) → severidad menor que 105; esto es CONSISTENCIA con el patrón lección
-- 097 (toda función SECURITY DEFINER → search_path='' + TODO calificado al schema).
--
-- obtener_clinica_principal_medico ya es auto-contenida (105) → segura de llamar bajo ''.
-- Comportamiento idéntico (mismos datos). Callers: 0 en DB; 1 en frontend (ConsultaPage).
-- ============================================================

CREATE OR REPLACE FUNCTION public.mi_clinica_medico()
RETURNS TABLE(clinica_id uuid, clinica_nombre text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT c.id, c.nombre
  FROM public.obtener_clinica_principal_medico(auth.uid()) m
  JOIN public.clinicas c ON c.id = m.clinica_id
  LIMIT 1
$function$;
