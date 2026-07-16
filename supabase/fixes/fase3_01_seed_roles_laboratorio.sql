-- Seed de roles y permisos del laboratorio en el catálogo data-driven (mismo modelo que farmacia).
INSERT INTO public.roles_empresa_catalogo (tipo_empresa, rol, nivel, es_admin, label) VALUES
  ('laboratorio_clinico', 'admin',     100, true,  'Administrador'),
  ('laboratorio_clinico', 'tecnico',    40, false, 'Tecnico/Bioquimico'),
  ('laboratorio_clinico', 'recepcion',  40, false, 'Recepcion')
ON CONFLICT (tipo_empresa, rol) DO NOTHING;

INSERT INTO public.permisos_empresa_rol (tipo_empresa, rol, accion) VALUES
  ('laboratorio_clinico','admin','usuarios_roles'),
  ('laboratorio_clinico','admin','config_empresa'),
  ('laboratorio_clinico','admin','catalogo_examenes_editar'),
  ('laboratorio_clinico','admin','resultados_cargar'),
  ('laboratorio_clinico','admin','walkin_registrar'),
  ('laboratorio_clinico','admin','afiliaciones_gestionar'),
  ('laboratorio_clinico','tecnico','resultados_cargar'),
  ('laboratorio_clinico','recepcion','walkin_registrar'),
  ('laboratorio_clinico','recepcion','afiliaciones_gestionar')
ON CONFLICT (tipo_empresa, rol, accion) DO NOTHING;
