-- ============================================================
-- FASE 4 · Bloque D — Tablas abiertas (medicos / medicamentos / farmacias /
--                     cuentas_bancarias_pais)
-- ------------------------------------------------------------
-- Cierra el CRUD anónimo/abierto. Lecturas de directorio se mantienen.
-- Verificado: medicos y medicamentos NO se escriben desde el frontend; farmacias
-- y cuentas_bancarias_pais se escriben solo desde paneles admin.
-- ============================================================

-- ---------- Helper: país del usuario (perfil O proveedor) ----------
CREATE OR REPLACE FUNCTION private.mi_pais()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(
    (SELECT pais_id FROM public.perfiles WHERE id = auth.uid()),
    (SELECT pais_id FROM public.cuentas_proveedor WHERE id = auth.uid()),
    (SELECT e.pais_id FROM public.cuentas_proveedor cp
       JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
      WHERE cp.id = auth.uid())
  );
$$;
REVOKE EXECUTE ON FUNCTION private.mi_pais() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION private.mi_pais() TO authenticated;

-- ============================================================
-- medicos — cerrar CRUD anónimo; lectura (directorio) se mantiene
-- ============================================================
DROP POLICY IF EXISTS "medicos_insert" ON medicos;   -- INSERT public WITH CHECK(true)
DROP POLICY IF EXISTS "medicos_update" ON medicos;   -- UPDATE public USING(true)
DROP POLICY IF EXISTS "medicos_delete" ON medicos;   -- DELETE public USING(true)
-- Se mantienen las SELECT (Allow anon/authenticated read, medicos_select, Medico ve su
-- perfil, Paciente ve medicos de su pais) y "Admin ve medicos de su pais" (ALL, super_admin).

-- Médico edita SU propio registro
CREATE POLICY medicos_update_propio ON medicos
  FOR UPDATE TO authenticated
  USING ( id = auth.uid() ) WITH CHECK ( id = auth.uid() );

-- Admin de clínica gestiona los médicos de SU clínica
CREATE POLICY medicos_admin_clinica ON medicos
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['admin_clinica','gerente']) AND clinica_id IN (SELECT private.clinicas_del_usuario()) )
  WITH CHECK ( private.tiene_rol(ARRAY['admin_clinica','gerente']) AND clinica_id IN (SELECT private.clinicas_del_usuario()) );

-- Anon: directorio profesional PÚBLICO sin PII (anon hoy lee cédula/teléfono/email).
-- GRANT por columna: anon solo puede SELECT columnas no sensibles. Los lectores del
-- frontend (id, nombre_completo) siguen funcionando. authenticated mantiene acceso
-- completo (el médico ve su propio registro vía "Medico ve su perfil").
REVOKE SELECT ON public.medicos FROM anon;
GRANT  SELECT (id, nombre_completo, especialidad, foto_url, clinica_id, pais_id, activo)
  ON public.medicos TO anon;

-- ============================================================
-- medicamentos — write solo super_admin; lectura (catálogo) se mantiene
-- ============================================================
DROP POLICY IF EXISTS "medicamentos_insert" ON medicamentos;
DROP POLICY IF EXISTS "medicamentos_update" ON medicamentos;
DROP POLICY IF EXISTS "medicamentos_delete" ON medicamentos;
-- Se mantiene medicamentos_select (authenticated).

CREATE POLICY medicamentos_write_admin ON medicamentos
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );

-- ============================================================
-- farmacias — write solo super_admin; lectura (directorio) se mantiene
-- ============================================================
DROP POLICY IF EXISTS "editar_farmacias" ON farmacias;   -- ALL authenticated USING(true)
-- Se mantienen las SELECT (Allow anon/authenticated read, ver_farmacias).

CREATE POLICY farmacias_write_admin ON farmacias
  FOR ALL TO authenticated
  USING ( private.tiene_rol(ARRAY['super_admin']) )
  WITH CHECK ( private.tiene_rol(ARRAY['super_admin']) );

-- ============================================================
-- cuentas_bancarias_pais — SELECT requiere auth + acotar por país
-- ============================================================
DROP POLICY IF EXISTS "cuentas_banco_read" ON cuentas_bancarias_pais;  -- SELECT public USING(true)
-- Se mantiene cuentas_banco_admin (ALL) para la gestión EzPay.

-- Un usuario autenticado solo ve la cuenta de SU país (perfil o proveedor).
CREATE POLICY cuentas_banco_read_pais ON cuentas_bancarias_pais
  FOR SELECT TO authenticated
  USING ( pais_id = private.mi_pais() );
