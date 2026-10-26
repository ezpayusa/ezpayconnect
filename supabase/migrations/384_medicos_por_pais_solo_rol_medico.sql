-- =====================================================================================================================
-- MIG 384 — listar_medicos_por_pais / contar_medicos_por_pais: la fuente `medicos` exige perfiles.rol = 'medico'.
-- Recon del 26-oct-2026 contra el objeto vivo (output/diseno-registro-clinica-26oct.md y su parada).
--
-- Por qué: una fila en `medicos` NO significa "es médico". crear-staff-clinica (y la siembra QA) crean una para todo el
-- staff de clínica porque medico_clinicas.medico_id tiene FK a `medicos`. La mig 299 cerró eso en
-- buscar_medicos_paciente y listar_especialidades_activas, pero no en estas dos. Medido el 26-oct como clinica.qa:
-- listar_medicos_por_pais(GT) devolvía 5 filas con clinica.qa (admin_clinica) entre ellas, y contar_medicos_por_pais(GT)
-- daba 5 (4 médicos + 1 admin_clinica). secretaria.qa quedaba afuera solo por tener medicos.pais_id NULL.
-- Las dos son prerequisito de la mig 385 (registro de clínica por invitación), que crea un admin_clinica con fila en
-- `medicos` y país.
--
-- Único cambio en cada cuerpo: el MISMO predicado de la mig 299, copiado de la función viva
-- public.buscar_medicos_paciente(uuid) (fuente 1):
--     AND EXISTS (SELECT 1 FROM perfiles pf_rol WHERE pf_rol.id = m.id AND pf_rol.rol = 'medico')
-- con `perfiles` calificado como `public.perfiles`: buscar_medicos_paciente corre con search_path = public y estas dos
-- con search_path = '' (regla 13). En contar_medicos_por_pais el FROM no tenía alias: se agrega `m`
-- (`FROM public.medicos m`) para que el predicado quede textual; `pais_id` sigue resolviendo a la misma columna.
-- Firma, retorno, volatilidad, SECURITY DEFINER, search_path, ACL y el gate de país (PC025/PC026) quedan iguales.
--
-- Técnica (patrón de la 347): el prosrc vivo de las dos tiene CRLF y el repo exige LF. El cuerpo nuevo se arma con
-- replace() sobre pg_get_functiondef() vivo, insertando el predicado con su CRLF, y se ejecuta con EXECUTE; se verifica
-- el md5 de partida, que el fragmento aparezca una sola vez y el md5 del resultado antes de ejecutar.
--
-- md5(prosrc):  listar_medicos_por_pais  489479f0f952afde7fd353f3b70c6d58 -> 838b41eb8b782f7a54d88d60b0c725ff
--               contar_medicos_por_pais  4d7ebf5dd516e7d83985df8347d7ba04 -> 2eb35e1dcc8e864314048570c51e63c2
-- Huellas medidas el 26-oct-2026 17:16:24 UTC (y otra vez 17:32:32, iguales):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ........ 0dca24ee3969b2fe56f98349b178663f 411
--   funciones completas SIN estas 2 ................................................ 371990da475778c83460c7035064b0ec 409
--   ACL de funciones (solo privilegios), public/private ............................ af6b7bf22f370f6ee5ff89ff59eb0ea5 411
--   ACL de relaciones de public ..................................................... 9b8f5af8892d3a5b87db15e15092eb77 2445
--   policies public/private/storage ................................................. 938d7e4111a9d332e6c55a645fafed86 314
-- Después: solo se mueve "funciones completas" (por estas 2); las otras tres quedan idénticas.
--
-- Consumidores en el front (ninguno necesita un no-médico; 0 citas con medico_id de un no-médico, medido el 26-oct):
--   src/pages/CitasPage.tsx:188 (selector de médico al crear cita), src/clinica/hooks/useClinicaCitas.ts:84 (médicos de
--   la clínica para asignar a una cita), src/pages/admin-ezpay/PaisDashboardPage.tsx:114 (tarjeta "Médicos").
--   Ninguna función, policy ni vista de la base las llama.
-- Sin errcodes nuevos. MIG84 = guarda de esta migración.
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/384_medicos_por_pais_solo_rol_medico.sql
-- Rollback: supabase/migrations/384_rollback.sql (cadena: 385_rollback -> 384_rollback -> 383_rollback -> ...).
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- a) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.listar_medicos_por_pais(uuid)', '489479f0f952afde7fd353f3b70c6d58',
       'TABLE(id uuid, nombre_completo text, especialidad text, foto_url text, activo boolean, pais_id uuid)'),
      ('public.contar_medicos_por_pais(uuid)', '4d7ebf5dd516e7d83985df8347d7ba04', 'integer')) AS t(firma, md5_vivo, ret)
  LOOP
    IF to_regprocedure(r.firma) IS NULL THEN
      bad := bad||r.firma||' no existe; ';
      CONTINUE;
    END IF;
    -- md5(prosrc) del cuerpo vivo, rotulado por función
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_vivo THEN bad := bad||r.firma||' md5(prosrc) '||COALESCE(v, '-')||'; '; END IF;
    -- el filtro no tiene que estar todavía
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma) AND p.prosrc LIKE $l$%pf_rol.rol = 'medico'%$l$) THEN
      bad := bad||r.firma||' ya tiene el filtro por rol (384 aplicada); ';
    END IF;
    -- forma que tiene que conservar
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)
                     AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']
                     AND p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
                     AND pg_get_function_result(p.oid) = r.ret) THEN
      bad := bad||r.firma||' secdef/config/ACL/retorno distintos de los medidos; ';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname IN ('listar_medicos_por_pais', 'contar_medicos_por_pais')) <> 2 THEN
    bad := bad||'sobrecargas de las 2 funciones; ';
  END IF;

  -- huellas (26-oct-2026 17:16:24 UTC)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid NOT IN ('public.listar_medicos_por_pais(uuid)'::regprocedure, 'public.contar_medicos_por_pais(uuid)'::regprocedure));
  IF v IS DISTINCT FROM '371990da475778c83460c7035064b0ec 409' THEN bad := bad||'huella de funciones completas sin las 2 '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'af6b7bf22f370f6ee5ff89ff59eb0ea5 411' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9b8f5af8892d3a5b87db15e15092eb77 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '938d7e4111a9d332e6c55a645fafed86 314' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG84: precondición: %', bad USING ERRCODE = 'MIG84';
  END IF;
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- b) CAMBIO: CREATE OR REPLACE (misma firma y retorno: conserva oid y ACL) con el predicado de la 299
-- ---------------------------------------------------------------------------------------------------------------------
DO $cambio$
DECLARE
  r record; v_def text; v_src text; v_new text; n int;
  v_pred text := $p$    AND EXISTS (SELECT 1 FROM public.perfiles pf_rol WHERE pf_rol.id = m.id AND pf_rol.rol = 'medico')$p$;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.listar_medicos_por_pais(uuid)',
       $o$  WHERE m.pais_id = v_pais AND m.activo = true$o$ || E'\r\n',
       $o$  WHERE m.pais_id = v_pais AND m.activo = true$o$ || E'\r\n' || v_pred || E'\r\n',
       '32e3b6e492cddded25474300f7af4066'),
      ('public.contar_medicos_por_pais(uuid)',
       $o$  SELECT COUNT(*) INTO v_count FROM public.medicos WHERE pais_id = p_pais_id;$o$ || E'\r\n',
       $o$  SELECT COUNT(*) INTO v_count FROM public.medicos m WHERE pais_id = p_pais_id$o$ || E'\r\n' || v_pred || E';\r\n',
       '6827d5528213e8d827ea23bc00f929db')) AS t(firma, viejo, nuevo, md5_def_nueva)
  LOOP
    SELECT pg_get_functiondef(p.oid), p.prosrc INTO v_def, v_src FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma);
    n := (length(v_src) - length(replace(v_src, r.viejo, ''))) / length(r.viejo);
    IF n <> 1 THEN
      RAISE EXCEPTION 'MIG84: % el fragmento a reemplazar aparece % veces (se esperaba 1)', r.firma, n USING ERRCODE = 'MIG84';
    END IF;
    v_new := replace(v_def, r.viejo, r.nuevo);
    IF md5(v_new) IS DISTINCT FROM r.md5_def_nueva THEN
      RAISE EXCEPTION 'MIG84: % la definición armada no es la esperada (md5 %)', r.firma, md5(v_new) USING ERRCODE = 'MIG84';
    END IF;
    EXECUTE v_new;
  END LOOP;
END $cambio$;

-- ---------------------------------------------------------------------------------------------------------------------
-- c) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.listar_medicos_por_pais(uuid)', '838b41eb8b782f7a54d88d60b0c725ff',
       'TABLE(id uuid, nombre_completo text, especialidad text, foto_url text, activo boolean, pais_id uuid)'),
      ('public.contar_medicos_por_pais(uuid)', '2eb35e1dcc8e864314048570c51e63c2', 'integer')) AS t(firma, md5_nuevo, ret)
  LOOP
    v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma));
    IF v IS DISTINCT FROM r.md5_nuevo THEN bad := bad||r.firma||' md5(prosrc) '||COALESCE(v, '-')||'; '; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)
                     AND p.prosrc LIKE $l$%AND EXISTS (SELECT 1 FROM public.perfiles pf_rol WHERE pf_rol.id = m.id AND pf_rol.rol = 'medico')%$l$) THEN
      bad := bad||r.firma||' sin el predicado por rol; ';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)
                     AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']
                     AND p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
                     AND pg_get_function_result(p.oid) = r.ret) THEN
      bad := bad||r.firma||' cambió secdef/config/ACL/retorno; ';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname IN ('listar_medicos_por_pais', 'contar_medicos_por_pais')) <> 2 THEN
    bad := bad||'sobrecargas de las 2 funciones; ';
  END IF;

  -- funciones completas: solo se movieron estas 2
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
           AND f.oid NOT IN ('public.listar_medicos_por_pais(uuid)'::regprocedure, 'public.contar_medicos_por_pais(uuid)'::regprocedure));
  IF v IS DISTINCT FROM '371990da475778c83460c7035064b0ec 409' THEN bad := bad||'cambió otra función (funciones completas sin las 2) '||COALESCE(v, '-')||'; '; END IF;
  -- ACL de funciones, ACL de relaciones de public y policies: idénticas a las de 17:16:24 UTC
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM 'af6b7bf22f370f6ee5ff89ff59eb0ea5 411' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '9b8f5af8892d3a5b87db15e15092eb77 2445' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '938d7e4111a9d332e6c55a645fafed86 314' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG84: autochequeo: %', bad USING ERRCODE = 'MIG84';
  END IF;
END $autochequeo$;

COMMIT;
