-- ============================================================================================
-- 307 — las 4 RPCs de medicos: search_path fijado y aislamiento por pais
-- ============================================================================================
-- Origen: docs/CENSO_SEGURIDAD_TRANSVERSAL_2026-09-20.md, seccion F4 (hallazgo #7), punto #2.
--
-- QUE PASABA. Las cuatro eran SECURITY DEFINER SIN `SET search_path` y sin ningun gate: cualquier
-- `authenticated` las ejecutaba, y el filtro de pais era
--     WHERE (p_pais_id IS NULL OR m.pais_id = p_pais_id OR m.pais_id IS NULL)
-- que ve de mas por DOS vias: `p_pais_id` NULL devuelve TODOS los paises, y `m.pais_id IS NULL`
-- cuela a los medicos sin pais siempre. `src/clinica/hooks/useClinicaCitas.ts:72` llama SIN
-- argumento, asi que una clinica recibia el padron de medicos de todos los paises.
-- `anon` ya estaba cerrado por la mig 295; lo que faltaba era el resto.
--
-- EL FIX. `SET search_path = ''` en las cuatro (todo calificado), el filtro pasa a `= v_pais`
-- estricto (sin la rama `IS NULL`), y las dos que reciben pais llevan gate de tres brazos:
--   1. private.puede_admin_pais(v_pais)  — super_admin, o admin_pais de ESE pais
--   2. v_pais = private.mi_pais_viewer() — su propio pais (cubre clinica, medico y paciente)
--   3. tener una clinica en ese pais via medico_clinicas
-- Las dos de ids solo exigen sesion: reciben ids ya resueltos por otra RPC y no filtran por pais.
--
-- Precedente: la mig 184 cerro exactamente este hueco en `buscar_medicos_paciente` derivando el
-- pais server-side, y dejo anotado que el de `listar_medicos_por_pais` quedaba como work item
-- aparte "verificar sus 3 consumidores antes de tocarla". Eso es lo que cierra esta migracion.
--
-- EL BRAZO 3 LLEVA `c.pais_id IS NOT NULL` EXPLICITO. `clinicas.pais_id` es NULABLE (medido:
-- attnotnull=false) y su FK es `ON DELETE SET NULL`, o sea que borrar un pais de
-- `configuracion_pais` deja sus clinicas con pais NULL. Sin ese chequeo, `NULL = v_pais` da NULL,
-- el EXISTS no cuenta la fila y el medico de esa clinica perderia el acceso EN SILENCIO — la
-- misma via trivaluada de las migs 265-271/300, solo que cerrando de mas en vez de abrir.
-- Hoy hay 0 clinicas con pais NULL; el chequeo es para que siga siendo irrelevante.
--
-- ERRCODES NUEVOS: PC025 (pais requerido), PC026 (no autorizado para este pais), PC027 (no
-- autenticado). Verificado sobre TODO el repo: PC llega hasta PC024, con PC008 como unico hueco.
--
-- QUE NO TOCA: `buscar_medicos(text,uuid,integer)`, la quinta del frente. Sigue sin search_path y
-- sin gate, y no tiene UN SOLO caller (ya lo dejo escrito la mig 295). Es candidata a DROP, no a
-- parche, y esa es una decision aparte.
--
-- Probes: P771-P778 en tests/rls/probes_escritura.sql.
-- ============================================================================================

CREATE OR REPLACE FUNCTION public.listar_medicos_por_pais(p_pais_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, nombre_completo text, especialidad text, foto_url text, activo boolean, pais_id uuid)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_pais uuid;
BEGIN
  v_pais := COALESCE(p_pais_id, private.mi_pais_viewer());
  IF v_pais IS NULL THEN
    RAISE EXCEPTION 'pais requerido' USING ERRCODE = 'PC025';
  END IF;
  IF NOT COALESCE(
    private.puede_admin_pais(v_pais)
    OR v_pais = private.mi_pais_viewer()
    OR EXISTS (
         SELECT 1 FROM public.medico_clinicas mc
         JOIN public.clinicas c ON c.id = mc.clinica_id
         WHERE mc.medico_id = auth.uid()
           AND c.pais_id IS NOT NULL
           AND c.pais_id = v_pais
       ),
    false
  ) THEN
    RAISE EXCEPTION 'no autorizado para este pais' USING ERRCODE = 'PC026';
  END IF;

  RETURN QUERY
  SELECT m.id, m.nombre_completo, m.especialidad, m.foto_url, m.activo, m.pais_id
  FROM public.medicos m
  WHERE m.pais_id = v_pais AND m.activo = true
  UNION
  SELECT p.id, p.nombre_completo, NULL::TEXT, p.avatar_url, p.activo, p.pais_id
  FROM public.perfiles p
  WHERE p.rol = 'medico' AND p.activo = true AND p.pais_id = v_pais
    AND NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = p.id)
  ORDER BY nombre_completo;
END;
$function$;

CREATE OR REPLACE FUNCTION public.contar_medicos_por_pais(p_pais_id uuid)
 RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_count INTEGER;
BEGIN
  IF p_pais_id IS NULL THEN
    RAISE EXCEPTION 'pais requerido' USING ERRCODE = 'PC025';
  END IF;
  IF NOT COALESCE(
    private.puede_admin_pais(p_pais_id)
    OR p_pais_id = private.mi_pais_viewer()
    OR EXISTS (
         SELECT 1 FROM public.medico_clinicas mc
         JOIN public.clinicas c ON c.id = mc.clinica_id
         WHERE mc.medico_id = auth.uid()
           AND c.pais_id IS NOT NULL
           AND c.pais_id = p_pais_id
       ),
    false
  ) THEN
    RAISE EXCEPTION 'no autorizado para este pais' USING ERRCODE = 'PC026';
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.medicos WHERE pais_id = p_pais_id;
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_medicos_por_ids(p_medico_ids uuid[])
 RETURNS TABLE(id uuid, nombre_completo text, especialidad text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'no autenticado' USING ERRCODE = 'PC027';
  END IF;
  RETURN QUERY
  SELECT m.id, m.nombre_completo, m.especialidad FROM public.medicos m WHERE m.id = ANY(p_medico_ids)
  UNION
  SELECT p.id, p.nombre_completo, NULL::TEXT FROM public.perfiles p
  WHERE p.id = ANY(p_medico_ids) AND p.rol = 'medico'
    AND NOT EXISTS (SELECT 1 FROM public.medicos m WHERE m.id = p.id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.contar_medicos_por_ids(p_medico_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_count INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'no autenticado' USING ERRCODE = 'PC027';
  END IF;
  SELECT COUNT(*) INTO v_count FROM public.medicos WHERE id = ANY(p_medico_ids);
  RETURN v_count;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.listar_medicos_por_pais(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.contar_medicos_por_pais(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.obtener_medicos_por_ids(uuid[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.contar_medicos_por_ids(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_medicos_por_pais(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.contar_medicos_por_pais(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obtener_medicos_por_ids(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.contar_medicos_por_ids(uuid[]) TO authenticated;

DO $$
DECLARE
  v_bad int;
BEGIN
  SELECT count(*) INTO v_bad
  FROM pg_proc
  WHERE proname IN ('listar_medicos_por_pais','contar_medicos_por_pais','obtener_medicos_por_ids','contar_medicos_por_ids')
    AND pronamespace = 'public'::regnamespace
    AND (proconfig IS NULL OR NOT EXISTS (SELECT 1 FROM unnest(proconfig) x WHERE x LIKE 'search_path=%'));
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'autochequeo: % funciones sin search_path fijado', v_bad;
  END IF;

  SELECT count(*) INTO v_bad
  FROM pg_proc
  WHERE proname IN ('listar_medicos_por_pais','contar_medicos_por_pais')
    AND pronamespace = 'public'::regnamespace
    AND pg_get_functiondef(oid) NOT LIKE '%OR m.pais_id IS NULL%'
    AND pg_get_functiondef(oid) NOT LIKE '%OR p.pais_id IS NULL%'
    AND pg_get_functiondef(oid) LIKE '%mi_pais_viewer%'
    AND pg_get_functiondef(oid) LIKE '%medico_clinicas%';
  IF v_bad <> 2 THEN
    RAISE EXCEPTION 'autochequeo: no quedaron las 2 funciones con el gate nuevo completo (got %)', v_bad;
  END IF;

  SELECT count(*) INTO v_bad
  FROM pg_proc
  WHERE proname IN ('obtener_medicos_por_ids','contar_medicos_por_ids')
    AND pronamespace = 'public'::regnamespace
    AND pg_get_functiondef(oid) LIKE '%auth.uid() IS NULL%';
  IF v_bad <> 2 THEN
    RAISE EXCEPTION 'autochequeo: no quedaron las 2 funciones de ids con el guard de auth (got %)', v_bad;
  END IF;

  RAISE NOTICE 'autochequeo OK';
END $$;
