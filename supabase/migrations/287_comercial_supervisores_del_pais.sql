-- ############################################################################################
-- 287 — comercial_supervisores_del_pais(): los candidatos validos para asignar_supervisor
-- ############################################################################################
-- PARA QUE. El selector de supervisor de la pantalla de fichas (D12) tiene que ofrecer SOLO
-- candidatos que el guard vaya a aceptar. `asignar_supervisor` no revalida nada: delega en el
-- trigger `guard_supervisor_asesor` de la 264, que rechaza con PA001 (rol), PA002 (ficha ausente o
-- inactiva), PA003 (otro pais) y PA004 (mas de dos niveles). Un selector que ofrezca cualquiera de
-- esos casos es una pantalla que deja elegir mal para que la base lo rechace despues — un rechazo
-- evitable no es una validacion.
--
-- Las tres condiciones que devuelve esta funcion son exactamente las tres que el guard exige y que
-- se pueden saber de antemano: rol supervisor_comercial (PA001), ficha activa (PA002) y mismo pais
-- (PA003). **PA004 NO se puede anticipar aca**: depende de a quien supervisa YA el candidato, y eso
-- cambia segun cual sea el asesor que se esta editando. Esa la sigue poniendo el guard.
--
-- GATE POR WHERE, NO POR RAISE: es lectura. Sin autoridad devuelve CERO FILAS, no 42501 — mismo
-- criterio que la 286. No agrega ningun errcode: proximo libre sigue siendo PA030.
--
-- El pais es PARAMETRO por la misma razon que en la 286: la pregunta no parte de una fila. Es
-- seguro solo porque `puede_admin_pais` rechaza NULL y pais ajeno dentro del COALESCE.
--
-- SECURITY DEFINER porque `perfiles` tiene RLS con una sola policy de SELECT util (`auth.uid() =
-- id`): sin esto, un admin_pais no leeria el nombre de nadie. Y por eso el WHERE es la unica
-- barrera. Devuelve DOS columnas y ninguna sensible.
--
-- Lo miden P644-P648.
-- ############################################################################################

CREATE OR REPLACE FUNCTION public.comercial_supervisores_del_pais(p_pais_id uuid)
 RETURNS TABLE(id uuid, nombre_completo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Candidatos validos para asignar_supervisor: rol supervisor_comercial, ficha activa, del pais
  -- pedido. Mismo patron de gate que comercial_perfiles_sin_ficha: lectura, no autorizado = 0
  -- filas, sin RAISE.
  SELECT ap.id, p.nombre_completo
    FROM public.asesores_perfil ap
    JOIN public.perfiles p ON p.id = ap.id
   WHERE COALESCE(private.puede_admin_pais(p_pais_id), false)
     AND ap.pais_id = p_pais_id
     AND ap.activo = true
     AND p.rol = 'supervisor_comercial'
$function$;

-- REVOKE primero y solo; GRANT despues. Toda funcion nueva en `public` nace con EXECUTE para
-- PUBLIC por los default privileges de Supabase: sin este REVOKE, `anon` la puede llamar.
REVOKE ALL ON FUNCTION public.comercial_supervisores_del_pais(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comercial_supervisores_del_pais(uuid) TO authenticated;

-- Re-verificacion: aborta la migracion si algo de esto no quedo.
DO $$
DECLARE v_oid oid; v_cols text[]; v_malas text;
BEGIN
  v_oid := to_regprocedure('public.comercial_supervisores_del_pais(uuid)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'la 287 no dejo la funcion creada';
  END IF;

  SELECT array_agg(a.name ORDER BY a.ord) INTO v_cols
    FROM unnest((SELECT proargnames FROM pg_proc WHERE oid = v_oid),
                (SELECT proargmodes FROM pg_proc WHERE oid = v_oid)) WITH ORDINALITY AS a(name, mode, ord)
   WHERE a.mode IN ('t','o');
  IF v_cols IS DISTINCT FROM ARRAY['id','nombre_completo'] THEN
    RAISE EXCEPTION 'el tipo de retorno no es el contratado: %', v_cols;
  END IF;

  SELECT string_agg(c, ', ') INTO v_malas FROM unnest(v_cols) c
   WHERE c IN ('email','telefono','celular','avatar_url','lat','lng','bio')
      OR c LIKE 'direccion%' OR c LIKE 'foto%';
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'la RPC devuelve columnas sensibles: %', v_malas;
  END IF;

  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon puede ejecutar comercial_supervisores_del_pais';
  END IF;
  IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated NO puede ejecutar comercial_supervisores_del_pais';
  END IF;
END $$;
