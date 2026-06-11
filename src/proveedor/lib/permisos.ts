// ============================================================
// Catálogo de roles y matriz de permisos del panel de proveedores.
// Fuente única de verdad para: menú lateral, gating de páginas/acciones
// y (en la BD) las políticas RLS por rol dentro de la empresa.
// ============================================================

export type PermisoProveedor =
  | 'usuarios.gestionar' // ver equipo y asignar/cambiar roles
  | 'empresa.editar' // editar perfil/datos de la empresa
  | 'pagos.ver' // ver pagos/comprobantes de la empresa
  | 'productos.ver' // ver catálogo de productos
  | 'productos.editar' // crear/editar/importar/eliminar productos
  | 'publicidad.ver' // ver campañas publicitarias
  | 'publicidad.gestionar' // crear/pagar campañas
  | 'planes.contratar' // contratar planes de visitador
  | 'visitas.propias' // un visitador ve/propone SUS visitas (menú visitador)
  | 'visitas.aprobar' // aprobar/asignar visitas del equipo
  | 'visitadores.gestionar' // ver equipo de visitadores, stats, invitar
  | 'ubicaciones.gestionar' // gestionar ubicaciones de médicos
  | 'reportes.ver' // ver dashboards/reportes

export interface RolProveedor {
  value: string
  label: string
  descripcion: string
  permisos: PermisoProveedor[]
}

const TODOS: PermisoProveedor[] = [
  'usuarios.gestionar',
  'empresa.editar',
  'pagos.ver',
  'productos.ver',
  'productos.editar',
  'publicidad.ver',
  'publicidad.gestionar',
  'planes.contratar',
  'visitas.propias',
  'visitas.aprobar',
  'visitadores.gestionar',
  'ubicaciones.gestionar',
  'reportes.ver',
]

// Catálogo PREDEFINIDO (el admin asigna estos roles; no se crean a medida).
export const ROLES_PROVEEDOR: RolProveedor[] = [
  {
    value: 'admin',
    label: 'Administrador',
    descripcion: 'Control total: empresa, pagos, usuarios y roles, y todo el panel.',
    permisos: TODOS,
  },
  {
    value: 'supervisor',
    label: 'Supervisor de visitadores',
    descripcion: 'Aprueba visitas, gestiona el equipo de visitadores, rutas y ubicaciones. No ve pagos ni configura la empresa.',
    permisos: [
      'visitas.aprobar',
      'visitadores.gestionar',
      'ubicaciones.gestionar',
      'planes.contratar',
      'productos.ver',
      'publicidad.ver',
      'reportes.ver',
    ],
  },
  {
    value: 'visitador_medico',
    label: 'Visitador médico',
    descripcion: 'Solo su propio trabajo: su agenda, proponer visitas, su ruta y su reporte.',
    permisos: ['visitas.propias', 'reportes.ver'],
  },
  {
    value: 'catalogo',
    label: 'Gestor de catálogo',
    descripcion: 'Sube y edita productos (incluida la carga masiva). No toca visitadores ni publicidad ni pagos.',
    permisos: ['productos.ver', 'productos.editar', 'reportes.ver'],
  },
  {
    value: 'marketing',
    label: 'Marketing / Publicidad',
    descripcion: 'Gestiona campañas publicitarias y sus pagos. No toca visitadores ni catálogo.',
    permisos: ['publicidad.ver', 'publicidad.gestionar', 'reportes.ver'],
  },
  {
    value: 'finanzas',
    label: 'Finanzas',
    descripcion: 'Ve pagos, comprobantes y reportes. Lectura del catálogo.',
    permisos: ['pagos.ver', 'productos.ver', 'reportes.ver'],
  },
  {
    value: 'lectura',
    label: 'Solo lectura',
    descripcion: 'Ve dashboards, catálogo y publicidad sin poder editar nada.',
    permisos: ['productos.ver', 'publicidad.ver', 'reportes.ver'],
  },
]

// Roles legacy que pueden existir en datos viejos -> a qué permisos equivalen.
// 'editor' se trataba como admin-lite; 'viewer' como solo lectura.
const LEGACY: Record<string, PermisoProveedor[]> = {
  editor: TODOS,
  viewer: ROLES_PROVEEDOR.find((r) => r.value === 'lectura')!.permisos,
}

const MAPA: Record<string, PermisoProveedor[]> = {
  ...Object.fromEntries(ROLES_PROVEEDOR.map((r) => [r.value, r.permisos])),
  ...LEGACY,
}

export function permisosDeRol(rol: string | null | undefined): PermisoProveedor[] {
  if (!rol) return []
  return MAPA[rol] ?? []
}

export function puedeRol(rol: string | null | undefined, permiso: PermisoProveedor): boolean {
  return permisosDeRol(rol).includes(permiso)
}

export function etiquetaRol(rol: string | null | undefined): string {
  if (!rol) return '—'
  return ROLES_PROVEEDOR.find((r) => r.value === rol)?.label ?? rol
}
