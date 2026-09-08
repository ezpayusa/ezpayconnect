-- ############################################################################################
-- LIMPIEZA DE LOS DATOS QA DEL MODULO COMERCIAL — pendiente #7, 8-sep-2026
-- ############################################################################################
-- NO ES UNA MIGRACION. No toca esquema, ni RLS, ni RPCs, ni el harness: son DELETE de filas de
-- datos. Por eso vive en `scripts/sql/` y no en `supabase/migrations/`, y NO consume el numero 290
-- ni un ERRCODE. Ponerlo entre las migraciones haria que cada entorno nuevo intentara borrar filas
-- que nunca existieron ahi.
--
-- Como se corre:
--   supabase db query --linked -f C:/dev/ezpayconnect/scripts/sql/limpieza-qa-comercial-2026-09-08.sql
--
-- TODO EN UNA SOLA TRANSACCION. Si cualquier verificacion o cualquier DELETE falla, no queda nada
-- a medias: o se borra el rastro completo o no se borra nada. Un borrado parcial de estas tablas es
-- peor que no empezar, porque deja perfiles sin ficha, visitas sin prospecto o fichas huerfanas que
-- despues nadie sabe de donde salieron.
--
-- TODOS LOS DELETE SON POR ID EXPLICITO. Ni un `LIKE 'QA-%'`, ni un `codigo_asesor`, ni ningun
-- patron: los ids salen de dos recon de solo lectura del 8-sep y estan escritos aca uno por uno.
-- Un patron es comodo hasta el dia que alguien crea una ficha real que empieza con QA.
--
-- LO QUE ESTE SCRIPT NO HACE, A PROPOSITO:
--   * NO toca `storage.objects` — hay un trigger `protect_objects_delete` y borrar el registro sin
--     borrar el binario deja el archivo vivo en el bucket.
--   * NO toca `auth.users` — las cuentas se borran con `auth.admin.deleteUser` y la clave de
--     servicio, nunca con un DELETE de SQL.
--   Las dos cosas las hace `scripts/limpieza-qa-comercial-storage-auth.mjs`, que corre DESPUES.
-- ############################################################################################

BEGIN;

-- ============================================================================================
-- 1) VERIFICACION PREVIA. Antes de borrar una sola fila.
-- ============================================================================================
-- El recon es del 8-sep y el estado pudo cambiar entre ese momento y esta corrida: alguien pudo
-- agendar una visita mas, borrar un prospecto a mano o crear otra jornada. Este bloque NO descubre
-- que borrar —eso ya esta decidido y escrito—: comprueba que el mundo sigue siendo el que el recon
-- vio, y si no, aborta la transaccion entera sin tocar nada.
DO $$
DECLARE
  v_n int;
  v_perfiles uuid[] := ARRAY[
    '97c5d673-bd6c-416b-8970-921a78c92887',   -- QA-ASE-01
    '97896ac3-1bd4-4e24-a9e0-e6c97ce07893',   -- QA-ASE-02
    '3d843fd1-695a-4958-9b57-b840b23994b3'    -- QA-SUP-01
  ]::uuid[];
  v_prospectos uuid[] := ARRAY[
    '1fa741b2-ee94-4594-8aac-232a05c9acde','69716d69-ccd9-4683-ab37-eb9b951cf1c3',
    '87d2f26a-9c00-4170-8294-0dfb5a9a7f38','cb8bddea-46d6-4d3c-b298-75e73ee5847e',
    'e8f1e69d-c494-4729-8847-75c90d63a2ee'
  ]::uuid[];
  v_jornadas uuid[] := ARRAY[
    'b8c117a2-4a12-49fe-907a-5d3aba4c5d92','db1ad4f2-6894-4452-a01c-7b8e315a6310',
    'a4c9a69f-4364-43f4-9afd-22f2ec6a06fc','c75d5d3f-eee3-46c1-8a5b-7986154575e9'
  ]::uuid[];
  v_visitas uuid[] := ARRAY[
    '39866a82-20c2-4994-95d3-900034333ab7','49bc4df8-11a2-4eca-afc6-b3066e70a765',
    '4ddfb907-1b51-4a0d-8aad-cadf98113585','4fa6abe9-0fa6-46e3-91dc-6fc7b57d48db'
  ]::uuid[];
  v_reportes uuid[] := ARRAY[
    'c0c67efe-2fb1-41da-92de-d73611aa274f','4d2691ba-a77d-49fe-bc3f-ae3066042705'
  ]::uuid[];
  v_contactos uuid[] := ARRAY['726c7567-7e87-4656-a53d-9c7713be2ef7']::uuid[];
  v_adjuntos  uuid[] := ARRAY['acfd9fa6-c7dc-4b8c-830e-8d06b96fbd57']::uuid[];
  v_roles     uuid[] := ARRAY[
    'd394de59-8aa6-46e1-a05c-b3cba3811e27','9ff9e2e0-6464-4ea7-ac1d-4f478501697e',
    '79392984-a35c-4894-a52c-fdbe6bb2e397'
  ]::uuid[];
BEGIN
  -- 1a) Los conteos exactos. Cada uno tiene que coincidir con lo que vio el recon.
  SELECT count(*) INTO v_n FROM public.prospectos WHERE id = ANY(v_prospectos);
  IF v_n <> 5 THEN RAISE EXCEPTION 'prospectos: se esperaban 5, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.jornadas_comerciales WHERE id = ANY(v_jornadas);
  IF v_n <> 4 THEN RAISE EXCEPTION 'jornadas_comerciales: se esperaban 4, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.visitas_comerciales WHERE id = ANY(v_visitas);
  IF v_n <> 4 THEN RAISE EXCEPTION 'visitas_comerciales: se esperaban 4, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.reportes_visita WHERE id = ANY(v_reportes);
  IF v_n <> 2 THEN RAISE EXCEPTION 'reportes_visita: se esperaban 2, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.prospecto_contactos WHERE id = ANY(v_contactos);
  IF v_n <> 1 THEN RAISE EXCEPTION 'prospecto_contactos: se esperaba 1, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.visita_adjuntos WHERE id = ANY(v_adjuntos);
  IF v_n <> 1 THEN RAISE EXCEPTION 'visita_adjuntos: se esperaba 1, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.usuario_roles WHERE id = ANY(v_roles);
  IF v_n <> 3 THEN RAISE EXCEPTION 'usuario_roles: se esperaban 3, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.asesores_perfil WHERE id = ANY(v_perfiles);
  IF v_n <> 3 THEN RAISE EXCEPTION 'asesores_perfil: se esperaban 3, hay %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.perfiles WHERE id = ANY(v_perfiles);
  IF v_n <> 3 THEN RAISE EXCEPTION 'perfiles: se esperaban 3, hay %', v_n; END IF;

  -- 1b) RED DE SEGURIDAD SOBRE EL ULTIMO DELETE, que es el que puede fallar tarde.
  -- Casi todas las FK que apuntan a `perfiles` desde el modulo comercial son ON DELETE RESTRICT
  -- (medido 7-sep). Si quedara UNA sola fila colgando de estos tres perfiles que no este en las
  -- listas de arriba, el DELETE final reventaria despues de haber borrado todo lo demas — la
  -- transaccion revierte, si, pero el diagnostico seria un error de FK a ciegas.
  -- Esto NO decide que borrar: sigue siendo todo por id explicito. Comprueba que no quede nada
  -- fuera de lo previsto, y si queda, lo NOMBRA.
  SELECT count(*) INTO v_n FROM public.jornadas_comerciales
   WHERE asesor_id = ANY(v_perfiles) AND NOT (id = ANY(v_jornadas));
  IF v_n > 0 THEN RAISE EXCEPTION
    'hay % jornada(s) de estos asesores que NO estan en la lista: el recon quedo viejo', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.visitas_comerciales
   WHERE (asesor_id = ANY(v_perfiles) OR planificada_por = ANY(v_perfiles))
     AND NOT (id = ANY(v_visitas));
  IF v_n > 0 THEN RAISE EXCEPTION
    'hay % visita(s) de estos asesores que NO estan en la lista: el recon quedo viejo', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.prospectos
   WHERE (asesor_id = ANY(v_perfiles) OR creado_por = ANY(v_perfiles))
     AND NOT (id = ANY(v_prospectos));
  IF v_n > 0 THEN RAISE EXCEPTION
    'hay % prospecto(s) de estos asesores que NO estan en la lista: el recon quedo viejo', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.reportes_visita
   WHERE creado_por = ANY(v_perfiles) AND NOT (id = ANY(v_reportes));
  IF v_n > 0 THEN RAISE EXCEPTION 'hay % informe(s) fuera de la lista', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.visita_adjuntos
   WHERE subido_por = ANY(v_perfiles) AND NOT (id = ANY(v_adjuntos));
  IF v_n > 0 THEN RAISE EXCEPTION 'hay % adjunto(s) fuera de la lista', v_n; END IF;

  -- Los contactos se comparan por el PROSPECTO del que cuelgan, no por quien los creo: es el unico
  -- conjunto cuyo dueno no es una de las tres cuentas. Un contacto de estos prospectos que no este
  -- en la lista bloquearia el DELETE de `prospectos`.
  SELECT count(*) INTO v_n FROM public.prospecto_contactos
   WHERE prospecto_id = ANY(v_prospectos) AND NOT (id = ANY(v_contactos));
  IF v_n > 0 THEN RAISE EXCEPTION
    'hay % contacto(s) de estos prospectos que NO estan en la lista: el recon quedo viejo', v_n; END IF;

  -- material_comercial NO esta en el plan de borrado. Si alguno lo subio una de estas cuentas,
  -- `material_comercial.subido_por` (RESTRICT) bloquearia el DELETE de perfiles. Se avisa ANTES.
  SELECT count(*) INTO v_n FROM public.material_comercial WHERE subido_por = ANY(v_perfiles);
  IF v_n > 0 THEN RAISE EXCEPTION
    'hay % material(es) subido(s) por estas cuentas; material_comercial.subido_por es RESTRICT y '
    'bloquearia el borrado. Decidir que hacer con ese material antes de limpiar.', v_n; END IF;

  -- Ninguna otra ficha puede tener a QA-SUP-01 como supervisor: asesores_perfil.supervisor_id
  -- tambien es RESTRICT.
  SELECT count(*) INTO v_n FROM public.asesores_perfil
   WHERE supervisor_id = ANY(v_perfiles) AND NOT (id = ANY(v_perfiles));
  IF v_n > 0 THEN RAISE EXCEPTION
    'hay % ficha(s) ajena(s) con estos asesores como supervisor: no se puede borrar el supervisor', v_n; END IF;

  RAISE NOTICE 'verificacion previa OK: el estado coincide con el recon del 8-sep';
END $$;

-- ============================================================================================
-- 2) LOS DELETE. De la hoja a la raiz, todos por id explicito.
-- ============================================================================================

-- 2.1 informes de visita (cuelgan de la visita)
DELETE FROM public.reportes_visita WHERE id IN (
  'c0c67efe-2fb1-41da-92de-d73611aa274f',
  '4d2691ba-a77d-49fe-bc3f-ae3066042705'
);

-- 2.2 adjuntos (cuelgan de la visita). El BINARIO del bucket lo borra el script de Node.
DELETE FROM public.visita_adjuntos WHERE id IN (
  'acfd9fa6-c7dc-4b8c-830e-8d06b96fbd57'
);

-- 2.3 visitas
DELETE FROM public.visitas_comerciales WHERE id IN (
  '39866a82-20c2-4994-95d3-900034333ab7',
  '49bc4df8-11a2-4eca-afc6-b3066e70a765',
  '4ddfb907-1b51-4a0d-8aad-cadf98113585',
  '4fa6abe9-0fa6-46e3-91dc-6fc7b57d48db'
);

-- 2.4 jornadas. VAN DESPUES DE LAS VISITAS y ANTES DE LOS PERFILES:
-- `jornadas_comerciales.asesor_id -> perfiles` es ON DELETE RESTRICT, asi que sin este DELETE el
-- ultimo paso fallaria. (Las 4 jornadas estaban en los conteos a verificar pero faltaban en el
-- orden de borrado del plan.)
DELETE FROM public.jornadas_comerciales WHERE id IN (
  'b8c117a2-4a12-49fe-907a-5d3aba4c5d92',
  'db1ad4f2-6894-4452-a01c-7b8e315a6310',
  'a4c9a69f-4364-43f4-9afd-22f2ec6a06fc',
  'c75d5d3f-eee3-46c1-8a5b-7986154575e9'
);

-- 2.5 contactos del prospecto
DELETE FROM public.prospecto_contactos WHERE id IN (
  '726c7567-7e87-4656-a53d-9c7713be2ef7'
);

-- 2.6 prospectos
DELETE FROM public.prospectos WHERE id IN (
  '1fa741b2-ee94-4594-8aac-232a05c9acde',
  '69716d69-ccd9-4683-ab37-eb9b951cf1c3',
  '87d2f26a-9c00-4170-8294-0dfb5a9a7f38',
  'cb8bddea-46d6-4d3c-b298-75e73ee5847e',
  'e8f1e69d-c494-4729-8847-75c90d63a2ee'
);

-- 2.7 asignaciones de rol
DELETE FROM public.usuario_roles WHERE id IN (
  'd394de59-8aa6-46e1-a05c-b3cba3811e27',
  '9ff9e2e0-6464-4ea7-ac1d-4f478501697e',
  '79392984-a35c-4894-a52c-fdbe6bb2e397'
);

-- 2.8 fichas: PRIMERO los dos asesores, DESPUES el supervisor.
-- Las dos fichas de asesor apuntan a QA-SUP-01 en `supervisor_id`, que es RESTRICT: al reves, el
-- borrado del supervisor fallaria.
DELETE FROM public.asesores_perfil WHERE id IN (
  '97c5d673-bd6c-416b-8970-921a78c92887',   -- QA-ASE-01
  '97896ac3-1bd4-4e24-a9e0-e6c97ce07893'    -- QA-ASE-02
);
DELETE FROM public.asesores_perfil WHERE id IN (
  '3d843fd1-695a-4958-9b57-b840b23994b3'    -- QA-SUP-01
);

-- 2.9 perfiles. `auth.users` NO se toca aca (ver cabecera).
DELETE FROM public.perfiles WHERE id IN (
  '97c5d673-bd6c-416b-8970-921a78c92887',
  '97896ac3-1bd4-4e24-a9e0-e6c97ce07893',
  '3d843fd1-695a-4958-9b57-b840b23994b3'
);

-- ============================================================================================
-- 3) GATE DE SALIDA, dentro de la MISMA transaccion y antes del COMMIT.
-- ============================================================================================
-- ESTO NO ES INFORMATIVO: ABORTA. Un `SELECT` de confirmacion no frena nada en un archivo que se
-- corre de una sola pasada — el `COMMIT` viene en la misma tanda, asi que cuando alguien leyera el
-- resultado ya estaria confirmado. Con `RAISE EXCEPTION` la transaccion se revierte entera y no
-- queda nada a medias.
--
-- SE VERIFICAN LOS NUEVE CONJUNTOS, no ocho: si uno solo quedara fuera del gate, seria justo el que
-- nadie mira. Y se revisan TODOS antes de abortar, acumulando los que fallan, para que el mensaje
-- diga de una vez todo lo que quedo vivo en lugar de obligar a descubrirlo de a una corrida.
DO $$
DECLARE
  v_n int;
  v_malas text := '';
  v_perfiles uuid[] := ARRAY[
    '97c5d673-bd6c-416b-8970-921a78c92887',
    '97896ac3-1bd4-4e24-a9e0-e6c97ce07893',
    '3d843fd1-695a-4958-9b57-b840b23994b3'
  ]::uuid[];
BEGIN
  SELECT count(*) INTO v_n FROM public.reportes_visita
   WHERE id IN ('c0c67efe-2fb1-41da-92de-d73611aa274f','4d2691ba-a77d-49fe-bc3f-ae3066042705');
  IF v_n <> 0 THEN v_malas := v_malas || format('reportes_visita=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.visita_adjuntos
   WHERE id IN ('acfd9fa6-c7dc-4b8c-830e-8d06b96fbd57');
  IF v_n <> 0 THEN v_malas := v_malas || format('visita_adjuntos=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.visitas_comerciales
   WHERE id IN ('39866a82-20c2-4994-95d3-900034333ab7','49bc4df8-11a2-4eca-afc6-b3066e70a765',
                '4ddfb907-1b51-4a0d-8aad-cadf98113585','4fa6abe9-0fa6-46e3-91dc-6fc7b57d48db');
  IF v_n <> 0 THEN v_malas := v_malas || format('visitas_comerciales=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.jornadas_comerciales
   WHERE id IN ('b8c117a2-4a12-49fe-907a-5d3aba4c5d92','db1ad4f2-6894-4452-a01c-7b8e315a6310',
                'a4c9a69f-4364-43f4-9afd-22f2ec6a06fc','c75d5d3f-eee3-46c1-8a5b-7986154575e9');
  IF v_n <> 0 THEN v_malas := v_malas || format('jornadas_comerciales=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.prospecto_contactos
   WHERE id IN ('726c7567-7e87-4656-a53d-9c7713be2ef7');
  IF v_n <> 0 THEN v_malas := v_malas || format('prospecto_contactos=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.prospectos
   WHERE id IN ('1fa741b2-ee94-4594-8aac-232a05c9acde','69716d69-ccd9-4683-ab37-eb9b951cf1c3',
                '87d2f26a-9c00-4170-8294-0dfb5a9a7f38','cb8bddea-46d6-4d3c-b298-75e73ee5847e',
                'e8f1e69d-c494-4729-8847-75c90d63a2ee');
  IF v_n <> 0 THEN v_malas := v_malas || format('prospectos=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.usuario_roles
   WHERE id IN ('d394de59-8aa6-46e1-a05c-b3cba3811e27','9ff9e2e0-6464-4ea7-ac1d-4f478501697e',
                '79392984-a35c-4894-a52c-fdbe6bb2e397');
  IF v_n <> 0 THEN v_malas := v_malas || format('usuario_roles=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.asesores_perfil WHERE id = ANY(v_perfiles);
  IF v_n <> 0 THEN v_malas := v_malas || format('asesores_perfil=%s, ', v_n); END IF;

  SELECT count(*) INTO v_n FROM public.perfiles WHERE id = ANY(v_perfiles);
  IF v_n <> 0 THEN v_malas := v_malas || format('perfiles=%s, ', v_n); END IF;

  IF v_malas <> '' THEN
    RAISE EXCEPTION 'quedaron filas sin borrar (%): la transaccion se revierte entera',
      rtrim(v_malas, ', ');
  END IF;

  RAISE NOTICE 'gate de salida OK: los 9 conjuntos quedaron en 0 filas';
END $$;

COMMIT;
