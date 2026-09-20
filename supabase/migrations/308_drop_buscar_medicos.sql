-- ============================================================================================
-- 308 — DROP de public.buscar_medicos(text, uuid, integer)
-- ============================================================================================
-- Origen: docs/CENSO_SEGURIDAD_TRANSVERSAL_2026-09-20.md, seccion F4 (hallazgo #7), punto #1.
--
-- POR QUE SE BORRA EN VEZ DE PARCHEARSE. Es la quinta del frente de RPCs de medicos y la unica
-- SIN UN SOLO CONSUMIDOR. Las otras cuatro (listar_medicos_por_pais, obtener_medicos_por_ids,
-- contar_medicos_por_pais, contar_medicos_por_ids) se endurecieron en la mig 307; esta habria
-- necesitado el mismo `SET search_path` y el mismo gate de pais solo para seguir sin usarse.
-- Codigo muerto con SECURITY DEFINER es superficie de ataque que nadie mira: no se parchea, se
-- saca. La mig 295 ya lo habia dejado escrito ("buscar_medicos(text,uuid,integer) NO tiene un
-- solo consumidor"), y esta migracion actua sobre eso.
--
-- ESTADO QUE TENIA AL BORRARLA (re-medido el 24-sep, no copiado del censo):
--   firma      : public.buscar_medicos(text,uuid,integer)
--   args       : p_query text, p_pais_id uuid, p_limit integer
--   secdef     : true
--   proconfig  : NINGUNO  (sin SET search_path — el mismo defecto que cerro la 307 en las otras 4)
--   anon       : false (revocado por la mig 295)
--   auth/srole : true / true
--   proacl     : postgres=X/postgres authenticated=X/postgres service_role=X/postgres
--
-- CENSO DE CALLERS, re-verificado hoy (habian pasado varios dias desde el censo original):
--   · `rpc('buscar_medicos'` con delimitador sobre TODO el repo: 0. El unico hit es el comentario
--     de la propia mig 295 documentando que no tiene consumidores.
--   · `buscar_medicos_proveedor` y `buscar_medicos_paciente` SI se usan, y son OTRAS funciones.
--     Un grep por subcadena las confunde; el de este censo usa delimitador.
--   · En la base: 0 funciones la mencionan, 0 vistas, 0 policies, 0 triggers, 0 filas en pg_depend.
--
-- LO UNICO QUE LA USA ES EL HARNESS: la probe P698 de tests/rls/probes_escritura.sql la ejercita
-- como `anon` esperando 42501. Con la funcion borrada eso pasa a dar 42883 (undefined_function),
-- que cae en su `WHEN OTHERS` y pone el harness en ROJO. P698 se actualiza junto con esta
-- migracion: deja de ser "anon no puede ejecutarla" y pasa a ser "la funcion ya no existe".
--
-- DEFINICION COMPLETA AL MOMENTO DEL DROP, para que quede en el historial y se pueda recrear:
--
--   CREATE OR REPLACE FUNCTION public.buscar_medicos(p_query text DEFAULT NULL::text, p_pais_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 10)
--    RETURNS TABLE(id uuid, nombre_completo text, especialidad text, foto_url text)
--    LANGUAGE plpgsql
--    SECURITY DEFINER
--   AS $function$
--   BEGIN
--     RETURN QUERY
--     SELECT * FROM (
--       SELECT m.id, m.nombre_completo, m.especialidad, m.foto_url
--       FROM medicos m
--       WHERE m.activo = true AND (p_pais_id IS NULL OR m.pais_id = p_pais_id OR m.pais_id IS NULL)
--         AND (p_query IS NULL OR p_query = '' OR m.nombre_completo ILIKE '%' || p_query || '%' OR m.especialidad ILIKE '%' || p_query || '%')
--       UNION
--       SELECT p.id, p.nombre_completo, NULL::TEXT, p.avatar_url
--       FROM perfiles p
--       WHERE p.rol = 'medico' AND p.activo = true
--         AND (p_pais_id IS NULL OR p.pais_id = p_pais_id OR p.pais_id IS NULL)
--         AND NOT EXISTS (SELECT 1 FROM medicos m WHERE m.id = p.id)
--         AND (p_query IS NULL OR p_query = '' OR p.nombre_completo ILIKE '%' || p_query || '%')
--     ) combined
--     ORDER BY nombre_completo LIMIT p_limit;
--   END;
--   $function$
--
--   NOTA si alguna vez se recrea: ese cuerpo tiene los DOS defectos que la mig 307 cerro en sus
--   hermanas — sin `SET search_path`, y el filtro `OR m.pais_id IS NULL` que cuela a los medicos
--   sin pais. Recrearla tal cual seria reintroducir el hallazgo. Ademas nacería con el ACL por
--   defecto (`anon=X`) salvo que se revoque explicitamente: la fabrica de default privilege esta
--   cerrada desde la mig 301 para FUNCIONES de `public`, asi que hoy ya no, pero conviene
--   verificarlo antes de asumirlo.
--
-- SIN DROP ... CASCADE, a proposito: si algo dependiera de ella que el censo no vio, el DROP a
-- secas FALLA y avisa, en vez de llevarse ese objeto por delante en silencio.
-- ============================================================================================

DROP FUNCTION public.buscar_medicos(text, uuid, integer);

-- ============================================================================================
-- AUTOCHEQUEO — aborta si la funcion sigue existiendo, y confirma que no se llevo puesta a
-- ninguna de sus hermanas (un DROP con la firma equivocada podria haber apuntado a otra).
-- ============================================================================================
DO $$
DECLARE
  v_n      int;
  v_faltan text;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'buscar_medicos';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '308: buscar_medicos sigue existiendo (% sobrecarga(s))', v_n;
  END IF;

  -- Las hermanas tienen que seguir en pie: las cuatro de la mig 307 y las dos que se le parecen
  -- por el nombre y que SI tienen consumidores.
  SELECT string_agg(e, ', ') INTO v_faltan
    FROM unnest(ARRAY['listar_medicos_por_pais','obtener_medicos_por_ids',
                      'contar_medicos_por_pais','contar_medicos_por_ids',
                      'buscar_medicos_paciente','buscar_medicos_proveedor']) e
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = e);
  IF v_faltan IS NOT NULL THEN
    RAISE EXCEPTION '308: el DROP se llevo funciones que debian quedar: %', v_faltan;
  END IF;

  RAISE NOTICE '308 OK: buscar_medicos borrada, las 6 hermanas intactas';
  PERFORM set_config('m308.auto', 'OK (buscar_medicos borrada; las 6 hermanas intactas)', true);
END $$;
