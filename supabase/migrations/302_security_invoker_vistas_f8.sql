-- ============================================================================================
-- 302 — las 4 vistas de public que corrian como su dueno pasan a security_invoker
-- ============================================================================================
-- Origen: docs/CENSO_SEGURIDAD_TRANSVERSAL_2026-09-20.md, seccion F8 (hallazgo #1, critico).
--
-- QUE PASABA. Una vista sin `security_invoker` se ejecuta con los privilegios de su DUENO. Estas
-- cuatro son de `postgres`, que tiene `rolbypassrls = true`: la RLS de las tablas base NO se
-- evaluaba. Como ademas `anon` tiene SELECT sobre las cuatro, cualquiera con la key publica —que
-- viaja en el bundle— las leia por REST sin sesion. Medido contra prod el 20-sep:
--
--   GET /rest/v1/v_pacientes_actividad   ->  HTTP 206  Content-Range: 0-0/26   (los 26 pacientes)
--   GET /rest/v1/v_estadisticas_medico   ->  HTTP 206  Content-Range: 0-0/4
--   GET /rest/v1/v_resumen_mensual       ->  HTTP 206  Content-Range: 0-0/2
--   GET /rest/v1/pacientes  (tabla base) ->  HTTP 200  Content-Range: */0      <- la RLS SI funciona
--
-- Esa ultima linea es el punto: la tabla le niega todo a `anon` y la vista se la entregaba entera.
-- `v_pacientes_actividad` expone nombre, telefono, ultima cita y conteo de recetas por paciente.
-- `v_citas_hoy` expone la agenda del dia con nombre y telefono del paciente y el medico que atiende.
--
-- `v_citas_hoy` daba 0 filas el dia de la medicion porque no habia citas agendadas para esa fecha,
-- no porque estuviera protegida. En el dry-run se sembro una cita de HOY dentro de la transaccion y
-- `anon` la vio. Es fuga real, no latente.
--
-- EL FIX es el mismo que la mig 234 aplico a `v_consultas_paciente` cuando cerro el hallazgo C2 de
-- la auditoria del 5-jul. Estas cuatro quedaron afuera de aquel cierre. Las otras tres vistas de
-- `public` (`v_medicamentos_bajo_stock`, `v_metricas_campana_pais`, `v_metricas_campana_resumen`)
-- ya tienen `security_invoker=on` y no se tocan.
--
-- POR QUE NO SE TOCA NINGUNA EDGE FUNCTION. Hay 5 call-sites reales de estas vistas:
--
--   supabase/functions/reportes-detalle/index.ts:78    v_pacientes_actividad
--   supabase/functions/exportar-csv/index.ts:226       v_pacientes_actividad
--   supabase/functions/exportar-csv/index.ts:246       v_resumen_mensual
--   supabase/functions/reportes-resumen/index.ts:46    v_resumen_mensual
--   supabase/functions/reportes-resumen/index.ts:63    v_estadisticas_medico
--
-- Las tres consultan con `createClient(url, SERVICE_ROLE_KEY)`. `service_role` tiene
-- `rolbypassrls = true`, asi que con `security_invoker=on` la vista corre como el invocador y ese
-- invocador igual saltea la RLS: siguen viendo lo mismo que hoy. El cliente anon+JWT que tambien
-- construyen lo usan SOLO para `getUser()`, y el gate es `rol = 'super_admin'` o 403. Medido en el
-- dry-run: service_role da 26/1/4/3 antes y despues del ALTER, identico. Por eso esta migracion no
-- toca codigo: no hay nada que adaptar del lado de las edges.
--
-- `v_citas_hoy` NO tiene ningun call-site en todo el repo. Se le aplica el mismo ALTER igual, en vez
-- de DROP: el DROP tambien cerraria la fuga, pero ninguna de las 4 vistas esta definida en
-- `supabase/migrations/` ni en `supabase/fixes/` (son drift; ver ESTADO_PROYECTO_EZPAYCONNECT.md
-- linea 292), asi que no existe el `CREATE VIEW` para revertir un DROP. Dropearla es una segunda
-- decision, y primero habria que versionar su definicion.
--
-- QUE PASA DESPUES, por actor (medido, no supuesto):
--   anon                  -> 0 filas en las 4. La fuga se cierra.
--   paciente autenticado  -> 1 fila SUYA en v_pacientes_actividad (policy `Paciente ve su perfil`,
--                            `auth_user_id = auth.uid()`), 0 en el resto. La vista no se apaga: le
--                            aplica RLS fila por fila, que es exactamente lo que se busca.
--   super_admin           -> todo, por las policies `Admin ve X de su pais`.
--   service_role          -> todo, por bypassrls. Los 5 call-sites intactos.
--
-- Ninguna de las 4 filtra por `auth.uid()`: son agregados globales. No hay panel que se quede sin
-- datos, porque el unico camino de lectura real pasa por service_role.
--
-- Probes: P745-P749 en tests/rls/probes_escritura.sql.
-- ============================================================================================

ALTER VIEW public.v_pacientes_actividad SET (security_invoker = on);
ALTER VIEW public.v_citas_hoy           SET (security_invoker = on);
ALTER VIEW public.v_estadisticas_medico SET (security_invoker = on);
ALTER VIEW public.v_resumen_mensual     SET (security_invoker = on);

-- ============================================================================================
-- AUTOCHEQUEO — aborta si algo no quedo como se pidio. Ejercita roles, no mira solo el catalogo:
-- el catalogo dice quien tiene que, no que pasa cuando se usa (leccion de la mig 284).
-- ============================================================================================
DO $$
DECLARE
  v_pac  constant uuid := '0dd0c68c-026c-4ebc-9475-e6791cc54933';  -- paciente real, sin rol
  v_mal  text := '';
  v_t    text;
  v_n    bigint;
  v_pid  bigint;
  v_mid  uuid;
  v_hoy  bigint := -1;
BEGIN
  -- (a) las 4 quedaron con la reloption puesta.
  FOREACH v_t IN ARRAY ARRAY['v_pacientes_actividad','v_citas_hoy','v_estadisticas_medico','v_resumen_mensual'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace,
                    unnest(coalesce(c.reloptions, '{}'::text[])) x
       WHERE ns.nspname = 'public' AND c.relname = v_t
         AND x IN ('security_invoker=true','security_invoker=on')
    ) THEN
      v_mal := v_mal || format('%s quedo SIN security_invoker; ', v_t);
    END IF;
  END LOOP;

  -- (b) y las 3 que ya lo tenian siguen igual: esta migracion no debe haberlas rozado.
  FOREACH v_t IN ARRAY ARRAY['v_medicamentos_bajo_stock','v_metricas_campana_pais','v_metricas_campana_resumen'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace,
                    unnest(coalesce(c.reloptions, '{}'::text[])) x
       WHERE ns.nspname = 'public' AND c.relname = v_t
         AND x IN ('security_invoker=true','security_invoker=on')
    ) THEN
      v_mal := v_mal || format('%s PERDIO security_invoker; ', v_t);
    END IF;
  END LOOP;

  -- (c) anon EJERCITADO: 0 filas en las 4.
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('role', 'anon', true);
  FOREACH v_t IN ARRAY ARRAY['v_pacientes_actividad','v_citas_hoy','v_estadisticas_medico','v_resumen_mensual'] LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', v_t) INTO v_n;
      IF v_n <> 0 THEN v_mal := v_mal || format('anon ve %s filas en %s; ', v_n, v_t); END IF;
    EXCEPTION WHEN OTHERS THEN
      v_mal := v_mal || format('%s fallo con %s para anon; ', v_t, SQLSTATE);
    END;
  END LOOP;
  PERFORM set_config('role', 'none', true);
  PERFORM set_config('request.jwt.claims', '', true);

  -- (c-bis) v_citas_hoy con una cita de HOY DE VERDAD. Sin esto el 0 de arriba no distingue
  -- "protegida" de "hoy no hay agenda" — que es justo el error que casi comete el censo. La
  -- fixture vive dentro de una SUBTRANSACCION de plpgsql (el bloque BEGIN/EXCEPTION) y se revierte
  -- con un RAISE propio: esta migracion se aplica fuera de una transaccion explicita, asi que un
  -- INSERT suelto quedaria escrito en prod.
  SELECT id INTO v_pid FROM public.pacientes ORDER BY id LIMIT 1;
  SELECT id INTO v_mid FROM public.perfiles WHERE rol = 'medico' AND activo ORDER BY id LIMIT 1;
  IF v_pid IS NOT NULL AND v_mid IS NOT NULL THEN
    BEGIN
      INSERT INTO public.citas (medico_id, paciente_id, fecha, hora_inicio, hora_fin, estado, motivo)
      VALUES (v_mid, v_pid, CURRENT_DATE, '09:00', '09:30', 'agendada', 'FIXTURE mig302 (se revierte)');

      PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
      PERFORM set_config('role', 'anon', true);
      SELECT count(*) INTO v_hoy FROM public.v_citas_hoy;
      PERFORM set_config('role', 'none', true);
      PERFORM set_config('request.jwt.claims', '', true);

      RAISE EXCEPTION 'M302_ROLLBACK_FIXTURE';   -- revierte el INSERT, conserva v_hoy
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('role', 'none', true);
      PERFORM set_config('request.jwt.claims', '', true);
      IF SQLERRM <> 'M302_ROLLBACK_FIXTURE' THEN
        v_mal := v_mal || format('la fixture de v_citas_hoy fallo (%s %s); ', SQLSTATE, SQLERRM);
      END IF;
    END;
    IF v_hoy <> 0 THEN
      v_mal := v_mal || format('anon ve %s filas en v_citas_hoy con una cita de HOY sembrada; ', v_hoy);
    END IF;
  END IF;

  -- La fixture no puede haber sobrevivido a la subtransaccion.
  SELECT count(*) INTO v_n FROM public.citas WHERE motivo = 'FIXTURE mig302 (se revierte)';
  IF v_n <> 0 THEN
    v_mal := v_mal || format('quedaron %s citas fixture escritas en prod; ', v_n);
  END IF;

  -- (d) CONTROL POSITIVO — el actor legitimo no se rompio: el paciente ve SU fila, y solo la suya.
  -- Sin este control, un ALTER que dejara la vista devolviendo 0 a todo el mundo tambien daria
  -- verde en (c), y nadie se enteraria hasta que un panel apareciera vacio.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_pac, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    SELECT count(*) INTO v_n FROM public.v_pacientes_actividad;
    IF v_n <> 1 THEN
      v_mal := v_mal || format('el paciente ve %s filas en v_pacientes_actividad (se esperaba 1: la suya); ', v_n);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('v_pacientes_actividad fallo con %s para el paciente; ', SQLSTATE);
  END;
  PERFORM set_config('role', 'none', true);
  PERFORM set_config('request.jwt.claims', '', true);

  -- (e) CONTROL POSITIVO — service_role sigue viendo todo. Es el unico camino de lectura real:
  -- si esto se rompiera, se romperian los 5 call-sites de las 3 edges de reportes.
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('role', 'service_role', true);
  BEGIN
    SELECT count(*) INTO v_n FROM public.v_pacientes_actividad;
    IF v_n <> (SELECT count(*) FROM public.pacientes) THEN
      v_mal := v_mal || format('service_role ve %s filas en v_pacientes_actividad (se esperaban todas); ', v_n);
    END IF;
    SELECT count(*) INTO v_n FROM public.v_estadisticas_medico;
    IF v_n = 0 THEN v_mal := v_mal || 'service_role ve 0 en v_estadisticas_medico; '; END IF;
    SELECT count(*) INTO v_n FROM public.v_resumen_mensual;
    IF v_n = 0 THEN v_mal := v_mal || 'service_role ve 0 en v_resumen_mensual; '; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('las vistas fallaron con %s para service_role; ', SQLSTATE);
  END;
  PERFORM set_config('role', 'none', true);
  PERFORM set_config('request.jwt.claims', '', true);

  IF v_mal <> '' THEN
    RAISE EXCEPTION '302: %', v_mal;
  END IF;
END $$;
