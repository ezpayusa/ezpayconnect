-- ############################################################################################
-- 286 — comercial_perfiles_sin_ficha(): a quien le falta la ficha de asesor
-- ############################################################################################
-- PARA QUE. La pantalla de fichas de asesor (D12) necesita una lista de a QUIEN darle ficha. Hoy
-- ese conjunto no existe en ningun lado: `crear-empleado` crea la cuenta (auth.users + perfiles +
-- usuario_roles) y NO toca `asesores_perfil`; `guardar_asesor_perfil` llena la ficha y falla con
-- PA009 si el perfil no tiene ya rol comercial. Entre los dos pasos hay un hueco —perfiles con rol
-- comercial y sin ficha— que hasta ahora solo se veia por SQL directo.
--
-- ES LECTURA, ASI QUE NO RECHAZA: el gate va en el WHERE dentro de COALESCE y un llamante sin
-- autoridad recibe CERO FILAS, no un 42501. Mismo patron que comercial_asesores_visibles (mig 283).
-- Un RAISE aca convertiria "no sos admin de este pais" en un error que el front tendria que
-- distinguir de "no hay nadie pendiente", que son dos cosas distintas y ninguna es un fallo.
--
-- EL PAIS ES PARAMETRO, y esta bien que lo sea: no hay fila previa de la que derivarlo —la pregunta
-- es justamente "quien NO tiene fila"—. Es la misma forma que guardar_material_comercial, y es
-- segura SOLO porque `puede_admin_pais` rechaza NULL y pais ajeno dentro del COALESCE: un p_pais_id
-- inventado no abre nada, devuelve vacio.
--
-- SECURITY DEFINER: hace falta porque `perfiles` tiene RLS con una sola policy de SELECT util
-- (`auth.uid() = id`), asi que un admin_pais no puede leer los perfiles de su propio pais por
-- consulta directa — el mismo motivo por el que existe la 283. Y por eso mismo el WHERE es la
-- unica barrera: la funcion lee perfiles SIN RLS.
--
-- Devuelve TRES columnas y ninguna sensible: nada de email, telefono, direccion_consultorio,
-- lat/lng ni avatar_url. El rol viaja porque el formulario tiene que distinguir asesor de
-- supervisor antes de guardar.
--
-- No agrega ningun ERRCODE: proximo libre sigue siendo PA030.
-- Lo miden P639-P643.
-- ############################################################################################

CREATE OR REPLACE FUNCTION public.comercial_perfiles_sin_ficha(p_pais_id uuid)
 RETURNS TABLE(id uuid, nombre_completo text, rol text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Mismo patron que comercial_asesores_visibles: gate en el WHERE con COALESCE, no RAISE — es
  -- lectura, no autorizado = 0 filas. El pais es PARAMETRO porque no hay fila previa de la que
  -- derivarlo (misma razon que guardar_material_comercial). NOT EXISTS contra asesores_perfil:
  -- antecedente en la mig 184 (medicos sin ficha).
  SELECT p.id, p.nombre_completo, p.rol
    FROM public.perfiles p
   WHERE COALESCE(private.puede_admin_pais(p_pais_id), false)
     AND p.pais_id = p_pais_id
     AND p.rol IN ('asesor_comercial','supervisor_comercial')
     AND NOT EXISTS (SELECT 1 FROM public.asesores_perfil ap WHERE ap.id = p.id)
$function$;

-- REVOKE primero y solo; GRANT despues. Toda funcion nueva en `public` nace con EXECUTE para
-- PUBLIC por los default privileges de Supabase: sin este REVOKE, `anon` la puede llamar.
REVOKE ALL ON FUNCTION public.comercial_perfiles_sin_ficha(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comercial_perfiles_sin_ficha(uuid) TO authenticated;

-- Re-verificacion: aborta la migracion si algo de esto no quedo.
DO $$
DECLARE v_oid oid; v_cols text[]; v_malas text;
BEGIN
  v_oid := to_regprocedure('public.comercial_perfiles_sin_ficha(uuid)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'la 286 no dejo la funcion creada';
  END IF;

  SELECT array_agg(a.name ORDER BY a.ord) INTO v_cols
    FROM unnest((SELECT proargnames FROM pg_proc WHERE oid = v_oid),
                (SELECT proargmodes FROM pg_proc WHERE oid = v_oid)) WITH ORDINALITY AS a(name, mode, ord)
   WHERE a.mode IN ('t','o');
  IF v_cols IS DISTINCT FROM ARRAY['id','nombre_completo','rol'] THEN
    RAISE EXCEPTION 'el tipo de retorno no es el contratado: %', v_cols;
  END IF;

  SELECT string_agg(c, ', ') INTO v_malas FROM unnest(v_cols) c
   WHERE c IN ('email','telefono','celular','avatar_url','lat','lng','bio')
      OR c LIKE 'direccion%' OR c LIKE 'foto%';
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'la RPC devuelve columnas sensibles: %', v_malas;
  END IF;

  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon puede ejecutar comercial_perfiles_sin_ficha';
  END IF;
  IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated NO puede ejecutar comercial_perfiles_sin_ficha';
  END IF;
END $$;
