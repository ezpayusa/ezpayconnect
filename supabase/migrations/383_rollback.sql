-- =====================================================================================================================
-- ROLLBACK MIG 383 — chat comercial: vuelve chat_comercial_enviar al cuerpo exacto de la 382 (sin notificación,
-- md5(prosrc) 1833b1083cbc1f33857c8e92ba595241) y devuelve a service_role TRUNCATE, REFERENCES, TRIGGER y MAINTAIN en las
-- 3 tablas (la ACL que dejó la 382). Las notificaciones 'chat_comercial' ya creadas quedan. Va ANTES que 382_rollback.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/383_rollback.sql
-- =====================================================================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.chat_comercial_enviar(p_hilo uuid, p_cuerpo text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_tipo text; v_sup uuid; v_txt text; v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.puede_ver_hilo_comercial(p_hilo), false) THEN
    IF COALESCE(EXISTS (SELECT 1 FROM public.chat_comercial_hilos h
                         WHERE h.id = p_hilo AND private.chat_comercial_relacion(h.tipo, h.comercial_id, h.pais_id, false)), false) THEN
      RAISE EXCEPTION 'La conversación está cerrada: una de las cuentas está inactiva' USING ERRCODE = 'PA039';
    END IF;
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT h.tipo, d.supervisor_id INTO v_tipo, v_sup
    FROM public.chat_comercial_hilos h
    LEFT JOIN public.asesores_perfil d ON d.id = h.comercial_id
   WHERE h.id = p_hilo;
  IF v_tipo = 'supervision' AND v_sup IS NULL AND NOT COALESCE(public.get_auth_user_rol() = 'super_admin', false) THEN
    RAISE EXCEPTION 'El asesor no tiene supervisor asignado' USING ERRCODE = 'PA038';
  END IF;

  v_txt := btrim(COALESCE(p_cuerpo, ''), E' \t\r\n');
  IF char_length(v_txt) NOT BETWEEN 1 AND 2000 THEN
    RAISE EXCEPTION 'El mensaje tiene que tener entre 1 y 2000 caracteres' USING ERRCODE = 'PA036';
  END IF;

  INSERT INTO public.chat_comercial_mensajes (hilo_id, autor_id, cuerpo)
  VALUES (p_hilo, v_uid, v_txt)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

REVOKE ALL ON FUNCTION public.chat_comercial_enviar(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_comercial_enviar(uuid, text) TO authenticated, service_role;

GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON public.chat_comercial_hilos, public.chat_comercial_mensajes, public.chat_comercial_lecturas
  TO service_role;

DO $$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.chat_comercial_enviar(uuid,text)')) IS DISTINCT FROM '1833b1083cbc1f33857c8e92ba595241' THEN
    RAISE EXCEPTION 'MIG83: rollback: chat_comercial_enviar no volvió al cuerpo de la 382' USING ERRCODE = 'MIG83';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['chat_comercial_hilos', 'chat_comercial_mensajes', 'chat_comercial_lecturas']) t
              WHERE (SELECT c.relacl::text FROM pg_class c WHERE c.oid = ('public.'||t)::regclass) NOT LIKE '%service_role=arwdDxtm/postgres%') THEN
    RAISE EXCEPTION 'MIG83: rollback: service_role no volvió a arwdDxtm' USING ERRCODE = 'MIG83';
  END IF;
END $$;

COMMIT;
