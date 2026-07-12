import { Link, useLocation, useNavigate, Outlet } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { useNotificaciones } from '@/hooks/useNotificaciones'
import { Button } from '@/components/ui/button'
import { LayoutDashboard, Pill, Package, Users, CreditCard, Bell, LogOut, Menu, X, Building2, ClipboardList, BarChart3, Truck, Receipt } from 'lucide-react'
import { useState, useEffect } from 'react'

interface NavItem { label: string; path: string; icon: React.ElementType; accion?: string; accionAny?: string[]; badge?: boolean }

// `accion` (si está) gatea el item por permiso data-driven — SOLO para mostrar/
// ocultar. `accionAny` muestra el item si tiene CUALQUIERA de los permisos.
// La barrera real es la RLS del Frente A.
const NAV_ITEMS: NavItem[] = [
  { label: 'Dashboard', path: '/farmacia/dashboard', icon: LayoutDashboard },
  { label: 'Inventario', path: '/farmacia/inventario', icon: Package },
  { label: 'Recetas entrantes', path: '/farmacia/recetas', icon: ClipboardList, accion: 'recetas_dispensar' },
  { label: 'Entregas', path: '/farmacia/entregas', icon: Truck, accion: 'entregas_ver' },
  { label: 'Reportes', path: '/farmacia/reportes', icon: BarChart3, accionAny: ['finanzas_reportes', 'recetas_reportes'] },
  { label: 'Personal y Roles', path: '/farmacia/personal', icon: Users, accion: 'usuarios_roles' },
  { label: 'Sucursales', path: '/farmacia/sucursales', icon: Building2, accion: 'sucursales_gestionar' },
  { label: 'Pagos', path: '/farmacia/pagos', icon: CreditCard, accion: 'finanzas_reportes' },
  { label: 'Comisiones', path: '/farmacia/comisiones', icon: Receipt, accion: 'finanzas_reportes' },
  { label: 'Perfil', path: '/farmacia/perfil', icon: Building2 },
  { label: 'Notificaciones', path: '/farmacia/notificaciones', icon: Bell, badge: true },
]

export default function FarmaciaLayout() {
  const { empresa, logout, loading } = useProveedorAuth()
  const { tienePermiso, loading: permLoading } = useFarmaciaPermisos()
  const { noLeidas, listarNotificaciones } = useNotificaciones()
  const location = useLocation()
  const navigate = useNavigate()
  const [mobileOpen, setMobileOpen] = useState(false)

  useEffect(() => {
    listarNotificaciones()
    const interval = setInterval(listarNotificaciones, 60000)
    return () => clearInterval(interval)
  }, [listarNotificaciones])

  if (loading || permLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#B45309]" />
      </div>
    )
  }

  const handleLogout = async () => {
    await logout()
    navigate('/farmacia/login')
  }

  const items = NAV_ITEMS.filter((i) =>
    i.accionAny ? i.accionAny.some((a) => tienePermiso(a)) : (!i.accion || tienePermiso(i.accion)),
  )

  const renderNav = (onClick?: () => void) =>
    items.map((item) => {
      const active = location.pathname === item.path || location.pathname.startsWith(item.path + '/')
      return (
        <Link
          key={item.path}
          to={item.path}
          onClick={onClick}
          className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors ${
            active ? 'bg-[#B45309] text-white' : 'text-white/70 hover:bg-white/5 hover:text-white'
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
    })

  return (
    <div className="min-h-screen bg-gray-50 flex">
      <aside className="hidden md:flex w-64 flex-col bg-[#3a2410] text-white fixed h-full z-20">
        <div className="p-6 border-b border-white/10">
          <Link to="/farmacia/dashboard" className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-[#B45309] flex items-center justify-center">
              <Pill className="h-5 w-5 text-white" />
            </div>
            <div className="min-w-0">
              <h1 className="font-bold text-sm truncate">EzPayConnect</h1>
              <p className="text-[10px] text-white/60 truncate">Farmacia</p>
            </div>
          </Link>
        </div>
        <nav className="flex-1 overflow-y-auto py-4 px-3 space-y-1">{renderNav()}</nav>
        <div className="p-4 border-t border-white/10">
          <div className="mb-3 px-3">
            <p className="text-xs text-white/50">Farmacia</p>
            <p className="text-sm font-medium truncate">{empresa?.nombre_empresa || 'Sin farmacia'}</p>
          </div>
          <Button variant="ghost" className="w-full justify-start text-white/70 hover:text-white hover:bg-white/5" onClick={handleLogout}>
            <LogOut className="h-4 w-4 mr-2" />
            Cerrar sesión
          </Button>
        </div>
      </aside>

      <div className="md:hidden fixed top-0 left-0 right-0 bg-[#3a2410] text-white z-30 flex items-center justify-between px-4 h-14">
        <div className="flex items-center gap-2">
          <Pill className="h-5 w-5" />
          <span className="font-bold text-sm">Farmacia</span>
        </div>
        <button onClick={() => setMobileOpen(!mobileOpen)}>
          {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {mobileOpen && (
        <div className="md:hidden fixed inset-0 bg-black/50 z-20" onClick={() => setMobileOpen(false)}>
          <div className="absolute right-0 top-14 bottom-0 w-64 bg-[#3a2410] text-white p-4 space-y-1" onClick={(e) => e.stopPropagation()}>
            {renderNav(() => setMobileOpen(false))}
            <div className="pt-4 border-t border-white/10 mt-4">
              <Button variant="ghost" className="w-full justify-start text-white/70 hover:text-white hover:bg-white/5" onClick={handleLogout}>
                <LogOut className="h-4 w-4 mr-2" />
                Cerrar sesión
              </Button>
            </div>
          </div>
        </div>
      )}

      <main className="flex-1 md:ml-64 min-h-screen pt-14 md:pt-0">
        <div className="p-4 md:p-8 max-w-7xl mx-auto">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
