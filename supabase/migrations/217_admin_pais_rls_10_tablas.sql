-- ============================================================================
-- Migración 217: RLS — admin_pais acotado a su país en las 10 tablas país-scoped
-- ============================================================================
-- Extiende la policy "Admin ve <X> de su pais" de 10 tablas para admitir, además de super_admin
-- (global), al rol admin_pais (reintroducido en mig 216) ACOTADO a su propio país
-- (pais_id = get_auth_user_pais_id()). Es la seguridad REAL de datos por país; la pieza 3 (front)
-- era solo navegación/UX.
--
-- (a) ALCANCE: 10 tablas. 9 tienen la policy como cmd=ALL → admin_pais gana lectura Y ESCRITURA
--     (INSERT/UPDATE/DELETE) dentro de su país, incluida perfiles (crear/editar cuentas de su país).
--     Es la decisión de negocio confirmada ("plena autoridad en su país"). La 10ª, facturas, tiene
--     la policy como cmd=SELECT (no ALL) → admin_pais gana SOLO LECTURA de facturas de su país
--     (los writes de facturas ya los gobiernan las policies de médico); se preserva ese cmd.
--     with_check era NULL en las 10 → se mantiene NULL: en una policy ALL sin WITH CHECK, Postgres
--     usa la expresión USING también para el chequeo de escritura, así que un admin_pais solo puede
--     INSERT/UPDATE filas con pais_id = su país (cross-país queda bloqueado, fail-closed).
--
-- (b) pais_id NULL: `pais_id = get_auth_user_pais_id()` con pais_id NULL evalúa a NULL (no TRUE) →
--     la fila NUNCA matchea para admin_pais. Es fail-closed natural, sin manejo especial. Esas filas
--     legacy siguen visibles para super_admin (rama super). Conteos verificados hoy (bajos): citas 1,
--     medicos 3, perfiles 3, recetas 2; el resto 0.
--
-- (c) NO se tocan las policies redundantes de solo-super_admin que existen en 2 de estas tablas
--     (visitas_agendadas: "Admin ezpay ve todas las visitas"; solicitudes_campana: sus policies
--     admin select/update): como RLS es OR-de-policies, son un extra para super_admin que ni bloquea
--     ni ayuda a admin_pais. Dejarlas intactas no cambia nada para admin_pais.
--
-- Helpers reutilizados (ya existen, STABLE SECURITY DEFINER, resuelven desde perfiles):
--   get_auth_user_rol(), get_auth_user_pais_id(). No se crea ninguno nuevo.
--
-- Atómico (BEGIN/COMMIT): los 10 DROP+CREATE van en una sola transacción; si alguno fallara,
-- ninguna tabla queda sin su policy admin (evita un estado intermedio inseguro).
-- ============================================================================

BEGIN;

-- === 9 tablas cmd=ALL (lectura + escritura acotadas al país) ===

DROP POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias;
CREATE POLICY "Admin ve campanas de su pais" ON public.campanas_publicitarias
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve citas de su pais" ON public.citas;
CREATE POLICY "Admin ve citas de su pais" ON public.citas
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve clinicas de su pais" ON public.clinicas;
CREATE POLICY "Admin ve clinicas de su pais" ON public.clinicas
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve medicos de su pais" ON public.medicos;
CREATE POLICY "Admin ve medicos de su pais" ON public.medicos
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve pacientes de su pais" ON public.pacientes;
CREATE POLICY "Admin ve pacientes de su pais" ON public.pacientes
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve perfiles de su pais" ON public.perfiles;
CREATE POLICY "Admin ve perfiles de su pais" ON public.perfiles
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve recetas de su pais" ON public.recetas;
CREATE POLICY "Admin ve recetas de su pais" ON public.recetas
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana;
CREATE POLICY "Admin ve solicitudes de su pais" ON public.solicitudes_campana
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

DROP POLICY "Admin ve visitas de su pais" ON public.visitas_agendadas;
CREATE POLICY "Admin ve visitas de su pais" ON public.visitas_agendadas
  FOR ALL
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

-- === 1 tabla cmd=SELECT (solo lectura acotada al país; se preserva el cmd) ===

DROP POLICY "Admin ve facturas de su pais" ON public.facturas;
CREATE POLICY "Admin ve facturas de su pais" ON public.facturas
  FOR SELECT
  USING (
    get_auth_user_rol() = 'super_admin'::text
    OR (get_auth_user_rol() = 'admin_pais'::text AND pais_id = get_auth_user_pais_id())
  );

COMMIT;
