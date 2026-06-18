-- ============================================================
-- Limpieza · Dropear el overload 7-arg MUERTO de registrar_campana_metrica
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probe P319 (estructural) + P291 (no-regresión logging 8-arg).
--
-- El overload de 7 args está SHADOWEADO por el de 8 args (p_pais_id tiene DEFAULT → toda llamada
-- con ≤7 args es ambigua → el 7-arg es INALCANZABLE vía PostgREST/SQL). El frontend usa el 8-arg
-- (pasa p_pais_id). Verificado: 0 dependencias del 7-arg (pg_depend / funciones / policies / vistas).
-- DROP de la firma EXACTA del 7-arg, sin CASCADE → solo ese overload; el 8-arg queda intacto.
-- ============================================================

DROP FUNCTION IF EXISTS public.registrar_campana_metrica(integer, uuid, integer, text, text, boolean, text);
