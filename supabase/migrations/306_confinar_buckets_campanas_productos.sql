-- ============================================================================================
-- 306 — los buckets `campanas` y `productos` se confinan por empresa
-- ============================================================================================
-- Origen: docs/CENSO_SEGURIDAD_TRANSVERSAL_2026-09-20.md, seccion F5 (hallazgo #5), mas el recon
-- de call-sites del 23-sep.
--
-- QUE PASABA. Las policies de escritura de estos dos buckets miraban SOLO el bucket y el rol:
--     "Usuarios autenticados pueden subir campanas"     INSERT  CHECK (bucket_id='campanas'  AND auth.role()='authenticated')
--     "Usuarios autenticados pueden eliminar campanas"  DELETE  USING (bucket_id='campanas'  AND auth.role()='authenticated')
--     "Autenticados suben productos"                    INSERT  CHECK (bucket_id='productos' AND auth.role()='authenticated')
--     "Autenticados eliminan productos"                 DELETE  USING (bucket_id='productos' AND auth.role()='authenticated')
-- Sin una sola condicion de pertenencia: cualquier cuenta autenticada —un paciente, un visitador
-- de otra empresa— podia subir o BORRAR la creatividad de cualquier anunciante. Los dos buckets
-- son publicos, asi que un objeto subido ahi se sirve desde el dominio del producto.
--
-- LOS TRES UPLOADERS REALES, censados sobre todo el repo:
--   src/proveedor/hooks/useSolicitudesCampana.ts:51,108  -> campanas   `${empresa.id}/${Date.now()}.ext`
--   src/proveedor/hooks/useProductosEmpresa.ts:51,148    -> productos  `${empresa.id}/${Date.now()}.ext`
--   src/webapp/components/CampanasPublicitariasContent.tsx:90 -> campanas  `${Date.now()}.ext`  (PLANO)
-- El tercero vive en `src/webapp/components/` pero lo monta
-- `src/pages/planes/PlanesPublicidadConfigPage.tsx:334`, el form ADMIN de house-ads. Por eso sube
-- sin carpeta de empresa, y por eso un confinamiento a secas romperia ese flujo.
-- Ningun `.remove()` del front toca estos dos buckets (solo `material-comercial` y
-- `tarjetas-asesor`), o sea que el DELETE abierto de hoy no lo usa nadie.
--
-- ESTADO DE LOS OBJETOS (medido): 14 en `campanas`, 0 en `productos`. 13 de los 14 ya estan bajo
-- `<empresa_id>/...` y quedan confinados por construccion — el primer segmento se verifico contra
-- las tablas y es `empresas_proveedoras.id`, no un perfil ni una cuenta. El objeto 14,
-- `1780525121711.png`, es PLANO, lo subio un super_admin el 3-jun y NO lo referencia ninguna
-- campana ni ninguna solicitud. No hace falta migrar ningun path.
--
-- POR QUE `split_part` Y NO `storage.foldername`. Medido:
--     (storage.foldername('1780525121711.png'))[1]  ->  NULL
--     split_part('1780525121711.png','/',1)          ->  '1780525121711.png'
-- Con `foldername` un path plano da NULL, y `NULL = <uuid>` es NULL: la policy no se cumple, pero
-- por la via trivaluada que este proyecto viene cerrando desde la mig 265. Con `split_part` la
-- comparacion es un texto contra un uuid, que da FALSE — fail-closed explicito. Ademas es el molde
-- que ya usan `comprobantes_scoped_*` y `resultados_scoped_*` en esta misma tabla.
--
-- LA ASIMETRIA ES DELIBERADA. `campanas` lleva el brazo de super_admin porque el form de house-ads
-- sube plano y sin empresa; sin ese brazo se rompe. `productos` NO lo lleva: el unico uploader es
-- el hook de proveedor, y la policy de la tabla duena (`productos_empresa`) le da al admin solo
-- SELECT ("Admin ezpay ve todos los productos"). Agregarselo seria conceder un permiso que no usa
-- nadie. Si algun dia hace falta, es una linea.
--
-- EL COALESCE del brazo de super_admin no es decorativo: `private.tiene_rol` podria devolver NULL
-- y `false OR NULL` es NULL. Una policy trata NULL como "no cumple", asi que el resultado seria el
-- mismo — pero se deja explicito para no depender de esa lectura, que es exactamente la clase de
-- suposicion que costo las migs 265-271 y 300.
--
-- QUE NO SE TOCA: las dos policies de lectura publica ("Lectura publica de campanas" / "Lectura
-- publica productos", `USING (bucket_id = '...')` a `public`), el flag `public=true` de los
-- buckets, los MIME permitidos ni el limite de 5 MB.
--
-- NO HAY POLICY DE UPDATE en estos buckets y esta migracion NO la agrega. Los tres uploads usan
-- `upsert: true`, pero el nombre lleva `Date.now()` y nunca colisiona, asi que el UPDATE no se
-- dispara; si alguna vez colisionara, ya estaria fallando hoy. Crearla seria conceder una
-- capacidad nueva, no cerrar un agujero.
--
-- DEUDA ANOTADA, NO TOCADA AQUI:
--   1. `1780525121711.png` quedo huerfano (0 campanas, 0 solicitudes lo usan). Borrarlo es un
--      cambio de DATOS, no de codigo.
--   2. `CampanasPublicitariasContent.tsx` deberia subir bajo un prefijo fijo (p. ej. `house/`) y
--      vivir en `src/pages/planes/`, no en `src/webapp/components/`. Eso permitiria confinar
--      tambien al admin en vez de darle el bucket entero. Es cambio de front + migracion de un
--      path: frente propio.
--
-- NOTA DE MEDICION: `storage.objects` trae un trigger BEFORE DELETE (`protect_objects_delete`)
-- que rechaza cualquier borrado directo por SQL salvo que `storage.allow_delete_query` = 'true'.
-- El autochequeo lo levanta LOCAL a su transaccion para que el DELETE lo decida la policy y no el
-- trigger; sin eso, los casos de borrado darian verde por el motivo equivocado. El INSERT no
-- tiene guard equivalente y se ejercita directo.
--
-- Probes: P766-P770 en tests/rls/probes_escritura.sql.
-- ============================================================================================

DROP POLICY IF EXISTS "Usuarios autenticados pueden subir campanas"    ON storage.objects;
DROP POLICY IF EXISTS "Usuarios autenticados pueden eliminar campanas" ON storage.objects;
DROP POLICY IF EXISTS "Autenticados suben productos"                   ON storage.objects;
DROP POLICY IF EXISTS "Autenticados eliminan productos"                ON storage.objects;

DROP POLICY IF EXISTS campanas_scoped_insert  ON storage.objects;
DROP POLICY IF EXISTS campanas_scoped_delete  ON storage.objects;
DROP POLICY IF EXISTS productos_scoped_insert ON storage.objects;
DROP POLICY IF EXISTS productos_scoped_delete ON storage.objects;

-- campanas: la empresa dueña del prefijo, o el super_admin (house-ads, que suben planas).
CREATE POLICY campanas_scoped_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'campanas'
    AND ( split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
          OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false) )
  );

CREATE POLICY campanas_scoped_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'campanas'
    AND ( split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
          OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false) )
  );

-- productos: solo la empresa dueña del prefijo. Sin brazo de admin, a proposito (ver header).
CREATE POLICY productos_scoped_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'productos'
    AND split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
  );

CREATE POLICY productos_scoped_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'productos'
    AND split_part(name, '/', 1) = (public.mi_empresa_proveedor())::text
  );

-- ============================================================================================
-- AUTOCHEQUEO — aborta si algo no quedo como se pidio. Ejercita los roles con SET ROLE y ESCRIBE
-- de verdad en storage.objects; cada prueba vive en una SUBTRANSACCION de plpgsql que se revierte
-- con un RAISE propio. Esta migracion se aplica FUERA de una transaccion explicita: un INSERT
-- suelto quedaria como un objeto fantasma en el bucket.
-- ============================================================================================
DO $$
DECLARE
  -- cuentas de proveedor REALES de dos empresas distintas, las dos con objetos en `campanas`
  v_cta_a constant uuid := '9ca0b977-3c91-48dc-aa04-2f1fab766963';  -- empresa A (411d6f8c...)
  v_emp_a constant text := '411d6f8c-a405-49d6-9ed6-fbeb0db05133';
  v_cta_b constant uuid := '5c9e60a7-6885-486b-adfd-c691d0db33a6';  -- empresa B (cc17afe8...)
  v_emp_b constant text := 'cc17afe8-fcd5-4ab0-84c4-08ba919d8481';
  v_sa    constant uuid := '41904e2c-5ef3-4fee-bd48-9ea58e0c8c37';  -- super_admin real
  v_plano constant text := '1780525121711.png';                      -- el objeto plano que ya existe
  v_mal   text := '';
  v_n     bigint;
  v_obj0  bigint;
  v_rc    int;

BEGIN
  SELECT count(*) INTO v_obj0 FROM storage.objects WHERE bucket_id IN ('campanas','productos');

  -- `storage.objects` tiene un trigger BEFORE DELETE (`protect_objects_delete`) que corta TODO
  -- borrado directo con «Direct deletion from storage tables is not allowed», a menos que el GUC
  -- `storage.allow_delete_query` valga 'true'. Es un guard de plataforma, no una policy: si no se
  -- levanta, los casos de DELETE de abajo fallarian por el trigger y no por el confinamiento, y no
  -- estarian midiendo nada. Se levanta LOCAL a esta transaccion, solo para que lo que decida sea
  -- la RLS. El guard sigue en pie para el resto del mundo.
  PERFORM set_config('storage.allow_delete_query', 'true', true);

  -- ------------------------------------------------------------------ (a) cada empresa, lo suyo
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_cta_a,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('campanas',  v_emp_a || '/_m306.png', v_cta_a);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('productos', v_emp_a || '/_m306.png', v_cta_a);
    DELETE FROM storage.objects WHERE name = v_emp_a || '/_m306.png';
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 2 THEN v_mal := v_mal || format('(a) la empresa borro %s de sus 2 objetos; ', v_rc); END IF;
    RAISE EXCEPTION 'M306_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M306_RB' THEN
      v_mal := v_mal || format('(a) la empresa NO pudo operar en su propio prefijo (%s %s); ', SQLSTATE, left(SQLERRM,60));
    END IF;
  END;

  -- ------------------------------------------------------------------ (b) empresa A -> prefijo de B
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_cta_a,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('campanas', v_emp_b || '/_m306_intruso.png', v_cta_a);
    PERFORM set_config('role','none', true);
    v_mal := v_mal || '(b) la empresa A subio al prefijo de B en campanas; ';
    RAISE EXCEPTION 'M306_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M306_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(b) campanas corto con %s, se esperaba 42501; ', SQLSTATE);
    END IF;
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_cta_a,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('productos', v_emp_b || '/_m306_intruso.png', v_cta_a);
    PERFORM set_config('role','none', true);
    v_mal := v_mal || '(b) la empresa A subio al prefijo de B en productos; ';
    RAISE EXCEPTION 'M306_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M306_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(b) productos corto con %s, se esperaba 42501; ', SQLSTATE);
    END IF;
  END;
  -- ...y tampoco puede BORRAR lo de B, que es la mitad que mas duele.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_cta_a,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    DELETE FROM storage.objects WHERE bucket_id='campanas' AND split_part(name,'/',1) = v_emp_b;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 0 THEN v_mal := v_mal || format('(b) la empresa A borro %s objeto(s) de B; ', v_rc); END IF;
    RAISE EXCEPTION 'M306_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M306_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(b) el DELETE cruzado corto con %s; ', SQLSTATE);
    END IF;
  END;

  -- ------------------------------------------------------------------ (c) super_admin, plano en campanas
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_sa,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('campanas', '_m306_housead.png', v_sa);
    DELETE FROM storage.objects WHERE bucket_id='campanas' AND name='_m306_housead.png';
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 1 THEN v_mal := v_mal || format('(c) el super_admin borro %s de su house-ad; ', v_rc); END IF;
    RAISE EXCEPTION 'M306_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M306_RB' THEN
      v_mal := v_mal || format('(c) el super_admin NO pudo subir la house-ad plana (%s): se rompe PlanesPublicidadConfigPage; ', SQLSTATE);
    END IF;
  END;

  -- ------------------------------------------------------------------ (d) super_admin, plano en PRODUCTOS
  -- La asimetria, EJERCITADA. Si esto pasara, el brazo de admin se colo en el bucket equivocado.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_sa,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('productos', '_m306_admin.png', v_sa);
    PERFORM set_config('role','none', true);
    v_mal := v_mal || '(d) el super_admin subio a productos: la asimetria no quedo; ';
    RAISE EXCEPTION 'M306_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M306_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(d) corto con %s, se esperaba 42501; ', SQLSTATE);
    END IF;
  END;

  -- ------------------------------------------------------------------ (e) un proveedor sobre el objeto plano
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_cta_b,'role','authenticated')::text, true);
    PERFORM set_config('role','authenticated', true);
    DELETE FROM storage.objects WHERE bucket_id='campanas' AND name = v_plano;
    GET DIAGNOSTICS v_rc = ROW_COUNT;
    PERFORM set_config('role','none', true);
    IF v_rc <> 0 THEN v_mal := v_mal || format('(e) un proveedor borro el objeto plano (%s); ', v_rc); END IF;
    RAISE EXCEPTION 'M306_RB';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role','none', true);
    IF SQLERRM <> 'M306_RB' AND SQLSTATE <> '42501' THEN
      v_mal := v_mal || format('(e) corto con %s; ', SQLSTATE);
    END IF;
  END;
  PERFORM set_config('request.jwt.claims','', true);

  -- ------------------------------------------------------------------ (f) ningun path se toco
  SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id IN ('campanas','productos');
  IF v_n <> v_obj0 THEN
    v_mal := v_mal || format('(f) los buckets pasaron de %s a %s objetos; ', v_obj0, v_n);
  END IF;
  SELECT count(*) INTO v_n FROM storage.objects
   WHERE bucket_id='campanas' AND split_part(name,'/',1) IN (v_emp_a, v_emp_b, 'f05f3451-2ff6-4558-8085-f82e35fa88be');
  IF v_n <> 13 THEN v_mal := v_mal || format('(f) quedan %s objetos confinables, eran 13; ', v_n); END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='campanas' AND name = v_plano) THEN
    v_mal := v_mal || '(f) el objeto plano desaparecio; ';
  END IF;
  SELECT count(*) INTO v_n FROM storage.objects WHERE name LIKE '%_m306%';
  IF v_n <> 0 THEN v_mal := v_mal || format('(f) quedaron %s objetos de prueba escritos; ', v_n); END IF;

  -- ------------------------------------------------------------------ (g) la lectura publica sigue igual
  IF NOT EXISTS (SELECT 1 FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
                  JOIN pg_namespace ns ON ns.oid=c.relnamespace
                 WHERE ns.nspname='storage' AND c.relname='objects' AND pol.polcmd::text='r'
                   AND pg_get_expr(pol.polqual, pol.polrelid) ~ 'campanas')
     OR NOT EXISTS (SELECT 1 FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
                  JOIN pg_namespace ns ON ns.oid=c.relnamespace
                 WHERE ns.nspname='storage' AND c.relname='objects' AND pol.polcmd::text='r'
                   AND pg_get_expr(pol.polqual, pol.polrelid) ~ 'productos') THEN
    v_mal := v_mal || '(g) se perdio una policy de lectura publica; ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='campanas'  AND public)
     OR NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='productos' AND public) THEN
    v_mal := v_mal || '(g) un bucket dejo de ser publico; ';
  END IF;

  -- ------------------------------------------------------------------ (h) catalogo
  SELECT count(*) INTO v_n FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
    JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE ns.nspname='storage' AND c.relname='objects'
     AND pol.polname IN ('Usuarios autenticados pueden subir campanas',
                         'Usuarios autenticados pueden eliminar campanas',
                         'Autenticados suben productos',
                         'Autenticados eliminan productos');
  IF v_n <> 0 THEN v_mal := v_mal || format('(h) sobrevivieron %s policies viejas; ', v_n); END IF;

  IF v_mal <> '' THEN
    RAISE EXCEPTION '306: %', v_mal;
  END IF;
END $$;
