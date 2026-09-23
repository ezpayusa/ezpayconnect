-- ############################################################################################
-- Migracion 325 - GUARD anti-auto-escalada del paciente sobre public.pacientes   (23-sep-2026)
-- ############################################################################################
-- CONTEXTO: el recon del 23-sep midio que un paciente autenticado puede UPDATE-ar columnas
-- PRIVILEGIADAS de SU PROPIA fila via PostgREST directo (WebAppPerfil), porque la policy
-- "Paciente actualiza su perfil" solo acota por fila (auth_user_id = auth.uid()) y NO por columna,
-- y no habia trigger protector sobre pacientes. Medido PERMITIDO: medico_id, medico_primario_id,
-- clinica_primaria_id, pais_id, activo (auth_user_id ya lo frenaba el WITH CHECK implicito).
-- Impacto: medico_id auto-asignado abre el expediente a un medico elegido por el paciente y pasa
-- el gate de emitir_receta (rama pacientes.medico_id = auth.uid()); pais_id evade el aislamiento
-- de admin_pais.
--
-- SOLUCION: trigger BEFORE UPDATE que, SOLO cuando el que edita es el propio paciente
-- (auth.uid() = OLD.auth_user_id) y no es un rol de BD privilegiado, rechaza con 42501 el cambio
-- de cualquier columna privilegiada. + endurecer la policy con WITH CHECK explicito y TO authenticated.
--
-- >>> DESVIO DELIBERADO respecto del pedido: la funcion es SECURITY INVOKER (NO DEFINER). <<<
-- Con DEFINER (dueno postgres) current_user DENTRO de la funcion = 'postgres' SIEMPRE (medido:
-- DEFINER->postgres, INVOKER->authenticated), y el chequeo `current_user NOT IN (...privilegiados)`
-- nunca disparia -> el guard no bloquearia a nadie. Los DOS guards que el pedido cita como
-- referencia de estilo (perfiles_guard_rol_update mig 262 y empresas_proveedoras_guard_update
-- mig 322) son INVOKER por exactamente esta razon. El autochequeo (b) exige prosecdef=false.
--
-- Sin cambios de GRANT sobre pacientes. La funcion se REVOCA de public/anon/authenticated (un
-- trigger dispara sin necesidad de EXECUTE del llamante).
-- ############################################################################################

-- 1) Funcion guard --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.pacientes_guard_update()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY INVOKER            -- explicito: current_user debe reflejar al LLAMANTE (ver header)
  SET search_path TO ''
AS $function$
DECLARE
  v_cols text := '';
BEGIN
  -- Guard clause 1: exencion por rol de BD privilegiado, PRIMERO y a proposito. Migraciones (postgres),
  -- edge (service_role) y superuser salen ACA sin evaluar auth.uid(). Importa el orden: en esos
  -- contextos request.jwt.claims puede venir vacio o con sub='' (p. ej. una migracion que hace UPDATE
  -- pacientes tras impersonar), y auth.uid() haria ''::uuid -> 22P02. Requiere SECURITY INVOKER para
  -- que current_user sea el LLAMANTE (ver header).
  IF current_user IN ('postgres','service_role','supabase_admin') THEN
    RETURN NEW;
  END IF;

  -- Guard clause 2: solo interviene cuando el editor ES el propio paciente de la fila.
  -- admin_pais/super_admin (policy ALL) y cualquier staff editan filas cuyo auth_user_id != su
  -- auth.uid() -> pasan. Fila sin auth_user_id (paciente creado por medico) -> NULL, tampoco dispara.
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM OLD.auth_user_id THEN
    RETURN NEW;
  END IF;

  -- A partir de aca: el propio paciente, por un rol no privilegiado (authenticated). Ninguna
  -- columna privilegiada puede cambiar.
  IF NEW.id                  IS DISTINCT FROM OLD.id                  THEN v_cols := v_cols || 'id, '; END IF;
  IF NEW.auth_user_id        IS DISTINCT FROM OLD.auth_user_id        THEN v_cols := v_cols || 'auth_user_id, '; END IF;
  IF NEW.medico_id           IS DISTINCT FROM OLD.medico_id           THEN v_cols := v_cols || 'medico_id, '; END IF;
  IF NEW.medico_primario_id  IS DISTINCT FROM OLD.medico_primario_id  THEN v_cols := v_cols || 'medico_primario_id, '; END IF;
  IF NEW.clinica_primaria_id IS DISTINCT FROM OLD.clinica_primaria_id THEN v_cols := v_cols || 'clinica_primaria_id, '; END IF;
  IF NEW.pais_id             IS DISTINCT FROM OLD.pais_id             THEN v_cols := v_cols || 'pais_id, '; END IF;
  IF NEW.activo              IS DISTINCT FROM OLD.activo              THEN v_cols := v_cols || 'activo, '; END IF;
  IF NEW.email               IS DISTINCT FROM OLD.email               THEN v_cols := v_cols || 'email, '; END IF;
  IF NEW.foto_path           IS DISTINCT FROM OLD.foto_path           THEN v_cols := v_cols || 'foto_path, '; END IF;
  IF NEW.created_at          IS DISTINCT FROM OLD.created_at          THEN v_cols := v_cols || 'created_at, '; END IF;

  IF v_cols <> '' THEN
    RAISE EXCEPTION 'No autorizado a modificar columna(s) privilegiada(s) de pacientes: %',
      rtrim(v_cols, ', ') USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.pacientes_guard_update() FROM public, anon, authenticated;

-- 2) Trigger --------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pacientes_guard_update ON public.pacientes;
CREATE TRIGGER trg_pacientes_guard_update
  BEFORE UPDATE ON public.pacientes
  FOR EACH ROW EXECUTE FUNCTION private.pacientes_guard_update();

-- 3) Policy: WITH CHECK explicito + TO authenticated ----------------------------------------
-- Antes: FOR UPDATE TO public, USING (auth_user_id = auth.uid()), WITH CHECK NULL (usaba el USING).
-- El WITH CHECK explicito es defensa en profundidad; la barrera real por columna es el trigger.
DROP POLICY IF EXISTS "Paciente actualiza su perfil" ON public.pacientes;
CREATE POLICY "Paciente actualiza su perfil" ON public.pacientes
  FOR UPDATE TO authenticated
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

-- 4) Autochequeo (aborta la migracion ante cualquier violacion) -----------------------------
DO $ac$
DECLARE
  v_viol   text := '';
  v_sec    boolean;
  v_cfg    text[];
  v_tgen   char;
  v_polc   text;
  v_roles  text;
  qa_uid   uuid;
  qa_pac   bigint;
  n        int;
BEGIN
  -- (a) trigger existe y esta habilitado (tgenabled = 'O')
  SELECT t.tgenabled INTO v_tgen
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE ns.nspname='public' AND c.relname='pacientes' AND t.tgname='trg_pacientes_guard_update' AND NOT t.tgisinternal;
  IF v_tgen IS NULL THEN v_viol := v_viol || E'\n(a) trigger trg_pacientes_guard_update no existe';
  ELSIF v_tgen <> 'O' THEN v_viol := v_viol || E'\n(a) trigger no habilitado (tgenabled='||v_tgen||')'; END IF;

  -- (b) funcion INVOKER (prosecdef=false) y search_path=''
  SELECT p.prosecdef, p.proconfig INTO v_sec, v_cfg
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='private' AND p.proname='pacientes_guard_update';
  IF v_sec IS NULL THEN v_viol := v_viol || E'\n(b) funcion private.pacientes_guard_update no existe';
  ELSE
    IF v_sec <> false THEN v_viol := v_viol || E'\n(b) funcion es SECURITY DEFINER (debe ser INVOKER)'; END IF;
    IF v_cfg IS NULL OR NOT EXISTS (SELECT 1 FROM unnest(v_cfg) e WHERE e LIKE 'search_path=%' AND btrim(split_part(e,'=',2),'"') = '')
      THEN v_viol := v_viol || E'\n(b) search_path no es vacio (proconfig='||COALESCE(array_to_string(v_cfg,','),'NULL')||')'; END IF;
  END IF;

  -- (c) policy roles={authenticated} y WITH CHECK no nulo
  SELECT pol.with_check, pol.roles::text INTO v_polc, v_roles
    FROM pg_policies pol WHERE pol.schemaname='public' AND pol.tablename='pacientes' AND pol.policyname='Paciente actualiza su perfil';
  IF v_roles IS NULL THEN v_viol := v_viol || E'\n(c) policy no existe';
  ELSE
    IF v_roles <> '{authenticated}' THEN v_viol := v_viol || E'\n(c) policy roles='||v_roles||' (esperado {authenticated})'; END IF;
    IF v_polc IS NULL THEN v_viol := v_viol || E'\n(c) policy sin WITH CHECK'; END IF;
  END IF;

  -- (d) EJERCICIO REAL: impersonar a Paciente QA (actor elegido como postgres) dentro de un
  --     savepoint que SIEMPRE se descarta (RAISE SENTINEL), para no dejar cambios.
  SELECT auth_user_id, id INTO qa_uid, qa_pac
    FROM public.pacientes WHERE email='paciente.qa@ezpayconnect.com';
  IF qa_uid IS NULL THEN
    v_viol := v_viol || E'\n(d) no se encontro Paciente QA con auth_user_id -> no se pudo ejercitar';
  ELSE
    BEGIN
      -- d1: medico_id debe lanzar 42501
      BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', qa_uid::text, 'role','authenticated')::text, true);
        PERFORM set_config('role','authenticated', true);
        UPDATE public.pacientes SET medico_id = gen_random_uuid() WHERE id = qa_pac;
        PERFORM set_config('role','none', true);
        v_viol := v_viol || E'\n(d) medico_id NO fue bloqueado por el paciente';
      EXCEPTION
        WHEN insufficient_privilege THEN PERFORM set_config('role','none', true);   -- esperado
        WHEN OTHERS THEN PERFORM set_config('role','none', true);
          v_viol := v_viol || E'\n(d) medico_id lanzo error inesperado '||SQLSTATE;
      END;
      -- d2: alergias (columna editable) debe afectar 1 fila
      BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', qa_uid::text, 'role','authenticated')::text, true);
        PERFORM set_config('role','authenticated', true);
        UPDATE public.pacientes SET alergias = '__AUTOCHK_325__' WHERE id = qa_pac;
        GET DIAGNOSTICS n = ROW_COUNT;
        PERFORM set_config('role','none', true);
        IF n <> 1 THEN v_viol := v_viol || E'\n(d) alergias no afecto 1 fila (n='||n||')'; END IF;
      EXCEPTION WHEN OTHERS THEN PERFORM set_config('role','none', true);
        v_viol := v_viol || E'\n(d) alergias lanzo error '||SQLSTATE;
      END;
      -- descartar TODO cambio del ejercicio
      RAISE EXCEPTION 'SENTINEL_ROLLBACK_325';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'SENTINEL_ROLLBACK_325' THEN RAISE; END IF;
    END;
  END IF;

  -- Higiene: no dejar estado de sesion (rol / claims) contaminado tras el ejercicio.
  PERFORM set_config('role','none', true);
  PERFORM set_config('request.jwt.claims','', true);

  IF v_viol <> '' THEN
    RAISE EXCEPTION 'MIG325 AUTOCHEQUEO FALLA:%', v_viol;
  END IF;
END $ac$;
