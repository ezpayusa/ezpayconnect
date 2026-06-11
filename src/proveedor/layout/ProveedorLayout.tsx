import { Link, useLocation, useNavigate, Outlet } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useNotificaciones } from '@/hooks/useNotificaciones'
import { Button } from '@/components/ui/button'
import { LayoutDashboard, Package, CalendarCheck, Megaphone, MapPin, CreditCard, LogOut, Menu, X, CheckCircle, Users, BarChart3, Bell, ShieldCheck } from 'lucide-react'
import { useState, useEffect } from 'react'
import { etiquetaRol, type PermisoProveedor } from '@/proveedor/lib/permisos'

interface NavItem {
  label: string
  path: string
  icon: React.ElementType
  badge?: boolean
  permiso?: PermisoProveedor // sin permiso => siempre visible
}

// Menú único dirigido por permisos. Cada usuario ve solo lo que su rol permite.
const NAV_ITEMS: NavItem[] = [
  { label: 'Dashboard', path: '/proveedor/dashboard', icon: LayoutDashboard },
  // Trabajo del visitador (su propia agenda)
  { label: 'Mis Visitas', path: '/proveedor/visitador/mis-visitas', icon: CalendarCheck, permiso: 'visitas.propias' },
  { label: 'Agendar Visita', path: '/proveedor/visitador/agendar', icon: CalendarCheck, permiso: 'visitas.propias' },
  { label: 'Mi Ruta', path: '/proveedor/visitador/ruta', icon: MapPin, permiso: 'visitas.propias' },
  { label: 'Mi Reporte', path: '/proveedor/visitador/reporte', icon: BarChart3, permiso: 'visitas.propias' },
  // Gestión (según rol)
  { label: 'Productos', path: '/proveedor/productos', icon: Package, permiso: 'productos.ver' },
  { label: 'Planes Visitador', path: '/proveedor/visitador/planes', icon: CalendarCheck, permiso: 'planes.contratar' },
  { label: 'Aprobar Visitas', path: '/proveedor/visitador/aprobar', icon: CheckCircle, permiso: 'visitas.aprobar' },
  { label: 'Visitadores', path: '/proveedor/visitadores', icon: Users, permiso: 'visitadores.gestionar' },
  { label: 'Ubicaciones Médicos', path: '/proveedor/visitador/ubicaciones-medicos', icon: MapPin, permiso: 'ubicaciones.gestionar' },
  { label: 'Publicidad', path: '/proveedor/publicidad/planes', icon: Megaphone, permiso: 'publicidad.ver' },
  { label: 'Equipo y Roles', path: '/proveedor/equipo', icon: ShieldCheck, permiso: 'usuarios.gestionar' },
  { label: 'Pagos', path: '/proveedor/pagos', icon: CreditCard, permiso: 'pagos.ver' },
  // Siempre visibles
  { label: 'Perfil', path: '/proveedor/perfil', icon: MapPin },
  { label: 'Notificaciones', path: '/proveedor/notificaciones', icon: Bell, badge: true },
]

export default function ProveedorLayout() {
  const { empresa, logout, loading, cuenta, puede } = useProveedorAuth()
  const { noLeidas, listarNotificaciones } = useNotificaciones()
  const location = useLocation()
  const navigate = useNavigate()
  const [mobileOpen, setMobileOpen] = useState(false)

  const rol = cuenta?.rol_en_empresa || 'visitador_medico'
  const navItems = NAV_ITEMS.filter((item) => !item.permiso || puede(item.permiso))

  useEffect(() => {
    listarNotificaciones()
    const interval = setInterval(listarNotificaciones, 60000)
    return () => clearInterval(interval)
  }, [listarNotificaciones])

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  const handleLogout = async () => {
    await logout()
    navigate('/proveedor/login')
  }

  return (
    <div className="min-h-screen bg-gray-50 flex">
      {/* Sidebar Desktop */}
      <aside className="hidden md:flex w-64 flex-col bg-[#1a2a3a] text-white fixed h-full z-20">
        <div className="p-6 border-b border-white/10">
          <Link to="/proveedor/dashboard" className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-[#1E5C8E] flex items-center justify-center">
              <MapPin className="h-5 w-5 text-white" />
            </div>
            <div className="min-w-0">
              <h1 className="font-bold text-sm truncate">EzPayConnect</h1>
              <p className="text-[10px] text-white/60 truncate">Portal Proveedores</p>
            </div>
          </Link>
        </div>

        <nav className="flex-1 overflow-y-auto py-4 px-3 space-y-1">
          {navItems.map((item) => {
            const active = location.pathname === item.path || location.pathname.startsWith(item.path + '/')
            return (
              <Link
                key={item.path}
                to={item.path}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors ${
                  active
                    ? 'bg-[#1E5C8E] text-white'
                    : 'text-white/70 hover:bg-white/5 hover:text-white'
                }`}
              >
                <item.icon className="h-4 w-4 shrink-0" />
                <span className="truncate flex-1">{item.label}</span>
                {item.badge && noLeidas > 0 && (
                  <span className="bg-red-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full min-w-[18px] text-center">
                    {noLeidas > 99 ? '99+' : noLeidas}
                  </span>
                )}
              </Link>
            )
          })}
        </nav>
        
        <div className="px-4 pb-2">
          <div className="px-3 py-2 rounded-lg bg-white/5">
            <p className="text-[10px] text-white/40 uppercase tracking-wider">Rol</p>
            <p className="text-xs text-white/80">{etiquetaRol(rol)}</p>
          </div>
        </div>

        <div className="p-4 border-t border-white/10">
          <div className="mb-3 px-3">
            <p className="text-xs text-white/50">Empresa</p>
            <p className="text-sm font-medium truncate">{empresa?.nombre_empresa || 'Sin empresa'}</p>
          </div>
          <Button
            variant="ghost"
            className="w-full justify-start text-white/70 hover:text-white hover:bg-white/5"
            onClick={handleLogout}
          >
            <LogOut className="h-4 w-4 mr-2" />
            Cerrar sesión
          </Button>
        </div>
      </aside>

      {/* Mobile Header */}
      <div className="md:hidden fixed top-0 left-0 right-0 bg-[#1a2a3a] text-white z-30 flex items-center justify-between px-4 h-14">
        <div className="flex items-center gap-2">
          <MapPin className="h-5 w-5" />
          <span className="font-bold text-sm">Proveedores</span>
        </div>
        <button onClick={() => setMobileOpen(!mobileOpen)}>
          {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {/* Mobile Menu */}
      {mobileOpen && (
        <div className="md:hidden fixed inset-0 bg-black/50 z-20" onClick={() => setMobileOpen(false)}>
          <div className="absolute right-0 top-14 bottom-0 w-64 bg-[#1a2a3a] text-white p-4 space-y-1" onClick={(e) => e.stopPropagation()}>
            {navItems.map((item) => {
              const active = location.pathname.startsWith(item.path)
              return (
                <Link
                  key={item.path}
                  to={item.path}
                  onClick={() => setMobileOpen(false)}
                  className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors ${
                    active
                      ? 'bg-[#1E5C8E] text-white'
                      : 'text-white/70 hover:bg-white/5 hover:text-white'
                  }`}
                >
                  <item.icon className="h-4 w-4 shrink-0" />
                  <span className="flex-1">{item.label}</span>
                  {item.badge && noLeidas > 0 && (
                    <span className="bg-red-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full min-w-[18px] text-center">
                      {noLeidas > 99 ? '99+' : noLeidas}
                    </span>
                  )}
                </Link>
              )
            })}
            <div className="pt-4 border-t border-white/10 mt-4">
              <Button
                variant="ghost"
                className="w-full justify-start text-white/70 hover:text-white hover:bg-white/5"
                onClick={handleLogout}
              >
                <LogOut className="h-4 w-4 mr-2" />
                Cerrar sesión
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Main Content */}
      <main className="flex-1 md:ml-64 min-h-screen pt-14 md:pt-0">
        <div className="p-4 md:p-8 max-w-7xl mx-auto">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
