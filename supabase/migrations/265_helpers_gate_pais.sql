-- ============================================================================
-- Migración 265: helpers de gate de país fail-closed (private.puede_admin_pais / es_admin_pais)
-- ============================================================================
-- Paquete PA-FAILOPEN · LOTE 0. Esta migración SOLO crea los dos helpers. NO toca ninguna de las
-- funciones afectadas: la primera que los consume es el lote 1 (metricas_campana_pais + REVOKE de
-- anon). Aplicarla no cambia el comportamiento de nada que exista hoy — es herramienta, no arreglo.
--
-- NUMERACIÓN: esta 265 OCUPA el número que estaba reservado para el bloque de RPCs del módulo
-- comercial (el incremento que sigue a la 264). Ese bloque pasa a ser la 266 (o la que corresponda
-- cuando se escriba). No re-usar el 265 para el módulo comercial.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ EXISTEN
-- ----------------------------------------------------------------------------
-- El gate de país canónico que se copió por todo el proyecto desde la mig 222 es TRIVALUADO y
-- falla ABIERTO:
--
--     IF NOT ( get_auth_user_rol() = 'super_admin'
--              OR ( get_auth_user_rol() = 'admin_pais'
--                   AND get_auth_user_pais_id() = p_pais_id ) ) THEN
--       RAISE EXCEPTION 'no_autorizado';
--     END IF;
--
-- public.get_auth_user_rol() y public.get_auth_user_pais_id() son `SELECT ... FROM perfiles WHERE
-- id = auth.uid()`: SIN fila devuelven NULL, no una cadena vacía ni false. Y un caller sin fila en
-- perfiles no es un caso raro — son TODAS las cuentas de proveedor (viven en cuentas_proveedor, no
-- en perfiles) y, donde haya GRANT, también anon.
--
-- Con rol = NULL la aritmética de tres valores hace esto:
--     NULL = 'super_admin'                       → NULL
--     (NULL = 'admin_pais' AND NULL = p_pais_id)  → NULL
--     NULL OR NULL                                → NULL
--     NOT NULL                                    → NULL
--     IF NULL THEN ...                            → la rama NO se ejecuta  ⇒ EL RAISE NUNCA CORRE
--
-- Es decir: el gate deja pasar exactamente a quien NO tiene identidad. Al revés de lo que parece
-- que hace al leerlo. Censo contra pg_proc del proyecto vivo: 27 funciones SECURITY DEFINER con un
-- gate de este tipo; en el subconjunto explotable hay MUTACIÓN DE DINERO confirmada
-- (cerrar_liquidacion crea la liquidación, marcar_liquidacion_cobrada la marca cobrada,
-- solicitar_contrato_comision inserta el contrato) y lectura de agregados de dinero
-- (liquidar_comision). metricas_campana_pais además tiene EXECUTE otorgado a anon.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ EL GATE ENTERO VA ADENTRO DEL COALESCE
-- ----------------------------------------------------------------------------
-- El COALESCE envuelve la expresión COMPLETA, no cada término. Envolver por término deja al que
-- escribe la función la tarea de acordarse de envolver TODOS — y ese olvido es justamente el bug
-- que estamos cerrando. Con el gate entero adentro no queda ninguna expresión trivaluada que
-- alguien pueda escribir mal: el helper devuelve boolean estricto, siempre true o false, nunca NULL.
--
-- El `p_pais_id IS NOT NULL AND` explícito es la misma idea aplicada al parámetro: si el caller
-- manda NULL, la comparación daría NULL y, sin este término, el COALESCE lo convertiría en false
-- igual — pero el término lo deja ESCRITO en vez de implícito. Un NULL en el parámetro es un error
-- del llamador, no una autorización global.
--
-- Se generaliza el patrón ya probado de private.admin_puede_gestionar_empresa (mig 219, pieza 7) en
-- vez de inventar uno nuevo: mismo COALESCE envolvente, mismo estilo, misma clase de objeto.
--
-- ----------------------------------------------------------------------------
-- REGLA PARA TODA FUNCIÓN NUEVA
-- ----------------------------------------------------------------------------
-- Toda función nueva con gate de país DEBE consumir estos helpers en vez de comparar a mano contra
-- get_auth_user_rol() / get_auth_user_pais_id(). El harness lo vigila con el centinela P480, que
-- barre pg_proc y se pone ROJO ante cualquier comparación directa sin COALESCE envolvente que no
-- esté en su allowlist (allowlist = deuda con fecha, se vacía lote por lote).
--
-- SECURITY DEFINER: los dos leen perfiles a través de helpers DEFINER; el objeto es un chokepoint
-- de autorización y no debe depender de la RLS del caller. STABLE: solo leen. search_path = ''
-- (todo calificado). Sin GRANT a service_role a propósito: una llamada anidada dentro de otra
-- función SECURITY DEFINER se ejecuta con los privilegios del DUEÑO (postgres), no del caller, así
-- que las ~27 funciones que van a consumirlos NO necesitan que el caller tenga EXECUTE sobre el
-- helper. El único GRANT que hace falta es el de quien los invoque DIRECTO — hoy, solo
-- authenticated. Si alguna vez una edge function los invocara directo con la service key, ahí sí
-- haría falta agregar el GRANT a service_role (está anotado en el COMMENT de cada helper).
-- ============================================================================

BEGIN;

-- ========================= 1) private.puede_admin_pais =========================
CREATE OR REPLACE FUNCTION private.puede_admin_pais(
  p_pais_id uuid,
  p_roles   text[] DEFAULT ARRAY['super_admin']
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE(
    private.tiene_rol(p_roles)
    OR (
      public.get_auth_user_rol() = 'admin_pais'
      AND p_pais_id IS NOT NULL
      AND public.get_auth_user_pais_id() = p_pais_id
    ),
    false
  );
$function$;

REVOKE ALL     ON FUNCTION private.puede_admin_pais(uuid, text[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.puede_admin_pais(uuid, text[]) TO authenticated;

COMMENT ON FUNCTION private.puede_admin_pais(uuid, text[]) IS
$c$Gate de país FAIL-CLOSED. true si el caller tiene alguno de p_roles (default: super_admin), o si
es admin_pais y p_pais_id es su país. NUNCA devuelve NULL.

POR QUÉ EXISTE: el gate de país que se copió desde la mig 222 --
  IF NOT (get_auth_user_rol()='super_admin' OR (get_auth_user_rol()='admin_pais'
          AND get_auth_user_pais_id()=p_pais_id)) THEN RAISE ...
es TRIVALUADO y falla ABIERTO. get_auth_user_rol()/get_auth_user_pais_id() leen perfiles y devuelven
NULL para todo caller sin fila ahi (TODAS las cuentas de proveedor, y anon donde haya GRANT). Con
NULL: NULL OR NULL = NULL, NOT NULL = NULL, IF NULL no ejecuta la rama, el RAISE nunca corre. El
gate deja pasar justo a quien no tiene identidad. Censo del proyecto vivo: 27 funciones SECURITY
DEFINER con este patron, con mutacion de dinero confirmada en el subconjunto explotable
(cerrar_liquidacion, marcar_liquidacion_cobrada, solicitar_contrato_comision) y metricas_campana_pais
con EXECUTE otorgado a anon.

POR QUE EL GATE ENTERO VA ADENTRO DEL COALESCE: envolver termino por termino deja al autor la tarea
de acordarse de envolverlos todos, que es el olvido que causo el bug. Con la expresion completa
adentro no queda ninguna expresion trivaluada que alguien pueda escribir mal. Mismo motivo para el
`p_pais_id IS NOT NULL AND` explicito: deja escrito que un NULL del llamador es un error, no una
autorizacion global.

REGLA: toda funcion nueva con gate de pais DEBE consumir este helper en vez de comparar a mano.
El centinela P480 del harness barre pg_proc y se pone ROJO ante cualquier comparacion directa sin
COALESCE envolvente fuera de su allowlist (allowlist = deuda con fecha, se vacia lote por lote).
Generaliza el patron de private.admin_puede_gestionar_empresa (mig 219).

SIN GRANT A service_role, A PROPOSITO: una llamada anidada dentro de otra funcion SECURITY DEFINER
corre con los privilegios del OWNER (postgres), no del caller, asi que las ~27 funciones que van a
consumir este helper no necesitan que el caller tenga EXECUTE sobre el. El unico GRANT que hace
falta es el de quien lo invoque DIRECTO, y eso hoy es solo authenticated. SI alguna vez una edge
function lo invocara directo con la service key, ahi si haria falta
`GRANT EXECUTE ON FUNCTION private.puede_admin_pais(uuid, text[]) TO service_role;`.$c$;


-- ========================= 2) private.es_admin_pais =========================
CREATE OR REPLACE FUNCTION private.es_admin_pais()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE(public.get_auth_user_rol() = 'admin_pais', false);
$function$;

REVOKE ALL     ON FUNCTION private.es_admin_pais() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.es_admin_pais() TO authenticated;

COMMENT ON FUNCTION private.es_admin_pais() IS
$c$"El caller es admin_pais?" FAIL-CLOSED: true o false, nunca NULL.

POR QUE EXISTE: es la mitad sin-parametro del mismo bug de la mig 222. Hay gates que preguntan solo
por el rol, sin pais que comparar (listar_canjes_pendientes, listar_propuestas_especialidad,
listar_solicitudes_personalizacion): ahi el termino es `get_auth_user_rol() = 'admin_pais'` suelto,
que para un caller sin fila en perfiles vale NULL y, en un `IF NOT (... OR NULL)`, saltea el RAISE.
Sin este helper esos gates tendrian que envolverse a mano en COALESCE, que es exactamente el olvido
que estamos cerrando: el gate ENTERO va adentro del COALESCE, y aca el gate entero ES esta
comparacion.

REGLA: toda funcion nueva que gatee por rol admin_pais sin pais DEBE consumir este helper en vez de
comparar a mano contra get_auth_user_rol(). Vigilado por el centinela P480 del harness.
Para el gate CON pais, usar private.puede_admin_pais(p_pais_id[, p_roles]).

SIN GRANT A service_role, A PROPOSITO: una llamada anidada dentro de otra funcion SECURITY DEFINER
corre con los privilegios del OWNER (postgres), no del caller, asi que las funciones que consuman
este helper no necesitan que el caller tenga EXECUTE sobre el. El unico GRANT que hace falta es el
de quien lo invoque DIRECTO, y eso hoy es solo authenticated. SI alguna vez una edge function lo
invocara directo con la service key, ahi si haria falta
`GRANT EXECUTE ON FUNCTION private.es_admin_pais() TO service_role;`.$c$;

COMMIT;
