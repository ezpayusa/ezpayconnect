-- ============================================================
-- FASE 0 · Fundación de seguridad — Helpers de autorización
-- ------------------------------------------------------------
-- (Se aplica ANTES que 068_fase0_roles_catalogo.sql: el catálogo usa
--  private.tiene_rol() en su política de admin.)
--
-- Decisiones de diseño:
--  * Esquema DEDICADO y NO expuesto: `private`. NO `public` ni `auth`.
--    - `auth` lo gestiona Supabase (crear objetos ahí se rompe en upgrades).
--    - `public` quedaría invocable como RPC vía la Data API (PostgREST).
--    Al vivir en `private` (no listado en "Exposed schemas" de PostgREST), estas
--    funciones NO son llamables desde el cliente; solo las usan las políticas
--    RLS server-side.
--  * Permisos mínimos: USAGE del esquema y EXECUTE solo para `authenticated`.
--    Se REVOCA de PUBLIC/anon (Postgres concede EXECUTE a PUBLIC por defecto).
--  * SECURITY DEFINER + STABLE + search_path = '' (VACÍO):
--    Con SECURITY DEFINER, un `search_path = public` dejaría que pg_temp se
--    busque PRIMERO, permitiendo a un `authenticated` crear tablas temporales
--    (perfiles, pacientes, …) que SOMBREEN las reales y escalar a super_admin.
--    Por eso search_path = '' y CADA relación va calificada con su esquema
--    (public.*, auth.uid()). Las llamadas a otras helpers van con private.*.
--    (Operadores/casts/built-ins viven en pg_catalog, siempre implícito.)
--  * Null-safe: si auth.uid() es NULL (anon), devuelven NULL/false.
--
-- IMPORTANTE (regla 3 del plan): estas helpers son de DECISIÓN/LECTURA. Las
-- funciones SECURITY DEFINER que MUTAN datos deben, además, revalidar la
-- autorización del caller internamente (se endurece en fases posteriores).
-- ============================================================

-- Esquema dedicado, no expuesto a la Data API.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO authenticated;
-- (anon NO recibe USAGE: ninguna política de Fase 0 invoca helpers para anon.)

-- ---- Rol del usuario actual (perfiles.rol) -----------------
CREATE OR REPLACE FUNCTION private.rol_usuario()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT rol FROM public.perfiles WHERE id = auth.uid();
$$;
COMMENT ON FUNCTION private.rol_usuario() IS 'Rol (perfiles.rol) del usuario autenticado. NULL si no es usuario de perfiles (p.ej. proveedor/lab usan mi_rol_proveedor()).';

-- ---- ¿El usuario tiene alguno de estos roles? --------------
CREATE OR REPLACE FUNCTION private.tiene_rol(p_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(private.rol_usuario() = ANY (p_roles), false);
$$;

-- ---- Clínicas a las que pertenece el usuario (PLURAL) ------
-- Cubre staff de clínica (obtener_clinica_usuario) y médicos (medico_clinicas).
-- USAR ESTA en las políticas de aislamiento (con IN/ANY), para soportar staff
-- y médicos que pertenecen a VARIAS clínicas.
CREATE OR REPLACE FUNCTION private.clinicas_del_usuario()
RETURNS SETOF UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT clinica_id FROM public.obtener_clinica_usuario(auth.uid())
  UNION
  SELECT clinica_id FROM public.medico_clinicas WHERE medico_id = auth.uid();
$$;

-- ---- Clínica principal (SINGULAR) -------------------------
-- ⚠️ SOLO PARA UI / conveniencia de visualización. Si el usuario pertenece a
-- VARIAS clínicas, devuelve UNA ARBITRARIA (la primera por LIMIT 1, sin orden
-- garantizado). NO usar en políticas de aislamiento: ahí va clinicas_del_usuario()
-- con IN/ANY para no excluir las demás clínicas del staff multi-clínica.
CREATE OR REPLACE FUNCTION private.clinica_del_usuario()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT clinica_id FROM public.obtener_clinica_usuario(auth.uid()) LIMIT 1;
$$;

-- ---- ¿El usuario es admin/gerente de ESA clínica? ----------
CREATE OR REPLACE FUNCTION private.es_admin_clinica(p_clinica UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.tiene_rol(ARRAY['admin_clinica','gerente'])
     AND p_clinica IN (SELECT private.clinicas_del_usuario());
$$;

-- ---- ¿El usuario es el médico asignado del paciente? -------
-- pacientes.id es bigint. Overload TEXT para tablas con paciente_id TEXT
-- (historial_medico, recetas_avanzadas, dispensaciones). La guarda ~ '^[0-9]+$'
-- evita errores de cast si el texto no es numérico.
CREATE OR REPLACE FUNCTION private.es_medico_de(p_paciente BIGINT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pacientes
    WHERE id = p_paciente AND medico_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION private.es_medico_de(p_paciente TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_paciente ~ '^[0-9]+$'
     AND EXISTS (
       SELECT 1 FROM public.pacientes
       WHERE id = p_paciente::bigint AND medico_id = auth.uid()
     );
$$;

-- ---- ¿El paciente es del propio usuario autenticado? -------
-- (el usuario ES el paciente). Para políticas de "paciente dueño".
CREATE OR REPLACE FUNCTION private.paciente_es_mio(p_paciente BIGINT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pacientes
    WHERE id = p_paciente AND auth_user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION private.paciente_es_mio(p_paciente TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_paciente ~ '^[0-9]+$'
     AND EXISTS (
       SELECT 1 FROM public.pacientes
       WHERE id = p_paciente::bigint AND auth_user_id = auth.uid()
     );
$$;

-- ---- Permisos: revocar de PUBLIC, conceder solo a authenticated ----
-- (Postgres concede EXECUTE a PUBLIC por defecto al crear funciones.)
REVOKE EXECUTE ON FUNCTION private.rol_usuario()           FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.tiene_rol(TEXT[])       FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.clinicas_del_usuario()  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.clinica_del_usuario()   FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.es_admin_clinica(UUID)  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.es_medico_de(BIGINT)    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.es_medico_de(TEXT)      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.paciente_es_mio(BIGINT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.paciente_es_mio(TEXT)   FROM PUBLIC;

GRANT EXECUTE ON FUNCTION private.rol_usuario()           TO authenticated;
GRANT EXECUTE ON FUNCTION private.tiene_rol(TEXT[])       TO authenticated;
GRANT EXECUTE ON FUNCTION private.clinicas_del_usuario()  TO authenticated;
GRANT EXECUTE ON FUNCTION private.clinica_del_usuario()   TO authenticated;
GRANT EXECUTE ON FUNCTION private.es_admin_clinica(UUID)  TO authenticated;
GRANT EXECUTE ON FUNCTION private.es_medico_de(BIGINT)    TO authenticated;
GRANT EXECUTE ON FUNCTION private.es_medico_de(TEXT)      TO authenticated;
GRANT EXECUTE ON FUNCTION private.paciente_es_mio(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION private.paciente_es_mio(TEXT)   TO authenticated;

-- ------------------------------------------------------------
-- VERIFICACIÓN MANUAL (no se ejecuta aquí): confirmar que el esquema `private`
-- NO esté en la lista "Exposed schemas" de PostgREST
-- (Dashboard → Project Settings → API → Exposed schemas; debe ser solo
--  `public, graphql_public`). Así estas funciones no son invocables como RPC.
-- ------------------------------------------------------------
