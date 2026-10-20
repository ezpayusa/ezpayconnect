-- ############################################################################################
-- 376 - administrar_visita('modificar') compila: cast explicito a time de las horas + PV003
-- ############################################################################################
-- Recon: 20-oct-2026, solo lectura, sobre prod (C:\tmp\mig376\: administrar_visita_vivo.sql = pg_get_functiondef vivo,
--   r1-r6.sql). Estado vivo medido:
--   - administrar_visita(uuid, text, date, text, text, text) RETURNS jsonb, plpgsql VOLATILE, SECURITY DEFINER,
--     search_path = '', dueno postgres, ACL {postgres, authenticated, service_role}; md5(prosrc) 666800e7be6ccee444632f933d5146c0.
--   - Acciones: aprobar, rechazar, modificar; otra -> {error:'Accion no valida'}. Sin errcodes propios: el unico RAISE
--     ('No autorizado para administrar esta visita') sale como P0001.
--   - 'modificar' hace hora_inicio = COALESCE(p_nueva_hora_inicio, hora_inicio) con el parametro text y la columna time:
--     42804 al planificar el UPDATE, para cualquier llamada a 'modificar' (tambien solo con fecha). Probado en ROLLBACK
--     con proveedor.qa y con un super_admin: aprobar, rechazar y la accion invalida andan; modificar da 42804 siempre.
--   - Unico llamador: src/proveedor/hooks/useVisitasAgendadas.ts (AdminAprobarVisitasPage): args con nombre, la fecha de
--     un <input type="date"> ('YYYY-MM-DD') y las horas de un <input type="time"> ('HH:MM'); campo vacio -> null.
--
-- Que cambia (solo 'modificar'; firma, retorno, DEFINER, search_path, dueno y ACL iguales):
--   - p_nueva_hora_inicio / p_nueva_hora_fin se castean a time en el COALESCE.
--   - Antes del UPDATE, una hora no NULL que no sea HH:MM o HH:MM:SS (00-23 / 00-59) da PV003 'La hora debe tener formato
--     HH:MM.'. NULL = sin cambio, asi que 'modificar' solo con fecha anda. La validacion va despues del gate de autorizacion.
--   - Nada mas: aprobar, rechazar, el gate y los retornos jsonb quedan igual.
--
-- Nota: los comentarios de la 375 hablan de administrar_visita('reprogramar'); la accion real es 'modificar'. La 375 esta
--   aplicada y no se edita (anotado en el backlog de CLAUDE.md).
--
-- Numeros: mig 376; errcode PV003 (sin uso en prod ni en el repo, medido el 20-oct-2026; PV001-PV002 y PV010-PV017 en uso);
--   probes P1062-P1064 (P1057-P1059 ajustados). md5(prosrc) 666800e7... -> 5d4a718de9d34fcfcc36e74a0e068bce.
--
-- Privilegios: sin cambio. CREATE OR REPLACE conserva la ACL; el REVOKE/GRANT de abajo la repone identica (documental).
--   Huellas post-375 sin cambio: funciones 9c59aeca.../392, relaciones 1889d1d8.../2393, policies 8a8dc5cf.../309.
--
-- Front: PV003 no esta mapeado (useVisitasAgendadas muestra 'Error administrando visita' para todo lo que no sea
--   'No autorizado'); con <input type="time"> el front no deberia mandar una hora invalida.
--
-- Rollback: 376_rollback.sql. Orden global: 376_rollback -> 375_rollback -> 374_rollback -> ...
-- ############################################################################################

BEGIN;

-- ---------------------------------------------------------------------------- 0: precondiciones
DO $precondicion$
DECLARE bad text := ''; v text;
BEGIN
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'));
  IF v IS DISTINCT FROM '666800e7be6ccee444632f933d5146c0' THEN bad := bad||'administrar_visita md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')||'|'||p.provolatile::text||'|'||
               pg_get_userbyid(p.proowner)||'|'||pg_get_function_result(p.oid)||'|'||pg_get_function_arguments(p.oid)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'));
  IF v IS DISTINCT FROM 'true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|v|postgres|jsonb|p_visita_id uuid, p_accion text, p_nueva_fecha date DEFAULT NULL::date, p_nueva_hora_inicio text DEFAULT NULL::text, p_nueva_hora_fin text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text' THEN
    bad := bad||'administrar_visita firma/DEFINER/config/ACL/dueno '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'administrar_visita') <> 1 THEN bad := bad||'administrar_visita sobrecargada; '; END IF;
  -- la 375 aplicada (md5 de sus 4 funciones, verificados en prod el 20-oct-2026)
  v := (SELECT string_agg(md5(p.prosrc), ',' ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.enrolar_medico(uuid)'), to_regprocedure('public.prioridad_activa(uuid)'),
                         to_regprocedure('public.trg_gate_head_start_lab()'), to_regprocedure('public.trg_medicos_lab_enrolador_inmutable()')));
  IF v IS DISTINCT FROM '58e441f3a68a5f80645f9b8f0452ffca,07c6a62ffa594ebd093eeca1efbea0d8,ba09b4fca04e22fe4c3ec0607691805e,2af30509d27efef4ed649c5785883381' THEN
    bad := bad||'375 no aplicada (md5 de enrolar_medico, prioridad_activa, trg_gate_head_start_lab, trg_medicos_lab_enrolador_inmutable: '||COALESCE(v, '-')||'); ';
  END IF;
  v := (SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.prosrc ~ 'PV003');
  IF v IS DISTINCT FROM NULL THEN bad := bad||'PV003 en ['||COALESCE(v, 'ninguna')||']; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '1889d1d89630994fe0d8faa1c52c4fd8 2393' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '9c59aecab498bbcb54ebe799b2fb6a3d 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG376_PRE FALLA:%', bad; END IF;

  -- huella de TODAS las funciones de public/private salvo administrar_visita (cuerpo, DEFINER, config, ACL):
  -- el autochequeo exige que quede igual (ningun efecto colateral sobre otra funcion)
  CREATE TEMP TABLE mig376_huella ON COMMIT DROP AS
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid <> 'public.administrar_visita(uuid,text,date,text,text,text)'::regprocedure;
END $precondicion$;

-- ---------------------------------------------------------------------------- 1: administrar_visita
CREATE OR REPLACE FUNCTION public.administrar_visita(p_visita_id uuid, p_accion text, p_nueva_fecha date DEFAULT NULL::date, p_nueva_hora_inicio text DEFAULT NULL::text, p_nueva_hora_fin text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_visita RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_visita FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Visita no encontrada');
  END IF;

  -- Revalidación del caller: aprobada_por referencia cuentas_proveedor → quien
  -- administra es la empresa proveedora (supervisor) o super_admin. El médico es
  -- la parte VISITADA, no el aprobador. COALESCE evita el fail-open trivaluado
  -- (mi_empresa_proveedor() NULL ⇒ 'false OR NULL' = NULL ⇒ RAISE saltado).
  -- HARDENING (mig 210): la rama de empresa proveedora ahora exige, además de pertenecer a la
  -- empresa de la visita, poder aprobar visitas (private.puede_aprobar_visitas, fail-closed).
  -- Antes cualquier miembro de la empresa podía administrar; ahora solo roles admin/supervisor/editor.
  IF NOT (
       private.tiene_rol(ARRAY['super_admin'])
    OR (
         COALESCE(public.mi_empresa_proveedor() = v_visita.empresa_id, false)
         AND private.puede_aprobar_visitas()
       )
  ) THEN
    RAISE EXCEPTION 'No autorizado para administrar esta visita';
  END IF;

  -- aprobada_por solo si el caller es proveedor (su uid ∈ cuentas_proveedor);
  -- para super_admin se preserva el valor previo (no viola la FK).
  IF p_accion = 'aprobar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada');
  ELSIF p_accion = 'rechazar' THEN
    UPDATE public.visitas_agendadas
    SET estado = 'rechazada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'rechazada');
  ELSIF p_accion = 'modificar' THEN
    -- mig 376: las horas llegan como text ('HH:MM' del <input type="time"> del front) y las columnas son time. Sin el
    -- cast, COALESCE(text, time) no compilaba (42804) y 'modificar' fallaba siempre, aun cambiando solo la fecha.
    -- Una hora que no es HH:MM (o HH:MM:SS) da PV003 antes del UPDATE; NULL = sin cambio.
    IF p_nueva_hora_inicio IS NOT NULL AND p_nueva_hora_inicio !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' THEN
      RAISE EXCEPTION 'La hora debe tener formato HH:MM.' USING ERRCODE = 'PV003';
    END IF;
    IF p_nueva_hora_fin IS NOT NULL AND p_nueva_hora_fin !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' THEN
      RAISE EXCEPTION 'La hora debe tener formato HH:MM.' USING ERRCODE = 'PV003';
    END IF;
    UPDATE public.visitas_agendadas
    SET fecha_visita = COALESCE(p_nueva_fecha, fecha_visita),
        hora_inicio = COALESCE(p_nueva_hora_inicio::time, hora_inicio),
        hora_fin = COALESCE(p_nueva_hora_fin::time, hora_fin),
        estado = 'confirmada',
        aprobada_por = CASE WHEN public.mi_empresa_proveedor() IS NOT NULL THEN auth.uid() ELSE aprobada_por END,
        fecha_aprobacion = NOW(),
        comentario_admin = COALESCE(p_comentario, comentario_admin)
    WHERE id = p_visita_id;
    v_result := jsonb_build_object('success', true, 'estado', 'confirmada', 'modificado', true);
  ELSE
    RETURN jsonb_build_object('error', 'Acción no válida');
  END IF;

  RETURN v_result;
END;
$function$;

-- ACL identica a la viva {postgres, authenticated, service_role} (CREATE OR REPLACE la conserva; esto es documental)
REVOKE ALL ON FUNCTION public.administrar_visita(uuid, text, date, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.administrar_visita(uuid, text, date, text, text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------- 2: autochequeo
DO $autochequeo$
DECLARE bad text := ''; v text; r_act record; r_ini record;
BEGIN
  v := (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'));
  IF v IS DISTINCT FROM '5d4a718de9d34fcfcc36e74a0e068bce' THEN bad := bad||'administrar_visita md5 '||COALESCE(v, 'no existe')||'; '; END IF;
  v := (SELECT p.prosecdef::text||'|'||COALESCE(p.proconfig::text, '-')||'|'||COALESCE(p.proacl::text, '-')||'|'||p.provolatile::text||'|'||
               pg_get_userbyid(p.proowner)||'|'||pg_get_function_result(p.oid)||'|'||pg_get_function_arguments(p.oid)
          FROM pg_proc p WHERE p.oid = to_regprocedure('public.administrar_visita(uuid,text,date,text,text,text)'));
  IF v IS DISTINCT FROM 'true|{"search_path=\"\""}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|v|postgres|jsonb|p_visita_id uuid, p_accion text, p_nueva_fecha date DEFAULT NULL::date, p_nueva_hora_inicio text DEFAULT NULL::text, p_nueva_hora_fin text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text' THEN
    bad := bad||'administrar_visita firma/DEFINER/config/ACL/dueno '||COALESCE(v, 'no existe')||'; ';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'administrar_visita') <> 1 THEN bad := bad||'administrar_visita sobrecargada; '; END IF;
  v := (SELECT string_agg(f.oid::regprocedure::text, ', ' ORDER BY f.oid::regprocedure::text) FROM pg_proc f WHERE f.prosrc ~ 'ERRCODE = ''PV003''');
  IF v IS DISTINCT FROM 'administrar_visita(uuid,text,date,text,text,text)' THEN bad := bad||'PV003 en ['||COALESCE(v, 'ninguna')||']; '; END IF;
  IF has_function_privilege('anon', 'public.administrar_visita(uuid,text,date,text,text,text)', 'EXECUTE') THEN bad := bad||'anon con EXECUTE; '; END IF;

  -- resto de las funciones intacto (huella del paso 0)
  SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                        COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                        ORDER BY f.oid::regprocedure::text COLLATE "C")) AS h,
         count(*) AS n INTO r_act
    FROM pg_proc f
   WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)
     AND f.oid <> 'public.administrar_visita(uuid,text,date,text,text,text)'::regprocedure;
  SELECT t.h, t.n INTO r_ini FROM pg_temp.mig376_huella t;
  IF r_act.h IS DISTINCT FROM r_ini.h OR r_act.n IS DISTINCT FROM r_ini.n THEN
    bad := bad||'cambio otra funcion: '||COALESCE(r_act.h, '-')||'/'||COALESCE(r_act.n::text, '-')||' vs '||COALESCE(r_ini.h, '-')||'/'||COALESCE(r_ini.n::text, '-')||'; ';
  END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM '8a8dc5cfaf8365f95208fb9e8ba79674 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM '1889d1d89630994fe0d8faa1c52c4fd8 2393' THEN bad := bad||'ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '9c59aecab498bbcb54ebe799b2fb6a3d 392' THEN bad := bad||'ACL de funciones '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN RAISE EXCEPTION 'MIG376_POST FALLA:%', bad; END IF;
END $autochequeo$;

COMMIT;
