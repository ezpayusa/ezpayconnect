-- =====================================================================================================================
-- MIG 382 — Chat comercial (PWA /comercial): esquema + helper + policies + Realtime + RPCs. SIN notificación (va en la 383).
-- Recon del 24-oct-2026 (scratchpad recon_chat_comercial), contra el objeto vivo.
--
-- Por qué tablas nuevas y no las del chat de proveedores (migs 053-057): aquellas cuelgan de cuentas_proveedor y exigen
-- empresa_id; los comerciales son perfiles de EzPay. Se clona el MODELO (membresía dinámica, lecturas por last_read_at),
-- no los objetos.
--
-- Decisiones de producto (Oscar, 24-oct-2026):
--   * Un hilo POR COMERCIAL y por tipo (UNIQUE (comercial_id, tipo)), no por par. Al cambiar el supervisor, el nuevo
--     hereda el historial y el viejo pierde el acceso: la membresía se recalcula en cada lectura y escritura.
--   * 'supervision' = asesor_comercial <-> su supervisor ACTUAL (asesores_perfil.supervisor_id).
--     'pais'        = asesor o supervisor <-> los admin_pais activos de su país; sin admin_pais activo, el super_admin.
--   * El super_admin lee y escribe en todos los hilos.
--   * Mensaje de 1 a 2000 caracteres tras recortar. Sin editar ni borrar. Sin retención automática.
--   * Cuenta inactiva (perfiles.activo o asesores_perfil.activo) en cualquiera de los dos extremos = hilo cerrado
--     (fail-closed), salvo para el super_admin. NO se reusa private.asesores_a_cargo() (ignora activo).
--
-- Objetos:
--   tablas  public.chat_comercial_hilos, public.chat_comercial_mensajes, public.chat_comercial_lecturas
--           RLS ON; authenticated SOLO SELECT (toda escritura por RPC DEFINER); service_role S/I/U/D; anon nada.
--   trigger private.trg_chat_comercial_hilos_guard (BEFORE INSERT OR UPDATE ON hilos): país = el de la ficha,
--           'supervision' solo para asesor_comercial, comercial_id/tipo/pais_id inmutables.
--   private.chat_comercial_relacion(tipo, comercial, pais, exigir_activos)  núcleo de la relación, EXECUTE solo postgres.
--           Se evalúa sobre los datos del PAR, así sirve antes de que el hilo exista (abrir) y para un hilo existente.
--           Con exigir_activos = false es la relación ESTRUCTURAL: distingue "sos parte pero el hilo está cerrado"
--           (PA039) de "no sos parte" (42501).
--   private.puede_ver_hilo_comercial(hilo)   helper de las policies (EXECUTE authenticated, regla 10).
--   RPCs    chat_comercial_contactos, chat_comercial_abrir, chat_comercial_mis_hilos, chat_comercial_mensajes,
--           chat_comercial_enviar, chat_comercial_marcar_leido.
--   Realtime: chat_comercial_mensajes en supabase_realtime (la policy SELECT de mensajes es la que filtra).
--
-- Errores:
--   42501 'no_autorizado'  sin sesión, no sos parte del hilo, o el hilo/comercial no existe (mismo texto en todos).
--   PA036  el mensaje está vacío o pasa de 2000 caracteres (después de recortar espacios, tabs y saltos de línea).
--   PA037  tipo de hilo inválido (no es 'supervision' ni 'pais', o 'supervision' para quien no es asesor_comercial).
--   PA038  el asesor no tiene supervisor asignado (abrir o escribir en el hilo 'supervision').
--   PA039  el hilo está cerrado: uno de los dos extremos está inactivo.
--   PA040  integridad del hilo (solo escritura directa, no la alcanza ninguna RPC): país distinto al de la ficha,
--          comercial sin ficha, o cambio de comercial_id/tipo/pais_id.
--   MIG82  guarda de la migración (precondición o autochequeo).
--
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/382_chat_comercial.sql
-- Rollback: supabase/migrations/382_rollback.sql (va antes que 381_rollback).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) PRECONDICIÓN: dependencias vivas con el cuerpo esperado (medido el 24-oct-2026)
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE v_malos text := '';
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('private.mi_pais()')) IS DISTINCT FROM '64ec50953f8d351c300c60a23b05f0a6' THEN
    v_malos := v_malos || 'private.mi_pais(); ';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.get_auth_user_rol()')) IS DISTINCT FROM '51df907aba35bf44abd671a3f23b7234' THEN
    v_malos := v_malos || 'public.get_auth_user_rol(); ';
  END IF;
  IF to_regclass('public.asesores_perfil') IS NULL OR to_regclass('public.configuracion_pais') IS NULL THEN
    v_malos := v_malos || 'asesores_perfil/configuracion_pais; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    v_malos := v_malos || 'publicación supabase_realtime; ';
  END IF;
  IF v_malos <> '' THEN
    RAISE EXCEPTION 'MIG82: precondición: %', v_malos USING ERRCODE = 'MIG82';
  END IF;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) TABLAS
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.chat_comercial_hilos (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  pais_id      uuid        NOT NULL,
  tipo         text        NOT NULL,
  comercial_id uuid        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.chat_comercial_mensajes (
  id         uuid        NOT NULL DEFAULT gen_random_uuid(),
  hilo_id    uuid        NOT NULL,
  autor_id   uuid        NOT NULL,
  cuerpo     text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  notificado boolean     NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.chat_comercial_lecturas (
  hilo_id      uuid        NOT NULL,
  usuario_id   uuid        NOT NULL,
  last_read_at timestamptz NOT NULL
);

-- Constraints por nombre (idempotente).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.chat_comercial_hilos'::regclass,    'chat_comercial_hilos_pkey',              'PRIMARY KEY (id)'),
    ('public.chat_comercial_hilos'::regclass,    'chat_comercial_hilos_pais_id_fkey',      'FOREIGN KEY (pais_id) REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT'),
    ('public.chat_comercial_hilos'::regclass,    'chat_comercial_hilos_comercial_id_fkey', 'FOREIGN KEY (comercial_id) REFERENCES public.perfiles(id) ON DELETE RESTRICT'),
    ('public.chat_comercial_hilos'::regclass,    'chat_comercial_hilos_tipo_check',        'CHECK (tipo IN (''supervision'', ''pais''))'),
    ('public.chat_comercial_hilos'::regclass,    'chat_comercial_hilos_comercial_tipo_uniq', 'UNIQUE (comercial_id, tipo)'),
    ('public.chat_comercial_mensajes'::regclass, 'chat_comercial_mensajes_pkey',           'PRIMARY KEY (id)'),
    ('public.chat_comercial_mensajes'::regclass, 'chat_comercial_mensajes_hilo_id_fkey',   'FOREIGN KEY (hilo_id) REFERENCES public.chat_comercial_hilos(id) ON DELETE RESTRICT'),
    ('public.chat_comercial_mensajes'::regclass, 'chat_comercial_mensajes_autor_id_fkey',  'FOREIGN KEY (autor_id) REFERENCES public.perfiles(id) ON DELETE RESTRICT'),
    ('public.chat_comercial_mensajes'::regclass, 'chat_comercial_mensajes_cuerpo_check',   'CHECK (char_length(btrim(cuerpo)) BETWEEN 1 AND 2000)'),
    ('public.chat_comercial_lecturas'::regclass, 'chat_comercial_lecturas_pkey',           'PRIMARY KEY (hilo_id, usuario_id)'),
    ('public.chat_comercial_lecturas'::regclass, 'chat_comercial_lecturas_hilo_id_fkey',   'FOREIGN KEY (hilo_id) REFERENCES public.chat_comercial_hilos(id) ON DELETE RESTRICT'),
    ('public.chat_comercial_lecturas'::regclass, 'chat_comercial_lecturas_usuario_id_fkey', 'FOREIGN KEY (usuario_id) REFERENCES public.perfiles(id) ON DELETE RESTRICT')
  ) AS t(rel, nombre, def)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = r.rel AND c.conname = r.nombre) THEN
      EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s', r.rel, r.nombre, r.def);
    END IF;
  END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS chat_comercial_mensajes_hilo_created_idx
  ON public.chat_comercial_mensajes (hilo_id, created_at DESC);

ALTER TABLE public.chat_comercial_hilos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_comercial_mensajes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_comercial_lecturas ENABLE ROW LEVEL SECURITY;

-- GRANTs explícitos (regla de GRANTs del Data API): authenticated solo SELECT, anon nada, service_role S/I/U/D.
REVOKE ALL ON public.chat_comercial_hilos, public.chat_comercial_mensajes, public.chat_comercial_lecturas FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.chat_comercial_hilos, public.chat_comercial_mensajes, public.chat_comercial_lecturas TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_comercial_hilos, public.chat_comercial_mensajes, public.chat_comercial_lecturas TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) GUARD DEL HILO (trigger)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.trg_chat_comercial_hilos_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_pais uuid; v_rol text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.comercial_id IS DISTINCT FROM OLD.comercial_id
       OR NEW.tipo IS DISTINCT FROM OLD.tipo
       OR NEW.pais_id IS DISTINCT FROM OLD.pais_id THEN
      RAISE EXCEPTION 'El comercial, el tipo y el país de un hilo no se cambian' USING ERRCODE = 'PA040';
    END IF;
    RETURN NEW;
  END IF;

  SELECT ap.pais_id, p.rol INTO v_pais, v_rol
    FROM public.asesores_perfil ap
    JOIN public.perfiles p ON p.id = ap.id
   WHERE ap.id = NEW.comercial_id;
  IF v_pais IS NULL THEN
    RAISE EXCEPTION 'El comercial del hilo no tiene ficha' USING ERRCODE = 'PA040';
  END IF;
  IF NEW.pais_id IS DISTINCT FROM v_pais THEN
    RAISE EXCEPTION 'El país del hilo tiene que ser el de la ficha del comercial' USING ERRCODE = 'PA040';
  END IF;
  IF NEW.tipo = 'supervision' AND v_rol IS DISTINCT FROM 'asesor_comercial' THEN
    RAISE EXCEPTION 'El hilo de supervisión es solo para asesores' USING ERRCODE = 'PA037';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS trg_chat_comercial_hilos_guard ON public.chat_comercial_hilos;
CREATE TRIGGER trg_chat_comercial_hilos_guard
  BEFORE INSERT OR UPDATE ON public.chat_comercial_hilos
  FOR EACH ROW EXECUTE FUNCTION private.trg_chat_comercial_hilos_guard();

-- ---------------------------------------------------------------------------------------------------------------------
-- d) NÚCLEO DE LA RELACIÓN Y HELPER DE LAS POLICIES
-- ---------------------------------------------------------------------------------------------------------------------
-- ¿El llamante es parte del hilo (p_tipo, p_comercial_id, p_pais_id)? El super_admin NO está acá (es la primera rama del
-- helper y de cada RPC). Ramas:
--   (2) el comercial dueño, con p_pais_id = private.mi_pais();
--   (3) 'supervision': el supervisor_id ACTUAL de la ficha del dueño, supervisor_comercial con ficha del mismo país;
--   (4) 'pais': un admin_pais con perfiles.pais_id = p_pais_id.
-- Siempre: la ficha del dueño existe, es de p_pais_id y el dueño es asesor o supervisor comercial.
-- Con p_exigir_activos: el dueño activo (perfil y ficha), el llamante activo y, en 'supervision', el supervisor actual
-- activo (perfil y ficha) si lo hay. Sin p_exigir_activos: la misma relación ignorando activo (relación estructural).
CREATE OR REPLACE FUNCTION private.chat_comercial_relacion(p_tipo text, p_comercial_id uuid, p_pais_id uuid, p_exigir_activos boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE((
    SELECT p_tipo IN ('supervision', 'pais')
       AND p_pais_id IS NOT NULL
       AND auth.uid() IS NOT NULL
       AND d.pais_id = p_pais_id
       AND dp.rol IN ('asesor_comercial', 'supervisor_comercial')
       AND (NOT p_exigir_activos OR (d.activo AND dp.activo IS TRUE))
       AND (
         -- (2) el dueño
         (    dp.id = auth.uid()
          AND private.mi_pais() = p_pais_id
          AND (NOT p_exigir_activos
               OR p_tipo <> 'supervision'
               OR d.supervisor_id IS NULL
               OR EXISTS (SELECT 1 FROM public.asesores_perfil s JOIN public.perfiles sp ON sp.id = s.id
                           WHERE s.id = d.supervisor_id AND s.activo AND sp.activo IS TRUE)))
         -- (3) el supervisor actual
         OR (    p_tipo = 'supervision'
             AND dp.rol = 'asesor_comercial'
             AND d.supervisor_id = auth.uid()
             AND private.mi_pais() = p_pais_id
             AND EXISTS (SELECT 1 FROM public.asesores_perfil s JOIN public.perfiles sp ON sp.id = s.id
                          WHERE s.id = auth.uid()
                            AND s.pais_id = p_pais_id
                            AND sp.rol = 'supervisor_comercial'
                            AND (NOT p_exigir_activos OR (s.activo AND sp.activo IS TRUE))))
         -- (4) admin_pais del país del hilo
         OR (    p_tipo = 'pais'
             AND EXISTS (SELECT 1 FROM public.perfiles yo
                          WHERE yo.id = auth.uid()
                            AND yo.rol = 'admin_pais'
                            AND yo.pais_id = p_pais_id
                            AND (NOT p_exigir_activos OR yo.activo IS TRUE)))
       )
      FROM public.asesores_perfil d
      JOIN public.perfiles dp ON dp.id = d.id
     WHERE d.id = p_comercial_id
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.puede_ver_hilo_comercial(p_hilo uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1 FROM public.chat_comercial_hilos h
     WHERE h.id = p_hilo
       AND (   COALESCE(public.get_auth_user_rol() = 'super_admin', false)                        -- (1)
            OR private.chat_comercial_relacion(h.tipo, h.comercial_id, h.pais_id, true))          -- (2)(3)(4)
  ), false)
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- e) POLICIES (solo SELECT, TO authenticated)
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY IF EXISTS chat_comercial_hilos_select ON public.chat_comercial_hilos;
CREATE POLICY chat_comercial_hilos_select ON public.chat_comercial_hilos
  FOR SELECT TO authenticated
  USING (private.puede_ver_hilo_comercial(id));

DROP POLICY IF EXISTS chat_comercial_mensajes_select ON public.chat_comercial_mensajes;
CREATE POLICY chat_comercial_mensajes_select ON public.chat_comercial_mensajes
  FOR SELECT TO authenticated
  USING (private.puede_ver_hilo_comercial(hilo_id));

DROP POLICY IF EXISTS chat_comercial_lecturas_select ON public.chat_comercial_lecturas;
CREATE POLICY chat_comercial_lecturas_select ON public.chat_comercial_lecturas
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() AND private.puede_ver_hilo_comercial(hilo_id));

-- ---------------------------------------------------------------------------------------------------------------------
-- f) RPCs
-- ---------------------------------------------------------------------------------------------------------------------
-- Los hilos que el llamante PUEDE abrir, existan o no. Solo id, nombre y rol de la contraparte. En el hilo 'pais' visto
-- por el comercial la contraparte es un grupo: contraparte_id NULL, 'Administración de país' (rol admin_pais) o, sin
-- admin_pais activo en el país, 'Administración EZPay' (rol super_admin).
CREATE OR REPLACE FUNCTION public.chat_comercial_contactos()
RETURNS TABLE (tipo text, comercial_id uuid, contraparte_id uuid, contraparte_nombre text, contraparte_rol text, hilo_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_sa boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  v_sa := COALESCE(public.get_auth_user_rol() = 'super_admin', false);

  RETURN QUERY
  WITH cand AS (
    SELECT t.tipo, d.id AS comercial_id, d.pais_id, d.supervisor_id, dp.nombre_completo AS dueno_nombre, dp.rol AS dueno_rol
      FROM public.asesores_perfil d
      JOIN public.perfiles dp ON dp.id = d.id
     CROSS JOIN (VALUES ('supervision'::text), ('pais'::text)) AS t(tipo)
     WHERE dp.rol IN ('asesor_comercial', 'supervisor_comercial')
       AND (t.tipo = 'pais' OR (dp.rol = 'asesor_comercial' AND d.supervisor_id IS NOT NULL))
       AND (v_sa OR private.chat_comercial_relacion(t.tipo, d.id, d.pais_id, true))
  )
  SELECT c.tipo,
         c.comercial_id,
         CASE WHEN c.comercial_id <> v_uid THEN c.comercial_id
              WHEN c.tipo = 'supervision' THEN c.supervisor_id
              ELSE NULL END,
         CASE WHEN c.comercial_id <> v_uid THEN c.dueno_nombre
              WHEN c.tipo = 'supervision' THEN (SELECT s.nombre_completo FROM public.perfiles s WHERE s.id = c.supervisor_id)
              WHEN EXISTS (SELECT 1 FROM public.perfiles a WHERE a.rol = 'admin_pais' AND a.pais_id = c.pais_id AND a.activo IS TRUE)
                THEN 'Administración de país'
              ELSE 'Administración EZPay' END,
         CASE WHEN c.comercial_id <> v_uid THEN c.dueno_rol
              WHEN c.tipo = 'supervision' THEN 'supervisor_comercial'
              WHEN EXISTS (SELECT 1 FROM public.perfiles a WHERE a.rol = 'admin_pais' AND a.pais_id = c.pais_id AND a.activo IS TRUE)
                THEN 'admin_pais'
              ELSE 'super_admin' END,
         (SELECT h.id FROM public.chat_comercial_hilos h WHERE h.comercial_id = c.comercial_id AND h.tipo = c.tipo)
    FROM cand c
   ORDER BY 4, 1;
END
$function$;

-- Get-or-create del hilo (p_tipo, p_comercial_id). El país sale de la ficha; nunca es parámetro.
CREATE OR REPLACE FUNCTION public.chat_comercial_abrir(p_tipo text, p_comercial_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_sa boolean; v_pais uuid; v_rol text; v_sup uuid; v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF p_tipo IS NULL OR p_tipo NOT IN ('supervision', 'pais') THEN
    RAISE EXCEPTION 'Tipo de conversación inválido' USING ERRCODE = 'PA037';
  END IF;
  v_sa := COALESCE(public.get_auth_user_rol() = 'super_admin', false);

  SELECT d.pais_id, dp.rol, d.supervisor_id INTO v_pais, v_rol, v_sup
    FROM public.asesores_perfil d
    JOIN public.perfiles dp ON dp.id = d.id
   WHERE d.id = p_comercial_id;

  -- Gate PRIMERO: antes de mirar si el hilo existe o de validar reglas de negocio.
  IF NOT COALESCE(v_pais IS NOT NULL AND (v_sa OR private.chat_comercial_relacion(p_tipo, p_comercial_id, v_pais, false)), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT h.id INTO v_id FROM public.chat_comercial_hilos h WHERE h.comercial_id = p_comercial_id AND h.tipo = p_tipo;
  IF v_sa AND v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  IF p_tipo = 'supervision' AND v_rol IS DISTINCT FROM 'asesor_comercial' THEN
    RAISE EXCEPTION 'La conversación de supervisión es solo para asesores' USING ERRCODE = 'PA037';
  END IF;
  IF p_tipo = 'supervision' AND v_sup IS NULL THEN
    RAISE EXCEPTION 'El asesor no tiene supervisor asignado' USING ERRCODE = 'PA038';
  END IF;
  IF NOT v_sa AND NOT private.chat_comercial_relacion(p_tipo, p_comercial_id, v_pais, true) THEN
    RAISE EXCEPTION 'La conversación está cerrada: una de las cuentas está inactiva' USING ERRCODE = 'PA039';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.chat_comercial_hilos (pais_id, tipo, comercial_id)
    VALUES (v_pais, p_tipo, p_comercial_id)
    ON CONFLICT (comercial_id, tipo) DO NOTHING;
    SELECT h.id INTO v_id FROM public.chat_comercial_hilos h WHERE h.comercial_id = p_comercial_id AND h.tipo = p_tipo;
  END IF;
  RETURN v_id;
END
$function$;

-- Los hilos visibles del llamante, con el último mensaje y los no leídos. Un hilo cerrado no aparece.
CREATE OR REPLACE FUNCTION public.chat_comercial_mis_hilos()
RETURNS TABLE (hilo_id uuid, tipo text, comercial_id uuid, contraparte_nombre text, ultimo_at timestamptz, ultimo_extracto text, no_leidos integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT h.id,
         h.tipo,
         h.comercial_id,
         CASE WHEN h.comercial_id <> v_uid THEN dp.nombre_completo
              WHEN h.tipo = 'supervision' THEN (SELECT s.nombre_completo FROM public.perfiles s WHERE s.id = d.supervisor_id)
              WHEN EXISTS (SELECT 1 FROM public.perfiles a WHERE a.rol = 'admin_pais' AND a.pais_id = h.pais_id AND a.activo IS TRUE)
                THEN 'Administración de país'
              ELSE 'Administración EZPay' END,
         u.created_at,
         left(u.cuerpo, 80),
         (SELECT count(*)::integer FROM public.chat_comercial_mensajes m
           WHERE m.hilo_id = h.id
             AND m.autor_id <> v_uid
             AND m.created_at > COALESCE((SELECT l.last_read_at FROM public.chat_comercial_lecturas l
                                           WHERE l.hilo_id = h.id AND l.usuario_id = v_uid), '-infinity'::timestamptz))
    FROM public.chat_comercial_hilos h
    JOIN public.perfiles dp ON dp.id = h.comercial_id
    LEFT JOIN public.asesores_perfil d ON d.id = h.comercial_id
    LEFT JOIN LATERAL (SELECT m.created_at, m.cuerpo FROM public.chat_comercial_mensajes m
                        WHERE m.hilo_id = h.id ORDER BY m.created_at DESC, m.id DESC LIMIT 1) u ON true
   WHERE private.puede_ver_hilo_comercial(h.id)
   ORDER BY u.created_at DESC NULLS LAST, h.created_at DESC;
END
$function$;

-- Mensajes de un hilo, del más nuevo al más viejo. p_antes = cursor (created_at estricto); p_limite acotado a 1..100.
CREATE OR REPLACE FUNCTION public.chat_comercial_mensajes(p_hilo uuid, p_antes timestamptz DEFAULT NULL, p_limite integer DEFAULT 50)
RETURNS TABLE (id uuid, autor_id uuid, autor_nombre text, cuerpo text, created_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_lim integer := LEAST(GREATEST(COALESCE(p_limite, 50), 1), 100);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.puede_ver_hilo_comercial(p_hilo), false) THEN
    IF COALESCE(EXISTS (SELECT 1 FROM public.chat_comercial_hilos h
                         WHERE h.id = p_hilo AND private.chat_comercial_relacion(h.tipo, h.comercial_id, h.pais_id, false)), false) THEN
      RAISE EXCEPTION 'La conversación está cerrada: una de las cuentas está inactiva' USING ERRCODE = 'PA039';
    END IF;
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT m.id, m.autor_id, p.nombre_completo, m.cuerpo, m.created_at
    FROM public.chat_comercial_mensajes m
    JOIN public.perfiles p ON p.id = m.autor_id
   WHERE m.hilo_id = p_hilo
     AND (p_antes IS NULL OR m.created_at < p_antes)
   ORDER BY m.created_at DESC, m.id DESC
   LIMIT v_lim;
END
$function$;

-- Envía un mensaje. autor_id = auth.uid(). Sin notificación (va en la 383).
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

-- Marca el hilo como leído para el llamante. Sin permiso: error (nunca vuelve en silencio).
CREATE OR REPLACE FUNCTION public.chat_comercial_marcar_leido(p_hilo uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid();
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

  INSERT INTO public.chat_comercial_lecturas (hilo_id, usuario_id, last_read_at)
  VALUES (p_hilo, v_uid, now())
  ON CONFLICT (hilo_id, usuario_id) DO UPDATE SET last_read_at = EXCLUDED.last_read_at;
END
$function$;

-- ACL de funciones: sin PUBLIC ni anon. Las de private que no usa una policy: solo postgres.
REVOKE ALL ON FUNCTION private.trg_chat_comercial_hilos_guard()                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.chat_comercial_relacion(text, uuid, uuid, boolean)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.puede_ver_hilo_comercial(uuid)                      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.puede_ver_hilo_comercial(uuid)                   TO authenticated;
REVOKE ALL ON FUNCTION public.chat_comercial_contactos()                           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chat_comercial_abrir(text, uuid)                     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chat_comercial_mis_hilos()                           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chat_comercial_mensajes(uuid, timestamptz, integer)  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chat_comercial_enviar(uuid, text)                    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chat_comercial_marcar_leido(uuid)                    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_comercial_contactos()                          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_comercial_abrir(text, uuid)                    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_comercial_mis_hilos()                          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_comercial_mensajes(uuid, timestamptz, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_comercial_enviar(uuid, text)                   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_comercial_marcar_leido(uuid)                   TO authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- g) REALTIME
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'chat_comercial_mensajes') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_comercial_mensajes';
  END IF;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- h) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE v_malos text := ''; r record; n int;
BEGIN
  -- tablas con RLS
  FOR r IN SELECT t FROM unnest(ARRAY['chat_comercial_hilos', 'chat_comercial_mensajes', 'chat_comercial_lecturas']) t LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
                    WHERE ns.nspname = 'public' AND c.relname = r.t AND c.relkind = 'r' AND c.relrowsecurity) THEN
      v_malos := v_malos || r.t || ' sin tabla o sin RLS; ';
    END IF;
    -- ACL exacta: anon nada; authenticated solo SELECT (ni de tabla ni de columna); PUBLIC nada; service_role S/I/U/D
    IF has_table_privilege('anon', 'public.'||r.t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       OR has_any_column_privilege('anon', 'public.'||r.t, 'SELECT,INSERT,UPDATE,REFERENCES') THEN
      v_malos := v_malos || r.t || ' anon con privilegio; ';
    END IF;
    IF NOT has_table_privilege('authenticated', 'public.'||r.t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.'||r.t, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       OR has_any_column_privilege('authenticated', 'public.'||r.t, 'INSERT,UPDATE,REFERENCES') THEN
      v_malos := v_malos || r.t || ' authenticated distinto de solo SELECT; ';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class c, aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a
                WHERE c.oid = ('public.'||r.t)::regclass AND a.grantee = 0) THEN
      v_malos := v_malos || r.t || ' con privilegio para PUBLIC; ';
    END IF;
    IF NOT (has_table_privilege('service_role', 'public.'||r.t, 'SELECT') AND has_table_privilege('service_role', 'public.'||r.t, 'INSERT')
            AND has_table_privilege('service_role', 'public.'||r.t, 'UPDATE') AND has_table_privilege('service_role', 'public.'||r.t, 'DELETE')) THEN
      v_malos := v_malos || r.t || ' service_role sin S/I/U/D; ';
    END IF;
  END LOOP;

  -- policies: exactamente 3, todas SELECT TO authenticated, una por tabla
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname = 'public' AND tablename LIKE 'chat_comercial_%';
  IF n <> 3 THEN v_malos := v_malos || 'policies = '||n||' (se esperaban 3); '; END IF;
  SELECT count(*) INTO n FROM pg_policies
   WHERE schemaname = 'public'
     AND (tablename, policyname) IN (('chat_comercial_hilos', 'chat_comercial_hilos_select'),
                                     ('chat_comercial_mensajes', 'chat_comercial_mensajes_select'),
                                     ('chat_comercial_lecturas', 'chat_comercial_lecturas_select'))
     AND cmd = 'SELECT' AND roles = '{authenticated}'::name[] AND permissive = 'PERMISSIVE';
  IF n <> 3 THEN v_malos := v_malos || 'policies con nombre/cmd/rol distinto ('||n||' de 3); '; END IF;

  -- funciones: DEFINER, search_path vacío, sin PUBLIC ni anon; EXECUTE de authenticated donde corresponde
  FOR r IN SELECT * FROM (VALUES
      ('public.chat_comercial_contactos()', true),
      ('public.chat_comercial_abrir(text,uuid)', true),
      ('public.chat_comercial_mis_hilos()', true),
      ('public.chat_comercial_mensajes(uuid,timestamptz,integer)', true),
      ('public.chat_comercial_enviar(uuid,text)', true),
      ('public.chat_comercial_marcar_leido(uuid)', true),
      ('private.puede_ver_hilo_comercial(uuid)', true),
      ('private.chat_comercial_relacion(text,uuid,uuid,boolean)', false),
      ('private.trg_chat_comercial_hilos_guard()', false)) AS f(firma, auth_exec)
  LOOP
    IF to_regprocedure(r.firma) IS NULL THEN
      v_malos := v_malos || r.firma || ' no existe; ';
      CONTINUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma) AND p.prosecdef
                     AND p.proconfig @> ARRAY['search_path=""']) THEN
      v_malos := v_malos || r.firma || ' no es DEFINER con search_path vacío; ';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
                WHERE p.oid = to_regprocedure(r.firma) AND a.privilege_type = 'EXECUTE'
                  AND (a.grantee = 0 OR a.grantee = 'anon'::regrole)) THEN
      v_malos := v_malos || r.firma || ' con EXECUTE para PUBLIC o anon; ';
    END IF;
    IF has_function_privilege('authenticated', to_regprocedure(r.firma), 'EXECUTE') IS DISTINCT FROM r.auth_exec THEN
      v_malos := v_malos || r.firma || ' EXECUTE de authenticated distinto de '||r.auth_exec||'; ';
    END IF;
  END LOOP;

  -- Realtime
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'chat_comercial_mensajes') THEN
    v_malos := v_malos || 'chat_comercial_mensajes fuera de supabase_realtime; ';
  END IF;

  -- constraints por nombre
  FOR r IN SELECT * FROM (VALUES
      ('public.chat_comercial_hilos', 'chat_comercial_hilos_tipo_check', 'c'),
      ('public.chat_comercial_hilos', 'chat_comercial_hilos_comercial_tipo_uniq', 'u'),
      ('public.chat_comercial_hilos', 'chat_comercial_hilos_pais_id_fkey', 'f'),
      ('public.chat_comercial_hilos', 'chat_comercial_hilos_comercial_id_fkey', 'f'),
      ('public.chat_comercial_mensajes', 'chat_comercial_mensajes_cuerpo_check', 'c'),
      ('public.chat_comercial_mensajes', 'chat_comercial_mensajes_hilo_id_fkey', 'f'),
      ('public.chat_comercial_mensajes', 'chat_comercial_mensajes_autor_id_fkey', 'f'),
      ('public.chat_comercial_lecturas', 'chat_comercial_lecturas_pkey', 'p'),
      ('public.chat_comercial_lecturas', 'chat_comercial_lecturas_hilo_id_fkey', 'f'),
      ('public.chat_comercial_lecturas', 'chat_comercial_lecturas_usuario_id_fkey', 'f')) AS k(rel, nombre, tipo)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = r.rel::regclass AND c.conname = r.nombre AND c.contype = r.tipo::"char") THEN
      v_malos := v_malos || 'falta '||r.nombre||'; ';
    END IF;
  END LOOP;
  -- FKs RESTRICT
  IF EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid IN ('public.chat_comercial_hilos'::regclass, 'public.chat_comercial_mensajes'::regclass,
                                                                 'public.chat_comercial_lecturas'::regclass)
                AND c.contype = 'f' AND c.confdeltype <> 'r') THEN
    v_malos := v_malos || 'FK sin ON DELETE RESTRICT; ';
  END IF;
  -- trigger
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.chat_comercial_hilos'::regclass AND tgname = 'trg_chat_comercial_hilos_guard' AND NOT tgisinternal) THEN
    v_malos := v_malos || 'falta el trigger guard; ';
  END IF;

  IF v_malos <> '' THEN
    RAISE EXCEPTION 'MIG82: autochequeo: %', v_malos USING ERRCODE = 'MIG82';
  END IF;
END $$;

COMMIT;
