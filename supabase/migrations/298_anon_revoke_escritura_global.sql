-- ############################################################################################
-- 298 — anon pierde TODO privilegio de escritura sobre public, y deja de recibirlos por default
-- ############################################################################################
-- ESTO NO ES HIGIENE. Censo del 18-sep contra prod: `anon` tenia
-- DELETE, INSERT, REFERENCES, TRIGGER, TRUNCATE, UPDATE sobre **73 relaciones** de public —
-- pacientes, recetas, expediente_notas, signos_vitales, examenes, citas, todo el expediente medico
-- incluido— y 5 de esas 73 son VISTAS con RLS apagada.
--
-- EL QUE IMPORTA ES TRUNCATE, Y LO TENIAN LAS 73. La RLS no lo cubre: Postgres no admite policies
-- de TRUNCATE, la operacion se autoriza SOLO por el privilegio. O sea que las policies de scoping
-- que cuidamos en las migs 294/295/296/297 son IRRELEVANTES frente a un TRUNCATE. No se probo que
-- `anon` pueda LLEGAR a ejecutarlo (PostgREST no expone TRUNCATE), asi que el riesgo vivo depende
-- de que no haya otra via; pero un privilegio destructivo que ninguna policy puede frenar no se
-- deja puesto "porque hoy no hay como invocarlo".
--
-- DE DONDE SALE: DEFAULT PRIVILEGES. No fue una migracion distraida, es una fabrica. En
-- pg_default_acl hay dos entradas para public/objtype=r que le dan `arwdDxtm` (= ALL, TRUNCATE
-- incluido) a anon: una del rol `postgres` y otra de `supabase_admin`. Cada relacion nueva nace
-- asi. Por eso un REVOKE tabla por tabla es pan para hoy: la capa 1 es la que corta el chorro.
--
-- LA ENTRADA DE `supabase_admin` NO SE PUEDE TOCAR DESDE ACA, Y SE MIDIO POR QUE NO IMPORTA
-- ---------------------------------------------------------------------------------------
-- `ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin` falla con 42501: la conexion del CLI es
-- `postgres`, que no es superuser ni miembro de supabase_admin. Probado ejecutandolo de verdad.
-- PERO un default privilege aplica segun QUIEN CREA el objeto, no como regla global. Medido en la
-- misma transaccion: con la entrada de supabase_admin VIVA e intacta, una tabla creada por
-- `postgres` nacio SIN un solo privilegio para anon. Y las 128 relaciones de public son de
-- `postgres` — no hay una sola de otro dueno. Nuestras migraciones corren como `postgres` y el SQL
-- editor tambien, asi que la entrada de supabase_admin queda inerte para todo lo que este proyecto
-- cree. Es una MITIGACION, no una eliminacion: si Supabase creara una tabla en public como
-- supabase_admin, volveria a nacer abierta. Eso lo vigila la probe P724, que no depende de que
-- alguien se acuerde de mirar.
--
-- LA CAPA 3 ES UN NO-OP HOY, Y VA IGUAL. `information_schema.column_privileges` REFLEJA el grant
-- de tabla columna por columna: las 844 filas del censo no eran 844 ACLs de columna. Los grants de
-- columna EXPLICITOS viven en `pg_attribute.attacl`, y los que mencionan a anon son CERO (los 36
-- que existen son de `authenticated` en jornadas_comerciales / visitas_comerciales /
-- notificaciones_pacientes, de la mig 277, y no se tocan). O sea que la capa 2 ya se los lleva. El
-- loop queda porque hace a la migracion autosuficiente si manana el estado difiere, y porque el
-- autochequeo exige el estado final en los dos niveles.
--
-- FUERA DE ALCANCE, DICHO PARA QUE SEA DECISION Y NO OLVIDO:
--   * `authenticated` tiene el MISMO cuadro, TRUNCATE incluido, y eso tampoco lo cubre ninguna
--     policy. Es un frente aparte porque ahi si hay escritura legitima por PostgREST y el REVOKE
--     tiene que ser selectivo.
--   * Los defaults de SECUENCIAS (objtype=S, `rwU`) y FUNCIONES (objtype=f, `X`) siguen dandole a
--     anon. El de funciones es la fabrica del hallazgo que cerro la mig 295: cada funcion nueva
--     nace ejecutable por anon. Esta migracion NO lo toca.
--
-- POR QUE ES SEGURO: censo de flujos publicos ya confirmado — tarjeta-asesor,
-- confirmar-recepcion-receta, registrar_proveedor y validar-invitacion corren por RPC SECURITY
-- DEFINER o con service_role dentro de la edge. Ninguno escribe como `anon` contra una tabla.
-- Y NO se toca el SELECT de anon: los flujos publicos que LEEN (p. ej. configuracion_pais, 21
-- filas para el registro de proveedor) siguen igual. Esta migracion es sobre ESCRITURA.
-- ############################################################################################

-- Foto del estado previo. La necesita el autochequeo: despues de revocar, la consulta que encuentra
-- "las 73" devuelve vacio y no habria contra que verificar. Temp: muere con la sesion.
CREATE TEMP TABLE _m298_antes AS
SELECT DISTINCT table_name::text AS tabla
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee = 'anon'
  AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER');

CREATE TEMP TABLE _m298_auth_select AS
SELECT DISTINCT table_name::text AS tabla
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee = 'authenticated' AND privilege_type = 'SELECT';

-- ============================================================================================
-- CAPA 1 — el default privilege. Sin esto, todo lo demas caduca con la proxima tabla.
-- ============================================================================================
-- Va ANTES del REVOKE masivo a proposito: si la migracion se cortara a la mitad, es preferible
-- quedarse con la fabrica apagada y el residuo puesto que al reves.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon;

-- ============================================================================================
-- CAPA 2 — REVOKE de los 6 privilegios de escritura, a nivel TABLA, sobre las 73.
-- ============================================================================================
-- Generado recorriendo el catalogo, no escrito a mano: una lista de 73 nombres copiada se
-- desactualiza el dia que aparece la 74. Se revoca SOLO escritura — el SELECT de anon no se toca.
DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT tabla FROM _m298_antes ORDER BY tabla LOOP
    EXECUTE format(
      'REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.%I FROM anon',
      r.tabla);
    n := n + 1;
  END LOOP;
  PERFORM set_config('m298.capa2', n::text, false);
  RAISE NOTICE '298 capa 2: % relaciones revocadas', n;
END $$;

-- ============================================================================================
-- CAPA 3 — grants de COLUMNA explicitos. Hoy son cero (ver cabecera); el loop es el seguro.
-- ============================================================================================
DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN
    SELECT c.relname::text AS tabla, a.attname::text AS col
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND a.attnum > 0 AND NOT a.attisdropped
       AND array_to_string(a.attacl, ',') LIKE '%anon=%'
     ORDER BY c.relname, a.attname
  LOOP
    EXECUTE format('REVOKE INSERT (%I), UPDATE (%I), REFERENCES (%I) ON public.%I FROM anon',
                   r.col, r.col, r.col, r.tabla);
    n := n + 1;
  END LOOP;
  PERFORM set_config('m298.capa3', n::text, false);
  RAISE NOTICE '298 capa 3: % columnas con ACL explicito revocadas', n;
END $$;

-- ============================================================================================
-- AUTOCHEQUEO — aborta si el estado final no es el pedido. Las tres condiciones importan lo mismo.
-- ============================================================================================
DO $$
DECLARE v_mal text := '';
        v_n int;
        v_lista text;
        v_acl text;
BEGIN
  -- (a1) anon no conserva NINGUNO de los 6 sobre NINGUNA relacion de public. Se mira global, no
  --      solo sobre las 73: si apareciera una 74 en el medio, tambien tiene que estar limpia.
  SELECT count(DISTINCT table_name), string_agg(DISTINCT table_name, ', ')
    INTO v_n, v_lista
    FROM information_schema.role_table_grants
   WHERE table_schema = 'public' AND grantee = 'anon'
     AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER');
  IF v_n <> 0 THEN
    v_mal := v_mal || format('anon conserva escritura de tabla en %s relacion(es): %s; ', v_n, left(v_lista, 300));
  END IF;

  -- (a2) lo mismo a nivel COLUMNA. information_schema refleja el de tabla, asi que con (a1) en cero
  --      esto tambien deberia dar cero; se comprueba igual, que es el punto de un autochequeo.
  SELECT count(*) INTO v_n
    FROM information_schema.column_privileges
   WHERE table_schema = 'public' AND grantee = 'anon'
     AND privilege_type IN ('INSERT','UPDATE','REFERENCES');
  IF v_n <> 0 THEN
    v_mal := v_mal || format('anon conserva %s privilegio(s) de columna; ', v_n);
  END IF;

  -- (b) la FABRICA quedo apagada: una tabla nueva creada por este mismo rol no le da nada a anon.
  --     Se crea y se borra DENTRO de este bloque, que es una sola sentencia: si algo revienta,
  --     la tabla se va con el rollback en vez de quedar de basura en public.
  BEGIN
    EXECUTE 'CREATE TABLE public._m298_probe_defacl (id int)';
    SELECT coalesce(array_to_string(c.relacl, '  '), '(NULL)') INTO v_acl
      FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND c.relname = '_m298_probe_defacl';
    IF has_table_privilege('anon', 'public._m298_probe_defacl', 'INSERT')
       OR has_table_privilege('anon', 'public._m298_probe_defacl', 'TRUNCATE')
       OR has_table_privilege('anon', 'public._m298_probe_defacl', 'UPDATE')
       OR has_table_privilege('anon', 'public._m298_probe_defacl', 'DELETE')
       OR has_table_privilege('anon', 'public._m298_probe_defacl', 'SELECT') THEN
      v_mal := v_mal || format('una tabla NUEVA sigue naciendo con privilegios para anon (acl=%s); ', v_acl);
    END IF;
    PERFORM set_config('m298.acl_nueva', v_acl, false);
    EXECUTE 'DROP TABLE public._m298_probe_defacl';
  EXCEPTION WHEN OTHERS THEN
    v_mal := v_mal || format('no se pudo probar el default privilege (%s %s); ', SQLSTATE, SQLERRM);
  END;

  -- (c) authenticated NO perdio SELECT en ninguna de las que lo tenia. Esta es la mitad que evita
  --     que "cerre anon" signifique "rompi la app": el REVOKE nombra a anon, pero un error de
  --     tipeo en el format() podria haber alcanzado a otro rol.
  SELECT count(*), string_agg(t.tabla, ', ') INTO v_n, v_lista
    FROM _m298_auth_select t
   WHERE NOT has_table_privilege('authenticated', format('public.%I', t.tabla), 'SELECT');
  IF v_n <> 0 THEN
    v_mal := v_mal || format('authenticated PERDIO SELECT en %s relacion(es): %s; ', v_n, left(v_lista, 300));
  END IF;

  -- (d) la capa 1 quedo registrada en el catalogo: la entrada de `postgres` ya no menciona a anon.
  IF EXISTS (
    SELECT 1 FROM pg_default_acl d JOIN pg_namespace ns ON ns.oid = d.defaclnamespace
     WHERE ns.nspname = 'public' AND d.defaclobjtype = 'r'
       AND pg_get_userbyid(d.defaclrole) = 'postgres'
       AND array_to_string(d.defaclacl, ',') LIKE '%anon=%'
  ) THEN
    v_mal := v_mal || 'el default privilege de postgres sigue dandole a anon; ';
  END IF;

  IF v_mal <> '' THEN RAISE EXCEPTION '298: %', v_mal; END IF;
END $$;

DROP TABLE IF EXISTS _m298_antes;
DROP TABLE IF EXISTS _m298_auth_select;
