-- ############################################################################################
-- 295 — las 6 RPCs de medicos dejan de ser ejecutables por anon / PUBLIC
-- ############################################################################################
-- CONTINUACION DE LA 294. Esa migracion cerro la lectura directa de `public.medicos` (tres policies
-- con USING(true) y el GRANT de columna de anon). Pero estas seis funciones son SECURITY DEFINER con
-- dueno `postgres`: corren con los privilegios del dueno y **no pasan por la RLS**. Con EXECUTE
-- abierto a anon, el cierre de la 294 quedaba puenteado: cualquiera sin sesion podia listar, buscar y
-- contar medicos llamando a la RPC en vez de a la tabla.
--
-- ACL medido el 16-sep, identico en las cinco de lectura:
--   =X/postgres (PUBLIC), postgres=X, anon=X, authenticated=X, service_role=X
-- guardar_foto_medico tiene el mismo ACL SIN la entrada de PUBLIC.
--
-- POR QUE SE PUEDE REVOCAR SIN ROMPER NADA (medido, no asumido)
-- -------------------------------------------------------------
-- listar_medicos_por_pais, obtener_medicos_por_ids, contar_medicos_por_pais y contar_medicos_por_ids
-- tienen consumidores reales (CitasPage, useClinicaCitas, useAdmisionCitas, useWebAppCitas,
-- PaisDashboardPage, ClinicaDashboardPage), y TODOS viven bajo pantallas con sesion: el ACL de anon
-- nunca les hizo falta. guardar_foto_medico la usa MedicoPerfilPage, tambien autenticada, y su cuerpo
-- ya exige auth.uid() — pero depender solo de la logica interna deja el ACL como unica cosa que
-- alguien puede aflojar sin darse cuenta.
-- buscar_medicos(text,uuid,integer) NO tiene un solo consumidor: verificado con grep exacto de
-- `rpc('buscar_medicos'` en src/, supabase/functions/, scripts/ y api/ — cero. (Ojo con el grep por
-- subcadena: buscar_medicos_proveedor y buscar_medicos_paciente SI se usan, y son otras funciones.)
-- Ninguna de las seis es llamada por otra funcion (verificado contra el prosrc de todo pg_proc).
--
-- NO se toca el GRANT a authenticated ni a service_role: son entradas de ACL separadas y revocar
-- PUBLIC/anon no deberia moverlas — el DO del final lo verifica en vez de darlo por hecho.
-- ############################################################################################

REVOKE EXECUTE ON FUNCTION public.listar_medicos_por_pais(uuid)        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.buscar_medicos(text, uuid, integer)  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.obtener_medicos_por_ids(uuid[])      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.contar_medicos_por_pais(uuid)        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.contar_medicos_por_ids(uuid[])       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.guardar_foto_medico(text)            FROM PUBLIC, anon;

-- Re-verificacion: la migracion comprueba lo que dejo y ABORTA si no quedo asi. Las dos mitades
-- importan lo mismo: que anon/PUBLIC quedaron afuera, y que authenticated/service_role NO se cayeron
-- de paso (eso romperia seis pantallas con sesion).
DO $$
DECLARE f text; v_mal text := ''; oid_f oid;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.listar_medicos_por_pais(uuid)',
    'public.buscar_medicos(text,uuid,integer)',
    'public.obtener_medicos_por_ids(uuid[])',
    'public.contar_medicos_por_pais(uuid)',
    'public.contar_medicos_por_ids(uuid[])',
    'public.guardar_foto_medico(text)'
  ] LOOP
    oid_f := f::regprocedure::oid;
    IF has_function_privilege('anon', oid_f, 'EXECUTE') THEN
      v_mal := v_mal || format('%s: anon conserva EXECUTE; ', f);
    END IF;
    -- PUBLIC se mira DIRECTO en el ACL: su entrada es la que no tiene rol a la izquierda ('=X/...').
    -- Preguntarlo con has_function_privilege() de un rol cualquiera obligaria a elegir un rol que no
    -- tenga grant propio, y eso ata la verificacion a que ese rol exista.
    IF EXISTS (SELECT 1 FROM pg_proc pr, unnest(coalesce(pr.proacl, '{}'::aclitem[])) a
                WHERE pr.oid = oid_f AND a::text LIKE '=%') THEN
      v_mal := v_mal || format('%s: PUBLIC conserva EXECUTE; ', f);
    END IF;
    IF NOT has_function_privilege('authenticated', oid_f, 'EXECUTE') THEN
      v_mal := v_mal || format('%s: authenticated PERDIO EXECUTE; ', f);
    END IF;
    IF NOT has_function_privilege('service_role', oid_f, 'EXECUTE') THEN
      v_mal := v_mal || format('%s: service_role PERDIO EXECUTE; ', f);
    END IF;
  END LOOP;

  IF v_mal <> '' THEN RAISE EXCEPTION '295: %', v_mal; END IF;
END $$;
