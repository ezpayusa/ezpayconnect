-- ============================================================================
-- Migración 223: registra 'admin_pais' en la tabla `roles` (sistema legacy id-based)
-- ============================================================================
-- CONTEXTO: existen dos sistemas de roles desconectados. (A) perfiles.rol + roles_catalogo
-- = la autoridad REAL (RLS/RPCs, get_auth_user_rol); admin_pais ya vive ahí desde la mig 216.
-- (B) roles + usuario_roles = RBAC legacy que usan crear-empleado / AsignacionRolesPage para
-- el ALTA de staff. admin_pais NO existía en (B), así que el flujo "Nuevo Empleado" no podía
-- producirlo. Esta migración solo conecta (B): agrega la fila para que el alta lo ofrezca.
--
-- permisos: NO se lee en ningún gate real (solo se muestra como badges en RolesPage). Valor
-- simbólico '["*_pais"]'.
-- nivel=1 (deliberado, NO igual que 'admin'): notificar-admin usa roles.nivel para la escalada
-- jerárquica de notificaciones (roles con nivel > configRol.nivel reciben copia "[Seguimiento]",
-- SIN filtro de país). Con nivel=1 admin_pais NUNCA entra en esa escalada global → no recibe
-- notificaciones cross-país, consistente con que está acotado a SU país en todo lo demás.
-- (La autoridad real de admin_pais vive en roles_catalogo/perfiles.rol, no en este nivel.)
--
-- Idempotente: solo inserta si no existe (verificado: 0 filas admin_pais en `roles` al aplicar).
-- ============================================================================

INSERT INTO roles (nombre, descripcion, nivel, permisos)
SELECT 'admin_pais', 'Administrador de un país (EzPay)', 1, '["*_pais"]'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM roles WHERE nombre = 'admin_pais');
