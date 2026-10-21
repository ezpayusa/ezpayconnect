-- =====================================================================================================================
-- CLEANUP de la siembra demo QA-MANUAL del deck de laboratorios (scripts/seed/demo_deck_labs.sql).
-- Script de DATOS. Borra, en orden: notificaciones (metadata visita_id de las 4 visitas) → visitas_agendadas
-- (notas_empresa LIKE 'QA-MANUAL deck%') → campana_metricas (sesion_id LIKE 'QA-MANUAL-deck-%'); y devuelve la campaña
-- 3183 a activa=false + fecha_fin 2026-10-19 en campanas_publicitarias y en su solicitud 035509f4.
--
-- No toca las métricas REALES que la RPC registre mientras se navega para las capturas (sesion_id = uuid del front):
-- esas quedan con la campaña 3183.
-- Aborta si alguien usó las visitas en la app (aviso por correo o recordatorio sobre ellas): notificaciones_email tiene
-- FK NO ACTION a visitas_agendadas y bloquearía el borrado; esos casos se miran a mano.
-- =====================================================================================================================

BEGIN;

CREATE TEMP TABLE deck_vis ON COMMIT DROP AS
SELECT id FROM public.visitas_agendadas WHERE notas_empresa LIKE 'QA-MANUAL deck%';

CREATE TEMP TABLE deck_pre ON COMMIT DROP AS
SELECT private.pvc_usadas(empresa_id, pais_id, fecha_inicio, fecha_fin, NULL) AS usadas,
       (SELECT count(*)::int FROM public.visitas_agendadas va
         WHERE va.id IN (SELECT id FROM deck_vis) AND va.estado NOT IN ('cancelada', 'rechazada')
           AND va.fecha_visita BETWEEN p.fecha_inicio AND p.fecha_fin AND va.pais_id = p.pais_id) AS vivas_deck
  FROM public.planes_visitador_contratados p WHERE id = '6570afce-679a-448b-94c0-9c8a3e24ef35';

-- ---------------------------------------------------------------------------------------------------------------------
-- Pre-asserts: conteos esperados 2 / 4 / 36
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM deck_vis;
  IF n <> 4 THEN RAISE EXCEPTION 'pre: % visitas QA-MANUAL deck (esperado 4)', n; END IF;

  SELECT count(*) INTO n FROM public.notificaciones WHERE metadata->>'visita_id' IN (SELECT id::text FROM deck_vis);
  IF n <> 2 THEN RAISE EXCEPTION 'pre: % notificaciones con visita deck (esperado 2)', n; END IF;
  SELECT count(*) INTO n FROM public.notificaciones
   WHERE metadata->>'visita_id' IN (SELECT id::text FROM deck_vis)
     AND tipo = 'visita_clinica_cancelada' AND usuario_id = '63591ecb-26d7-49ef-96c8-265c6bdaa916';
  IF n <> 2 THEN RAISE EXCEPTION 'pre: % notificaciones visita_clinica_cancelada de secretaria.qa (esperado 2)', n; END IF;

  SELECT count(*) INTO n FROM public.campana_metricas WHERE sesion_id LIKE 'QA-MANUAL-deck-%';
  IF n <> 36 THEN RAISE EXCEPTION 'pre: % filas QA-MANUAL-deck en campana_metricas (esperado 36)', n; END IF;

  SELECT count(*) INTO n FROM public.notificaciones_email WHERE visita_id IN (SELECT id FROM deck_vis);
  IF n <> 0 THEN RAISE EXCEPTION 'pre: % notificaciones_email apuntan a visitas deck (revisar a mano)', n; END IF;
  SELECT count(*) INTO n FROM public.recordatorios WHERE visita_id IN (SELECT id FROM deck_vis);
  IF n <> 0 THEN RAISE EXCEPTION 'pre: % recordatorios apuntan a visitas deck (revisar a mano)', n; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.campanas_publicitarias WHERE id = 3183 AND titulo LIKE 'QA-MANUAL%'
                   AND empresa_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133'
                   AND solicitud_campana_id = '035509f4-0842-4d63-b821-97645ee3108d') THEN
    RAISE EXCEPTION 'pre: la campaña 3183 no es la QA-MANUAL de 411d6f8c con la solicitud 035509f4'; END IF;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Borrado y restauración
-- ---------------------------------------------------------------------------------------------------------------------
DELETE FROM public.notificaciones
 WHERE metadata->>'visita_id' IN (SELECT id::text FROM deck_vis);

DELETE FROM public.visitas_agendadas
 WHERE notas_empresa LIKE 'QA-MANUAL deck%';

DELETE FROM public.campana_metricas
 WHERE sesion_id LIKE 'QA-MANUAL-deck-%';

UPDATE public.campanas_publicitarias
   SET activa = false, fecha_fin = DATE '2026-10-19'
 WHERE id = 3183;

UPDATE public.solicitudes_campana
   SET fecha_fin = DATE '2026-10-19'
 WHERE id = '035509f4-0842-4d63-b821-97645ee3108d';

-- ---------------------------------------------------------------------------------------------------------------------
-- Post-asserts: 0 restos, 3183 restaurada, la bolsa devuelve las visitas deck que contaban
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE n int; v_post int; p record;
BEGIN
  SELECT count(*) INTO n FROM public.notificaciones WHERE metadata->>'visita_id' IN (SELECT id::text FROM deck_vis);
  IF n <> 0 THEN RAISE EXCEPTION 'post: quedan % notificaciones deck', n; END IF;
  SELECT count(*) INTO n FROM public.visitas_agendadas WHERE notas_empresa LIKE 'QA-MANUAL deck%';
  IF n <> 0 THEN RAISE EXCEPTION 'post: quedan % visitas deck', n; END IF;
  SELECT count(*) INTO n FROM public.campana_metricas WHERE sesion_id LIKE 'QA-MANUAL-deck-%';
  IF n <> 0 THEN RAISE EXCEPTION 'post: quedan % filas QA-MANUAL-deck', n; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.campanas_publicitarias WHERE id = 3183 AND activa = false
                   AND fecha_fin = DATE '2026-10-19') THEN
    RAISE EXCEPTION 'post: 3183 no quedó restaurada (activa=false, fecha_fin 2026-10-19)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.solicitudes_campana WHERE id = '035509f4-0842-4d63-b821-97645ee3108d'
                   AND fecha_fin = DATE '2026-10-19') THEN
    RAISE EXCEPTION 'post: la solicitud 035509f4 no quedó con fecha_fin 2026-10-19'; END IF;

  SELECT * INTO p FROM deck_pre;
  SELECT private.pvc_usadas(empresa_id, pais_id, fecha_inicio, fecha_fin, NULL) INTO v_post
    FROM public.planes_visitador_contratados WHERE id = '6570afce-679a-448b-94c0-9c8a3e24ef35';
  IF v_post IS DISTINCT FROM p.usadas - p.vivas_deck THEN
    RAISE EXCEPTION 'post: pvc_usadas de 6570afce = % (esperado % - %)', v_post, p.usadas, p.vivas_deck; END IF;
END $$;

COMMIT;
