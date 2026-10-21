-- =====================================================================================================================
-- SIEMBRA DEMO QA-MANUAL para las capturas del deck de laboratorios.
-- Script de DATOS (no es migración, no se re-aplica). Cleanup gemelo: scripts/cleanup/demo_deck_labs_cleanup.sql
--
-- Se aplica EL DÍA DE LAS CAPTURAS: todas las fechas son relativas a CURRENT_DATE (UTC en la base; en GT, después de
-- las 18:00 hora local CURRENT_DATE ya es el día siguiente).
--
-- Qué deja:
--   B) campaña 3183 (QA-MANUAL, QA Laboratorio) activa y con fecha_fin 2026-11-30, en campanas_publicitarias y en su
--      solicitud 035509f4 (solo activa y fecha_fin; nada más cambia).
--   C) 36 filas de campana_metricas para 3183 (30 impresiones + 6 clics) de medico.qa, clinica.qa y paciente.qa en los
--      últimos 6 días. Marcador: sesion_id LIKE 'QA-MANUAL-deck-%'.
--   D) 4 visitas de visitador.qa con medico.qa (empresa 411d6f8c): 2 canceladas (hoy-2, hoy-1) y 2 confirmadas hoy a
--      las 09:00 y 10:00 (ruta del día, sin check-in). Marcador: notas_empresa LIKE 'QA-MANUAL deck%'.
--   E) 2 notificaciones in-app 'visita_clinica_cancelada' SOLO para secretaria.qa, con el mensaje que arma
--      cancelar_visita. Marcador: metadata->>'visita_id'. Sin push ni email.
--
-- Efectos externos (medidos el 21-oct-2026, solo lectura): ningún trigger de campanas_publicitarias, campana_metricas
-- ni notificaciones; los de solicitudes_campana (trg_reset_notif_envio: solo UPDATE OF estado; gate de capacidad:
-- solo si mi_empresa_proveedor() = empresa, y en el tramo B no hay claims) y los de visitas_agendadas (gate de país,
-- estado propuesta, límite de cancelación, head-start) son BEFORE y no llaman a pg_net, push ni email. cron.job vacío;
-- procesar-recordatorios solo lee la tabla recordatorios, que este script no toca.
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- A) Pre-asserts (idempotencia: aborta si ya se corrió)
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE c record; s record; n int;
BEGIN
  SELECT * INTO c FROM public.campanas_publicitarias WHERE id = 3183;
  IF NOT FOUND THEN RAISE EXCEPTION 'pre: la campaña 3183 no existe'; END IF;
  IF c.empresa_id IS DISTINCT FROM '411d6f8c-a405-49d6-9ed6-fbeb0db05133'::uuid THEN
    RAISE EXCEPTION 'pre: 3183 empresa_id = % (esperado 411d6f8c)', c.empresa_id; END IF;
  IF c.titulo NOT LIKE 'QA-MANUAL%' THEN RAISE EXCEPTION 'pre: 3183 titulo = % (esperado QA-MANUAL…)', c.titulo; END IF;
  IF c.activa IS DISTINCT FROM false THEN RAISE EXCEPTION 'pre: 3183 activa = % (esperado false)', c.activa; END IF;
  IF c.fecha_fin IS DISTINCT FROM DATE '2026-10-19' THEN
    RAISE EXCEPTION 'pre: 3183 fecha_fin = % (esperado 2026-10-19)', c.fecha_fin; END IF;
  IF c.solicitud_campana_id IS DISTINCT FROM '035509f4-0842-4d63-b821-97645ee3108d'::uuid THEN
    RAISE EXCEPTION 'pre: 3183 solicitud_campana_id = % (esperado 035509f4)', c.solicitud_campana_id; END IF;

  SELECT * INTO s FROM public.solicitudes_campana WHERE id = '035509f4-0842-4d63-b821-97645ee3108d';
  IF NOT FOUND THEN RAISE EXCEPTION 'pre: la solicitud 035509f4 no existe'; END IF;
  IF s.fecha_fin IS DISTINCT FROM DATE '2026-10-19' THEN
    RAISE EXCEPTION 'pre: solicitud 035509f4 fecha_fin = % (esperado 2026-10-19)', s.fecha_fin; END IF;

  SELECT count(*) INTO n FROM public.campana_metricas WHERE sesion_id LIKE 'QA-MANUAL-deck-%';
  IF n <> 0 THEN RAISE EXCEPTION 'pre: ya hay % filas QA-MANUAL-deck en campana_metricas (¿ya se corrió?)', n; END IF;
  SELECT count(*) INTO n FROM public.visitas_agendadas WHERE notas_empresa LIKE 'QA-MANUAL deck%';
  IF n <> 0 THEN RAISE EXCEPTION 'pre: ya hay % visitas QA-MANUAL deck (¿ya se corrió?)', n; END IF;

  -- Actores
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '63591ecb-26d7-49ef-96c8-265c6bdaa916'
                   AND email = 'secretaria.qa@ezpayconnect.com') THEN
    RAISE EXCEPTION 'pre: secretaria.qa (63591ecb) no existe'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = '9ca0b977-3c91-48dc-aa04-2f1fab766963'
                   AND empresa_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133' AND rol_en_empresa = 'admin' AND activo) THEN
    RAISE EXCEPTION 'pre: proveedor.qa (9ca0b977) no es admin activo de 411d6f8c'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = 'e00f68c8-bd30-4d62-b73b-9490e4e17efe'
                   AND empresa_id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133' AND activo) THEN
    RAISE EXCEPTION 'pre: visitador.qa (e00f68c8) no es cuenta activa de 411d6f8c'; END IF;

  -- Bolsa 6570afce vigente para los 3 días, con lugar para las 4 visitas (V1/V2 cuentan hasta que se cancelan)
  SELECT private.pvc_usadas(empresa_id, pais_id, fecha_inicio, fecha_fin, NULL) + 4 - cantidad_visitas_incluidas INTO n
    FROM public.planes_visitador_contratados
   WHERE id = '6570afce-679a-448b-94c0-9c8a3e24ef35' AND estado = 'activo'
     AND CURRENT_DATE - 2 >= fecha_inicio AND CURRENT_DATE <= fecha_fin;
  IF n IS NULL THEN RAISE EXCEPTION 'pre: la bolsa 6570afce no está activa o no cubre hoy-2..hoy'; END IF;
  IF n > 0 THEN RAISE EXCEPTION 'pre: la bolsa 6570afce no tiene lugar para 4 visitas'; END IF;

  -- Slots sin choque (médico o visitador) con visitas vivas
  SELECT count(*) INTO n
    FROM public.visitas_agendadas v
    JOIN (VALUES (CURRENT_DATE - 2, TIME '09:00', TIME '09:15'),
                 (CURRENT_DATE - 1, TIME '09:00', TIME '09:15'),
                 (CURRENT_DATE,     TIME '09:00', TIME '09:15'),
                 (CURRENT_DATE,     TIME '10:00', TIME '10:15')) AS slot_q(fecha_q, hi_q, hf_q)
      ON v.fecha_visita = slot_q.fecha_q AND v.hora_inicio < slot_q.hf_q AND v.hora_fin > slot_q.hi_q
   WHERE v.estado NOT IN ('cancelada', 'rechazada')
     AND (v.medico_id = '09d243d5-b222-482a-9762-94a582e9e752'
          OR v.cuenta_proveedor_id = 'e00f68c8-bd30-4d62-b73b-9490e4e17efe');
  IF n <> 0 THEN RAISE EXCEPTION 'pre: % visita(s) viva(s) chocan con los slots de la siembra', n; END IF;
END $$;

-- Usadas de la bolsa antes de sembrar (para el post-assert)
CREATE TEMP TABLE deck_pre ON COMMIT DROP AS
SELECT private.pvc_usadas(empresa_id, pais_id, fecha_inicio, fecha_fin, NULL) AS usadas
  FROM public.planes_visitador_contratados WHERE id = '6570afce-679a-448b-94c0-9c8a3e24ef35';

-- ---------------------------------------------------------------------------------------------------------------------
-- B) Campaña 3183 activa hasta el 30-nov (sin claims: el gate de capacidad de solicitudes_campana no aplica)
-- ---------------------------------------------------------------------------------------------------------------------
UPDATE public.campanas_publicitarias
   SET activa = true, fecha_fin = DATE '2026-11-30'
 WHERE id = 3183;

UPDATE public.solicitudes_campana
   SET fecha_fin = DATE '2026-11-30'
 WHERE id = '035509f4-0842-4d63-b821-97645ee3108d';

-- ---------------------------------------------------------------------------------------------------------------------
-- C) Métricas: 30 impresiones (n 1-30) + 6 clics (n 31-36), 12 filas por actor (10 + 2), últimos 6 días
-- ---------------------------------------------------------------------------------------------------------------------
INSERT INTO public.campana_metricas
       (campana_id, perfil_id, paciente_id, tipo_perfil, sesion_id, visto_at, clickeado, contexto, pais_id)
SELECT 3183,
       CASE n % 3 WHEN 0 THEN '09d243d5-b222-482a-9762-94a582e9e752'::uuid      -- medico.qa
                  WHEN 1 THEN '7e9ee700-48ac-43e1-812b-777518b971ec'::uuid      -- clinica.qa
                  ELSE        '5bfb5b4c-dc91-4714-93cb-a292faa6717d'::uuid END, -- paciente.qa (auth id, como la RPC)
       CASE WHEN n % 3 = 2 THEN 23 END,
       CASE n % 3 WHEN 0 THEN 'medico' WHEN 1 THEN 'clinica' ELSE 'paciente' END,
       'QA-MANUAL-deck-' || n,
       now() - make_interval(days => n % 6, hours => 1 + (n * 5) % 20),
       n > 30,
       CASE WHEN n % 3 = 2 THEN 'webapp_dashboard' ELSE 'dashboard' END,
       (SELECT pais_id FROM public.campanas_publicitarias WHERE id = 3183)
  FROM generate_series(1, 36) AS n;

-- ---------------------------------------------------------------------------------------------------------------------
-- D) Visitas, impersonando al admin de QA Laboratorio (proveedor.qa): el gate de país encuentra la bolsa por
--    mi_empresa_proveedor() y set_default_estado_propuesta deja el estado 'confirmada' (como el alta del admin en el
--    front: estado confirmada, propuesta_por NULL).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE deck_vis (id uuid PRIMARY KEY, nota text NOT NULL) ON COMMIT DROP;

SELECT set_config('request.jwt.claims', '{"sub":"9ca0b977-3c91-48dc-aa04-2f1fab766963","role":"authenticated"}', true);

WITH ins AS (
  INSERT INTO public.visitas_agendadas
         (empresa_id, medico_id, cuenta_proveedor_id, fecha_visita, hora_inicio, hora_fin, tipo_visita,
          productos_a_presentar, estado, notas_empresa, propuesta_por, pais_id)
  SELECT '411d6f8c-a405-49d6-9ed6-fbeb0db05133', '09d243d5-b222-482a-9762-94a582e9e752',
         'e00f68c8-bd30-4d62-b73b-9490e4e17efe', v.f, v.hi, v.hi + interval '15 minutes', 'presentacion_producto',
         '{}'::uuid[], 'confirmada', v.nota, NULL,
         (SELECT pais_id FROM public.empresas_proveedoras WHERE id = '411d6f8c-a405-49d6-9ed6-fbeb0db05133')
    FROM (VALUES (CURRENT_DATE - 2, TIME '09:00', 'QA-MANUAL deck cancelada 1/2'),
                 (CURRENT_DATE - 1, TIME '09:00', 'QA-MANUAL deck cancelada 2/2'),
                 (CURRENT_DATE,     TIME '09:00', 'QA-MANUAL deck ruta 1/2'),
                 (CURRENT_DATE,     TIME '10:00', 'QA-MANUAL deck ruta 2/2')) AS v(f, hi, nota)
  RETURNING id, notas_empresa
)
INSERT INTO deck_vis (id, nota) SELECT id, notas_empresa FROM ins;

SELECT set_config('request.jwt.claims', '', true);

-- Ya sin impersonar: V1 y V2 canceladas, con el claim de aviso puesto (como cancelar_visita)
UPDATE public.visitas_agendadas
   SET estado = 'cancelada', email_cancelacion_enviado = now()
 WHERE id IN (SELECT id FROM deck_vis WHERE nota LIKE 'QA-MANUAL deck cancelada%');

-- ---------------------------------------------------------------------------------------------------------------------
-- E) Aviso in-app de cancelación SOLO a secretaria.qa, con el mensaje exacto de cancelar_visita. Sin push ni email.
-- ---------------------------------------------------------------------------------------------------------------------
INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata)
SELECT '63591ecb-26d7-49ef-96c8-265c6bdaa916',
       'visita_clinica_cancelada',
       'Visita de laboratorio cancelada',
       'Se canceló la visita de '
         || COALESCE((SELECT nombre_empresa FROM public.empresas_proveedoras WHERE id = va.empresa_id), 'un laboratorio')
         || ' con ' || COALESCE((SELECT nombre_completo FROM public.perfiles WHERE id = va.medico_id), 'el médico')
         || ' del ' || to_char(va.fecha_visita, 'DD/MM/YYYY')
         || ' a las ' || substr(va.hora_inicio::text, 1, 5) || '.',
       '/clinica/calendario',
       jsonb_build_object('visita_id', va.id::text)
  FROM public.visitas_agendadas va
  JOIN deck_vis d ON d.id = va.id
 WHERE d.nota LIKE 'QA-MANUAL deck cancelada%';

-- ---------------------------------------------------------------------------------------------------------------------
-- F) Post-asserts
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE n int; n2 int; v_pre int; v_post int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.campanas_publicitarias WHERE id = 3183 AND activa AND fecha_fin = DATE '2026-11-30') THEN
    RAISE EXCEPTION 'post: 3183 no quedó activa con fecha_fin 2026-11-30'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.solicitudes_campana WHERE id = '035509f4-0842-4d63-b821-97645ee3108d'
                   AND fecha_fin = DATE '2026-11-30') THEN
    RAISE EXCEPTION 'post: la solicitud 035509f4 no quedó con fecha_fin 2026-11-30'; END IF;

  SELECT count(*) FILTER (WHERE NOT clickeado), count(*) FILTER (WHERE clickeado) INTO n, n2
    FROM public.campana_metricas WHERE sesion_id LIKE 'QA-MANUAL-deck-%' AND campana_id = 3183;
  IF n <> 30 OR n2 <> 6 THEN RAISE EXCEPTION 'post: métricas deck = % impresiones / % clics (esperado 30/6)', n, n2; END IF;
  SELECT count(*) INTO n FROM public.campana_metricas WHERE sesion_id LIKE 'QA-MANUAL-deck-%';
  IF n <> 36 THEN RAISE EXCEPTION 'post: % filas QA-MANUAL-deck (esperado 36)', n; END IF;

  SELECT count(*) INTO n FROM public.visitas_agendadas WHERE notas_empresa LIKE 'QA-MANUAL deck%';
  IF n <> 4 THEN RAISE EXCEPTION 'post: % visitas QA-MANUAL deck (esperado 4)', n; END IF;
  SELECT count(*) INTO n FROM public.visitas_agendadas
   WHERE notas_empresa LIKE 'QA-MANUAL deck cancelada%' AND estado = 'cancelada' AND email_cancelacion_enviado IS NOT NULL
     AND fecha_visita IN (CURRENT_DATE - 2, CURRENT_DATE - 1);
  IF n <> 2 THEN RAISE EXCEPTION 'post: % canceladas con aviso (esperado 2)', n; END IF;
  SELECT count(*) INTO n FROM public.visitas_agendadas
   WHERE notas_empresa LIKE 'QA-MANUAL deck ruta%' AND estado = 'confirmada' AND fecha_visita = CURRENT_DATE
     AND checkin_fecha IS NULL
     AND pais_id = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909';
  IF n <> 2 THEN RAISE EXCEPTION 'post: % confirmadas de hoy (esperado 2)', n; END IF;

  SELECT count(*) INTO n FROM public.notificaciones nt
   WHERE nt.tipo = 'visita_clinica_cancelada'
     AND nt.metadata->>'visita_id' IN (SELECT id::text FROM deck_vis WHERE nota LIKE 'QA-MANUAL deck cancelada%')
     AND nt.usuario_id = '63591ecb-26d7-49ef-96c8-265c6bdaa916';
  SELECT count(*) INTO n2 FROM public.notificaciones nt
   WHERE nt.metadata->>'visita_id' IN (SELECT id::text FROM deck_vis);
  IF n <> 2 OR n2 <> 2 THEN
    RAISE EXCEPTION 'post: notificaciones de secretaria.qa = %, total con visita deck = % (esperado 2/2)', n, n2; END IF;

  SELECT usadas INTO v_pre FROM deck_pre;
  SELECT private.pvc_usadas(empresa_id, pais_id, fecha_inicio, fecha_fin, NULL) INTO v_post
    FROM public.planes_visitador_contratados WHERE id = '6570afce-679a-448b-94c0-9c8a3e24ef35';
  IF v_post IS DISTINCT FROM v_pre + 2 THEN
    RAISE EXCEPTION 'post: pvc_usadas de 6570afce = % (esperado % + 2)', v_post, v_pre; END IF;

  IF current_setting('request.jwt.claims', true) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'post: el claim de impersonación sigue puesto'; END IF;
END $$;

COMMIT;
