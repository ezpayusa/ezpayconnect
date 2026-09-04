// Helper puro: destino "home" según el rol/país del perfil. Sin efectos secundarios, sin imports
// de react/router. Fuente única de los destinos acordados (consumido por el botón "Volver al
// Dashboard" de SidebarAdmin y por el ruteo post-login).
//
// POR QUE ESTO ES UNA TABLA EXPLICITA Y YA NO UN `return '/dashboard'` AL FINAL
// -----------------------------------------------------------------------------
// El default anterior mandaba CUALQUIER rol no contemplado a /dashboard, que es el panel médico:
// PrivateLayout no chequea rol (sólo `user`), el Sidebar filtra por rol y no encuentra ningún item,
// y DashboardPage lee expediente_notas. O sea que el rol desconocido no quedaba "sin ruta": quedaba
// en una pantalla ajena, vacía y sin salida. Eso no es un vacío, es un callejón — y se lee como app
// rota. Ahora /dashboard es un destino que hay que MERECER estando en la lista.
// `asistente_medico` está acá por MEDICIÓN, no por diseño: es el único de los seis roles que el
// default mandaba a /dashboard y que tiene una cuenta real y activa (login 2026-07-21). Mandarla
// a /sin-panel le cambiaba el aterrizaje a una persona de verdad, y eso es decisión de producto.
// Los otros cinco (cliente, enfermeria, gerente, soporte, vendedor) sólo tienen cuentas de prueba
// y quedan en /sin-panel; su destino real es un frente abierto.
export const ROLES_DASHBOARD_CLINICO = ['admin_clinica', 'asistente_medico'] as const

// Destinos:
//   medico                       -> /medico
//   admin_pais CON pais_id       -> /admin-ezpay/pais/{pais_id}
//   admin_pais SIN pais_id       -> /sin-panel   (cuenta rota: el CHECK de la mig 216 lo impide)
//   super_admin                  -> /admin-ezpay
//   secretaria                   -> /clinica/calendario   (su única superficie operativa)
//   asesor_comercial             -> /comercial
//   supervisor_comercial         -> /comercial   (misma superficie: la cartera la ensancha la RLS)
//   admin_clinica                -> /dashboard   (el único rol del catálogo con menú propio ahí)
//   cualquier otro / sin rol     -> /sin-panel
export function rutaHomePorRol(
  perfil: { rol?: string | null; pais_id?: string | null } | null | undefined
): string {
  const rol = perfil?.rol
  if (rol === 'medico') return '/medico'
  if (rol === 'admin_pais') return perfil?.pais_id ? `/admin-ezpay/pais/${perfil.pais_id}` : '/sin-panel'
  if (rol === 'super_admin') return '/admin-ezpay'
  if (rol === 'secretaria') return '/clinica/calendario'
  if (rol === 'asesor_comercial' || rol === 'supervisor_comercial') return '/comercial'
  if (rol && (ROLES_DASHBOARD_CLINICO as readonly string[]).includes(rol)) return '/dashboard'
  // Sin rama clínica de consuelo. /sin-panel no lee nada, no muestra datos de nadie y ofrece
  // cerrar sesión: es correcto para un rol que no conocemos, que es justo cuando menos sabemos
  // qué tiene derecho a ver.
  return '/sin-panel'
}
