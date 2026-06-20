-- ============================================================
-- Seguridad · Endurecer search_path de mi_rol_proveedor a '' (consistencia anti-hijack)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probe estructural P343 + equivalencia conductual P344.
--
-- mi_rol_proveedor (SECURITY DEFINER) pinea 'public' y usa `cuentas_proveedor` SIN calificar.
-- NO es prepend-hijackable hoy (el pin 'public' bloquea el prepend; sin schema sombra de
-- cuentas_proveedor) → severidad menor; esto es CONSISTENCIA con el patrón lección 097 (toda
-- DEFINER → search_path='' + TODO calificado). auth.uid() ya está en schema auth. NO llama
-- funciones anidadas (lección 39 N/A). Comportamiento idéntico (mismo SELECT, calificado).
--
-- LOAD-BEARING: lo usan private.sucursal_visible (C.2/114) + 11 policies (productos_empresa,
-- ubicaciones_medico_proveedor, equipos_visitadores, pagos_proveedor, visitas_agendadas,
-- cuentas_proveedor, invitaciones_visitador) → el valor de retorno NO cambia (equivalencia P344).
-- ============================================================

CREATE OR REPLACE FUNCTION public.mi_rol_proveedor()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT rol_en_empresa FROM public.cuentas_proveedor WHERE id = auth.uid() AND activo = true LIMIT 1;
$function$;
