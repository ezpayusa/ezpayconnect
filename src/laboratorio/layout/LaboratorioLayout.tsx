import { Link, useLocation, useNavigate, Outlet } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { ProveedorNotificacionesProvider, useProveedorNotificaciones } from '@/proveedor/context/ProveedorNotificacionesContext'
import { Button } from '@/components/ui/button'
import { LayoutDashboard, FlaskConical, ClipboardList, UserPlus, Building2, Bell, LogOut, Menu, X, ListChecks } from 'lucide-react'
import { useState } from 'react'

interface NavItem { label: string; path: string; icon: React.ElementType; badge?: boolean }

const NAV_ITEMS: NavItem[] = [
  { label: 'Dashboard', path: '/laboratorio/dashboard', icon: LayoutDashboard },
  { label: 'Órdenes de examen', path: '/laboratorio/ordenes', icon: ClipboardList },
  { label: 'Catálogo de exámenes', path: '/laboratorio/catalogo', icon: ListChecks },
  { label: 'Paciente walk-in', path: '/laboratorio/walk-in', icon: UserPlus },
  { label: 'Afiliaciones', path: '/laboratorio/afiliaciones', icon: Building2 },
  { label: 'Perfil', path: '/laboratorio/perfil', icon: FlaskConical },
  { label: 'Notificaciones', path: '/laboratorio/notificaciones', icon: Bell, badge: true },
]

// Monta UNA instancia de notificaciones (badge del layout + página compartida vía Outlet) → mismo
// estado y un solo polling (el provider hace init + polling de 60s). La página compartida
// ProveedorNotificacionesPage hace throw si falta este provider.
export default function LaboratorioLayout() {
  return (
    <ProveedorNotificacionesProvider>
      <LaboratorioLayoutContent />
    </ProveedorNotificacionesProvider>
  )
}

function LaboratorioLayoutContent() {
  const { empresa, logout, loading } = useProveedorAuth()
  const { noLeidas } = useProveedorNotificaciones()
  const location = useLocation()
  const navigate = useNavigate()
  const [mobileOpen, setMobileOpen] = useState(false)

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  const handleLogout = async () => {
    await logout()
    navigate('/laboratorio/login')
  }

  const renderNav = (onClick?: () => void) =>
    NAV_ITEMS.map((item) => {
      const active = location.pathname === item.path || location.pathname.startsWith(item.path + '/')
      return (
        <Link
          key={item.path}
          to={item.path}
          onClick={onClick}
          className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors ${
            active ? 'bg-[#0E7C6B] text-white' : 'text-white/70 hover:bg-white/5 hover:text-white'
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
      {/* Sidebar Desktop */}
      <aside className="hidden md:flex w-64 flex-col bg-[#0c2a26] text-white fixed h-full z-20">
        <div className="p-6 border-b border-white/10">
          <Link to="/laboratorio/dashboard" className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-[#0E7C6B] flex items-center justify-center">
              <FlaskConical className="h-5 w-5 text-white" />
            </div>
            <div className="min-w-0">
              <h1 className="font-bold text-sm truncate">EzPayConnect</h1>
              <p className="text-[10px] text-white/60 truncate">Laboratorio Clínico</p>
            </div>
          </Link>
        </div>

        <nav className="flex-1 overflow-y-auto py-4 px-3 space-y-1">{renderNav()}</nav>

        <div className="p-4 border-t border-white/10">
          <div className="mb-3 px-3">
            <p className="text-xs text-white/50">Laboratorio</p>
            <p className="text-sm font-medium truncate">{empresa?.nombre_empresa || 'Sin laboratorio'}</p>
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
      <div className="md:hidden fixed top-0 left-0 right-0 bg-[#0c2a26] text-white z-30 flex items-center justify-between px-4 h-14">
        <div className="flex items-center gap-2">
          <FlaskConical className="h-5 w-5" />
          <span className="font-bold text-sm">Laboratorio</span>
        </div>
        <button onClick={() => setMobileOpen(!mobileOpen)}>
          {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {/* Mobile Menu */}
      {mobileOpen && (
        <div className="md:hidden fixed inset-0 bg-black/50 z-20" onClick={() => setMobileOpen(false)}>
          <div className="absolute right-0 top-14 bottom-0 w-64 bg-[#0c2a26] text-white p-4 space-y-1" onClick={(e) => e.stopPropagation()}>
            {renderNav(() => setMobileOpen(false))}
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
