// Helper puro: destino "home" según el rol/país del perfil. Sin efectos secundarios, sin imports
// de react/router. Fuente única de los destinos acordados (consumido por el botón "Volver al
// Dashboard" de SidebarAdmin y, opcionalmente, por el ruteo post-login).
//
// Destinos:
//   medico                  -> /medico
//   admin_pais CON pais_id   -> /admin-ezpay/pais/{pais_id}
//   admin_pais SIN pais_id   -> /dashboard   (mismo fallback que AdminRoute cuando falta pais_id)
//   super_admin              -> /admin-ezpay
//   cualquier otro / sin rol -> /dashboard
export function rutaHomePorRol(
  perfil: { rol?: string | null; pais_id?: string | null } | null | undefined
): string {
  const rol = perfil?.rol
  if (rol === 'medico') return '/medico'
  if (rol === 'admin_pais') return perfil?.pais_id ? `/admin-ezpay/pais/${perfil.pais_id}` : '/dashboard'
  if (rol === 'super_admin') return '/admin-ezpay'
  return '/dashboard'
}
