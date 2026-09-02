-- 262_perfiles_guard_scope_columns.sql
--
-- QUE CIERRA: P435 — self-update de perfiles.pais_id.
-- La policy "Actualizar propio perfil" es FOR UPDATE USING (auth.uid() = id). Tiene with_check NULL
-- a nivel de catalogo, pero eso NO significa que no haya chequeo: cuando WITH CHECK se omite,
-- Postgres usa la propia expresion USING como WITH CHECK efectivo. O sea, el chequeo real sobre la
-- fila NEW es (auth.uid() = id): valida QUIEN es la fila, no QUE columnas cambian. El id no cambia,
-- asi que reescribir pais_id/rol_id/activo de la propia fila lo pasa sin problema.
-- Ademas las policies permisivas se combinan con OR: aunque "Admin ve perfiles de su pais" (FOR ALL,
-- with_check efectivo = pais_id = get_auth_user_pais_id()) rechace la fila NEW con otro pais, el
-- self-update queda igual habilitado por "Actualizar propio perfil". ESE es el hueco.
-- Probe en vivo (rolled back): un admin_pais se cambio su pais_id a otro pais, filas_afectadas=1.
-- Como get_auth_user_pais_id() lee de perfiles, eso mueve el scope de todo lo que gatea por pais
-- (liquidar_comision, cerrar_liquidacion, marcar_liquidacion_cobrada, listar_*): escalada lateral de pais.
--
-- LA RLS NO ES EL CONTROL para este caso. Su WITH CHECK efectivo razona sobre identidad y pertenencia
-- de la fila, no sobre columnas; para un self-update siempre da verdadero. El trigger BEFORE UPDATE es
-- el UNICO punto real donde se puede frenar la escritura de las columnas de identidad/scope. Por eso
-- el guard se extiende aca y no se toca la RLS (ampliarla no arreglaria nada y abriria superficie).
-- Nota: para SUJETOS DE TERCEROS la RLS si corta el cambio de pais_id (probe P445), pero por el
-- WITH CHECK de la policy de admin, no por el guard: son controles distintos y se testean por separado.
--
-- ALCANCE: se extiende el guard existente para vigilar, ademas de rol, tambien pais_id, rol_id y activo.
-- MISMO nombre y MISMA firma: el trigger trg_perfiles_guard_rol_update ya apunta a esta funcion.
-- NO se recrea el trigger. NO se dropea la funcion (CREATE OR REPLACE conserva la dependencia).
-- Se preserva LANGUAGE plpgsql, SET search_path TO '' y el hecho de que NO es SECURITY DEFINER
-- (corre con los privilegios del invocante; current_user es justamente lo que se inspecciona).
--
-- CALLERS LEGITIMOS (censo previo) — todos quedan exentos:
--   * RPCs SECURITY DEFINER owner=postgres: registrar_medico_desde_invitacion,
--     registrar_clinica_desde_invitacion (ambas hacen UPDATE perfiles SET rol=..., pais_id=...)
--     -> current_user = 'postgres'.
--   * Edge functions (crear-empleado, crear-staff-clinica, registrar-medico-invitacion,
--     registrar-clinica-invitacion) -> current_user = 'service_role'; ademas son INSERT, no UPDATE.
--   * UI que escribe rol / rol_id / activo (UsuariosAdminPage, useRoles) -> la dispara super_admin.
--   * Self-updates de datos no sensibles (avatar_url, nombre_completo, laboratorio_preferido_id)
--     -> ninguna de las 4 columnas cambia, el guard ni se evalua.

CREATE OR REPLACE FUNCTION public.perfiles_guard_rol_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_exento boolean;
BEGIN
  -- Guard clause: solo si cambia alguna de las 4 columnas vigiladas se resuelve la exencion.
  -- Evita pagar get_auth_user_rol() (un SELECT sobre perfiles) en cada UPDATE de avatar/telefono/etc.
  IF NEW.rol     IS DISTINCT FROM OLD.rol
     OR NEW.pais_id IS DISTINCT FROM OLD.pais_id
     OR NEW.rol_id  IS DISTINCT FROM OLD.rol_id
     OR NEW.activo  IS DISTINCT FROM OLD.activo
  THEN

    -- Punto de exencion UNICO y compartido por las 4 columnas.
    -- Permitido: roles de BD privilegiados (edge=service_role; migraciones y RPCs DEFINER=postgres)
    -- o super_admin autenticado (panel admin).
    -- COALESCE obligatorio: get_auth_user_rol() puede devolver NULL y `false OR NULL` = NULL,
    -- que en un IF se comporta como falso pero en cualquier reuso posterior es fail-open.
    v_exento := current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin')
                OR COALESCE(public.get_auth_user_rol() = 'super_admin', false);

    IF NOT v_exento THEN

      -- Mensaje y ERRCODE originales, textuales: hay front que puede depender de este string.
      IF NEW.rol IS DISTINCT FROM OLD.rol THEN
        RAISE EXCEPTION 'No autorizado a modificar el rol del perfil'
          USING ERRCODE = '42501';
      END IF;

      -- P435: el hueco que cierra esta migracion.
      IF NEW.pais_id IS DISTINCT FROM OLD.pais_id THEN
        RAISE EXCEPTION 'No autorizado a modificar el pais del perfil'
          USING ERRCODE = '42501';
      END IF;

      IF NEW.rol_id IS DISTINCT FROM OLD.rol_id THEN
        RAISE EXCEPTION 'No autorizado a modificar el rol_id del perfil'
          USING ERRCODE = '42501';
      END IF;

      IF NEW.activo IS DISTINCT FROM OLD.activo THEN
        RAISE EXCEPTION 'No autorizado a modificar el estado activo del perfil'
          USING ERRCODE = '42501';
      END IF;

    END IF;

  END IF;

  RETURN NEW;
END;
$function$;
