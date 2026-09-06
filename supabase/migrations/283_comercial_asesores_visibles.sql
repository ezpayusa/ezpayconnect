-- ############################################################################################
-- 283 — comercial_asesores_visibles(): el nombre del asesor, SIN abrir public.perfiles
-- ############################################################################################
-- EL PROBLEMA (medido, no supuesto)
-- ---------------------------------
-- El supervisor ve "sin asesor" en su cartera y "QA-ASE-01" en vez del nombre en Equipo. La causa
-- NO es el front —el select pide el embed y la pantalla lo pinta— ni un privilegio de columna:
-- `authenticated` tiene SELECT de tabla entera sobre perfiles. La causa es la RLS de perfiles, que
-- tiene UNA sola policy de SELECT util: `Ver propio perfil` con `auth.uid() = id`. Ningun rol
-- comercial aparece en ninguna policy, asi que el embed a perfiles vuelve NULL para todo asesor que
-- no sea uno mismo. Medido bajo impersonacion: el supervisor ve su propia fila de asesores_perfil y
-- la de su asesor a cargo (el chokepoint funciona), pero el JOIN a perfiles devuelve NULL para el
-- asesor y el nombre para si mismo — exactamente la linea que traza `auth.uid() = id`.
--
-- POR QUE UNA RPC Y NO UNA POLICY
-- -------------------------------
-- perfiles NO tiene privilegio por columna: `authenticated` tiene SELECT de TABLA. Una policy nueva
-- de SELECT expondria las 16 columnas de golpe — email, telefono, direccion_consultorio, lat/lng
-- del consultorio y avatar_url incluidos — a cambio de un solo campo. La RPC devuelve 5 columnas y
-- ni una mas. Es la misma decision que el frente de metricas: dar acceso por funcion, nunca
-- ensanchando la RLS de la tabla que tiene los datos.
--
-- EL WHERE ES LA UNICA BARRERA. LEER ESTO ANTES DE TOCAR EL GATE.
-- --------------------------------------------------------------
-- Medido: perfiles y asesores_perfil son de `postgres`, que tiene rolbypassrls = true, y ninguna de
-- las dos tiene FORCE ROW LEVEL SECURITY. Una funcion SECURITY DEFINER cuyo owner es postgres, por
-- lo tanto, lee las dos tablas SIN RLS. Aca no hay una policy detras haciendo de red: si el gate
-- deja pasar, sale la lista entera de asesores del sistema con nombre.
-- Por eso el gate va envuelto ENTERO en COALESCE(..., false). Sin ese envoltorio, un usuario sin
-- fila en perfiles (get_auth_user_rol() -> NULL, mi_pais() -> NULL) produce un WHERE que evalua a
-- NULL, y un NULL en un WHERE filtra igual que false... hoy. El COALESCE lo hace explicito y
-- sobrevive a que alguien reordene los operandos manana. Es la leccion de PA-FAILOPEN.
--
-- EL GATE ES UNA COPIA LITERAL de la policy `asesores_perfil_select`, con las mismas dos ramas y el
-- mismo `a(a)`. No se reescribe la regla de quien ve a quien: si manana cambia, cambia en los dos
-- lados o se nota. `private.asesores_a_cargo()` y `private.mi_pais()` son SECURITY DEFINER STABLE y
-- resuelven al LLAMANTE, no al owner: SECURITY DEFINER cambia el rol de ejecucion, no el GUC
-- `request.jwt.claims` del que sale auth.uid().
--
-- No se inlinea: Postgres no aplica inlining de funciones SQL con prosecdef, asi que el gate no se
-- puede fusionar con el query del llamante ni perder el contexto del DEFINER.
--
-- LO QUE **NO** HACE ESTA MIGRACION: no crea ni toca ninguna policy de perfiles. Despues de
-- aplicarla, el supervisor sigue SIN poder leer la fila de perfiles de su asesor por PostgREST
-- directo. P614 fija esa negativa: es la que prueba que no abrimos la tabla.
-- ############################################################################################

CREATE OR REPLACE FUNCTION public.comercial_asesores_visibles()
RETURNS TABLE(id uuid, codigo_asesor text, nombre_completo text,
              activo boolean, supervisor_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  -- INNER JOIN y no LEFT: asesores_perfil.id es FK a perfiles(id) ON DELETE RESTRICT, asi que una
  -- ficha sin perfil no puede existir (medido: 0 huerfanos). El JOIN no esconde nada.
  SELECT ap.id, ap.codigo_asesor, p.nombre_completo, ap.activo, ap.supervisor_id
    FROM public.asesores_perfil ap
    JOIN public.perfiles p ON p.id = ap.id
   WHERE COALESCE(
           (public.get_auth_user_rol() = 'super_admin')
           OR (ap.pais_id = private.mi_pais()
               AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a(a)
                            WHERE a.a = ap.id)),
         false)
$function$;

-- REVOKE primero y solo; GRANT despues. Toda funcion nueva en `public` nace con EXECUTE para
-- PUBLIC por los default privileges de Supabase: sin este REVOKE, `anon` la puede llamar.
REVOKE ALL ON FUNCTION public.comercial_asesores_visibles() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comercial_asesores_visibles() TO authenticated;

-- Re-verificacion. Aborta la migracion si algo de esto no quedo.
DO $$
DECLARE v_oid oid; v_cols text[]; v_malas text; v_pol int;
BEGIN
  v_oid := to_regprocedure('public.comercial_asesores_visibles()');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'la 283 no dejo la funcion creada';
  END IF;

  -- las 5 columnas del contrato, en orden, y NINGUNA sensible
  SELECT array_agg(a.name ORDER BY a.ord) INTO v_cols
    FROM unnest(
      (SELECT proargnames FROM pg_proc WHERE oid = v_oid),
      (SELECT proargmodes FROM pg_proc WHERE oid = v_oid)
    ) WITH ORDINALITY AS a(name, mode, ord)
   WHERE a.mode IN ('t','o');
  IF v_cols IS DISTINCT FROM ARRAY['id','codigo_asesor','nombre_completo','activo','supervisor_id'] THEN
    RAISE EXCEPTION 'el tipo de retorno no es el contratado: %', v_cols;
  END IF;

  SELECT string_agg(c, ', ') INTO v_malas FROM unnest(v_cols) c
   WHERE c IN ('email','telefono','celular','avatar_url','lat','lng','bio')
      OR c LIKE 'direccion%' OR c LIKE 'foto%';
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'la RPC devuelve columnas sensibles: %', v_malas;
  END IF;

  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon puede ejecutar comercial_asesores_visibles';
  END IF;
  IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated NO puede ejecutar comercial_asesores_visibles';
  END IF;

  -- Y la promesa central: NO tocamos perfiles. Sus 5 policies siguen siendo las mismas.
  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE schemaname='public' AND tablename='perfiles';
  IF v_pol <> 5 THEN
    RAISE EXCEPTION 'perfiles quedo con % policies (esperaba las 5 de siempre): esta migracion no debe tocarlas', v_pol;
  END IF;
END $$;
