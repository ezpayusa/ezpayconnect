-- ============================================================================================
-- 309 — "Admin ve visitas de su pais" sobre public.visitas_agendadas: de cmd=ALL a cmd=SELECT
-- ============================================================================================
-- Origen: recon del mini-frente visitas_agendadas (punto #3), 20-sep-2026.
--
-- QUE ESTABA MAL. La policy nacio como `FOR ALL`. Su nombre promete lectura ("ve visitas") pero
-- `ALL` cubre los cuatro comandos, asi que ademas le daba a super_admin y a admin_pais
-- INSERT / UPDATE / DELETE sobre la tabla de visitas de proveedores. No es un permiso que alguien
-- haya decidido: es el default de haber escrito `FOR ALL` en vez de `FOR SELECT`.
--
-- MEDIDO CONTRA PROD (dry-run en BEGIN/ROLLBACK, 20-sep), no deducido del catalogo:
--     admin_pais 85a3faf8 · UPDATE directo -> 1 fila(s) actualizada(s)
--     admin_pais 85a3faf8 · DELETE directo -> 1 fila(s) borrada(s)
--     super_admin 41904e2c · idem, 1 y 1
-- Es mutacion real por PostgREST, sin pasar por ninguna RPC.
--
-- POR QUE NO ROMPE NADA:
--   · Las 7 funciones que escriben la tabla (administrar_visita, cancelar_visita, checkin_visita,
--     checkout_visita, marcar_visitador_presente, notificar_visita_propuesta,
--     notificar_visita_resultado) son TODAS `SECURITY DEFINER` con `search_path=''`. No dependen
--     de la RLS del llamante, asi que esta policy no las toca.
--   · En el front hay UNA sola escritura directa sobre la tabla en todo el repo
--     (useVisitasAgendadas.ts:186, un INSERT de proveedor que va por la policy
--     "Proveedor crea visitas de su empresa"). Ningun `.update()` ni `.delete()` directo.
--     AdminVisitasProveedoresPage.tsx es `.select()` y nada mas.
--   · La LECTURA se conserva identica: el `USING` es el mismo texto que tenia la policy `ALL`.
--     super_admin ademas lee por partida doble, via "Admin ezpay ve todas las visitas".
--
-- EL BRAZO INSERT YA ESTABA MUERTO, y por eso esta migracion no lo menciona: `trg_gate_visita_pais`
-- es BEFORE INSERT, y los triggers BEFORE corren ANTES del WITH CHECK de la RLS. Para un admin
-- (cuyo `mi_empresa_proveedor()` es NULL) el INSERT muere con P0001 "sin plan de visitas activo"
-- igual antes que despues. Lo que esta migracion cierra de verdad es UPDATE y DELETE.
--
-- EL TRIGGER NO ERA UNA SEGUNDA BARRERA. `trg_gate_visita_pais` es
-- `BEFORE INSERT OR UPDATE OF medico_id`: un UPDATE de `comentario_admin` (o de `estado`, o de
-- cualquier otra columna) NO lo dispara. Para un UPDATE arbitrario la policy era lo unico que se
-- interponia. Para DELETE no hay ningun trigger BEFORE en la tabla.
--
-- LO QUE SE PIERDE, dicho explicito: un super_admin o un admin_pais ya no puede reasignar
-- `cuenta_proveedor_id` ni borrar una visita por SQL directo. Hoy no hay UI que lo haga. Si en
-- algun momento EzPay necesita agendar o reasignar por cuenta de una empresa, eso va por una RPC
-- SECURITY DEFINER con gate propio, no reabriendo la policy.
--
-- PROBES: P779-P782 + fixture VAG_FX en tests/rls/probes_escritura.sql. MIDEN ROW_COUNT, NO
-- SQLSTATE: en UPDATE y DELETE la RLS filtra filas EN SILENCIO, no lanza 42501. Una probe que
-- esperara 42501 saldria roja con esta migracion bien aplicada.
-- ============================================================================================

DROP POLICY "Admin ve visitas de su pais" ON public.visitas_agendadas;

CREATE POLICY "Admin ve visitas de su pais" ON public.visitas_agendadas
  FOR SELECT
  TO public
  USING (
    (get_auth_user_rol() = 'super_admin')
    OR ((get_auth_user_rol() = 'admin_pais') AND (pais_id = get_auth_user_pais_id()))
  );

-- ============================================================================================
-- AUTOCHEQUEO
-- ============================================================================================
-- OJO con `pg_policies.cmd`: es TEXTO ('ALL' / 'SELECT' / ...), no el `r/a/w/d/*` de
-- `pg_policy.polcmd`, que es otra vista. Un autochequeo que compare `cmd <> 'r'` aborta SIEMPRE,
-- incluso con la policy correcta. Se verifican las dos representaciones.
DO $$
DECLARE
  v_cmd text; v_polcmd "char"; v_wc text; v_n int;
BEGIN
  SELECT cmd, with_check INTO v_cmd, v_wc
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'visitas_agendadas'
     AND policyname = 'Admin ve visitas de su pais';

  SELECT pol.polcmd INTO v_polcmd
    FROM pg_policy pol
    JOIN pg_class c      ON c.oid = pol.polrelid
    JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname = 'public' AND c.relname = 'visitas_agendadas'
     AND pol.polname = 'Admin ve visitas de su pais';

  IF v_cmd IS NULL THEN
    RAISE EXCEPTION '309: la policy no existe despues del CREATE';
  END IF;
  IF v_cmd <> 'SELECT' OR v_polcmd <> 'r' THEN
    RAISE EXCEPTION '309: la policy no quedo en SELECT (pg_policies.cmd=% / polcmd=%)', v_cmd, v_polcmd;
  END IF;
  IF v_wc IS NOT NULL THEN
    RAISE EXCEPTION '309: una policy SELECT no deberia tener WITH CHECK (%)', v_wc;
  END IF;

  -- La tabla tenia 7 policies y tiene que seguir teniendo 7: el DROP+CREATE no perdio ninguna
  -- de las otras seis ni dejo la nueva duplicada.
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'visitas_agendadas';
  IF v_n <> 7 THEN
    RAISE EXCEPTION '309: la tabla tiene % policies, se esperaban 7', v_n;
  END IF;

  -- Sin este control, "7 policies" pasaria igual si alguien repusiera una ALL con otro nombre.
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'visitas_agendadas' AND cmd IN ('ALL', 'DELETE');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '309: quedan % policies ALL/DELETE en visitas_agendadas', v_n;
  END IF;

  RAISE NOTICE '309 OK: policy en SELECT, sin WITH CHECK, 7 policies, 0 ALL/DELETE';
  PERFORM set_config('m309.auto',
    'OK (cmd=SELECT, polcmd=r, with_check=NULL, 7 policies, 0 ALL/DELETE)', true);
END $$;
