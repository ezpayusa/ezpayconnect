-- ############################################################################################
-- 288 — tarjeta publica del asesor (D11), BACKEND
-- ############################################################################################
-- QUE ES. Una tarjeta de presentacion que el asesor puede mostrarle a un prospecto: su nombre,
-- cargo, territorio, telefonos y foto. Es la UNICA superficie anonima del modulo comercial.
--
-- COMO SE SIRVE, Y POR QUE ESO IMPORTA PARA ESTA MIGRACION
-- --------------------------------------------------------
-- NO se sirve por PostgREST. La resuelve una edge publica con service_role que llama a
-- `tarjeta_publica_por_token`. **`anon` nunca toca la base**: no tiene EXECUTE sobre ninguna de las
-- cuatro RPCs de este archivo, ni SELECT sobre las columnas nuevas. El molde es
-- confirmar-recepcion-receta. Por eso la resolutora se le concede SOLO a `service_role` — ni
-- siquiera a `authenticated`, que no tiene nada que hacer llamandola.
--
-- EL CONSENTIMIENTO SE EVALUA EN CADA REQUEST. No hay scheduler (cron.job esta vacio), asi que
-- revocar es puramente cambiar `tarjeta_publica` a false: el proximo request ya no responde. No hay
-- ventana, ni cache, ni trabajo diferido que pueda quedar pendiente.
--
-- POR QUE **NO** HAY GRANTS POR COLUMNA EN ESTA TABLA
-- ---------------------------------------------------
-- Medido antes de escribir esto: las 15 columnas de `asesores_perfil` tienen `attacl` NULL — la
-- tabla NO tiene privilegios por columna, `authenticated` tiene un unico SELECT de TABLA. Un
-- `ADD COLUMN` hereda ese grant, asi que `tarjeta_token` sera legible por `authenticated`, acotado
-- por la RLS de `asesores_perfil_select` a la propia cartera.
--
-- Y esta bien que sea asi. Introducir grants por columna aca convertiria esto en una migracion de
-- privilegios de ALTO RIESGO —es exactamente lo que rompio la lectura de visitas en la 280/281, y
-- lo que rompio prod en la 284— **a cambio de nada**: el token no es un secreto que proteja datos.
-- Lo unico que abre es una tarjeta que el asesor ENCENDIO a proposito y que contiene lo que el
-- mismo eligio publicar. Quien puede leer el token de su propia ficha ya es el dueno de la tarjeta.
-- NO agregar grants por columna a esta tabla.
--
-- LAS DOS RPCs DE CONSENTIMIENTO SON DOS, Y NO UNA CON PARAMETRO OPCIONAL
-- ----------------------------------------------------------------------
-- `tarjeta_set_consentimiento(boolean)` opera sobre `auth.uid()` y **no toma id de asesor**:
-- encender la tarjeta es una decision del dueno de la cara y del telefono, y nadie mas puede
-- tomarla por el. `tarjeta_apagar_de_asesor(uuid)` **solo apaga** y es la potestad del admin de
-- pais, que puede bajar una tarjeta pero nunca subir la de otro.
-- Una sola firma con `p_asesor_id uuid DEFAULT NULL` haria que el mismo codigo decidiera dos cosas
-- distintas segun un parametro, que es justo el patron que este modulo viene evitando desde la 272.
-- Separadas, cada gate se lee solo y ninguna puede hacer de mas.
--
-- Errcode nuevo: **PA030** (no tenes ficha de asesor). Proximo libre: PA031.
-- Lo miden P649-P661.
-- ############################################################################################

-- ============================================================================================
-- 1) Columnas. Idempotentes.
-- ============================================================================================
ALTER TABLE public.asesores_perfil
  ADD COLUMN IF NOT EXISTS tarjeta_token text NOT NULL
    DEFAULT encode(extensions.gen_random_bytes(32), 'hex');

-- El consentimiento nace APAGADO. Que el default sea false no es un detalle: una tarjeta que
-- naciera encendida publicaria el telefono de alguien que nunca lo pidio.
ALTER TABLE public.asesores_perfil
  ADD COLUMN IF NOT EXISTS tarjeta_publica boolean NOT NULL DEFAULT false;

-- Cuando se encendio. NULL = nunca. Al apagar NO se borra: queda el historico de que alguna vez
-- hubo consentimiento, que es un dato distinto de "esta publicada ahora".
ALTER TABLE public.asesores_perfil
  ADD COLUMN IF NOT EXISTS tarjeta_consentimiento_at timestamptz;

ALTER TABLE public.asesores_perfil
  ADD COLUMN IF NOT EXISTS tarjeta_token_rotado_at timestamptz;

-- UNIQUE sobre el token: la resolutora busca POR token, y dos fichas con el mismo token harian que
-- la respuesta dependiera del plan. Idempotente via pg_constraint.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.asesores_perfil'::regclass
                    AND conname = 'asesores_perfil_tarjeta_token_uniq') THEN
    ALTER TABLE public.asesores_perfil
      ADD CONSTRAINT asesores_perfil_tarjeta_token_uniq UNIQUE (tarjeta_token);
  END IF;
END $$;

-- ============================================================================================
-- 2a) tarjeta_set_consentimiento — el asesor enciende y apaga SU PROPIA tarjeta
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.tarjeta_set_consentimiento(p_activo boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_hay boolean;
BEGIN
  -- SIN parametro de asesor: el sujeto es auth.uid() y no hay forma de nombrar a otro.
  SELECT true INTO v_hay FROM public.asesores_perfil ap WHERE ap.id = auth.uid();
  IF NOT COALESCE(v_hay, false) THEN
    RAISE EXCEPTION 'PA030: no tenes ficha de asesor' USING ERRCODE = 'PA030';
  END IF;

  UPDATE public.asesores_perfil
     SET tarjeta_publica = COALESCE(p_activo, false),
         -- al ENCENDER se sella el momento; al apagar se deja el sello viejo.
         tarjeta_consentimiento_at = CASE WHEN COALESCE(p_activo, false)
                                          THEN now() ELSE tarjeta_consentimiento_at END,
         updated_at = now()
   WHERE id = auth.uid();
END
$function$;

-- ============================================================================================
-- 2b) tarjeta_apagar_de_asesor — SOLO apagar. La potestad del admin de pais.
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.tarjeta_apagar_de_asesor(p_asesor_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais uuid;
BEGIN
  -- LA LINEA QUE ATA: el pais sale de la FICHA, nunca de un parametro. Ficha inexistente ->
  -- v_pais NULL -> puede_admin_pais(NULL) da false dentro del COALESCE: "no existe" y "no podes"
  -- devuelven el MISMO 42501, y no se filtra existencia.
  SELECT ap.pais_id INTO v_pais FROM public.asesores_perfil ap WHERE ap.id = p_asesor_id;

  IF NOT COALESCE(private.puede_admin_pais(v_pais), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  -- Solo apaga. No hay rama que encienda: encender es del dueno.
  UPDATE public.asesores_perfil
     SET tarjeta_publica = false, updated_at = now()
   WHERE id = p_asesor_id;
END
$function$;

-- ============================================================================================
-- 2c) tarjeta_rotar_token — el asesor invalida el link que ya repartio
-- ============================================================================================
CREATE OR REPLACE FUNCTION public.tarjeta_rotar_token()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_hay boolean;
BEGIN
  SELECT true INTO v_hay FROM public.asesores_perfil ap WHERE ap.id = auth.uid();
  IF NOT COALESCE(v_hay, false) THEN
    RAISE EXCEPTION 'PA030: no tenes ficha de asesor' USING ERRCODE = 'PA030';
  END IF;

  UPDATE public.asesores_perfil
     SET tarjeta_token = encode(extensions.gen_random_bytes(32), 'hex'),
         tarjeta_token_rotado_at = now(),
         updated_at = now()
   WHERE id = auth.uid();
END
$function$;

-- ============================================================================================
-- 3) tarjeta_publica_por_token — la resolutora. La llama la EDGE, nadie mas.
-- ============================================================================================
-- DEVUELVE NULL, no un jsonb vacio. `'{}'::jsonb` es un objeto valido: un consumidor descuidado
-- haria `data.nombre_completo` -> undefined y pintaria una tarjeta en blanco como si existiera.
-- Un NULL de SQL obliga a decidir, y en la edge `if (!data) return 404` es la comprobacion natural.
--
-- LOS CUATRO CASOS DEVUELVEN LO MISMO —token inexistente, consentimiento apagado, ficha inactiva,
-- perfil inactivo— y eso es deliberado: distinguirlos convertiria la resolutora en un oraculo que
-- le confirma a un anonimo que cierto token EXISTE pero esta apagado. No hay nada que ganar
-- diciendolo y hay un enumerador que perder.
CREATE OR REPLACE FUNCTION public.tarjeta_publica_por_token(p_token text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT jsonb_build_object(
           'nombre_completo',    p.nombre_completo,
           'cargo',              ap.cargo,
           'territorio',         ap.territorio,
           'telefono',           ap.telefono,
           'celular',            ap.celular,
           'foto_publica_path',  ap.foto_publica_path)
    FROM public.asesores_perfil ap
    JOIN public.perfiles p ON p.id = ap.id
   WHERE ap.tarjeta_token = p_token
     AND ap.tarjeta_publica
     AND ap.activo
     AND COALESCE(p.activo, false);
$function$;

-- ============================================================================================
-- 4) PRIVILEGIOS. REVOKE primero y solo; GRANT despues.
-- ============================================================================================
REVOKE ALL ON FUNCTION public.tarjeta_set_consentimiento(boolean)  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tarjeta_apagar_de_asesor(uuid)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tarjeta_rotar_token()                FROM PUBLIC, anon;
-- La resolutora tambien se le quita a authenticated: la llama la edge con service_role y nadie mas.
REVOKE ALL ON FUNCTION public.tarjeta_publica_por_token(text)      FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.tarjeta_set_consentimiento(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tarjeta_apagar_de_asesor(uuid)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.tarjeta_rotar_token()               TO authenticated;
GRANT EXECUTE ON FUNCTION public.tarjeta_publica_por_token(text)     TO service_role;

-- ============================================================================================
-- 5) Re-verificacion. Aborta si algo de esto no quedo.
-- ============================================================================================
DO $$
DECLARE v_oid oid; v_def text; v_malas text; v_default text; v_falta text;
BEGIN
  -- las cuatro columnas
  SELECT string_agg(c, ', ') INTO v_falta
    FROM unnest(ARRAY['tarjeta_token','tarjeta_publica','tarjeta_consentimiento_at',
                      'tarjeta_token_rotado_at']) c
   WHERE NOT EXISTS (SELECT 1 FROM pg_attribute a
                      WHERE a.attrelid='public.asesores_perfil'::regclass
                        AND a.attname=c AND a.attnum>0 AND NOT a.attisdropped);
  IF v_falta IS NOT NULL THEN
    RAISE EXCEPTION 'faltan columnas: %', v_falta;
  END IF;

  -- el consentimiento NACE APAGADO. Si el default cambiara, toda ficha nueva se publicaria sola.
  SELECT pg_get_expr(d.adbin, d.adrelid) INTO v_default
    FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid='public.asesores_perfil'::regclass AND a.attname='tarjeta_publica';
  IF v_default IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'tarjeta_publica tiene default %, se esperaba false', COALESCE(v_default,'(ninguno)');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.asesores_perfil'::regclass
                    AND conname='asesores_perfil_tarjeta_token_uniq') THEN
    RAISE EXCEPTION 'falta el UNIQUE sobre tarjeta_token';
  END IF;

  -- la resolutora: quien puede llamarla
  v_oid := to_regprocedure('public.tarjeta_publica_por_token(text)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'la 288 no dejo tarjeta_publica_por_token creada';
  END IF;
  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon puede ejecutar tarjeta_publica_por_token';
  END IF;
  IF has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated puede ejecutar tarjeta_publica_por_token: la llama la edge, nadie mas';
  END IF;
  IF NOT has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role NO puede ejecutar tarjeta_publica_por_token: la edge no funcionaria';
  END IF;

  -- que devuelve: ni una columna de mas. Se mira el CUERPO, que es donde estan las claves.
  v_def := pg_get_functiondef(v_oid);
  SELECT string_agg(c, ', ') INTO v_malas
    FROM unnest(ARRAY['''id''','''email''','''pais_id''','''codigo_asesor''','''bio''',
                      '''supervisor_id''','''tarjeta_token''','''foto_path''']) c
   WHERE v_def LIKE '%'||c||'%';
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'la tarjeta publica expone campos prohibidos: %', v_malas;
  END IF;

  -- las tres de escritura: anon fuera, authenticated dentro
  SELECT string_agg(f, ', ') INTO v_malas FROM (
    SELECT p.oid::regprocedure::text AS f FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public'
       AND p.proname IN ('tarjeta_set_consentimiento','tarjeta_apagar_de_asesor','tarjeta_rotar_token')
       AND (has_function_privilege('anon', p.oid, 'EXECUTE')
            OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  ) s;
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'privilegios mal en: %', v_malas;
  END IF;
END $$;
