-- ============================================================
-- FASE 0 · Fundación de seguridad — Catálogo de roles
-- ------------------------------------------------------------
-- (Se aplica DESPUÉS de 067_fase0_helpers_autorizacion.sql: la política
--  roles_catalogo_admin usa private.tiene_rol().)
--
-- Fuente ÚNICA de verdad para perfiles.rol (roles de sistema/clínica).
-- NO se aplica todavía ningún FK ni CHECK sobre perfiles.rol: eso es
-- FASE 6 (cierre del riesgo fail-open). Aquí solo se establece el catálogo
-- (TABLA, no enum) y las políticas posteriores lo usarán como referencia.
--
-- NOTA: los roles de proveedor/laboratorio (cuentas_proveedor.rol_en_empresa:
-- admin, supervisor, visitador_medico, …) son una DIMENSIÓN SEPARADA y NO se
-- modelan aquí. Este catálogo cubre exclusivamente perfiles.rol.
-- ============================================================

CREATE TABLE IF NOT EXISTS roles_catalogo (
  codigo       TEXT PRIMARY KEY,           -- valor exacto que vive en perfiles.rol
  descripcion  TEXT NOT NULL,
  ambito       TEXT NOT NULL,              -- 'sistema' | 'clinica' | 'paciente'
  es_super     BOOLEAN NOT NULL DEFAULT false,  -- acceso global sin filtro
  es_staff_clinica BOOLEAN NOT NULL DEFAULT false, -- opera dentro de una clínica
  activo       BOOLEAN NOT NULL DEFAULT true,
  orden        INTEGER NOT NULL DEFAULT 100
);

COMMENT ON TABLE roles_catalogo IS 'Catálogo canónico de roles de perfiles.rol (fuente única de verdad). Los roles de proveedor (cuentas_proveedor.rol_en_empresa) son una dimensión aparte.';

-- Los 7 roles reales que existen hoy en perfiles.rol
INSERT INTO roles_catalogo (codigo, descripcion, ambito, es_super, es_staff_clinica, orden) VALUES
  ('super_admin',  'Administrador global de EzPay (acceso total)', 'sistema', true,  false, 10),
  ('admin_clinica','Administrador de una clínica',                 'clinica', false, true,  20),
  ('gerente',      'Gerente de clínica (staff administrativo)',    'clinica', false, true,  30),
  ('medico',       'Médico tratante',                              'clinica', false, true,  40),
  ('soporte',      'Soporte interno EzPay',                        'sistema', false, false, 50),
  ('vendedor',     'Vendedor / comercial EzPay',                   'sistema', false, false, 60),
  ('cliente',      'Cuenta de cliente/paciente genérica',          'paciente',false, false, 70)
ON CONFLICT (codigo) DO UPDATE
  SET descripcion = EXCLUDED.descripcion,
      ambito = EXCLUDED.ambito,
      es_super = EXCLUDED.es_super,
      es_staff_clinica = EXCLUDED.es_staff_clinica,
      orden = EXCLUDED.orden;

-- RLS: lectura para autenticados (es dato de referencia); escritura solo super_admin.
ALTER TABLE roles_catalogo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS roles_catalogo_read ON roles_catalogo;
CREATE POLICY roles_catalogo_read ON roles_catalogo
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS roles_catalogo_admin ON roles_catalogo;
CREATE POLICY roles_catalogo_admin ON roles_catalogo
  FOR ALL TO authenticated
  USING (private.tiene_rol(ARRAY['super_admin']))
  WITH CHECK (private.tiene_rol(ARRAY['super_admin']));

-- (FASE 6) Aquí irá, cuando se confirme:
--   ALTER TABLE perfiles ADD CONSTRAINT perfiles_rol_fk
--     FOREIGN KEY (rol) REFERENCES roles_catalogo(codigo);
-- o un CHECK equivalente. NO se aplica en Fase 0.
