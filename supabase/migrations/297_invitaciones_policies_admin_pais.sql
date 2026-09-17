-- ############################################################################################
-- 297 — invitaciones_medico / invitaciones_clinica: el admin_pais pasa a tener policy propia
-- ############################################################################################
-- EL DEFECTO ES EL INVERSO DEL QUE CERRARON LAS 294/295/296. Ahi sobraba acceso; aca FALTA. El
-- sidebar de admin_pais tiene los dos items de invitaciones desde que existe (SidebarAdmin.tsx:28-29),
-- pero ninguna de las dos tablas tenia una policy que lo contemplara:
--
--   invitaciones_medico_admin_all    [ALL, TO PUBLIC]  USING EXISTS(perfiles p ... p.rol='super_admin')
--   invitaciones_medico_service_all  [ALL, TO service_role] USING true
--   invitaciones_clinica_admin_all   [ALL, TO PUBLIC]  USING EXISTS(perfiles p ... p.rol='super_admin')
--   invitaciones_clinica_service_all [ALL, TO service_role] USING true
--
-- O sea que un admin_pais entraba a la pantalla y veia la lista VACIA. Sin error, sin 42501: cero
-- filas, que se lee igual que "todavia no hay invitaciones". Y en clinicas era peor que inutil,
-- porque crear-invitacion-clinica SI lo autoriza: creaba la invitacion y despues no la veia.
--
-- ALCANCE: FOR ALL, no solo lectura (decision de Oscar). Un admin_pais tiene sobre las invitaciones
-- de SU pais el mismo alcance que el super_admin sobre todas. Eso ABRE superficie nueva: hasta hoy
-- el unico que podia INSERT/UPDATE/DELETE directo por PostgREST sobre estas tablas era super_admin
-- (la edge escribe con service_role, que tiene su propia policy y no necesita esta).
--
-- POR QUE `TO public` Y NO `TO authenticated`: para ser consistente con las dos *_admin_all que ya
-- estan. Se verifico que no arrastre el problema de la mig 284 — una policy se evalua con los
-- privilegios del LLAMANTE, asi que un EXISTS sobre `perfiles` revienta con 42501 para cualquier rol
-- que no pueda leer `perfiles`. Medido el 17-sep: anon.SELECT=true y authenticated.SELECT=true sobre
-- public.perfiles, asi que el EXISTS resuelve para todos y niega devolviendo false, no lanzando. Para
-- anon ademas auth.uid() es NULL y el EXISTS no matchea nunca. Las probes P719/P720 lo EJERCITAN en
-- vez de darlo por hecho.
--
-- SIN `WITH CHECK` EXPLICITO, y eso NO es un descuido — es lo que hace falta. Las dos *_admin_all
-- tampoco lo tienen, y en una policy FOR ALL el WITH CHECK omitido HEREDA el USING. Consecuencia,
-- que es justo lo que se queria:
--   INSERT -> corre solo el WITH CHECK heredado: la fila nueva tiene que ser de SU pais.
--   UPDATE -> corre el USING sobre la fila VIEJA y el WITH CHECK sobre la NUEVA: un admin_pais no
--             puede agarrar una fila suya y mandarla a otro pais, porque la version nueva ya no
--             satisface el predicado.
--   DELETE -> solo USING: borra dentro de su pais.
-- Un WITH CHECK explicito con el mismo texto seria ruido. Pero esto se AFIRMA porque se midio:
-- P717 prueba el INSERT cruzado y P718 el UPDATE que intenta mover el pais_id. Sin esas dos, la
-- suficiencia del WITH CHECK implicito es una creencia sobre el manual, no un hecho sobre esta base.
--
-- NO se tocan las policies de super_admin ni las de service_role.
-- ############################################################################################

CREATE POLICY invitaciones_medico_adminpais_all
ON public.invitaciones_medico
AS PERMISSIVE FOR ALL TO public
USING (
  EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = auth.uid()
      AND p.rol = 'admin_pais'
      AND p.pais_id = invitaciones_medico.pais_id
  )
);

CREATE POLICY invitaciones_clinica_adminpais_all
ON public.invitaciones_clinica
AS PERMISSIVE FOR ALL TO public
USING (
  EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = auth.uid()
      AND p.rol = 'admin_pais'
      AND p.pais_id = invitaciones_clinica.pais_id
  )
);

-- Re-verificacion: la migracion comprueba lo que dejo y ABORTA si no quedo asi. Las dos mitades
-- importan: que las policies nuevas existen con la forma esperada, y que las CUATRO viejas siguen
-- intactas — una policy PERMISSIVE de mas se combina con OR y anula el scoping de las otras (que es
-- exactamente como nacio el hallazgo de `medicos` en la mig 294).
DO $$
DECLARE v_mal text := '';
        v_n int;
        v_wc text;
BEGIN
  FOREACH v_wc IN ARRAY ARRAY['invitaciones_medico', 'invitaciones_clinica'] LOOP
    -- La nueva existe, es PERMISSIVE, FOR ALL y TO PUBLIC (polroles = {0} es PUBLIC).
    SELECT count(*) INTO v_n FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
     WHERE c.relname = v_wc AND p.polname = v_wc || '_adminpais_all'
       AND p.polpermissive AND p.polcmd = '*' AND p.polroles = '{0}'::oid[];
    IF v_n <> 1 THEN
      v_mal := v_mal || format('%s: la policy nueva no quedo PERMISSIVE/ALL/PUBLIC; ', v_wc);
    END IF;

    -- WITH CHECK omitido a proposito: tiene que HEREDAR el USING, no quedar en NULL por otra razon.
    IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
                WHERE c.relname = v_wc AND p.polname = v_wc || '_adminpais_all'
                  AND p.polwithcheck IS NOT NULL) THEN
      v_mal := v_mal || format('%s: la policy nueva trae WITH CHECK propio; ', v_wc);
    END IF;

    -- Las dos viejas de esa tabla siguen ahi.
    SELECT count(*) INTO v_n FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
     WHERE c.relname = v_wc AND p.polname IN (v_wc || '_admin_all', v_wc || '_service_all');
    IF v_n <> 2 THEN
      v_mal := v_mal || format('%s: quedaron %s de las 2 policies preexistentes; ', v_wc, v_n);
    END IF;

    -- Y no aparecio ninguna otra: 3 en total y ni una mas.
    SELECT count(*) INTO v_n FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid WHERE c.relname = v_wc;
    IF v_n <> 3 THEN
      v_mal := v_mal || format('%s: tiene %s policies, se esperaban 3; ', v_wc, v_n);
    END IF;

    IF NOT (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND c.relname = v_wc) THEN
      v_mal := v_mal || format('%s: RLS apagada; ', v_wc);
    END IF;
  END LOOP;

  IF v_mal <> '' THEN RAISE EXCEPTION '297: %', v_mal; END IF;
END $$;
