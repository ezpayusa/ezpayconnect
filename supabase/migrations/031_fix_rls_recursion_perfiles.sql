-- ============================================
-- Migración 031: Fix recursión infinita en RLS de perfiles
-- ============================================
-- El patrón EXISTS(SELECT 1 FROM perfiles ...) dentro de policies de perfiles
-- causa recursión infinita porque el subquery también aplica RLS.
-- Solución: usar funciones SECURITY DEFINER para leer el perfil del usuario.

-- ============================================
-- 1. Funciones auxiliares (SECURITY DEFINER = saltan RLS)
-- ============================================
CREATE OR REPLACE FUNCTION public.get_auth_user_rol()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT rol FROM perfiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_auth_user_pais_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT pais_id FROM perfiles WHERE id = auth.uid();
$$;

-- ============================================
-- 2. Reemplazar policy recursiva en PERFILES
-- ============================================
DROP POLICY IF EXISTS "Admin ve perfiles de su pais" ON perfiles;
CREATE POLICY "Admin ve perfiles de su pais" ON perfiles
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- ============================================
-- 3. Reemplazar policies recursivas en otras tablas
-- ============================================

-- FACTURAS
DROP POLICY IF EXISTS "Admin ve facturas de su pais" ON facturas;
CREATE POLICY "Admin ve facturas de su pais" ON facturas
  FOR SELECT USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- MEDICOS
DROP POLICY IF EXISTS "Admin ve medicos de su pais" ON medicos;
CREATE POLICY "Admin ve medicos de su pais" ON medicos
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- CLINICAS
DROP POLICY IF EXISTS "Admin ve clinicas de su pais" ON clinicas;
CREATE POLICY "Admin ve clinicas de su pais" ON clinicas
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- PACIENTES
DROP POLICY IF EXISTS "Admin ve pacientes de su pais" ON pacientes;
CREATE POLICY "Admin ve pacientes de su pais" ON pacientes
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- CITAS
DROP POLICY IF EXISTS "Admin ve citas de su pais" ON citas;
CREATE POLICY "Admin ve citas de su pais" ON citas
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- RECETAS
DROP POLICY IF EXISTS "Admin ve recetas de su pais" ON recetas;
CREATE POLICY "Admin ve recetas de su pais" ON recetas
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- CAMPANAS PUBLICITARIAS
DROP POLICY IF EXISTS "Admin ve campanas de su pais" ON campanas_publicitarias;
CREATE POLICY "Admin ve campanas de su pais" ON campanas_publicitarias
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- NOTIFICACIONES
DROP POLICY IF EXISTS "Admin ve notificaciones de su pais" ON notificaciones;
CREATE POLICY "Admin ve notificaciones de su pais" ON notificaciones
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- VISITAS AGENDADAS
DROP POLICY IF EXISTS "Admin ve visitas de su pais" ON visitas_agendadas;
CREATE POLICY "Admin ve visitas de su pais" ON visitas_agendadas
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );

-- SOLICITUDES CAMPANA
DROP POLICY IF EXISTS "Admin ve solicitudes de su pais" ON solicitudes_campana;
CREATE POLICY "Admin ve solicitudes de su pais" ON solicitudes_campana
  FOR ALL USING (
    get_auth_user_rol() IN ('super_admin', 'admin', 'admin_pais')
    AND (get_auth_user_rol() = 'super_admin' OR pais_id = get_auth_user_pais_id())
  );
