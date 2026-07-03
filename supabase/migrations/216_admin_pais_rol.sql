-- ============================================================================
-- Migración 216: rol admin_pais — base de la pieza "administrador de país"
-- ============================================================================
-- CONTEXTO: el rol admin_pais existió en versiones tempranas y fue REMOVIDO en la mig 076
-- (el back-office EzPay quedó reducido a super_admin). Se REINTRODUCE acá con un diseño nuevo:
-- entra al catálogo de roles como rol de ámbito 'sistema' (no super), y perfiles gana un CHECK
-- que garantiza que un admin_pais siempre tenga país asignado. Esta migración es solo la BASE
-- (catálogo + integridad de datos); el reconocimiento en el front (useAdminAuth) y el enforcement
-- real de "modo país" son piezas posteriores.
--
-- Nota: esta migración corre como owner/postgres → NO está sujeta a la RLS de roles_catalogo
-- (verificado: hay RLS con policies para authenticated, pero el INSERT del owner la bypassa).
-- Verificado antes de aplicar: 0 filas en roles_catalogo con codigo='admin_pais' y 0 filas en
-- perfiles con rol='admin_pais' → ni el INSERT ni el CHECK rompen datos existentes.
-- ============================================================================

-- 1a) Alta en el catálogo de roles. Ámbito 'sistema' (como super_admin/soporte), no super.
--     orden=15: entre super_admin (10) y admin_clinica (20), refleja la jerarquía y NO comparte
--     orden con ningún rol existente (admin_clinica ya usa 20, aunque sea de otro ámbito).
INSERT INTO public.roles_catalogo (codigo, descripcion, ambito, es_super, es_staff_clinica, activo, orden)
VALUES ('admin_pais', 'Administrador de un país (EzPay)', 'sistema', false, false, true, 15);

-- 1b) Integridad: un admin_pais SIN país asignado no tiene sentido (sería un bug de datos).
ALTER TABLE public.perfiles
  ADD CONSTRAINT admin_pais_requiere_pais
  CHECK (rol <> 'admin_pais' OR pais_id IS NOT NULL);
