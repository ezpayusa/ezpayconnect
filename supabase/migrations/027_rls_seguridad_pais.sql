-- ============================================
-- Migración 027: Refuerzo RLS + Seguridad por País
-- ============================================
-- Objetivo: Asegurar que usuarios de un país no accedan a datos de otro país

-- ============================================
-- 1. FACTURAS — Habilitar RLS + Políticas
-- ============================================
ALTER TABLE facturas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Medico ve sus facturas" ON facturas;
CREATE POLICY "Medico ve sus facturas" ON facturas
  FOR SELECT USING (medico_id = auth.uid());

DROP POLICY IF EXISTS "Medico crea sus facturas" ON facturas;
CREATE POLICY "Medico crea sus facturas" ON facturas
  FOR INSERT WITH CHECK (medico_id = auth.uid());

DROP POLICY IF EXISTS "Medico actualiza sus facturas" ON facturas;
CREATE POLICY "Medico actualiza sus facturas" ON facturas
  FOR UPDATE USING (medico_id = auth.uid());

DROP POLICY IF EXISTS "Admin ve facturas de su pais" ON facturas;
CREATE POLICY "Admin ve facturas de su pais" ON facturas
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = facturas.pais_id)
    )
  );

-- ============================================
-- 2. MEDICOS — Habilitar RLS + Políticas
-- ============================================
ALTER TABLE medicos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Medico ve su perfil" ON medicos;
CREATE POLICY "Medico ve su perfil" ON medicos
  FOR SELECT USING (id = auth.uid());

DROP POLICY IF EXISTS "Admin ve medicos de su pais" ON medicos;
CREATE POLICY "Admin ve medicos de su pais" ON medicos
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = medicos.pais_id)
    )
  );

-- ============================================
-- 3. CLINICAS — Reforzar con país
-- ============================================
DROP POLICY IF EXISTS "Admin ve clinicas de su pais" ON clinicas;
CREATE POLICY "Admin ve clinicas de su pais" ON clinicas
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = clinicas.pais_id)
    )
  );

-- ============================================
-- 4. PACIENTES — Reforzar SELECT con país del médico
-- ============================================
-- La política original (medico_id = auth.uid()) ya aísla por médico.
-- Agregamos una capa extra para admins por país.
DROP POLICY IF EXISTS "Admin ve pacientes de su pais" ON pacientes;
CREATE POLICY "Admin ve pacientes de su pais" ON pacientes
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = pacientes.pais_id)
    )
  );

-- ============================================
-- 5. CITAS — Reforzar con país
-- ============================================
DROP POLICY IF EXISTS "Admin ve citas de su pais" ON citas;
CREATE POLICY "Admin ve citas de su pais" ON citas
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = citas.pais_id)
    )
  );

-- ============================================
-- 6. RECETAS — Reforzar con país
-- ============================================
DROP POLICY IF EXISTS "Admin ve recetas de su pais" ON recetas;
CREATE POLICY "Admin ve recetas de su pais" ON recetas
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = recetas.pais_id)
    )
  );

-- ============================================
-- 7. CAMPANAS PUBLICITARIAS — Paciente solo ve campañas de su país
-- ============================================
-- Actualizar política existente para incluir filtro por país del paciente
DROP POLICY IF EXISTS "Paciente ve campanas activas" ON campanas_publicitarias;
CREATE POLICY "Paciente ve campanas activas" ON campanas_publicitarias
  FOR SELECT USING (
    activa = true 
    AND fecha_fin >= CURRENT_DATE
    AND pais_id IN (
      SELECT pais_id FROM pacientes WHERE auth_user_id = auth.uid() LIMIT 1
    )
  );

-- Admin por país
DROP POLICY IF EXISTS "Admin ve campanas de su pais" ON campanas_publicitarias;
CREATE POLICY "Admin ve campanas de su pais" ON campanas_publicitarias
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = campanas_publicitarias.pais_id)
    )
  );

-- ============================================
-- 8. NOTIFICACIONES — Reforzar con país
-- ============================================
DROP POLICY IF EXISTS "Admin ve notificaciones de su pais" ON notificaciones;
CREATE POLICY "Admin ve notificaciones de su pais" ON notificaciones
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = notificaciones.pais_id)
    )
  );

-- ============================================
-- 9. VISITAS AGENDADAS — Reforzar con país
-- ============================================
DROP POLICY IF EXISTS "Admin ve visitas de su pais" ON visitas_agendadas;
CREATE POLICY "Admin ve visitas de su pais" ON visitas_agendadas
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = visitas_agendadas.pais_id)
    )
  );

-- ============================================
-- 10. SOLICITUDES CAMPANA — Reforzar con país
-- ============================================
DROP POLICY IF EXISTS "Admin ve solicitudes de su pais" ON solicitudes_campana;
CREATE POLICY "Admin ve solicitudes de su pais" ON solicitudes_campana
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = solicitudes_campana.pais_id)
    )
  );

-- ============================================
-- 11. PERFILES — Reforzar con país
-- ============================================
-- El super_admin ya puede ver todo. Agregamos admin_pais.
DROP POLICY IF EXISTS "Admin ve perfiles de su pais" ON perfiles;
CREATE POLICY "Admin ve perfiles de su pais" ON perfiles
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles p 
      WHERE p.id = auth.uid() 
      AND p.rol IN ('super_admin', 'admin', 'admin_pais')
      AND (p.rol = 'super_admin' OR p.pais_id = perfiles.pais_id)
    )
  );
