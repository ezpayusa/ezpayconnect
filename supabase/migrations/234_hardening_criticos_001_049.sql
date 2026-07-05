-- ============================================================================
-- Migración 234: Hardening de los 4 críticos heredados de la era 001–049
-- ============================================================================
-- Cierra los hallazgos CRÍTICOS de AUDITORIA-PROFUNDA-2026-07-05.md §1, todos
-- CONFIRMADOS contra la BD viva de producción (probes de solo lectura 2026-07-05):
--
--   C1  perfiles: escalada a super_admin por self-INSERT y self-UPDATE de `rol`.
--       Probe: policy "Insertar propio perfil" WITH CHECK (auth.uid()=id) sin
--       restringir rol; policy "Actualizar propio perfil" UPDATE con with_check
--       NULL → un usuario existente puede cambiarse el rol. anon+authenticated
--       tienen INSERT/UPDATE de tabla (default Supabase). roles_catalogo incluye
--       super_admin.
--   C2  v_consultas_paciente: reloptions NULL (security_invoker OFF) + SELECT a
--       anon y authenticated → notas SOAP de todos los tenants a cualquiera.
--   C3  get_invitaciones_empresa / get_ubicaciones_con_medico: SECURITY DEFINER
--       ejecutables por anon (has_function_privilege('anon',...)=true).
--       (Las otras 3 del informe — get_ruta_dia_visitador,
--        get_visitas_pendientes_aprobacion, get_visitadores_empresa — NO existen
--        en producción; drift repo↔prod. No se tocan aquí.)
--   C4  obtener_perfil(uuid): SECURITY DEFINER ejecutable por anon, sin gate →
--       enumeración masiva de PII.
--
-- Convención (fase0/mig 067+): SECURITY DEFINER + SET search_path='' + refs
-- calificadas + REVOKE de PUBLIC/anon + GRANT sólo donde hay caller legítimo.
-- Idempotente y segura de re-correr. Diseñada contra los nombres REALES de
-- producción (que difieren del repo por renombrados fuera de migraciones).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- FIX C1 — perfiles: bloquear auto-asignación de roles privilegiados
-- ----------------------------------------------------------------------------
-- Decisión: se usa una DENYLIST de roles globales/de sistema en el self-INSERT
-- (en vez de forzar rol='paciente'), porque el alta self-service de
-- medico/admin_clinica/gerente es comportamiento intencional de LoginPage.tsx
-- (mapea su dropdown a esos roles por este mismo INSERT). Forzar 'paciente'
-- rompería el registro de médicos y clínicas. La denylist cierra la escalada
-- crítica (acceso cross-tenant/global) sin romper el alta legítima.
--
-- NOTA (no es parte de este fix): que cualquiera pueda auto-registrarse como
-- medico/admin_clinica/gerente sigue abierto POR DISEÑO del producto. No es una
-- fuga cross-tenant por sí sola (esos roles quedan acotados por membresía de
-- clínica en los RPCs endurecidos 159/163), pero es una decisión de negocio a
-- revisar aparte.

-- INSERT: se recrean AMBOS nombres conocidos (repo: perfiles_insert;
-- producción: "Insertar propio perfil") para ser idempotente en los dos estados.
DROP POLICY IF EXISTS perfiles_insert ON public.perfiles;
DROP POLICY IF EXISTS "Insertar propio perfil" ON public.perfiles;
CREATE POLICY "Insertar propio perfil" ON public.perfiles
  FOR INSERT TO public
  WITH CHECK (
    auth.uid() = id
    AND rol NOT IN ('super_admin','admin_pais','admin','ezpay_admin','soporte','vendedor')
  );
-- (Se conserva intacta la policy "Admins pueden insertar perfiles" = super_admin,
--  y service_role/postgres siguen insertando cualquier rol por bypass de RLS.)

-- UPDATE: la policy "Actualizar propio perfil" (USING auth.uid()=id, with_check
-- NULL) permite que un usuario cambie su propio `rol`. Un WITH CHECK no puede
-- comparar OLD vs NEW, así que el vector de escalada por UPDATE se cierra con un
-- trigger BEFORE UPDATE que bloquea cambios de rol salvo actores privilegiados.
-- SECURITY INVOKER a propósito: así current_user es el rol efectivo del caller
-- (authenticated/anon/service_role), no el owner de la función.
CREATE OR REPLACE FUNCTION public.perfiles_guard_rol_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF NEW.rol IS DISTINCT FROM OLD.rol THEN
    -- Permitido: roles de BD privilegiados (edge=service_role; migraciones y
    -- RPCs DEFINER=postgres) o super_admin autenticado (panel admin).
    IF current_user IN ('service_role','postgres','supabase_admin','supabase_auth_admin')
       OR COALESCE(public.get_auth_user_rol() = 'super_admin', false) THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'No autorizado a modificar el rol del perfil'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_perfiles_guard_rol_update ON public.perfiles;
CREATE TRIGGER trg_perfiles_guard_rol_update
  BEFORE UPDATE ON public.perfiles
  FOR EACH ROW
  EXECUTE FUNCTION public.perfiles_guard_rol_update();

-- ----------------------------------------------------------------------------
-- FIX C2 — v_consultas_paciente: activar security_invoker (patrón migs 109/113)
-- ----------------------------------------------------------------------------
-- Con security_invoker=on la vista respeta la RLS de expediente_notas/pacientes
-- del usuario que consulta, en vez de correr como owner (BYPASSRLS).
ALTER VIEW IF EXISTS public.v_consultas_paciente SET (security_invoker = on);

-- ----------------------------------------------------------------------------
-- FIX C3 — RPCs DEFINER de la era 015–017 ejecutables por anon
-- ----------------------------------------------------------------------------

-- get_invitaciones_empresa: 0 callers en front/edge/SQL (superficie muerta que
-- filtra el TOKEN de invitación + PII). Se revoca por completo. (Se puede DROPear
-- en un follow-up; se deja el REVOKE para no borrar sin confirmación explícita.)
REVOKE EXECUTE ON FUNCTION public.get_invitaciones_empresa(uuid) FROM PUBLIC, anon, authenticated;

-- get_ubicaciones_con_medico: SÍ tiene caller (useUbicacionesMedico.ts:34). Se
-- recrea con SET search_path='' + gate fail-closed por empresa del caller, y se
-- revoca a anon (queda sólo authenticated). Firma/columnas idénticas a la viva.
CREATE OR REPLACE FUNCTION public.get_ubicaciones_con_medico(p_empresa_id uuid)
RETURNS TABLE(
  ubicacion_id uuid, medico_id uuid, nombre_completo text, email text,
  direccion text, lat double precision, lng double precision, notas text,
  updated_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.id AS ubicacion_id, u.medico_id, p.nombre_completo, p.email,
         u.direccion, u.lat, u.lng, u.notas, u.updated_at
  FROM public.ubicaciones_medico_proveedor u
  JOIN public.perfiles p ON p.id = u.medico_id
  WHERE u.empresa_id = p_empresa_id
    AND u.empresa_id = public.mi_empresa_proveedor();  -- gate: sólo la empresa del caller (NULL⇒0 filas)
$$;
REVOKE EXECUTE ON FUNCTION public.get_ubicaciones_con_medico(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ubicaciones_con_medico(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- FIX C4 — obtener_perfil(uuid): gate anti-enumeración + revocar anon
-- ----------------------------------------------------------------------------
-- Sólo el propio perfil (p_user_id = auth.uid()) o super_admin. useAuth.ts
-- siempre pasa el auth.uid() propio, así que el flujo legítimo no se rompe.
CREATE OR REPLACE FUNCTION public.obtener_perfil(p_user_id uuid)
RETURNS TABLE(
  id uuid, rol text, nombre_completo text, email text, telefono text,
  avatar_url text, pais_id uuid, activo boolean,
  created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT (p_user_id = auth.uid()
          OR COALESCE(public.get_auth_user_rol() = 'super_admin', false)) THEN
    RETURN;  -- fail-closed: 0 filas
  END IF;
  RETURN QUERY
  SELECT p.id, p.rol::text, p.nombre_completo, p.email, p.telefono,
         p.avatar_url, p.pais_id, p.activo, p.created_at, p.updated_at
  FROM public.perfiles p
  WHERE p.id = p_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.obtener_perfil(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_perfil(uuid) TO authenticated;

-- ============================================================================
-- Verificación post-aplicación (re-correr los probes de solo lectura):
--   C1  SELECT policyname, with_check FROM pg_policies
--         WHERE tablename='perfiles' AND cmd='INSERT';           -- with_check debe incluir la denylist
--       SELECT tgname FROM pg_trigger WHERE tgrelid='public.perfiles'::regclass; -- trg_perfiles_guard_rol_update presente
--   C2  SELECT reloptions FROM pg_class WHERE oid='public.v_consultas_paciente'::regclass; -- {security_invoker=on}
--   C3/C4 SELECT proname, has_function_privilege('anon',p.oid,'EXECUTE') AS anon_exec
--         FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--         WHERE n.nspname='public' AND proname IN
--           ('get_invitaciones_empresa','get_ubicaciones_con_medico','obtener_perfil'); -- anon_exec=false en las 3
-- ============================================================================
