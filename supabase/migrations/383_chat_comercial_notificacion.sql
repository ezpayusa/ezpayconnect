-- =====================================================================================================================
-- MIG 383 — Chat comercial: notificación dentro de chat_comercial_enviar + ACL exacta de service_role.
-- Recon del 24-oct-2026 contra el objeto vivo (patrón de las migs 353, 377 y 381).
--
-- 1) chat_comercial_enviar (misma firma, mismo retorno, mismo gate y mismas validaciones que la 382): después del INSERT
--    del mensaje avisa, en la misma transacción, a los participantes ACTUALES y ACTIVOS del hilo, menos el autor:
--      'supervision' -> el asesor dueño + su supervisor actual;
--      'pais'        -> el comercial dueño + los admin_pais activos de hilo.pais_id; sin ninguno, los super_admin activos
--                       (el mismo fallback que chat_comercial_contactos y que solicitar_alta_medico, mig 377).
--    "Activo" = perfiles.activo y, para un comercial, además la ficha activa y del país del hilo. Los destinatarios salen
--    de la fila del hilo y de las fichas, nunca de un parámetro.
--    Notificación (patrón 377/381): INSERT en public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url,
--    metadata, pais_id) + PERFORM private.push_notificar('notificaciones', id). push_notificar es best-effort (pg_net
--    asíncrono, no-op sin push_edge_url/push_secret, EXCEPTION WHEN others -> RETURN).
--      tipo 'chat_comercial'; titulo 'Nuevo mensaje'; mensaje '<nombre del autor> te escribió' (SIN el texto: se ve en
--      la pantalla de bloqueo); metadata {hilo_id, mensaje_id}; pais_id = el del hilo.
--      accion_url: comercial -> /comercial/mensajes/<hilo>; admin_pais o super_admin -> /admin-ezpay/pais/<pais>/mensajes/<hilo>
--      (las rutas del front todavía no existen: van en los PRs del front).
--    Anti-spam: si el destinatario ya tiene una 'chat_comercial' NO leída del mismo hilo (metadata.hilo_id), no se crea
--    otra ni se manda push.
--    Al final, claim: UPDATE chat_comercial_mensajes SET notificado = true WHERE id = <nuevo> AND notificado = false.
--    Todo el bloque de aviso va en un sub-bloque con EXCEPTION: si algo de la notificación falla, el mensaje NO se pierde
--    y queda con notificado = false (rastreable). La notificación no agrega errores visibles para el usuario.
-- 2) ACL de service_role en las 3 tablas chat_comercial_*: REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN (Postgres 17.6,
--    MAINTAIN existe). Queda exacta: postgres arwdDxtm, service_role arwd, authenticated r, anon nada.
-- Sin errcodes nuevos. MIG83 = guarda de esta migración.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/383_chat_comercial_notificacion.sql
-- Rollback: supabase/migrations/383_rollback.sql (va antes que 382_rollback).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) PRECONDICIÓN: las 9 funciones de la 382 con el cuerpo verificado y el helper de push vivo
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TEMP TABLE m383_pre ON COMMIT DROP AS
SELECT e.firma, e.md5_esperado, (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(e.firma)) AS md5_vivo
  FROM (VALUES
    ('public.chat_comercial_enviar(uuid,text)',                       '1833b1083cbc1f33857c8e92ba595241'),
    ('public.chat_comercial_contactos()',                             'be86285010efb72f9a5ed15ad53f4e61'),
    ('public.chat_comercial_abrir(text,uuid)',                        'ddd5557ffc2981586a473bf28a364529'),
    ('public.chat_comercial_mis_hilos()',                             '34b5c2aa9b67ac55cb851947c66dd6cf'),
    ('public.chat_comercial_mensajes(uuid,timestamptz,integer)',      '2cfc395fd0c8caebb5034c27368e2115'),
    ('public.chat_comercial_marcar_leido(uuid)',                      '1fa96a651fc13b1313d2a6185400cc8a'),
    ('private.puede_ver_hilo_comercial(uuid)',                        'e9bdbcda865ec37a121b600af8cf3129'),
    ('private.chat_comercial_relacion(text,uuid,uuid,boolean)',       '90b45ee36594b78b6180c8ffda303962'),
    ('private.trg_chat_comercial_hilos_guard()',                      '6fd8781d3828cd80efffc03249134851')
  ) AS e(firma, md5_esperado);

DO $$
DECLARE v_malos text := '';
BEGIN
  SELECT string_agg(firma||' (vivo '||COALESCE(md5_vivo, 'ausente')||')', '; ') INTO v_malos
    FROM m383_pre WHERE md5_vivo IS DISTINCT FROM md5_esperado;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('private.push_notificar(text,text)')) IS DISTINCT FROM '90e6e8ec7eb37240e400a7c5768a8997' THEN
    v_malos := COALESCE(v_malos||'; ', '')||'private.push_notificar(text,text)';
  END IF;
  IF v_malos IS NOT NULL AND v_malos <> '' THEN
    RAISE EXCEPTION 'MIG83: el objeto vivo no es el de la precondición: %', v_malos USING ERRCODE = 'MIG83';
  END IF;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) chat_comercial_enviar con la notificación
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.chat_comercial_enviar(p_hilo uuid, p_cuerpo text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_tipo text; v_sup uuid; v_txt text; v_id uuid;
        v_pais uuid; v_dueno uuid; v_autor text; v_nid uuid; v_admins int; rec record;
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

  -- Aviso a los participantes actuales y activos, menos el autor (mig 383). Best-effort: un fallo acá no pierde el
  -- mensaje; queda con notificado = false.
  BEGIN
    SELECT h.pais_id, h.comercial_id INTO v_pais, v_dueno FROM public.chat_comercial_hilos h WHERE h.id = p_hilo;
    v_autor := COALESCE((SELECT p.nombre_completo FROM public.perfiles p WHERE p.id = v_uid), 'Alguien');
    v_admins := (SELECT count(*) FROM public.perfiles a WHERE a.rol = 'admin_pais' AND a.activo IS TRUE AND a.pais_id = v_pais);

    FOR rec IN
      -- comerciales: el dueño y, en 'supervision', el supervisor actual (perfil activo, ficha activa y del país del hilo)
      SELECT c.id AS usuario_id, '/comercial/mensajes/' || p_hilo::text AS url
        FROM public.perfiles c
        JOIN public.asesores_perfil f ON f.id = c.id
       WHERE c.id IN (v_dueno, CASE WHEN v_tipo = 'supervision' THEN v_sup END)
         AND c.rol IN ('asesor_comercial', 'supervisor_comercial')
         AND c.activo IS TRUE AND f.activo AND f.pais_id = v_pais
      UNION
      -- 'pais': los admin_pais activos del país del hilo; sin ninguno, los super_admin activos
      SELECT a.id, '/admin-ezpay/pais/' || v_pais::text || '/mensajes/' || p_hilo::text
        FROM public.perfiles a
       WHERE v_tipo = 'pais' AND a.activo IS TRUE
         AND ((v_admins > 0 AND a.rol = 'admin_pais' AND a.pais_id = v_pais)
           OR (v_admins = 0 AND a.rol = 'super_admin'))
    LOOP
      CONTINUE WHEN rec.usuario_id = v_uid;
      -- anti-spam: ya tiene una 'chat_comercial' no leída de este hilo
      CONTINUE WHEN EXISTS (SELECT 1 FROM public.notificaciones n
                             WHERE n.usuario_id = rec.usuario_id AND n.tipo = 'chat_comercial'
                               AND n.leida IS NOT TRUE AND n.metadata ->> 'hilo_id' = p_hilo::text);
      INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url, metadata, pais_id)
      VALUES (rec.usuario_id, 'chat_comercial', 'Nuevo mensaje', v_autor || ' te escribió', rec.url,
              jsonb_build_object('hilo_id', p_hilo, 'mensaje_id', v_id), v_pais)
      RETURNING id INTO v_nid;
      PERFORM private.push_notificar('notificaciones', v_nid::text);   -- push best-effort (sale al COMMIT)
    END LOOP;

    UPDATE public.chat_comercial_mensajes SET notificado = true WHERE id = v_id AND notificado = false;
  EXCEPTION WHEN OTHERS THEN
    NULL;   -- el mensaje queda guardado con notificado = false
  END;

  RETURN v_id;
END
$function$;

REVOKE ALL ON FUNCTION public.chat_comercial_enviar(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_comercial_enviar(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) ACL exacta de service_role en las 3 tablas
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON public.chat_comercial_hilos, public.chat_comercial_mensajes, public.chat_comercial_lecturas
  FROM service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- d) AUTOCHEQUEO
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE v_malos text := ''; r record; v_acl text;
BEGIN
  -- ACL de tabla exacta (comparación de conjunto, no "al menos")
  FOR r IN SELECT t FROM unnest(ARRAY['chat_comercial_hilos', 'chat_comercial_mensajes', 'chat_comercial_lecturas']) t LOOP
    SELECT string_agg(CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type, ','
                      ORDER BY CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END, a.privilege_type)
      INTO v_acl
      FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
     WHERE c.oid = ('public.'||r.t)::regclass;
    IF v_acl IS DISTINCT FROM
       'authenticated:SELECT,postgres:DELETE,postgres:INSERT,postgres:MAINTAIN,postgres:REFERENCES,postgres:SELECT,postgres:TRIGGER,postgres:TRUNCATE,postgres:UPDATE,service_role:DELETE,service_role:INSERT,service_role:SELECT,service_role:UPDATE' THEN
      v_malos := v_malos || r.t || ' ACL ' || COALESCE(v_acl, 'NULL') || '; ';
    END IF;
  END LOOP;

  -- chat_comercial_enviar: firma, retorno, DEFINER, search_path vacío, sin PUBLIC ni anon, authenticated con EXECUTE
  IF NOT EXISTS (SELECT 1 FROM pg_proc p
                  WHERE p.oid = to_regprocedure('public.chat_comercial_enviar(uuid,text)')
                    AND p.prorettype = 'uuid'::regtype AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
                    AND p.prosrc LIKE '%private.push_notificar(''notificaciones''%'
                    AND p.prosrc LIKE '%SET notificado = true%') THEN
    v_malos := v_malos || 'chat_comercial_enviar sin la forma esperada; ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
              WHERE p.oid = to_regprocedure('public.chat_comercial_enviar(uuid,text)') AND a.privilege_type = 'EXECUTE'
                AND (a.grantee = 0 OR a.grantee = 'anon'::regrole)) THEN
    v_malos := v_malos || 'chat_comercial_enviar con EXECUTE para PUBLIC o anon; ';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.chat_comercial_enviar(uuid,text)', 'EXECUTE') THEN
    v_malos := v_malos || 'chat_comercial_enviar sin EXECUTE de authenticated; ';
  END IF;

  -- las otras 8 funciones de la 382, sin tocar
  FOR r IN SELECT pre.firma, pre.md5_esperado FROM m383_pre pre WHERE pre.firma <> 'public.chat_comercial_enviar(uuid,text)' LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)) IS DISTINCT FROM r.md5_esperado THEN
      v_malos := v_malos || r.firma || ' cambió; ';
    END IF;
  END LOOP;

  IF v_malos <> '' THEN
    RAISE EXCEPTION 'MIG83: autochequeo: %', v_malos USING ERRCODE = 'MIG83';
  END IF;
END $$;

COMMIT;
