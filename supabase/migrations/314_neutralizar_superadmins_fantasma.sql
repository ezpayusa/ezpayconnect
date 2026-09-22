-- ############################################################################################
-- 314 — neutralizar los dos super_admin fantasma
-- ############################################################################################
-- POR QUE EXISTE ESTA MIGRACION, en tres lineas:
--   `perfiles.activo` NO ES UN GATE. Las dos funciones que resuelven el rol en todo el sistema,
--   public.get_auth_user_rol() y private.rol_usuario(), leen `rol` de perfiles SIN MIRAR `activo`.
--   Por eso `activo = false` no neutralizaba nada: estas dos cuentas eran super_admins plenos.
--
-- Frente A, paso (a). admin@ezpayconnect.com y doctor@prueba.com tienen `perfiles.rol =
-- 'super_admin'` y `activo = false`, y ESE `activo = false` NO LOS FRENA. Medido contra el cuerpo
-- vivo de las dos funciones que resuelven el rol en todo el sistema:
--
--   public.get_auth_user_rol()  ->  SELECT rol FROM perfiles WHERE id = auth.uid();
--   private.rol_usuario()       ->  SELECT rol FROM public.perfiles WHERE id = auth.uid();
--
-- Ninguna mira `activo`. Toda policy que pregunte `get_auth_user_rol() = 'super_admin'` o
-- `private.tiene_rol(ARRAY['super_admin'])` les dice que si. Son super_admins plenos.
--
-- ESTRATEGIA DOBLE, NO DESTRUCTIVA. No se borra ni una fila:
--   (i)  el rol baja a 'cliente'
--   (ii) el login se bloquea en auth.users con banned_until
-- Cada mitad sola serviria; juntas cubren los dos caminos (una sesion viva ya emitida sigue
-- teniendo JWT valido hasta que expire, y ahi la que protege es (i); un login nuevo lo ataja (ii)).
--
-- POR QUE 'cliente' Y NO OTRO. Del catalogo REAL (public.roles_catalogo, 13 codigos):
--   · es el de `orden` mas alto (70), que es el propio orden de privilegio del catalogo;
--   · `ambito='paciente'`, `es_super=false`, `es_staff_clinica=false`;
--   · y lo que termina de decidirlo: NINGUNA policy y NINGUNA funcion de `public`/`private`
--     nombran el literal 'cliente' (censo hecho sobre pg_policy y pg_get_functiondef: 0 y 0).
--     O sea que no es "menos privilegiado": es INERTE. Un rol que nadie consulta no habilita nada.
--   Los otros candidatos por orden eran `vendedor` (60) y `soporte` (50), los dos con
--   `ambito='sistema'`, que es justo el ambito del que se los quiere sacar.
--
-- rol_id NO SE TOCA y no hay nada que sincronizar: las dos cuentas lo tienen en NULL, y ademas
-- `perfiles.rol_id` apunta a `public.roles` mientras `perfiles.rol` apunta a
-- `public.roles_catalogo(codigo)` — son DOS catalogos distintos. Inventar un rol_id seria empeorar
-- la incoherencia, no arreglarla. El autochequeo exige que siga NULL o que concuerde con `rol`.
--
-- BORRAR HABRIA SIDO DESTRUCTIVO, y por eso no se borra. Las dos cuentas estan referenciadas desde
-- public: notificaciones.usuario_id=31, pagos_proveedor.verificado_por=7, facturas.medico_id=3,
-- auditoria_logs.usuario_id=3, usuario_roles=2. Varias de esas FK son ON DELETE NO ACTION o
-- RESTRICT (facturas, pagos_proveedor, auditoria_ia, expediente_notas), asi que un DELETE ni
-- siquiera pasaria; y las que son SET NULL borrarian la trazabilidad de quien verifico un pago.
--
-- banned_until: SE USA UNA FECHA FINITA LEJANA, NO 'infinity'. La columna es timestamptz y la base
-- acepta 'infinity' sin problema, pero quien LEE esa fila es GoTrue (Go), y el driver de Postgres
-- de Go falla al escanear `infinity` en un time.Time salvo que se habilite explicitamente. Un
-- valor que rompe al lector no bloquea: rompe. '9999-12-31' cumple lo mismo (banned_until > now()
-- durante los proximos ~7975 anios) y se parsea en cualquier cliente.
--
-- NO SE TOCA superadmin@ezpayconnect.com: es el unico super_admin activo real que queda.
-- ############################################################################################


-- ============================================================================================
-- 0) Estado previo + identificacion por EMAIL (nunca por uuid hardcodeado)
-- ============================================================================================
DO $pre$
DECLARE
  v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.perfiles
   WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com');
  IF v_n <> 2 THEN
    RAISE EXCEPTION '314: se esperaban EXACTAMENTE 2 perfiles objetivo por email, hay %', v_n;
  END IF;

  -- Los dos tienen que estar hoy en super_admin: si alguno ya no lo esta, algo cambio desde el
  -- recon y la migracion no puede asumir el punto de partida.
  SELECT count(*) INTO v_n FROM public.perfiles
   WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com') AND rol = 'super_admin';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '314: se esperaban 2 objetivos con rol=super_admin, hay % (estado de partida distinto al medido)', v_n;
  END IF;

  -- Y tiene que existir el super_admin que se conserva.
  SELECT count(*) INTO v_n FROM public.perfiles
   WHERE email = 'superadmin@ezpayconnect.com' AND rol = 'super_admin';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '314: superadmin@ezpayconnect.com no esta como super_admin (hay % filas): abortar antes de dejar el sistema sin ninguno', v_n;
  END IF;

  -- 'cliente' tiene que existir en el catalogo al que apunta la FK perfiles_rol_fkey.
  IF NOT EXISTS (SELECT 1 FROM public.roles_catalogo WHERE codigo = 'cliente') THEN
    RAISE EXCEPTION '314: el codigo de rol destino no existe en roles_catalogo';
  END IF;

  PERFORM set_config('m314.perfiles_antes', (SELECT count(*)::text FROM public.perfiles), true);
  PERFORM set_config('m314.authusers_antes', (SELECT count(*)::text FROM auth.users), true);
  PERFORM set_config('m314.usuroles_antes', (SELECT count(*)::text FROM public.usuario_roles), true);
END $pre$;


-- ============================================================================================
-- (i) El rol baja a 'cliente'
-- ============================================================================================
-- El trigger trg_perfiles_guard_rol_update es BEFORE UPDATE FOR EACH ROW sobre perfiles y vigila
-- rol/pais_id/rol_id/activo. NO bloquea esta migracion: su punto de exencion es
--   current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin')
--       OR COALESCE(public.get_auth_user_rol() = 'super_admin', false)
-- y `db query --linked` corre como `postgres` (verificado: current_user = postgres), asi que
-- cortocircuita en el primer operando y `auth.uid() = NULL` no llega a importar.
UPDATE public.perfiles
   SET rol = 'cliente',
       updated_at = now()
 WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com');


-- ============================================================================================
-- (ii) El login se bloquea en auth.users
-- ============================================================================================
UPDATE auth.users
   SET banned_until = timestamptz '9999-12-31 23:59:59+00'
 WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com');


-- ============================================================================================
-- (iii) public.usuario_roles: apagar las asignaciones de los 2 objetivos
-- ============================================================================================
-- TERCER LUGAR DONDE VIVEN ROLES, y nadie lo sabia. `doctor@prueba.com` tiene ahi DOS filas,
-- una de ellas `super_admin`. Hoy es tabla MUERTA — censo sobre pg_proc y pg_policy: 0 funciones
-- y 0 policies la mencionan, asi que ninguna de sus filas habilita nada. Se apagan igual, porque
-- una asignacion de super_admin latente para una cuenta que se acaba de neutralizar es una mina:
-- el dia que alguien cablee esta tabla, vuelve sola.
--
-- SOLO esos 2 usuarios. Las otras 14 filas no se tocan, y el autochequeo verifica que el total
-- siga en 16 — o sea que esto apaga, no borra.
UPDATE public.usuario_roles
   SET activo = false
 WHERE usuario_id IN (
         SELECT id FROM public.perfiles
          WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com'));


-- ============================================================================================
-- AUTOCHEQUEO — aborta la migracion entera si algo no quedo como se pidio
-- ============================================================================================
DO $ac$
DECLARE
  v_n int; v_email text; v_detalle text;
BEGIN
  -- 1. queda como mucho un super_admin
  SELECT count(*) INTO v_n FROM public.perfiles WHERE rol = 'super_admin';
  IF v_n > 1 THEN
    RAISE EXCEPTION '314 autochequeo: quedan % perfiles con rol=super_admin, se esperaba 1', v_n;
  END IF;
  IF v_n = 0 THEN
    RAISE EXCEPTION '314 autochequeo: NO queda ningun super_admin — el sistema quedaria sin administrador';
  END IF;

  -- 2. y es el que corresponde
  SELECT email INTO v_email FROM public.perfiles WHERE rol = 'super_admin';
  IF v_email IS DISTINCT FROM 'superadmin@ezpayconnect.com' THEN
    RAISE EXCEPTION '314 autochequeo: el unico super_admin es "%", se esperaba superadmin@ezpayconnect.com',
      COALESCE(v_email, '(sin email)');
  END IF;

  -- 3. las 2 objetivo quedaron en el rol destino
  SELECT count(*) INTO v_n FROM public.perfiles
   WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com') AND rol = 'cliente';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '314 autochequeo: % de 2 objetivos quedaron en rol=cliente', v_n;
  END IF;

  -- 4. las 2 quedaron con el login bloqueado, y hacia el futuro
  SELECT count(*) INTO v_n FROM auth.users
   WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com')
     AND banned_until IS NOT NULL AND banned_until > now();
  IF v_n <> 2 THEN
    RAISE EXCEPTION '314 autochequeo: % de 2 objetivos tienen banned_until vigente', v_n;
  END IF;

  -- 5. rol y rol_id coherentes: o rol_id sigue NULL, o el nombre en `roles` coincide con `rol`.
  --    (son dos catalogos distintos: rol -> roles_catalogo.codigo, rol_id -> roles.id)
  SELECT string_agg(p.email || ' rol=' || p.rol || ' rol_id=' || COALESCE(p.rol_id::text,'NULL'), '; ')
    INTO v_detalle
    FROM public.perfiles p
    LEFT JOIN public.roles r ON r.id = p.rol_id
   WHERE p.email IN ('admin@ezpayconnect.com', 'doctor@prueba.com')
     AND p.rol_id IS NOT NULL
     AND r.nombre IS DISTINCT FROM p.rol;
  IF v_detalle IS NOT NULL THEN
    RAISE EXCEPTION '314 autochequeo: rol y rol_id incoherentes -> %', v_detalle;
  END IF;

  -- 6. usuario_roles: ninguna fila viva de los 2 objetivos
  SELECT count(*) INTO v_n FROM public.usuario_roles ur
   WHERE ur.activo
     AND ur.usuario_id IN (SELECT id FROM public.perfiles
                            WHERE email IN ('admin@ezpayconnect.com', 'doctor@prueba.com'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION '314 autochequeo: quedan % fila(s) de usuario_roles con activo=true de los objetivos', v_n;
  END IF;

  -- 7. NO SE BORRO NADA. Es la garantia de que esto fue una neutralizacion y no una limpieza.
  SELECT count(*) INTO v_n FROM public.perfiles;
  IF v_n::text IS DISTINCT FROM current_setting('m314.perfiles_antes', true) THEN
    RAISE EXCEPTION '314 autochequeo: perfiles paso de % a % filas',
      current_setting('m314.perfiles_antes', true), v_n;
  END IF;
  SELECT count(*) INTO v_n FROM auth.users;
  IF v_n::text IS DISTINCT FROM current_setting('m314.authusers_antes', true) THEN
    RAISE EXCEPTION '314 autochequeo: auth.users paso de % a % filas',
      current_setting('m314.authusers_antes', true), v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.usuario_roles;
  IF v_n::text IS DISTINCT FROM current_setting('m314.usuroles_antes', true) THEN
    RAISE EXCEPTION '314 autochequeo: usuario_roles paso de % a % filas (se apaga, no se borra)',
      current_setting('m314.usuroles_antes', true), v_n;
  END IF;

  PERFORM set_config('m314.auto', format(
    'OK (1 super_admin y es %s; 2 objetivos en rol=cliente con banned_until vigente; rol/rol_id coherentes; '
    || '0 filas vivas en usuario_roles de los objetivos; perfiles=%s, auth.users=%s y usuario_roles=%s sin cambios de conteo)',
    v_email, current_setting('m314.perfiles_antes', true), current_setting('m314.authusers_antes', true),
    current_setting('m314.usuroles_antes', true)), true);
END $ac$;
