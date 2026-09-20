-- ============================================================================================
-- 304 — configuracion_sistema deja de mostrarle los datos bancarios a `anon`
-- ============================================================================================
-- Origen: docs/CENSO_SEGURIDAD_TRANSVERSAL_2026-09-20.md, seccion F2 (hallazgo #3, medio), mas
-- el recon de Codex del 21-sep sobre los call-sites.
--
-- QUE PASABA. La policy "Cualquiera lee configuracion" (mig 019) era `FOR SELECT TO public` con
-- `USING (true)`, y `anon` tiene SELECT sobre la tabla. O sea que las 21 filas se leian por REST
-- sin sesion. Medido el 20-sep contra prod:
--
--   GET /rest/v1/configuracion_sistema  ->  HTTP 206  Content-Range: 0-0/21
--
-- Cinco de esas filas son datos bancarios de cobro, todas con `categoria = 'general'`:
--   banco · cuenta_bancaria · tipo_cuenta · titular_cuenta · email_pagos
-- Las otras 16 son branding (app_nombre, color_*, app_logo_url), integraciones (integ_*),
-- notificaciones (notif_*) y formato (sistema_*): nada sensible, y el front publico las usa.
--
-- POR QUE UNA POLICY POR ROL Y NO OTRA COSA:
--   · Privilegio por COLUMNA no sirve. El secreto vive en `valor`, que es la MISMA columna de las
--     21 filas: revocarla a nivel columna taparia tambien el color primario y el nombre de la app.
--     El corte es por FILA, y eso es RLS.
--   · Una vista filtrada tampoco: habria que cambiar todos los lectores y dejar la tabla igual de
--     abierta por debajo. Ademas, la leccion de la mig 302 es que una vista mal configurada es un
--     agujero mas, no uno menos.
--   · La excepcion NO puede ser `TO public`: `public` tambien alcanza a `authenticated`, asi que
--     una sola policy no puede distinguir los dos casos. Van dos, con el rol nombrado.
--
-- SE REEMPLAZA TAMBIEN `ver_configuracion`, que no estaba en el pedido. Medido antes de escribir
-- esto: ya existia una tercera policy `ver_configuracion` (`FOR SELECT TO authenticated`,
-- `USING true`) que hace exactamente lo que haria la policy nueva de authenticated. Dejar las dos
-- seria tener dos policies identicas sobre el mismo rol — el tipo de drift que hace ilegible la
-- proxima auditoria. Se reemplaza por la nueva, con nombre consistente con la de anon. El
-- comportamiento de `authenticated` no cambia: antes veia las 21 por `ver_configuracion`, ahora
-- las ve por `configuracion_sistema_select_authenticated`. Ningun codigo referencia esos nombres
-- (verificado con grep en todo el repo: solo aparecen en la mig 019 que los creo).
--
-- NO se toca `Admin ezpay actualiza configuracion` (`FOR ALL TO public`, gate de super_admin):
-- para `anon` su USING evalua `EXISTS (... auth.uid() ...)` = false, asi que no le suma filas.
--
-- CALL-SITES (recon de Codex, re-verificado):
--   · src/pages/ConfiguracionPage.tsx -> edge `actualizar-configuracion` -> service_role
--     (rolbypassrls): no lo afecta ninguna policy.
--   · src/proveedor/hooks/useConfiguracionSistema.ts EXISTE pero no se importa en ninguna
--     pantalla (grep: la unica aparicion es su propia definicion). No es un caller real hoy. Si
--     manana se montara, queda cubierto igual: con sesion ve las 21 por la policy de
--     authenticated; sin sesion ya no veria las 5 bancarias.
--   · Ningun flujo publico (login, landing) las necesita. El checkout autenticado
--     (/proveedor/checkout) lee `cuentas_bancarias_pais`, que es otra tabla.
--
-- Probes: P755-P758 en tests/rls/probes_escritura.sql.
-- ============================================================================================

DROP POLICY IF EXISTS "Cualquiera lee configuracion" ON public.configuracion_sistema;
DROP POLICY IF EXISTS ver_configuracion               ON public.configuracion_sistema;

CREATE POLICY configuracion_sistema_select_anon
  ON public.configuracion_sistema
  FOR SELECT TO anon
  USING (clave NOT IN ('banco', 'cuenta_bancaria', 'tipo_cuenta', 'titular_cuenta', 'email_pagos'));

CREATE POLICY configuracion_sistema_select_authenticated
  ON public.configuracion_sistema
  FOR SELECT TO authenticated
  USING (true);

-- ============================================================================================
-- AUTOCHEQUEO — aborta si algo no quedo como se pidio. Ejercita los roles con SET ROLE: el
-- catalogo dice quien tiene que, no que pasa cuando se usa (leccion de la mig 284).
-- ============================================================================================
DO $$
DECLARE
  v_mal   text := '';
  v_n     bigint;
  v_tot   bigint;
  v_lista text;
  bancarias constant text[] := ARRAY['banco','cuenta_bancaria','tipo_cuenta','titular_cuenta','email_pagos'];
BEGIN
  SELECT count(*) INTO v_tot FROM public.configuracion_sistema;
  IF v_tot <> 21 THEN
    -- no es un error en si, pero los conteos de abajo son relativos: se deja constancia.
    RAISE NOTICE '304: la tabla tiene % filas (el censo midio 21)', v_tot;
  END IF;

  -- ---------------------------------------------------------------- (a) anon NO ve las 5
  PERFORM set_config('request.jwt.claims','{"role":"anon"}', true);
  PERFORM set_config('role','anon', true);
  BEGIN
    SELECT count(*), string_agg(clave, ', ' ORDER BY clave) INTO v_n, v_lista
      FROM public.configuracion_sistema WHERE clave = ANY(bancarias);
    IF v_n <> 0 THEN
      v_mal := v_mal || format('(a) anon todavia ve %s clave(s) bancaria(s): %s; ', v_n, v_lista);
    END IF;

    -- (b) ...y SI ve el resto. Control positivo: sin esto, una policy que devolviera 0 filas a
    -- anon tambien daria verde en (a) y romperia el branding del front publico.
    SELECT count(*) INTO v_n FROM public.configuracion_sistema;
    IF v_n <> v_tot - 5 THEN
      v_mal := v_mal || format('(b) anon ve %s filas, se esperaban %s (todas menos las 5); ', v_n, v_tot - 5);
    END IF;

    -- (b-bis) y nombrando las que el front publico realmente usa, no solo el conteo.
    SELECT count(*) INTO v_n FROM public.configuracion_sistema
     WHERE clave IN ('app_nombre','color_primario','sistema_moneda','notif_email_activo');
    IF v_n <> 4 THEN
      v_mal := v_mal || format('(b-bis) anon solo ve %s de las 4 claves de branding/sistema; ', v_n);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('(a/b) la tabla fallo con %s para anon; ', SQLSTATE);
  END;
  PERFORM set_config('role','none', true);
  PERFORM set_config('request.jwt.claims','', true);

  -- ---------------------------------------------------------------- (c) authenticated: las 21
  -- CONTROL POSITIVO del camino que NO debia tocarse. Se verifica por nombre, no solo por conteo.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"0dd0c68c-026c-4ebc-9475-e6791cc54933","role":"authenticated"}', true);
  PERFORM set_config('role','authenticated', true);
  BEGIN
    SELECT count(*) INTO v_n FROM public.configuracion_sistema;
    IF v_n <> v_tot THEN
      v_mal := v_mal || format('(c) un authenticated ve %s de %s filas; ', v_n, v_tot);
    END IF;
    SELECT count(*), string_agg(b, ', ') INTO v_n, v_lista
      FROM unnest(bancarias) b
     WHERE NOT EXISTS (SELECT 1 FROM public.configuracion_sistema cs WHERE cs.clave = b);
    IF v_n <> 0 THEN
      v_mal := v_mal || format('(c) un authenticated PERDIO %s clave(s): %s; ', v_n, v_lista);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('(c) la tabla fallo con %s para authenticated; ', SQLSTATE);
  END;
  PERFORM set_config('role','none', true);
  PERFORM set_config('request.jwt.claims','', true);

  -- ---------------------------------------------------------------- (d) service_role: las 21
  -- Es el camino de la edge `actualizar-configuracion`. Tiene rolbypassrls, asi que ninguna
  -- policy deberia afectarlo; se comprueba igual, porque suponerlo es como no medirlo.
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}', true);
  PERFORM set_config('role','service_role', true);
  BEGIN
    SELECT count(*) INTO v_n FROM public.configuracion_sistema;
    IF v_n <> v_tot THEN
      v_mal := v_mal || format('(d) service_role ve %s de %s filas: se rompe actualizar-configuracion; ', v_n, v_tot);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('(d) la tabla fallo con %s para service_role; ', SQLSTATE);
  END;
  PERFORM set_config('role','none', true);
  PERFORM set_config('request.jwt.claims','', true);

  -- ---------------------------------------------------------------- (e) el catalogo quedo limpio
  -- Ni la policy vieja sobreviviendo junto a las nuevas, ni policies de SELECT de mas.
  IF EXISTS (SELECT 1 FROM pg_policy pol JOIN pg_class c ON c.oid = pol.polrelid
              JOIN pg_namespace ns ON ns.oid = c.relnamespace
             WHERE ns.nspname = 'public' AND c.relname = 'configuracion_sistema'
               AND pol.polname IN ('Cualquiera lee configuracion','ver_configuracion')) THEN
    v_mal := v_mal || '(e) una policy vieja sobrevivio junto a las nuevas; ';
  END IF;

  SELECT count(*), string_agg(pol.polname, ', ' ORDER BY pol.polname) INTO v_n, v_lista
    FROM pg_policy pol JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname = 'public' AND c.relname = 'configuracion_sistema'
     AND pol.polcmd::text = 'r';
  IF v_n <> 2 THEN
    v_mal := v_mal || format('(e) quedaron %s policies de SELECT (se esperaban 2): %s; ', v_n, v_lista);
  END IF;

  IF v_mal <> '' THEN
    RAISE EXCEPTION '304: %', v_mal;
  END IF;
END $$;
