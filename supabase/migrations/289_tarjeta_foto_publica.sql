-- ############################################################################################
-- 289 — foto de la tarjeta publica del asesor (D11, pieza 3a)
-- ############################################################################################
-- QUE ES. El bucket donde vive la foto que se muestra en /t/<token>, y la RPC con la que el asesor
-- registra el path despues de subirla.
--
-- EL BUCKET ES PRIVADO, Y ESA ES LA DECISION CENTRAL DE ESTE ARCHIVO
-- ------------------------------------------------------------------
-- Un bucket PUBLICO entrega una URL de objeto que responde PARA SIEMPRE a cualquiera que la tenga.
-- Apagar `tarjeta_publica` mataria la tarjeta pero NO esa URL: la foto —una cara, el dato mas
-- personal de los seis que publica la tarjeta— seguiria sirviendose despues de revocar. Todo este
-- frente existe para que revocar mate el acceso de verdad y no solo esconda un boton (la 288 lo
-- garantiza para los datos; sin esto la foto seria la excepcion silenciosa).
-- Por eso el bucket es privado y la foto la sirve NUESTRA edge, que la resuelve por el MISMO gate
-- que la tarjeta: si `tarjeta_publica_por_token` devuelve NULL, no hay foto. Un solo gate, un solo
-- lugar donde se decide.
--
-- POR QUE EL MOLDE `fotos-medicos` NO SIRVE ACA. Medido contra prod: su policy de lectura es
-- `fotos_medicos_public_select`, `FOR SELECT` a `{public}` con la unica condicion
-- `bucket_id = 'fotos-medicos'`. O sea: cualquiera, sin sesion, lee cualquier objeto de ese bucket.
-- Copiarla aca reintroduciria por la puerta de atras la URL eterna que este archivo viene a evitar.
--
-- LO QUE SE MIDIO ANTES DE ESCRIBIR ESTO (prod, 7-sep-2026): las 39 policies de `storage.objects`
-- filtran TODAS por `bucket_id` — no hay ninguna incondicional. Importa porque una policy sin
-- `bucket_id` en su `USING` aplicaria tambien a un bucket nuevo, y este bucket habria nacido
-- publico sin que nadie escribiera una linea al respecto. No es el caso, pero se verifica igual en
-- el bloque final: si algun dia aparece una, esta migracion tiene que enterarse.
--
-- CONVENCION DE PATH: {asesor_id}/{uuid}.{ext}
-- El primer segmento es el scope —el mismo criterio que `fotos_medicos_owner_*`— y lo que ata las
-- cuatro policies. El segundo es un **uuid NUEVO POR CADA SUBIDA**, no un nombre fijo tipo
-- `foto.jpg`: con nombre fijo, reemplazar la foto dejaria la URL igual y habria que pelearse con
-- las caches de todo el camino para que el cambio se vea. Con uuid por subida el path viejo
-- simplemente deja de estar referenciado y el nuevo se ve al instante.
--
-- SIN SVG, a proposito. Un SVG es codigo: puede traer <script>, y esta imagen la sirve nuestra edge
-- desde nuestro dominio. Se aceptan solo jpeg, png y webp — que son datos y no programas.
--
-- SELECT PARA `authenticated`: SI, ACOTADO AL PROPIO PREFIJO. Justificacion, porque no es gratis.
-- El asesor necesita VER su propia foto en su pantalla (pieza 4) antes y despues de publicarla: un
-- consentimiento sobre una imagen que el titular no puede mirar no es un consentimiento informado.
-- La policy lo acota a `split_part(name,'/',1) = auth.uid()::text`, o sea a lo suyo y nada mas:
-- ningun asesor ve la foto de otro, ni el supervisor, ni el admin de pais. Y no toca la superficie
-- publica, que no pasa por `authenticated` sino por el `service_role` de la edge.
-- NI `anon` NI `public` tienen policy sobre este bucket. Ninguna. Es lo que se verifica al final.
--
-- Errcodes nuevos: **PA031** (no tenes ficha de asesor, en esta RPC) y **PA032** (el path no
-- empieza con tu propio id). Proximo libre: PA033. Los miden P662-P668.
-- ############################################################################################

-- ============================================================================================
-- 1) Bucket. Idempotente.
-- ============================================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('tarjetas-asesor','tarjetas-asesor', false, 2097152,
   ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================================
-- 2) Policies. Las CUATRO son del propio asesor y ninguna alcanza a anon ni a public.
--    Molde: fotos_medicos_owner_insert/update/delete (el mismo split_part del segmento 1), pero
--    SIN su fotos_medicos_public_select, que es justo la que no se puede copiar.
-- ============================================================================================
DROP POLICY IF EXISTS tarjeta_foto_owner_insert ON storage.objects;
CREATE POLICY tarjeta_foto_owner_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'tarjetas-asesor'
    AND split_part(name, '/', 1) = auth.uid()::text
  );

DROP POLICY IF EXISTS tarjeta_foto_owner_update ON storage.objects;
CREATE POLICY tarjeta_foto_owner_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'tarjetas-asesor'
    AND split_part(name, '/', 1) = auth.uid()::text
  );

DROP POLICY IF EXISTS tarjeta_foto_owner_delete ON storage.objects;
CREATE POLICY tarjeta_foto_owner_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'tarjetas-asesor'
    AND split_part(name, '/', 1) = auth.uid()::text
  );

-- El SELECT acotado del que habla la cabecera. Lo unico que habilita es "vea SU foto".
DROP POLICY IF EXISTS tarjeta_foto_owner_select ON storage.objects;
CREATE POLICY tarjeta_foto_owner_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'tarjetas-asesor'
    AND split_part(name, '/', 1) = auth.uid()::text
  );

-- ============================================================================================
-- 3) RPC: el asesor registra el path de SU foto.
-- ============================================================================================
-- EL PATH LO ARMA EL CLIENTE Y NO SE CONFIA EN EL. Molde PA023 de guardar_material_comercial: la
-- policy de storage ya impide SUBIR fuera del propio prefijo, pero esta RPC escribe una columna de
-- otra tabla y podria apuntarla a cualquier lado. Sin este guard, un asesor podria registrar como
-- suya la foto de otro y publicar la cara ajena en su propia tarjeta. Se valida contra auth.uid(),
-- no contra un parametro.
CREATE OR REPLACE FUNCTION public.guardar_foto_publica_asesor(p_path text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_hay boolean; v_path text;
BEGIN
  -- SIN parametro de asesor: el sujeto es auth.uid(), igual que tarjeta_set_consentimiento.
  SELECT true INTO v_hay FROM public.asesores_perfil ap WHERE ap.id = auth.uid();
  IF NOT COALESCE(v_hay, false) THEN
    RAISE EXCEPTION 'PA031: no tenes ficha de asesor' USING ERRCODE = 'PA031';
  END IF;

  -- NULL o vacio = BORRAR la foto. Es parte del mismo derecho que enciende la tarjeta: quien puede
  -- publicar su cara tiene que poder despublicarla sin depender de nadie. No es un caso de error.
  v_path := NULLIF(btrim(COALESCE(p_path, '')), '');

  IF v_path IS NOT NULL THEN
    -- Exactamente {asesor_id}/{archivo}: el prefijo tiene que ser el propio uuid y tiene que haber
    -- un segundo segmento no vacio. Se rechaza tambien un tercer segmento, porque un path mas
    -- profundo no lo produce ningun cliente nuestro y no hay por que aceptarlo.
    IF split_part(v_path, '/', 1) IS DISTINCT FROM auth.uid()::text
       OR NULLIF(btrim(split_part(v_path, '/', 2)), '') IS NULL
       OR split_part(v_path, '/', 3) <> ''
    THEN
      RAISE EXCEPTION 'PA032: el path % no es {tu_id}/{archivo}', v_path USING ERRCODE = 'PA032';
    END IF;
  END IF;

  UPDATE public.asesores_perfil
     SET foto_publica_path = v_path,
         updated_at = now()
   WHERE id = auth.uid();
END
$function$;

REVOKE ALL ON FUNCTION public.guardar_foto_publica_asesor(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_foto_publica_asesor(text) TO authenticated;

COMMENT ON FUNCTION public.guardar_foto_publica_asesor(text) IS
'D11 pieza 3a: el asesor registra el path de SU foto publica. Opera sobre auth.uid() y no toma id
de asesor. Valida que el path empiece con su propio uuid (PA032): la policy de storage impide
subir fuera del prefijo propio, pero esta RPC escribe una columna y sin el guard se podria
registrar la foto de otro. p_path NULL o vacio borra la foto.';

-- La 264 documento esta columna como "bucket publico de la tarjeta comercial". Dejo de ser cierto
-- en esta migracion y un comentario que miente sobre si algo es publico es peor que no tenerlo.
COMMENT ON COLUMN public.asesores_perfil.foto_publica_path IS
'Path en el bucket PRIVADO tarjetas-asesor, {asesor_id}/{uuid}.{ext}. La foto NO se sirve por una
URL de storage: la sirve la edge tarjeta-asesor bajo el mismo gate que la tarjeta (mig 289). El
bucket es privado a proposito — una URL publica de objeto sobreviviria a revocar el consentimiento.
NULL = sin foto.';

-- ============================================================================================
-- 4) Re-verificacion. La migracion ABORTA si algo de esto no esta: un bucket sin policy, o con la
--    policy equivocada, es el modo de falla de FASE 4.
-- ============================================================================================
DO $$
DECLARE v_n int; v_malas text; v_b RECORD; v_oid oid;
BEGIN
  -- 4.1 el bucket existe y es PRIVADO, con sus limites
  SELECT * INTO v_b FROM storage.buckets WHERE id = 'tarjetas-asesor';
  IF v_b IS NULL THEN RAISE EXCEPTION 'no existe el bucket tarjetas-asesor'; END IF;
  IF v_b.public THEN
    RAISE EXCEPTION 'tarjetas-asesor quedo PUBLICO: la URL del objeto sobreviviria a revocar el consentimiento';
  END IF;
  IF v_b.file_size_limit IS DISTINCT FROM 2097152 THEN
    RAISE EXCEPTION 'tarjetas-asesor sin el limite de 2 MB (es %)', v_b.file_size_limit;
  END IF;
  IF v_b.allowed_mime_types IS DISTINCT FROM ARRAY['image/jpeg','image/png','image/webp'] THEN
    RAISE EXCEPTION 'tarjetas-asesor con mime types inesperados: %', v_b.allowed_mime_types;
  END IF;
  IF 'image/svg+xml' = ANY(COALESCE(v_b.allowed_mime_types, ARRAY[]::text[])) THEN
    RAISE EXCEPTION 'tarjetas-asesor acepta SVG: un SVG es codigo y esto lo sirve nuestra edge';
  END IF;

  -- 4.2 las CUATRO policies existen
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND policyname IN ('tarjeta_foto_owner_insert','tarjeta_foto_owner_update',
                        'tarjeta_foto_owner_delete','tarjeta_foto_owner_select');
  IF v_n <> 4 THEN
    RAISE EXCEPTION 'BUCKET SIN POLICY: se esperaban 4 policies de tarjetas-asesor, hay % — es el modo de falla de FASE 4', v_n;
  END IF;

  -- 4.3 NINGUNA de las cuatro alcanza a anon ni a public, y las cuatro nombran el bucket
  SELECT string_agg(policyname, ', ') INTO v_malas FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND policyname LIKE 'tarjeta_foto_%'
     AND ( roles::text[] && ARRAY['anon','public']
        OR COALESCE(qual, with_check) NOT LIKE '%tarjetas-asesor%' );
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'policies de la foto abiertas a anon/public o sin filtrar el bucket: %', v_malas;
  END IF;

  -- 4.4 nadie MAS le da acceso a este bucket. Una policy que no filtre por bucket_id aplicaria
  -- tambien aca y lo haria publico sin que este archivo diga nada. Medido 7-sep-2026: cero.
  SELECT string_agg(policyname, ', ') INTO v_malas FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND COALESCE(qual, '') NOT LIKE '%bucket_id%'
     AND COALESCE(with_check, '') NOT LIKE '%bucket_id%';
  IF v_malas IS NOT NULL THEN
    RAISE EXCEPTION 'hay policies de storage.objects SIN filtro de bucket, alcanzan a tarjetas-asesor: %', v_malas;
  END IF;

  -- 4.5 privilegios de la RPC
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='guardar_foto_publica_asesor';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'no existe guardar_foto_publica_asesor'; END IF;
  IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon puede ejecutar guardar_foto_publica_asesor';
  END IF;
  IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated NO puede ejecutar guardar_foto_publica_asesor';
  END IF;

  -- 4.6 el guard del path esta en el cuerpo. Si alguien lo saca, esta migracion no revalida sola:
  -- que el texto este es lo unico que se puede afirmar sin ejecutar (lo EJERCITAN P664-P666).
  IF pg_get_functiondef(v_oid) NOT LIKE '%PA032%' THEN
    RAISE EXCEPTION 'guardar_foto_publica_asesor sin el guard PA032 del path';
  END IF;
END $$;
