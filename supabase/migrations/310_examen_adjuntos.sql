-- ############################################################################################
-- 310 — examen_adjuntos: adjuntos multiples por examen
-- ############################################################################################
-- Frente 3 de la cola de Fase 4. Diseno cerrado por Oscar el 20-sep sobre el recon del mismo dia.
--
-- QUE HAY HOY: `examenes.archivo_url text` guarda UN solo path del bucket privado
-- `resultados-examenes` (medido: las 6 filas con archivo guardan PATH PELADO, ninguna URL
-- completa; formato `<empresa_uuid>/<examen_id>-<epoch>.<ext>`). Un examen con dos PDFs no se
-- puede representar.
--
-- ORDEN DE LAS PIEZAS (importa):
--   1. private.puede_ver_examen()      — el predicado de lectura, en UN solo lugar
--   2. public.examen_adjuntos          — la tabla, RLS ENABLE + FORCE, solo policy de SELECT
--   3. resultados_scoped_select        — deja de repetirlo inline, lo llama, y suma la rama
--                                        de adjuntos (sin ella un adjunto se sube y no se abre).
--                                        Va DESPUES de la tabla: el USING la nombra.
--   4. registrar_examen_adjunto()      — la UNICA via de escritura (SECURITY DEFINER)
--   5. resultados_scoped_delete        — borrar solo objetos que NADIE referencia
--   6. hardening del bucket            — limite de tamanio y mime types
--
-- ERRCODES QUE GASTA: PE002 (adjuntar sobre examen ya liberado) y PE003 (no autenticado).
--   PE003 es NUEVO. El "no autenticado" del frente #7 es PC027, pero PC es la familia de
--   capacidades/pais y se acunio para las RPCs de medicos; reusarlo aca dejaria al front sin
--   forma de distinguir de que modulo viene el error. La familia de este frente es PE
--   (expediente, abierta por la mig 291 con PE001). Proximo PE libre despues de esta: PE004.
-- ############################################################################################


-- ============================================================================================
-- 1) private.puede_ver_examen(integer)
-- ============================================================================================
-- Encapsula, sin cambiarlo, el predicado que hoy vive inline dentro de resultados_scoped_select.
-- Lo van a consultar DOS lugares (esa policy y la de examen_adjuntos) y tenerlo escrito dos veces
-- es la forma de que se separen con el tiempo.
--
-- SECURITY DEFINER no es decorativo, pero SI cambia una cosa y conviene tenerlo escrito: el
-- EXISTS inline se evalua con los privilegios del LLAMANTE, asi que la RLS de `examenes` tambien
-- filtraba; adentro de una funcion DEFINER que corre como `postgres` (rolbypassrls=true) no.
-- El autochequeo de abajo compara las dos formas 1 a 1 contra los datos vivos justamente por eso.
--
-- COALESCE obligatorio: sin el, un examen inexistente devuelve NULL y cualquier `IF NOT ...`
-- rio abajo cae en el fail-open trivaluado que cerro la mig 300.
CREATE OR REPLACE FUNCTION private.puede_ver_examen(p_examen_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT COALESCE((
    SELECT (private.paciente_es_mio((e.paciente_id)::bigint) AND e.liberado_al_paciente)
        OR (e.medico_id = auth.uid())
        OR private.medico_atiende_paciente((e.paciente_id)::bigint)
        OR ((e.clinica_id IS NOT NULL) AND private.es_admin_clinica(e.clinica_id))
        OR (e.laboratorio_id = public.mi_empresa_proveedor())
        OR private.tiene_rol(ARRAY['super_admin'::text])
      FROM public.examenes e
     WHERE e.id = p_examen_id
  ), false)
$fn$;

REVOKE ALL ON FUNCTION private.puede_ver_examen(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.puede_ver_examen(integer) TO authenticated;

-- -------- AUTOCHEQUEO 1: helper vs predicado inline, 1 a 1 sobre los datos vivos --------
-- Cada actor se impersona y se evaluan LAS DOS formas. Si alguna pareja difiere, aborta ANTES
-- de tocar la policy: un refactor que amplie o recorte lectura sobre datos medicos no se aplica.
DO $ac1$
DECLARE
  a record; e record;
  v_in boolean; v_hp boolean;
  v_pares int := 0; v_div int := 0; v_err int := 0;
  v_detalle text := '';
  v_resumen text := '';
BEGIN
  -- Cada rama va ENTRE PARENTESIS: un ORDER BY/LIMIT suelto antes de UNION ALL es 42601.
  FOR a IN
    (SELECT 'super_admin' AS rot, p.id AS uid FROM public.perfiles p
      WHERE p.rol='super_admin' AND p.activo ORDER BY p.id LIMIT 1)
    UNION ALL
    (SELECT 'admin_clinica', p.id FROM public.perfiles p
      WHERE p.rol='admin_clinica' AND p.activo ORDER BY p.id LIMIT 1)
    UNION ALL
    (SELECT 'medico_a', p.id FROM public.perfiles p
      WHERE p.rol='medico' AND p.activo ORDER BY p.id LIMIT 1)
    UNION ALL
    (SELECT 'medico_b', p.id FROM public.perfiles p
      WHERE p.rol='medico' AND p.activo ORDER BY p.id OFFSET 2 LIMIT 1)
    UNION ALL
    (SELECT 'paciente', p.auth_user_id FROM public.pacientes p
      WHERE p.auth_user_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM public.examenes e2 WHERE e2.paciente_id = p.id)
      ORDER BY p.id LIMIT 1)
    UNION ALL
    (SELECT 'lab_duenio', cp.id FROM public.cuentas_proveedor cp
      WHERE cp.activo AND cp.empresa_id = (
        SELECT e3.laboratorio_id FROM public.examenes e3
         WHERE e3.laboratorio_id IS NOT NULL
         GROUP BY e3.laboratorio_id ORDER BY count(*) DESC, e3.laboratorio_id LIMIT 1)
      ORDER BY cp.id LIMIT 1)
  LOOP
    CONTINUE WHEN a.uid IS NULL;
    FOR e IN SELECT id FROM public.examenes ORDER BY id LOOP
      v_in := NULL; v_hp := NULL;
      BEGIN
        PERFORM set_config('request.jwt.claims',
          json_build_object('sub', a.uid, 'role', 'authenticated')::text, true);
        PERFORM set_config('role', 'authenticated', true);

        SELECT EXISTS (
          SELECT 1 FROM public.examenes ex
           WHERE ex.id = e.id
             AND ( (private.paciente_es_mio((ex.paciente_id)::bigint) AND ex.liberado_al_paciente)
                OR (ex.medico_id = auth.uid())
                OR private.medico_atiende_paciente((ex.paciente_id)::bigint)
                OR ((ex.clinica_id IS NOT NULL) AND private.es_admin_clinica(ex.clinica_id))
                OR (ex.laboratorio_id = public.mi_empresa_proveedor())
                OR private.tiene_rol(ARRAY['super_admin'::text]) )) INTO v_in;

        v_hp := private.puede_ver_examen(e.id);
        PERFORM set_config('role', 'none', true);
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('role', 'none', true);
        v_err := v_err + 1;
        v_detalle := v_detalle || format(' [%s/ex%s ERROR %s]', a.rot, e.id, SQLSTATE);
      END;
      -- NOTA: cualquier escritura va DESPUES del reset de rol. Bajo el rol impersonado una
      -- escritura auxiliar da 42501 y, atrapada, se lee como "coinciden" — falso verde medido
      -- al armar este mismo chequeo.
      v_pares := v_pares + 1;
      IF COALESCE(v_in, false) IS DISTINCT FROM COALESCE(v_hp, false) THEN
        v_div := v_div + 1;
        v_detalle := v_detalle || format(' [%s/ex%s inline=%s helper=%s]',
                                         a.rot, e.id, COALESCE(v_in::text,'NULL'), COALESCE(v_hp::text,'NULL'));
      END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('request.jwt.claims', '', true);

  IF v_pares = 0 THEN
    RAISE EXCEPTION '310 autochequeo 1: 0 pares evaluados — el chequeo no midio nada';
  END IF;
  IF v_err > 0 THEN
    RAISE EXCEPTION '310 autochequeo 1: % par(es) con ERROR:%', v_err, v_detalle;
  END IF;
  IF v_div > 0 THEN
    RAISE EXCEPTION '310 autochequeo 1: el helper NO reproduce el predicado inline en % de % pares:%',
      v_div, v_pares, v_detalle;
  END IF;

  v_resumen := format('OK (%s pares actor x examen, 0 errores, 0 divergencias)', v_pares);
  PERFORM set_config('m310.ac1', v_resumen, true);
END $ac1$;


-- ============================================================================================
-- 2) public.examen_adjuntos
-- ============================================================================================
-- NOTA DE ORDEN: la tabla va ANTES del refactor de la policy. El USING nuevo referencia
-- public.examen_adjuntos, y un CREATE POLICY que nombra una tabla inexistente falla con 42P01
-- (medido en el dry-run, no supuesto).
-- FORCE ROW LEVEL SECURITY: hoy NINGUNA tabla de `public` lo tiene (medido), asi que esta es la
-- primera. Ojo con lo que FORCE hace y lo que no: alcanza al DUENIO de la tabla, pero NO a un rol
-- con `rolbypassrls`, y `postgres` lo tiene. O sea que la RPC SECURITY DEFINER de abajo sigue
-- pudiendo insertar (probado, no supuesto: probe P783). Lo que FORCE aporta es que si manana la
-- tabla cambia de duenio, o una migracion corre con un rol sin bypassrls, la RLS sigue en pie.
CREATE TABLE public.examen_adjuntos (
  id           bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  examen_id    integer     NOT NULL REFERENCES public.examenes(id) ON DELETE CASCADE,
  storage_path text        NOT NULL,
  mime_type    text,
  subido_por   uuid,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_examen_adjuntos_examen ON public.examen_adjuntos (examen_id);
-- El mismo objeto no se adjunta dos veces al mismo examen.
CREATE UNIQUE INDEX ux_examen_adjuntos_path ON public.examen_adjuntos (examen_id, storage_path);

ALTER TABLE public.examen_adjuntos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.examen_adjuntos FORCE ROW LEVEL SECURITY;

-- Toda tabla nueva en `public` nace con ALL a `authenticated` por default privileges. Sin este
-- REVOKE la tabla nace escribible y la unica barrera seria la ausencia de policy.
REVOKE ALL ON public.examen_adjuntos FROM PUBLIC;
REVOKE ALL ON public.examen_adjuntos FROM anon;
REVOKE ALL ON public.examen_adjuntos FROM authenticated;
GRANT SELECT ON public.examen_adjuntos TO authenticated;

-- Unica policy. Sin INSERT/UPDATE/DELETE: la escritura entra por la RPC de abajo, mismo patron
-- que visitas_comerciales. Lo que no tiene policy queda negado por default.
CREATE POLICY examen_adjuntos_select ON public.examen_adjuntos
  FOR SELECT TO authenticated
  USING (private.puede_ver_examen(examen_id));


-- ============================================================================================
-- 3) resultados_scoped_select — llama al helper en vez de repetir el predicado
-- ============================================================================================
-- El USING es el mismo salvo esa sustitucion: sigue el brazo de tenant por prefijo de path y
-- sigue el mismo join a `examenes` con el mismo COALESCE(NULLIF(split_part(...))), que es lo que
-- tolera tanto el path pelado (lo que hay hoy) como una URL completa historica.
DROP POLICY IF EXISTS resultados_scoped_select ON storage.objects;

CREATE POLICY resultados_scoped_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'resultados-examenes'
    AND (
      split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
      OR EXISTS (
        SELECT 1 FROM public.examenes e
         WHERE COALESCE(NULLIF(split_part(e.archivo_url, '/resultados-examenes/', 2), ''), e.archivo_url) = storage.objects.name
           AND private.puede_ver_examen(e.id))
      -- Rama de ADJUNTOS. Sin ella un adjunto se puede subir pero NO abrir: el paciente y el
      -- medico no entran por el brazo de tenant (su mi_empresa_proveedor() no es la del lab) y
      -- el join a `examenes` no los alcanza, porque un adjunto NO vive en examenes.archivo_url.
      -- Misma autoridad que las otras dos ramas: la decide el mismo helper.
      OR EXISTS (
        SELECT 1 FROM public.examen_adjuntos a
         WHERE a.storage_path = storage.objects.name
           AND private.puede_ver_examen(a.examen_id))
    )
  );

-- -------- AUTOCHEQUEO 2: la policy nueva conserva join y COALESCE, y llama al helper --------
DO $ac2$
DECLARE v_using text; v_cmd "char";
BEGIN
  SELECT pg_get_expr(pol.polqual, pol.polrelid), pol.polcmd INTO v_using, v_cmd
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname='storage' AND c.relname='objects' AND pol.polname='resultados_scoped_select';

  IF v_using IS NULL THEN
    RAISE EXCEPTION '310 autochequeo 2: resultados_scoped_select no existe';
  END IF;
  IF v_cmd <> 'r' THEN
    RAISE EXCEPTION '310 autochequeo 2: la policy no es SELECT (polcmd=%)', v_cmd;
  END IF;
  IF v_using NOT LIKE '%puede_ver_examen%' THEN
    RAISE EXCEPTION '310 autochequeo 2: la policy no llama al helper';
  END IF;
  IF v_using LIKE '%paciente_es_mio%' OR v_using LIKE '%medico_atiende_paciente%' THEN
    RAISE EXCEPTION '310 autochequeo 2: el predicado sigue inline (quedo duplicado)';
  END IF;
  IF v_using NOT LIKE '%FROM examenes e%' THEN
    RAISE EXCEPTION '310 autochequeo 2: se perdio el join a examenes';
  END IF;
  IF v_using NOT LIKE '%/resultados-examenes/%' OR v_using NOT LIKE '%split_part%' THEN
    RAISE EXCEPTION '310 autochequeo 2: se perdio el COALESCE(NULLIF(split_part(...)))';
  END IF;
  IF v_using NOT LIKE '%mi_empresa_proveedor%' THEN
    RAISE EXCEPTION '310 autochequeo 2: se perdio el brazo de tenant por prefijo';
  END IF;
  -- Sin la rama de adjuntos la feature sube archivos que despues nadie puede abrir.
  IF v_using NOT LIKE '%examen_adjuntos%' THEN
    RAISE EXCEPTION '310 autochequeo 2: falta la rama de examen_adjuntos en el USING';
  END IF;

  PERFORM set_config('m310.ac2',
    'OK (SELECT, llama al helper, sin predicado duplicado, conserva join + COALESCE + tenant, con rama de adjuntos)', true);
END $ac2$;


-- ============================================================================================
-- 4) public.registrar_examen_adjunto(integer, text, text)
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.registrar_examen_adjunto(
  p_examen_id    integer,
  p_storage_path text,
  p_mime_type    text DEFAULT NULL
) RETURNS public.examen_adjuntos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid;
  v_lab uuid;
  v_liberado boolean;
  v_fila public.examen_adjuntos;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = 'PE003';
  END IF;

  IF p_storage_path IS NULL OR btrim(p_storage_path) = '' THEN
    RAISE EXCEPTION 'storage_path requerido' USING ERRCODE = 'PE003';
  END IF;

  SELECT e.laboratorio_id, e.liberado_al_paciente
    INTO v_lab, v_liberado
    FROM public.examenes e
   WHERE e.id = p_examen_id;

  -- Fail-closed: si el examen no existe, NOT FOUND y se corta aca. Sin esto, v_lab queda NULL y
  -- la comparacion de abajo daria NULL, que es justo el trivaluado de la mig 300.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(v_lab = public.mi_empresa_proveedor()
                  OR private.tiene_rol(ARRAY['super_admin'::text]), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  -- Se chequea DESPUES de la autoridad, a proposito: a quien no es duenio del examen no se le
  -- revela si ese examen esta liberado o no.
  IF COALESCE(v_liberado, false) THEN
    RAISE EXCEPTION 'El examen ya fue liberado al paciente: no admite adjuntos nuevos'
      USING ERRCODE = 'PE002';
  END IF;

  INSERT INTO public.examen_adjuntos (examen_id, storage_path, mime_type, subido_por)
  VALUES (p_examen_id, btrim(p_storage_path), p_mime_type, v_uid)
  RETURNING * INTO v_fila;

  RETURN v_fila;
END;
$fn$;

REVOKE ALL ON FUNCTION public.registrar_examen_adjunto(integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.registrar_examen_adjunto(integer, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_examen_adjunto(integer, text, text) TO authenticated;

-- -------- AUTOCHEQUEO 3: tabla, RLS, grants y firma de la RPC --------
DO $ac3$
DECLARE
  v_rls boolean; v_force boolean; v_pol int; v_n int; v_acl text;
BEGIN
  SELECT c.relrowsecurity, c.relforcerowsecurity INTO v_rls, v_force
    FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname='public' AND c.relname='examen_adjuntos';
  IF v_rls IS NULL THEN
    RAISE EXCEPTION '310 autochequeo 3: examen_adjuntos no existe';
  END IF;
  IF NOT v_rls OR NOT v_force THEN
    RAISE EXCEPTION '310 autochequeo 3: RLS enabled=% forced=% (se esperaba true/true)', v_rls, v_force;
  END IF;

  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE schemaname='public' AND tablename='examen_adjuntos';
  IF v_pol <> 1 THEN
    RAISE EXCEPTION '310 autochequeo 3: examen_adjuntos tiene % policies, se esperaba 1 (solo SELECT)', v_pol;
  END IF;
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='examen_adjuntos' AND cmd <> 'SELECT';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '310 autochequeo 3: apareció una policy de escritura en examen_adjuntos';
  END IF;

  -- authenticated: SELECT y nada mas. anon: nada.
  SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type) INTO v_acl
    FROM information_schema.role_table_grants g
   WHERE g.table_schema='public' AND g.table_name='examen_adjuntos' AND g.grantee='authenticated';
  IF COALESCE(v_acl,'') <> 'SELECT' THEN
    RAISE EXCEPTION '310 autochequeo 3: authenticated tiene "%" sobre examen_adjuntos, se esperaba SELECT', COALESCE(v_acl,'(nada)');
  END IF;
  SELECT count(*) INTO v_n FROM information_schema.role_table_grants g
   WHERE g.table_schema='public' AND g.table_name='examen_adjuntos' AND g.grantee='anon';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '310 autochequeo 3: anon quedo con % privilegio(s) sobre examen_adjuntos', v_n;
  END IF;

  -- la RPC: existe, es DEFINER, con search_path vacio, y anon no la ejecuta
  -- `SET search_path = ''` se guarda en proconfig como `search_path=""` CON comillas; buscar
  -- `search_path=` a secas da 0 y el chequeo falla con la funcion bien definida.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='registrar_examen_adjunto'
     AND p.prosecdef
     AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg
                  WHERE cfg IN ('search_path=""', 'search_path='));
  IF v_n <> 1 THEN
    RAISE EXCEPTION '310 autochequeo 3: registrar_examen_adjunto no quedo SECURITY DEFINER con search_path=''''';
  END IF;
  IF has_function_privilege('anon', 'public.registrar_examen_adjunto(integer,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION '310 autochequeo 3: anon puede ejecutar registrar_examen_adjunto';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.registrar_examen_adjunto(integer,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION '310 autochequeo 3: authenticated NO puede ejecutar registrar_examen_adjunto';
  END IF;

  PERFORM set_config('m310.ac3',
    'OK (tabla con RLS enabled+forced, 1 sola policy y es SELECT, authenticated=SELECT, anon=0, RPC DEFINER sp='''' sin anon)', true);
END $ac3$;


-- ============================================================================================
-- 5) resultados_scoped_delete — borrar solo lo que NADIE referencia
-- ============================================================================================
-- Hoy el bucket no tiene NINGUNA policy de DELETE: nadie puede borrar por RLS. Esta es nueva.
-- Mismo check de tenant que insert/update, y ademas las dos negativas: el objeto no puede estar
-- referenciado ni por examen_adjuntos ni por examenes.archivo_url.
--
-- La segunda negativa repite el COALESCE(NULLIF(split_part(...))) de la policy de SELECT a
-- proposito. Comparar `e.archivo_url = objects.name` pelado daria por NO referenciada una fila
-- historica que guardara la URL completa, y habilitaria borrar un archivo vivo.
CREATE POLICY resultados_scoped_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'resultados-examenes'
    AND ( split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
          OR private.tiene_rol(ARRAY['super_admin'::text]) )
    AND NOT EXISTS (
      SELECT 1 FROM public.examen_adjuntos a
       WHERE a.storage_path = storage.objects.name)
    AND NOT EXISTS (
      SELECT 1 FROM public.examenes e
       WHERE COALESCE(NULLIF(split_part(e.archivo_url, '/resultados-examenes/', 2), ''), e.archivo_url) = storage.objects.name)
  );

-- -------- AUTOCHEQUEO 4: la DELETE existe y trae las dos negativas --------
DO $ac4$
DECLARE v_using text; v_n int;
BEGIN
  SELECT pg_get_expr(pol.polqual, pol.polrelid) INTO v_using
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname='storage' AND c.relname='objects' AND pol.polname='resultados_scoped_delete'
     AND pol.polcmd = 'd';
  IF v_using IS NULL THEN
    RAISE EXCEPTION '310 autochequeo 4: resultados_scoped_delete no existe o no es DELETE';
  END IF;
  IF v_using NOT LIKE '%examen_adjuntos%' THEN
    RAISE EXCEPTION '310 autochequeo 4: falta la negativa sobre examen_adjuntos';
  END IF;
  IF v_using NOT LIKE '%/resultados-examenes/%' THEN
    RAISE EXCEPTION '310 autochequeo 4: la negativa sobre examenes no usa el COALESCE(split_part(...))';
  END IF;
  IF v_using NOT LIKE '%mi_empresa_proveedor%' THEN
    RAISE EXCEPTION '310 autochequeo 4: falta el check de tenant';
  END IF;

  -- las 3 policies viejas del bucket siguen en pie, ahora son 4
  SELECT count(*) INTO v_n FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname='storage' AND c.relname='objects'
     AND pol.polname IN ('resultados_scoped_select','resultados_scoped_insert',
                         'resultados_scoped_update','resultados_scoped_delete');
  IF v_n <> 4 THEN
    RAISE EXCEPTION '310 autochequeo 4: el bucket tiene % policies resultados_*, se esperaban 4', v_n;
  END IF;

  PERFORM set_config('m310.ac4','OK (DELETE con tenant + 2 negativas; 4 policies resultados_*)', true);
END $ac4$;


-- ============================================================================================
-- 6) Hardening del bucket — PENDIENTE DE CONFIRMAR POR OSCAR
-- ============================================================================================
-- Hoy los dos campos estan en NULL, o sea sin limite y cualquier mime type, sobre un bucket que
-- guarda resultados medicos. Valores PROPUESTOS a partir de lo que ya circula (medido: 6 objetos,
-- application/pdf entre 4 KB y 99 KB, e image/jpeg de 57 KB y 68 KB):
--   file_size_limit    20 MB — holgado para un PDF escaneado de varias paginas sin volverse un
--                              canal de subida de cualquier cosa.
--   allowed_mime_types pdf + jpeg + png. `png` no aparece en los datos de hoy; entra porque es lo
--                              que produce una captura de pantalla, que es un camino realista.
-- OJO si se confirma: a partir de este UPDATE, una subida con otro mime type falla en el gateway
-- de storage. Los 6 objetos existentes NO se revalidan, pero cualquier reintento de subida de un
-- formato distinto (heic de iPhone, tiff de un equipo de laboratorio) empieza a fallar.
UPDATE storage.buckets
   SET file_size_limit    = 20971520,
       allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png']
 WHERE id = 'resultados-examenes';

DO $ac5$
DECLARE v_lim bigint; v_mimes text;
BEGIN
  SELECT b.file_size_limit, array_to_string(b.allowed_mime_types, ',')
    INTO v_lim, v_mimes
    FROM storage.buckets b WHERE b.id = 'resultados-examenes';
  IF v_lim IS NULL OR v_mimes IS NULL THEN
    RAISE EXCEPTION '310 autochequeo 5: el bucket quedo sin limite o sin mime types';
  END IF;
  PERFORM set_config('m310.ac5',
    'OK (file_size_limit=' || v_lim || ' allowed_mime_types=' || v_mimes || ')', true);
END $ac5$;


-- ============================================================================================
-- RESUMEN de los 5 autochequeos (el RAISE NOTICE no lo expone la Management API)
-- ============================================================================================
DO $fin$
BEGIN
  PERFORM set_config('m310.auto',
    'AC1 ' || COALESCE(current_setting('m310.ac1', true), 'FALTA') ||
    ' || AC2 ' || COALESCE(current_setting('m310.ac2', true), 'FALTA') ||
    ' || AC3 ' || COALESCE(current_setting('m310.ac3', true), 'FALTA') ||
    ' || AC4 ' || COALESCE(current_setting('m310.ac4', true), 'FALTA') ||
    ' || AC5 ' || COALESCE(current_setting('m310.ac5', true), 'FALTA'), true);
  RAISE NOTICE '310 OK';
END $fin$;
