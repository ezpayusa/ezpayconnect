-- =====================================================================================================================
-- MIG 398 — facturas: solo un médico activo factura a sus pacientes, el país sale de su perfil y la factura es inmutable
-- salvo el estado (pendiente → pagada | cancelada). Sin front, un solo paso.
-- Diseño: output/diseno-disp-fact-notas-20nov.md, sección 4.1, decisiones D-1 (a), D-2 (A), D-3, D-4 y D-5 aprobadas.
--
-- Por qué (medido el 20-nov, ver el diseño, sección 2.2): cualquier authenticated creaba facturas (el medico_id es una FK a
-- auth.users y la policy solo pedía medico_id = auth.uid()), a pacientes que no atiende y en cualquier país; el dueño les
-- reescribía estado, paciente, país y montos (con total negativo: el descuento no tenía tope); una cuenta inactiva seguía
-- escribiendo. Las facturas entran en los números del admin_pais (PaisDashboardPage, ReporteFacturacion).
--
-- Censo de escritores (re-confirmado el 20-nov sobre origin/main 29b6898): src/hooks/useFacturas.ts:51 (createFactura, desde
-- FacturasPage.tsx:76) hace INSERT de paciente_id, concepto, cantidad, precio_unitario, descuento, metodo_pago, estado
-- (siempre 'pendiente': el form no lo deja elegir), notas, medico_id (= user.id) y pais_id (usePaisFiltro); useFacturas.ts:72
-- (updateFactura, desde FacturasPage.tsx:271) hace UPDATE de { estado: 'pagada' }; deleteFactura (useFacturas.ts:80) no
-- tiene llamadores y authenticated no tiene DELETE. Ninguna edge ni función ni vista escribe o lee la tabla.
--
-- Qué hace (y nada más):
--   1. UPDATE solo por columna: REVOKE UPDATE de tabla a authenticated + GRANT UPDATE (estado). INSERT de tabla se QUEDA
--      (el front inserta directo; quién y qué lo decide el guard): así facturas_id_seq sigue en el conjunto necesario de
--      P928 y la receta de P929 sigue valiendo (con un paciente atendido). DELETE: authenticated no tenía y no se otorga.
--      anon: nada, como antes.
--   2. Guard private.facturas_guard() — BEFORE INSERT OR UPDATE, INVOKER, SET search_path = ''. Exentos por current_user
--      los roles de servicio (service_role, postgres, supabase_admin, supabase_auth_admin), como el guard de la 389: así
--      una función DEFINER (dueña postgres) o service_role no pasan por él. (El diseño decía DEFINER con exención por
--      auth.uid() NULL; un guard DEFINER corre siempre como postgres y la exención por current_user no serviría.)
--      Errores:
--        FA001 = quien escribe no es un médico activo (private.tiene_rol(ARRAY['medico']): rol 'medico' y activo IS TRUE);
--        FA002 = el paciente no es suyo (las ramas de exp_select_medico: private.es_medico_de o
--                private.medico_atiende_paciente, COALESCE fail-closed) — mismo error si el paciente es NULL o no existe;
--        FA003 = una factura nueva solo nace 'pendiente' o 'pagada';
--        FA004 = UPDATE fuera de pendiente → pagada | cancelada (incluye repetir el estado y cualquier otra columna).
--      En INSERT el guard fija pais_id = public.get_auth_user_pais_id() (el país del perfil del médico; ignora lo que
--      mande el cliente), fecha_emision = CURRENT_DATE y created_at = now().
--   3. CHECKs (las 3 filas vivas los cumplen; la guarda aborta si alguna no):
--        facturas_estado_valido      estado IS NOT NULL AND estado IN ('pendiente','pagada','cancelada')
--        facturas_cantidad_positiva  cantidad IS NOT NULL AND cantidad > 0
--        facturas_precio_no_negativo precio_unitario >= 0
--        facturas_descuento_valido   descuento IS NOT NULL AND descuento >= 0 AND descuento <= cantidad * precio_unitario
--      (con el último el total generado nunca es negativo).
--   4. Policies: DROP de las 3 duplicadas (medicos_crear_facturas, medicos_ver_facturas, medicos_actualizar_facturas);
--      «Medico actualiza sus facturas» gana WITH CHECK (medico_id = auth.uid()) explícito. Quedan 4: «Admin ve facturas de
--      su pais» (SELECT), «Medico crea sus facturas» (INSERT), «Medico ve sus facturas» (SELECT) y «Medico actualiza sus
--      facturas» (UPDATE).
--   MIG98 = guarda de la migración.
--
-- Estado ANTES, medido el 20-nov-2026 19:13:39 UTC (post-397):
--   funciones completas (cuerpo + DEFINER + config + ACL), public/private ..... 77ae9f738b13c5b920383d0cf0bda746 420
--   ACL de funciones (solo privilegios), public/private .......................... 6eca74c670156e3a2d290b96651fc30e 420
--   ACL de relaciones de public ................................................... cf5c7c56aaf30e6dd11b8407134b70d3 2446
--     (sin facturas ............................................................... 160d8cbb2b9abffa9f3f14d69ab42918 2427)
--   ACL de secuencias de public ................................................... f889b7db4c222d80c7b507251f88ae7c 238
--   policies public/private/storage ............................................... eba82b3fc822926313534f04caa4f853 309
--     (sin las de facturas ........................................................ 228a04dcf0d8992fdfbc06a9af8c813d 302)
--   facturas: relacl {postgres=arwdDxtm/postgres,authenticated=arw/postgres,service_role=arwdDxtm/postgres}, sin attacl;
--   facturas_id_seq {postgres=rwU/postgres,authenticated=U/postgres,service_role=rwU/postgres}; sin triggers ni CHECKs;
--   7 policies (las 3 duplicadas de a pares + la del admin); 3 filas (md5 8e4986fe…), las 3 'pendiente', cantidad 1,
--   precio 150-300, descuento 50-150.
-- Huellas post-398: ver el dry-run (en el PR). Rollback: supabase/migrations/398_rollback.sql (va antes que 397_rollback).
-- Aplicar con: npx supabase db query --linked -f supabase/migrations/398_facturas_cierre.sql
-- =====================================================================================================================

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- 0) PRECONDICIÓN
-- ---------------------------------------------------------------------------------------------------------------------
DO $precondicion$
DECLARE bad text := ''; v text; r record;
BEGIN
  -- la 397 está aplicada; la 398 no
  IF has_column_privilege('authenticated', 'public.recetas_avanzadas', 'dispatch_token', 'SELECT') THEN
    bad := bad||'la 397 no está aplicada; ';
  END IF;
  IF to_regprocedure('private.facturas_guard()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.facturas'::regclass AND NOT t.tgisinternal)
     OR EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.facturas'::regclass AND c.contype = 'c') THEN
    bad := bad||'facturas ya tiene guard, triggers o CHECKs (¿la 398 ya se aplicó?); ';
  END IF;
  -- privilegios exactos (relacl ordenado)
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.facturas'::regclass)
     IS DISTINCT FROM 'authenticated=arw/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres'
     OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.facturas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     OR (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.facturas_id_seq'::regclass)
     IS DISTINCT FROM 'authenticated=U/postgres,postgres=rwU/postgres,service_role=rwU/postgres' THEN
    bad := bad||'privilegios de facturas o facturas_id_seq distintos de los medidos; ';
  END IF;
  -- columnas exactas
  IF (SELECT string_agg(a.attname||':'||format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.facturas'::regclass AND a.attnum > 0 AND NOT a.attisdropped)
     IS DISTINCT FROM 'id:integer,paciente_id:integer,medico_id:uuid,fecha_emision:date,concepto:character varying(255),cantidad:integer,precio_unitario:numeric(10,2),subtotal:numeric(10,2),descuento:numeric(10,2),total:numeric(10,2),metodo_pago:character varying(50),estado:character varying(20),notas:text,created_at:timestamp without time zone,pais_id:uuid' THEN
    bad := bad||'columnas de facturas distintas de las medidas; ';
  END IF;
  -- las 7 policies medidas
  IF (SELECT string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                        COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C")
        FROM pg_policy pl WHERE pl.polrelid = 'public.facturas'::regclass)
     IS DISTINCT FROM E'Admin ve facturas de su pais|r|{authenticated}|((get_auth_user_rol() = ''super_admin''::text) OR ((get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = get_auth_user_pais_id())))|-\n'
                    ||E'Medico actualiza sus facturas|w|{authenticated}|(medico_id = auth.uid())|-\n'
                    ||E'Medico crea sus facturas|a|{authenticated}|-|(medico_id = auth.uid())\n'
                    ||E'Medico ve sus facturas|r|{authenticated}|(medico_id = auth.uid())|-\n'
                    ||E'medicos_actualizar_facturas|w|{authenticated}|(medico_id = auth.uid())|-\n'
                    ||E'medicos_crear_facturas|a|{authenticated}|-|(medico_id = auth.uid())\n'
                    ||'medicos_ver_facturas|r|{authenticated}|(medico_id = auth.uid())|-' THEN
    bad := bad||'policies de facturas distintas de las medidas; ';
  END IF;
  -- helpers que usa el guard
  FOR r IN SELECT * FROM (VALUES
      ('private.tiene_rol(text[])',                 '2032eb10b9e9a90e5be58100607370e3'),
      ('private.es_medico_de(bigint)',              'f68727f9861162f212f57ff2412d7c8b'),
      ('private.medico_atiende_paciente(bigint)',   'ffbb220849b4c21896d103faf8d05abd'),
      ('public.get_auth_user_pais_id()',            '2a9bfcd0913e5879081e927d78a22b28')) AS t(firma, md)
  LOOP
    IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)) IS DISTINCT FROM r.md
       OR NOT has_function_privilege('authenticated', r.firma, 'EXECUTE') THEN
      bad := bad||r.firma||' distinta de la medida o sin EXECUTE de authenticated; ';
    END IF;
  END LOOP;
  -- errcodes FA libres
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND p.prosrc ~ '''FA[0-9]{3}''') THEN
    bad := bad||'el prefijo FA ya está en uso; ';
  END IF;
  -- las filas vivas cumplen los CHECKs nuevos
  v := (SELECT string_agg(f.id::text, ',') FROM public.facturas f
         WHERE NOT (f.estado IS NOT NULL AND f.estado IN ('pendiente', 'pagada', 'cancelada'))
            OR NOT (f.cantidad IS NOT NULL AND f.cantidad > 0)
            OR NOT (f.precio_unitario >= 0)
            OR NOT (f.descuento IS NOT NULL AND f.descuento >= 0 AND f.descuento <= f.cantidad * f.precio_unitario));
  IF v IS NOT NULL THEN bad := bad||'facturas que violan los CHECKs nuevos: '||v||'; '; END IF;

  -- huellas post-397 (20-nov-2026)
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace));
  IF v IS DISTINCT FROM '77ae9f738b13c5b920383d0cf0bda746 420' THEN bad := bad||'huella de funciones completas '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) y);
  IF v IS DISTINCT FROM '6eca74c670156e3a2d290b96651fc30e 420' THEN bad := bad||'huella de ACL de funciones '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) x);
  IF v IS DISTINCT FROM 'cf5c7c56aaf30e6dd11b8407134b70d3 2446' THEN bad := bad||'huella de ACL de relaciones de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) y);
  IF v IS DISTINCT FROM 'eba82b3fc822926313534f04caa4f853 309' THEN bad := bad||'huella de policies '||COALESCE(v, '-')||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG98: precondición: %', bad USING ERRCODE = 'MIG98';
  END IF;

  PERFORM set_config('mig398.filas', (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.facturas t), true);
END $precondicion$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1) PRIVILEGIOS: UPDATE solo de estado
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE UPDATE ON TABLE public.facturas FROM authenticated;
GRANT UPDATE (estado) ON TABLE public.facturas TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2) GUARD
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION private.facturas_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF current_user IN ('service_role', 'postgres', 'supabase_admin', 'supabase_auth_admin') THEN
    RETURN NEW;
  END IF;

  IF NOT COALESCE(private.tiene_rol(ARRAY['medico']), false) THEN
    RAISE EXCEPTION 'Solo un médico activo puede emitir o modificar facturas' USING ERRCODE = 'FA001';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.paciente_id IS NULL
       OR NOT (COALESCE(private.es_medico_de(NEW.paciente_id::bigint), false)
               OR COALESCE(private.medico_atiende_paciente(NEW.paciente_id::bigint), false)) THEN
      RAISE EXCEPTION 'No puedes facturar a este paciente' USING ERRCODE = 'FA002';
    END IF;
    IF NEW.estado IS NULL OR NEW.estado NOT IN ('pendiente', 'pagada') THEN
      RAISE EXCEPTION 'Una factura nueva solo puede estar pendiente o pagada' USING ERRCODE = 'FA003';
    END IF;
    NEW.pais_id := public.get_auth_user_pais_id();
    NEW.fecha_emision := CURRENT_DATE;
    NEW.created_at := now();
    RETURN NEW;
  END IF;

  IF (to_jsonb(NEW) - 'estado' - 'subtotal' - 'total') IS DISTINCT FROM (to_jsonb(OLD) - 'estado' - 'subtotal' - 'total')
     OR NOT (OLD.estado = 'pendiente' AND NEW.estado IN ('pagada', 'cancelada')) THEN
    RAISE EXCEPTION 'Solo se puede pasar una factura pendiente a pagada o cancelada' USING ERRCODE = 'FA004';
  END IF;
  RETURN NEW;
END
$fn$;

REVOKE ALL ON FUNCTION private.facturas_guard() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_facturas_guard
  BEFORE INSERT OR UPDATE ON public.facturas
  FOR EACH ROW EXECUTE FUNCTION private.facturas_guard();

-- ---------------------------------------------------------------------------------------------------------------------
-- 3) CHECKs
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.facturas
  ADD CONSTRAINT facturas_estado_valido CHECK (estado IS NOT NULL AND estado IN ('pendiente', 'pagada', 'cancelada')),
  ADD CONSTRAINT facturas_cantidad_positiva CHECK (cantidad IS NOT NULL AND cantidad > 0),
  ADD CONSTRAINT facturas_precio_no_negativo CHECK (precio_unitario >= 0),
  ADD CONSTRAINT facturas_descuento_valido CHECK (descuento IS NOT NULL AND descuento >= 0 AND descuento <= cantidad * precio_unitario);

-- ---------------------------------------------------------------------------------------------------------------------
-- 4) POLICIES: fuera las 3 duplicadas; WITH CHECK explícito en el UPDATE
-- ---------------------------------------------------------------------------------------------------------------------
DROP POLICY medicos_crear_facturas ON public.facturas;
DROP POLICY medicos_ver_facturas ON public.facturas;
DROP POLICY medicos_actualizar_facturas ON public.facturas;
ALTER POLICY "Medico actualiza sus facturas" ON public.facturas USING (medico_id = auth.uid()) WITH CHECK (medico_id = auth.uid());

-- ---------------------------------------------------------------------------------------------------------------------
-- 5) AUTOCHEQUEO (aborta toda la migración si algo no quedó como se espera)
-- ---------------------------------------------------------------------------------------------------------------------
DO $autochequeo$
DECLARE bad text := ''; v text;
BEGIN
  -- privilegios: tabla sin UPDATE de authenticated, UPDATE solo de estado, INSERT y SELECT de tabla, sin DELETE
  IF (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.facturas'::regclass)
     IS DISTINCT FROM 'authenticated=ar/postgres,postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres' THEN
    bad := bad||'relacl de facturas = '||COALESCE((SELECT relacl::text FROM pg_class WHERE oid = 'public.facturas'::regclass), '-')||'; ';
  END IF;
  IF (SELECT string_agg(a.attname||'='||a.attacl::text, ',' ORDER BY a.attnum) FROM pg_attribute a
       WHERE a.attrelid = 'public.facturas'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
     IS DISTINCT FROM 'estado={authenticated=w/postgres}' THEN
    bad := bad||'attacl de facturas fuera de lo esperado; ';
  END IF;
  v := (SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
         WHERE a.attrelid = 'public.facturas'::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND has_column_privilege('authenticated', 'public.facturas', a.attname, 'UPDATE') <> (a.attname = 'estado'));
  IF v IS NOT NULL THEN bad := bad||'UPDATE de authenticated fuera de lo esperado en: '||v||'; '; END IF;
  IF NOT has_table_privilege('authenticated', 'public.facturas', 'INSERT') OR NOT has_table_privilege('authenticated', 'public.facturas', 'SELECT')
     OR has_table_privilege('authenticated', 'public.facturas', 'DELETE,TRUNCATE,TRIGGER,MAINTAIN')
     OR has_any_column_privilege('anon', 'public.facturas', 'SELECT,INSERT,UPDATE,REFERENCES')
     OR (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pg_class c, unnest(c.relacl) x WHERE c.oid = 'public.facturas_id_seq'::regclass)
        IS DISTINCT FROM 'authenticated=U/postgres,postgres=rwU/postgres,service_role=rwU/postgres' THEN
    bad := bad||'INSERT/SELECT/DELETE de authenticated, anon o la secuencia fuera de lo esperado; ';
  END IF;

  -- guard: INVOKER, search_path vacío, EXECUTE solo postgres, una sobrecarga, y el trigger exacto
  IF (SELECT count(*) FROM pg_proc p WHERE p.proname = 'facturas_guard') <> 1
     OR (SELECT p.prosecdef::text||' '||COALESCE(p.proconfig::text, '-')||' '||COALESCE(p.proacl::text, '-')
           FROM pg_proc p WHERE p.oid = to_regprocedure('private.facturas_guard()'))
        IS DISTINCT FROM 'false {"search_path=\"\""} {postgres=X/postgres}' THEN
    bad := bad||'private.facturas_guard fuera de lo esperado; ';
  END IF;
  IF (SELECT string_agg(t.tgname||' '||t.tgenabled::text||' '||t.tgfoid::regprocedure::text||' '||t.tgtype::text, ',')
        FROM pg_trigger t WHERE t.tgrelid = 'public.facturas'::regclass AND NOT t.tgisinternal)
     IS DISTINCT FROM 'trg_facturas_guard O private.facturas_guard() 23' THEN
    bad := bad||'trigger de facturas fuera de lo esperado; ';
  END IF;

  -- CHECKs validados
  IF (SELECT string_agg(c.conname||':'||c.convalidated::text||':'||pg_get_constraintdef(c.oid), E'\n' ORDER BY c.conname)
        FROM pg_constraint c WHERE c.conrelid = 'public.facturas'::regclass AND c.contype = 'c')
     IS DISTINCT FROM E'facturas_cantidad_positiva:true:CHECK (((cantidad IS NOT NULL) AND (cantidad > 0)))\n'
                    ||E'facturas_descuento_valido:true:CHECK (((descuento IS NOT NULL) AND (descuento >= (0)::numeric) AND (descuento <= ((cantidad)::numeric * precio_unitario))))\n'
                    ||E'facturas_estado_valido:true:CHECK (((estado IS NOT NULL) AND ((estado)::text = ANY ((ARRAY[''pendiente''::character varying, ''pagada''::character varying, ''cancelada''::character varying])::text[]))))\n'
                    ||'facturas_precio_no_negativo:true:CHECK ((precio_unitario >= (0)::numeric))' THEN
    bad := bad||'CHECKs de facturas fuera de lo esperado: '||COALESCE((SELECT string_agg(c.conname||':'||pg_get_constraintdef(c.oid), ' | ' ORDER BY c.conname)
        FROM pg_constraint c WHERE c.conrelid = 'public.facturas'::regclass AND c.contype = 'c'), '-')||'; ';
  END IF;

  -- policies: las 4 que quedan, exactas
  IF (SELECT string_agg(pl.polname||'|'||pl.polcmd::text||'|'||ARRAY(SELECT pg_get_userbyid(x) FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
                        COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-'), E'\n' ORDER BY pl.polname COLLATE "C")
        FROM pg_policy pl WHERE pl.polrelid = 'public.facturas'::regclass)
     IS DISTINCT FROM E'Admin ve facturas de su pais|r|{authenticated}|((get_auth_user_rol() = ''super_admin''::text) OR ((get_auth_user_rol() = ''admin_pais''::text) AND (pais_id = get_auth_user_pais_id())))|-\n'
                    ||E'Medico actualiza sus facturas|w|{authenticated}|(medico_id = auth.uid())|(medico_id = auth.uid())\n'
                    ||E'Medico crea sus facturas|a|{authenticated}|-|(medico_id = auth.uid())\n'
                    ||'Medico ve sus facturas|r|{authenticated}|(medico_id = auth.uid())|-' THEN
    bad := bad||'policies de facturas fuera de lo esperado; ';
  END IF;

  -- datos intactos
  IF (SELECT count(*)||' '||COALESCE(md5(string_agg(t::text, E'\n' ORDER BY t.id)), '-') FROM public.facturas t)
     IS DISTINCT FROM current_setting('mig398.filas', true) THEN
    bad := bad||'cambiaron filas de facturas; ';
  END IF;

  -- huellas: lo que no es facturas ni el guard, igual a la entrada; secuencias igual; conteos nuevos
  v := (SELECT md5(string_agg(f.oid::regprocedure::text||'|'||md5(f.prosrc)||'|'||f.prosecdef::text||'|'||
                              COALESCE(f.proconfig::text, '-')||'|'||COALESCE(f.proacl::text, '-'), E'\n'
                              ORDER BY f.oid::regprocedure::text COLLATE "C"))||' '||count(*)
          FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.proname <> 'facturas_guard');
  IF v IS DISTINCT FROM '77ae9f738b13c5b920383d0cf0bda746 420' THEN bad := bad||'huella de funciones completas sin el guard '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(COALESCE(string_agg(y.s, ',' ORDER BY y.s COLLATE "C"), ''))||' '||count(DISTINCT y.o) FROM (
      SELECT f.oid AS o, f.oid::regprocedure::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
        FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
       WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.proname <> 'facturas_guard') y);
  IF v IS DISTINCT FROM '6eca74c670156e3a2d290b96651fc30e 420' THEN bad := bad||'huella de ACL de funciones sin el guard '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_proc f WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace)) <> 421 THEN
    bad := bad||'no quedaron 421 funciones en public/private; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f') AND cl.relname <> 'facturas') x);
  IF v IS DISTINCT FROM '160d8cbb2b9abffa9f3f14d69ab42918 2427' THEN bad := bad||'huella de ACL de relaciones sin facturas '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('r', cl.relowner))) a
       WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind IN ('r','p','v','m','f')) <> 2445 THEN
    bad := bad||'la ACL de relaciones de public no quedó en 2445 entradas; ';
  END IF;
  v := (SELECT md5(COALESCE(string_agg(x.s, ',' ORDER BY x.s COLLATE "C"), ''))||' '||count(*) FROM (SELECT cl.relname||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||pg_get_userbyid(a.grantor)||'|'||a.privilege_type||'|'||a.is_grantable::text AS s
      FROM pg_class cl, aclexplode(COALESCE(cl.relacl, acldefault('s', cl.relowner))) a
     WHERE cl.relnamespace = 'public'::regnamespace AND cl.relkind = 'S') x);
  IF v IS DISTINCT FROM 'f889b7db4c222d80c7b507251f88ae7c 238' THEN bad := bad||'huella de ACL de secuencias de public '||COALESCE(v, '-')||'; '; END IF;
  v := (SELECT md5(string_agg(y.s, E'\n' ORDER BY y.s COLLATE "C"))||' '||count(*) FROM (
      SELECT n.nspname||'.'||cl.relname||'|'||pl.polname||'|'||pl.polcmd::text||'|'||pl.polpermissive::text||'|'||
         ARRAY(SELECT CASE x WHEN 0 THEN 'public' ELSE pg_get_userbyid(x) END FROM unnest(pl.polroles) x ORDER BY 1)::text||'|'||
         COALESCE(pg_get_expr(pl.polqual, pl.polrelid), '-')||'|'||COALESCE(pg_get_expr(pl.polwithcheck, pl.polrelid), '-') AS s
        FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage') AND cl.oid <> 'public.facturas'::regclass) y);
  IF v IS DISTINCT FROM '228a04dcf0d8992fdfbc06a9af8c813d 302' THEN bad := bad||'huella de policies sin facturas '||COALESCE(v, '-')||'; '; END IF;
  IF (SELECT count(*) FROM pg_policy pl JOIN pg_class cl ON cl.oid = pl.polrelid JOIN pg_namespace n ON n.oid = cl.relnamespace
       WHERE n.nspname IN ('public','private','storage')) <> 306 THEN
    bad := bad||'no quedaron 306 policies; ';
  END IF;

  -- P800 (j)/(k) y P931
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f, aclexplode(COALESCE(f.proacl, acldefault('f', f.proowner))) a
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR (a.grantee = 'anon'::regrole AND f.oid <> 'public.catalogo_planes_visitador_publico()'::regprocedure)));
  IF v IS NOT NULL THEN bad := bad||'EXECUTE para PUBLIC/anon: '||v||'; '; END IF;
  v := (SELECT string_agg(f.oid::regprocedure::text, ',') FROM pg_proc f
         WHERE f.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND f.prosecdef
           AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(f.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%'));
  IF v IS NOT NULL THEN bad := bad||'DEFINER sin search_path: '||v||'; '; END IF;

  IF bad <> '' THEN
    RAISE EXCEPTION 'MIG98: autochequeo: %', bad USING ERRCODE = 'MIG98';
  END IF;
END $autochequeo$;

NOTIFY pgrst, 'reload schema';

COMMIT;
