-- =====================================================================================================================
-- ROLLBACK MIG 382 — chat comercial. Va ANTES que 381_rollback.
-- Saca chat_comercial_mensajes de supabase_realtime y borra las 3 tablas, el trigger y las 9 funciones.
-- Aborta si ya hay mensajes: borrar el chat comercial con conversaciones reales es una decisión aparte (export previo).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/382_rollback.sql
-- =====================================================================================================================
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.chat_comercial_mensajes') IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.chat_comercial_mensajes) THEN
    RAISE EXCEPTION 'MIG82: rollback abortado: chat_comercial_mensajes tiene filas' USING ERRCODE = 'MIG82';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication_tables
              WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'chat_comercial_mensajes') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime DROP TABLE public.chat_comercial_mensajes';
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.chat_comercial_contactos();
DROP FUNCTION IF EXISTS public.chat_comercial_abrir(text, uuid);
DROP FUNCTION IF EXISTS public.chat_comercial_mis_hilos();
DROP FUNCTION IF EXISTS public.chat_comercial_mensajes(uuid, timestamptz, integer);
DROP FUNCTION IF EXISTS public.chat_comercial_enviar(uuid, text);
DROP FUNCTION IF EXISTS public.chat_comercial_marcar_leido(uuid);

DROP TABLE IF EXISTS public.chat_comercial_lecturas;
DROP TABLE IF EXISTS public.chat_comercial_mensajes;
DROP TABLE IF EXISTS public.chat_comercial_hilos;      -- se lleva su trigger y sus policies

DROP FUNCTION IF EXISTS private.puede_ver_hilo_comercial(uuid);
DROP FUNCTION IF EXISTS private.chat_comercial_relacion(text, uuid, uuid, boolean);
DROP FUNCTION IF EXISTS private.trg_chat_comercial_hilos_guard();

DO $$
DECLARE n int;
BEGIN
  n := (SELECT count(*) FROM pg_class WHERE relname LIKE 'chat_comercial%')
     + (SELECT count(*) FROM pg_proc WHERE proname LIKE '%chat_comercial%' OR proname = 'puede_ver_hilo_comercial')
     + (SELECT count(*) FROM pg_publication_tables WHERE tablename LIKE 'chat_comercial%');
  IF n <> 0 THEN
    RAISE EXCEPTION 'MIG82: rollback incompleto: quedan % objetos', n USING ERRCODE = 'MIG82';
  END IF;
END $$;

COMMIT;
