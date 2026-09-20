-- ============================================================================================
-- 305 — notificaciones: UPDATE acotado por COLUMNA, y las broadcast dejan de ser de todos
-- ============================================================================================
-- Origen: docs/CENSO_SEGURIDAD_TRANSVERSAL_2026-09-20.md, seccion F2 (hallazgo #4), mas el
-- recon de call-sites del 22-sep.
--
-- QUE PASABA. `authenticated` tenia UPDATE a nivel TABLA (todas las columnas) y la policy
-- `notificaciones_update_propias` decia:
--     USING (usuario_id = auth.uid() OR usuario_id IS NULL)   -- sin WITH CHECK: lo hereda
-- Las filas broadcast (`usuario_id IS NULL`, 3 en prod) entraban por ese segundo brazo, asi que
-- CUALQUIER cuenta podia escribirlas. Ejercitado en prod dentro de BEGIN/ROLLBACK con un
-- paciente sin relacion, columna por columna:
--
--     titulo -> 1 fila | mensaje -> 1 fila | tipo -> 1 fila | leida -> 1 fila
--     metadata -> 1 fila | rol_destinatario -> 1 fila | accion_url -> bloqueado (23514)
--     apropiarse (usuario_id = el mio) -> 1 fila
--     CONTROL notificacion ajena -> 0 filas | DELETE ajena -> 0 filas
--
-- DOS PRECISIONES sobre el hallazgo original, las dos medidas:
--   1. El vector de phishing hacia un dominio externo YA ESTABA CERRADO, y no por RLS sino por
--      un CHECK que no teniamos en el mapa:
--          notif_accion_url_interna: CHECK (accion_url IS NULL OR accion_url ~ '^/[A-Za-z0-9/_-]*$')
--      `accion_url` solo admite rutas internas. Lo explotable era el TEXTO (titulo, mensaje),
--      la redireccion a OTRA ruta interna, y la APROPIACION de la fila.
--   2. `anon` tambien LEIA las 3 broadcast (por el mismo brazo en la policy de SELECT). No podia
--      escribirlas (no tiene grant de UPDATE), pero las veia: 3 de 3.
--
-- EL FIX, tres piezas:
--
-- (1) PRIVILEGIO POR COLUMNA. Es la pieza que mas cierra, porque se evalua ANTES que la RLS y
--     aplica a TODAS las filas, no solo a las broadcast. Copia exacta del precedente que ya vive
--     en la tabla hermana:
--         notificaciones_pacientes: leida = authenticated=w/postgres, UPDATE de tabla = false
--     Con esto `titulo`, `mensaje`, `tipo`, `metadata`, `rol_destinatario`, `accion_url`,
--     `usuario_id`, `pais_id`, ... dejan de ser escribibles por `authenticated` en cualquier fila.
--
--     SE OTORGAN DOS COLUMNAS, NO UNA. El alcance acordado decia `GRANT UPDATE (leida)`. El censo
--     de call-sites se habia hecho grepeando `from('notificaciones')` con comillas SIMPLES, y
--     `src/hooks/admin/useNotificacionesAdmin.ts` usa comillas DOBLES: quedo afuera. Ese hook
--     mueve el flujo de trabajo del admin escribiendo tambien `estado`:
--         :96  .update({ estado: "en_proceso", leida: true })
--         :119 .update({ estado: "completada", leida: true })
--         :127 .update({ estado: "archivada",  leida: true })
--     Con `GRANT UPDATE (leida)` a secas, ese panel se rompia. Re-censado con las dos comillas
--     sobre todo el repo, las UNICAS columnas que el front escribe son `leida` y `estado`.
--     `service_role` no se toca: conserva UPDATE de tabla, asi que las edges siguen igual.
--
-- (2) SIN BRAZO DE BROADCAST EN UPDATE. Se dropea `notificaciones_update_propias` y se recrea
--     `notificaciones_update_propia` con WITH CHECK EXPLICITO en vez de heredado. Un
--     `authenticated` deja de poder escribir NADA en una fila compartida, ni siquiera `leida`:
--     `leida` sobre una fila sin dueno es estado GLOBAL, no por-usuario, y marcarla se la
--     marcaria a todos. Si algun dia hace falta "leida por usuario" sobre broadcasts, eso es una
--     tabla de lecturas, no una columna de la fila compartida.
--     Se conserva `TO public` en vez de nombrar el rol (a diferencia de la mig 304): aca anon y
--     authenticated necesitan la MISMA regla, y `anon` no tiene grant de UPDATE, asi que separar
--     por rol no agregaria nada y ensancharia el diff.
--
-- (3) SIN BRAZO DE BROADCAST EN SELECT, y DELETE revocado. `notificaciones_select_propias` se
--     dropea; queda `notificaciones_select_propia` (`auth.uid() = usuario_id`) para el caso
--     normal y `notificaciones_select_super_admin` sin tocar. Esto no estaba en el pedido
--     original y se agrego con acuerdo explicito: ningun caller consume broadcasts (los TRES
--     hooks filtran `usuario_id = el mio`, asi que nunca llegan a la UI), o sea costo cero de
--     romper algo, y cierra una lectura no autorizada. El DELETE de `authenticated` era un grant
--     sin ninguna policy de DELETE — medido: 0 filas borradas. Higiene.
--
-- QUE NO SE TOCA: `notificaciones_select_super_admin` ni `notificaciones_update_super_admin`
-- (esta ultima ya traia WITH CHECK explicito). OJO: el super_admin entra por PostgREST como el
-- rol de base `authenticated`, asi que la pieza (1) tambien lo alcanza — solo podra escribir
-- `leida` y `estado`. Es lo correcto y no rompe nada: el unico panel de admin sobre esta tabla
-- (useNotificacionesAdmin) escribe exactamente esas dos.
--
-- Probes: P759-P765 en tests/rls/probes_escritura.sql.
-- ============================================================================================

-- (1) -----------------------------------------------------------------------------------------
REVOKE UPDATE ON public.notificaciones FROM authenticated;
GRANT  UPDATE (leida, estado) ON public.notificaciones TO authenticated;

-- (3b) ----------------------------------------------------------------------------------------
REVOKE DELETE ON public.notificaciones FROM authenticated;

-- (2) -----------------------------------------------------------------------------------------
DROP POLICY IF EXISTS notificaciones_update_propias ON public.notificaciones;
DROP POLICY IF EXISTS notificaciones_update_propia  ON public.notificaciones;

CREATE POLICY notificaciones_update_propia
  ON public.notificaciones
  FOR UPDATE TO public
  USING      (usuario_id = auth.uid())
  WITH CHECK (usuario_id = auth.uid());

-- (3a) ----------------------------------------------------------------------------------------
DROP POLICY IF EXISTS notificaciones_select_propias ON public.notificaciones;

-- ============================================================================================
-- AUTOCHEQUEO — aborta si algo no quedo como se pidio. Ejercita los roles con SET ROLE y
-- ESCRIBE de verdad; cada prueba vive en una SUBTRANSACCION de plpgsql que se revierte con un
-- RAISE propio. Esta migracion se aplica FUERA de una transaccion explicita: un UPDATE suelto
-- quedaria escrito en prod.
-- ============================================================================================
DO $$
DECLARE
  v_med  constant uuid := '09d243d5-b222-482a-9762-94a582e9e752';  -- medico real, 30 notifs propias
  v_pac  constant uuid := '0dd0c68c-026c-4ebc-9475-e6791cc54933';  -- paciente real, 0 notifs propias
  v_sa   constant uuid := '41904e2c-5ef3-4fee-bd48-9ea58e0c8c37';  -- super_admin real
  v_mal  text := '';
  v_n    bigint;
  v_rc   int;
  v_bc   uuid;      -- una broadcast
  v_mia  uuid;      -- una notificacion del medico
  v_tot0 bigint;
  v_err  text;
BEGIN
  SELECT count(*) INTO v_tot0 FROM public.notificaciones;
  SELECT id INTO v_bc  FROM public.notificaciones WHERE usuario_id IS NULL ORDER BY created_at LIMIT 1;
  SELECT id INTO v_mia FROM public.notificaciones WHERE usuario_id = v_med ORDER BY created_at LIMIT 1;
  IF v_bc IS NULL OR v_mia IS NULL THEN
    RAISE EXCEPTION '305: faltan filas para el autochequeo (broadcast=% propia=%)', v_bc, v_mia;
  END IF;

  -- (a) el medico marca SU propia como leida -> tiene que funcionar
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_med,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    UPDATE public.notificaciones SET leida = true WHERE id = v_mia;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 1 THEN v_mal := v_mal || format('(a) marcar leida la propia afecto %s filas; ', v_rc); END IF;
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M305_RB' THEN v_mal := v_mal || format('(a) marcar leida la propia fallo (%s); ', SQLSTATE); END IF;
  END;

  -- (a2) ...y tambien `estado`, que es lo que mueve el panel de admin (useNotificacionesAdmin).
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_med,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    UPDATE public.notificaciones SET estado = 'en_proceso', leida = true WHERE id = v_mia;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 1 THEN v_mal := v_mal || format('(a2) actualizar estado afecto %s filas; ', v_rc); END IF;
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M305_RB' THEN v_mal := v_mal || format('(a2) actualizar estado fallo (%s): se rompe el panel de admin; ', SQLSTATE); END IF;
  END;

  -- (b) el medico sobre SU PROPIA fila, pero la columna `titulo` -> tiene que cortar el GRANT,
  --     no la RLS. Se distingue por el mensaje: la RLS dice "row-level security policy".
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_med,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    UPDATE public.notificaciones SET titulo = 'AUTOCHEQUEO 305' WHERE id = v_mia;
    PERFORM set_config('role','none', true);
    v_mal := v_mal || '(b) se pudo escribir `titulo`: el privilegio por columna no quedo; ';
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    v_err := SQLERRM;
    IF v_err <> 'M305_RB' THEN
      IF SQLSTATE <> '42501' THEN
        v_mal := v_mal || format('(b) `titulo` corto con %s, se esperaba 42501; ', SQLSTATE);
      ELSIF v_err ILIKE '%row-level security%' THEN
        v_mal := v_mal || '(b) `titulo` lo corto la RLS y no el privilegio de columna; ';
      END IF;
    END IF;
  END;

  -- (c) un paciente sobre una BROADCAST: ni siquiera `leida`. Corta el USING de la policy
  --     (la fila no entra), asi que son 0 filas, no un error.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_pac,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    UPDATE public.notificaciones SET leida = false WHERE id = v_bc;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 0 THEN v_mal := v_mal || format('(c) un paciente escribio %s broadcast(s); ', v_rc); END IF;
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M305_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(c) corto con %s inesperado; ', SQLSTATE);
    END IF;
  END;

  -- (c2) ...y lo MISMO sin WHERE. Es un caso aparte, no un duplicado: un UPDATE que lee columnas
  --      (WHERE o RETURNING) aplica TAMBIEN las policies de SELECT, asi que el (c) de arriba lo
  --      puede estar cortando el cierre de lectura y no el de escritura. Sin WHERE no hace falta
  --      SELECT, y esto ejercita el USING del UPDATE a solas. Se descubrio porque la contraprueba
  --      por mutacion de esta pieza NO disparaba con (c) solo.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_pac,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    UPDATE public.notificaciones SET leida = false;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 0 THEN v_mal := v_mal || format('(c2) un UPDATE sin WHERE de un ajeno toco %s fila(s); ', v_rc); END IF;
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M305_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(c2) corto con %s inesperado; ', SQLSTATE);
    END IF;
  END;

  -- (d) APROPIACION: ponerse como dueno de una fila ajena. Con el grant de columna, `usuario_id`
  --     no es escribible: tiene que cortar con 42501 de privilegio.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_pac,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    UPDATE public.notificaciones SET usuario_id = v_pac WHERE id = v_bc;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    v_mal := v_mal || format('(d) la apropiacion funciono (%s fila(s)); ', v_rc);
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    v_err := SQLERRM;
    IF v_err <> 'M305_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(d) corto con %s, se esperaba 42501; ', SQLSTATE);
    END IF;
  END;

  -- (e) anon ya no LEE las broadcast
  PERFORM set_config('request.jwt.claims','{"role":"anon"}', true);
  PERFORM set_config('role','anon', true);
  BEGIN
    SELECT count(*) INTO v_n FROM public.notificaciones;
    IF v_n <> 0 THEN v_mal := v_mal || format('(e) anon ve %s notificacion(es); ', v_n); END IF;
  EXCEPTION WHEN OTHERS THEN v_mal := v_mal || format('(e) anon corto con %s; ', SQLSTATE);
  END;
  PERFORM set_config('role','none', true);

  -- (f) un authenticated sin relacion tampoco
  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_pac,'role','authenticated')::text, true);
  PERFORM set_config('role','authenticated', true);
  BEGIN
    SELECT count(*) INTO v_n FROM public.notificaciones;
    IF v_n <> 0 THEN v_mal := v_mal || format('(f) un authenticated ajeno ve %s notificacion(es); ', v_n); END IF;
  EXCEPTION WHEN OTHERS THEN v_mal := v_mal || format('(f) el ajeno corto con %s; ', SQLSTATE);
  END;

  -- (h) DELETE revocado
  BEGIN
    DELETE FROM public.notificaciones WHERE id = v_bc;
    PERFORM set_config('role','none', true);
    v_mal := v_mal || '(h) un authenticated pudo ejecutar DELETE; ';
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M305_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(h) DELETE corto con %s, se esperaba 42501; ', SQLSTATE);
    END IF;
  END;
  PERFORM set_config('request.jwt.claims','', true);

  -- (g) CONTROL POSITIVO de punta a punta: el medico VE las suyas y marca una como leida.
  --     Sin esto, un cierre de mas daria verde en (c)(e)(f) y dejaria la campana muda para todos.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_med,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    SELECT count(*) INTO v_n FROM public.notificaciones;
    IF v_n = 0 THEN
      v_mal := v_mal || '(g) el medico dejo de ver SUS notificaciones; ';
    ELSE
      UPDATE public.notificaciones SET leida = true
       WHERE id IN (SELECT id FROM public.notificaciones LIMIT 1);
      GET DIAGNOSTICS v_rc = ROW_COUNT;
      IF v_rc <> 1 THEN v_mal := v_mal || format('(g) no pudo marcar la suya (%s filas); ', v_rc); END IF;
    END IF;
    PERFORM set_config('role','none', true);
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M305_RB' THEN v_mal := v_mal || format('(g) el camino legitimo fallo (%s); ', SQLSTATE); END IF;
  END;

  -- (i) el super_admin no cambia: sigue viendo todo y marcando leida por su propia policy.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_sa,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    SELECT count(*) INTO v_n FROM public.notificaciones;
    IF v_n <> v_tot0 THEN
      v_mal := v_mal || format('(i) el super_admin ve %s de %s; ', v_n, v_tot0);
    END IF;
    UPDATE public.notificaciones SET leida = true WHERE id = v_bc;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    IF v_rc <> 1 THEN v_mal := v_mal || format('(i) el super_admin no pudo actualizar (%s filas); ', v_rc); END IF;
    PERFORM set_config('role','none', true);
    RAISE EXCEPTION 'M305_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M305_RB' THEN v_mal := v_mal || format('(i) el super_admin fallo (%s); ', SQLSTATE); END IF;
  END;
  PERFORM set_config('request.jwt.claims','', true);

  -- (j) catalogo: las policies viejas no sobreviven, y el grant quedo por columna.
  IF EXISTS (SELECT 1 FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
              JOIN pg_namespace ns ON ns.oid=c.relnamespace
             WHERE ns.nspname='public' AND c.relname='notificaciones'
               AND pol.polname IN ('notificaciones_update_propias','notificaciones_select_propias')) THEN
    v_mal := v_mal || '(j) una policy vieja sobrevivio; ';
  END IF;
  IF has_table_privilege('authenticated','public.notificaciones','UPDATE') THEN
    v_mal := v_mal || '(j) authenticated conserva UPDATE a nivel TABLA; ';
  END IF;
  IF has_table_privilege('authenticated','public.notificaciones','DELETE') THEN
    v_mal := v_mal || '(j) authenticated conserva DELETE; ';
  END IF;
  IF NOT has_column_privilege('authenticated','public.notificaciones','leida','UPDATE')
     OR NOT has_column_privilege('authenticated','public.notificaciones','estado','UPDATE') THEN
    v_mal := v_mal || '(j) falta el GRANT UPDATE sobre leida/estado; ';
  END IF;
  IF has_column_privilege('authenticated','public.notificaciones','titulo','UPDATE')
     OR has_column_privilege('authenticated','public.notificaciones','usuario_id','UPDATE') THEN
    v_mal := v_mal || '(j) titulo/usuario_id siguen siendo escribibles; ';
  END IF;
  IF NOT has_table_privilege('service_role','public.notificaciones','UPDATE') THEN
    v_mal := v_mal || '(j) service_role PERDIO el UPDATE: se rompen las edges; ';
  END IF;

  -- (k) nada se escribio en prod
  SELECT count(*) INTO v_n FROM public.notificaciones;
  IF v_n <> v_tot0 THEN
    v_mal := v_mal || format('(k) la tabla paso de %s a %s filas; ', v_tot0, v_n);
  END IF;
  SELECT count(*) INTO v_n FROM public.notificaciones WHERE titulo = 'AUTOCHEQUEO 305';
  IF v_n <> 0 THEN v_mal := v_mal || format('(k) quedaron %s filas con titulo de prueba; ', v_n); END IF;

  IF v_mal <> '' THEN
    RAISE EXCEPTION '305: %', v_mal;
  END IF;
END $$;
