// Fuente ÚNICA de la regla de acceso por estado de empresa (front, CORTESÍA).
//
// La barrera real vive en el servidor (mig 322, verificada en prod): los helpers de identidad
// (mi_empresa_proveedor / mi_rol_proveedor / mi_equipo_proveedor / pais_de_proveedor) devuelven NULL
// si la empresa no está 'activa' → las superficies operativas quedan fail-closed; y los helpers de
// onboarding (mi_empresa_onboarding / mi_rol_onboarding) habilitan pagos+comprobante en
// activa|pendiente|suspendida. Este módulo NO decide seguridad: sólo evita pantallas rotas y calca
// la MISMA regla del servidor. Nada de comparar 'pendiente' suelto en los componentes.
//
//   activa                        → 'operativa'  (todo el portal)
//   pendiente, suspendida         → 'onboarding' (ver cuenta/empresa, editar perfil, pagar+comprobante)
//   rechazada                     → 'bloqueada'  (solo ver su estado y cerrar sesión)
//   cualquier otro valor / null   → 'bloqueada'  (fail-closed)

export type AccesoEmpresa = 'operativa' | 'onboarding' | 'bloqueada'

export function accesoEmpresa(estado: string | null | undefined): AccesoEmpresa {
  switch (estado) {
    case 'activa':
      return 'operativa'
    case 'pendiente':
    case 'suspendida':
      return 'onboarding'
    case 'rechazada':
      return 'bloqueada'
    default:
      // null / undefined / valor desconocido → fail-closed, igual que el servidor.
      return 'bloqueada'
  }
}

export type PortalBase = '/proveedor' | '/farmacia' | '/laboratorio'

// Sufijos de ruta permitidos durante onboarding, POR portal. Cada portal monta su propio
// subconjunto (lab no tiene pagos/checkout; farmacia no tiene checkout). 'estado' es la pantalla de
// destino y siempre está permitida. Si una de estas rutas se renombra en el router, el test
// estructural (estadoEmpresa.test.ts) falla — para que un pendiente nunca quede sin salida.
export const RUTAS_ONBOARDING_POR_PORTAL: Record<PortalBase, string[]> = {
  '/proveedor': ['estado', 'perfil', 'pagos', 'checkout'],
  '/farmacia': ['estado', 'perfil', 'pagos'],
  '/laboratorio': ['estado', 'perfil'],
}

// Lista plana de rutas COMPLETAS permitidas en onboarding (para el guard y el test estructural).
export const RUTAS_ONBOARDING: string[] = (
  Object.entries(RUTAS_ONBOARDING_POR_PORTAL) as [PortalBase, string[]][]
).flatMap(([base, sufijos]) => sufijos.map((s) => `${base}/${s}`))

export function portalBase(pathname: string): PortalBase {
  if (pathname.startsWith('/farmacia')) return '/farmacia'
  if (pathname.startsWith('/laboratorio')) return '/laboratorio'
  return '/proveedor'
}

// Ruta de la pantalla de estado del portal al que pertenece pathname.
export function rutaEstado(pathname: string): string {
  return `${portalBase(pathname)}/estado`
}

// ¿La ruta pedida está permitida durante onboarding? (match exacto o sub-ruta).
export function rutaPermitidaEnOnboarding(pathname: string): boolean {
  return RUTAS_ONBOARDING.some((r) => pathname === r || pathname.startsWith(`${r}/`))
}
