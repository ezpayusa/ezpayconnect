import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { useNotificaciones } from '@/hooks/useNotificaciones'
import {
  LayoutDashboard,
  Users,
  CalendarDays,
  FileText,
  Pill,
  Settings,
  LogOut,
  Stethoscope,
  DollarSign,
  Bell,
  Shield,
  BarChart3,
} from 'lucide-react'
import { Button } from '@/components/ui/button'

export function Sidebar() {
  const navigate = useNavigate()
  const location = useLocation()
  const { logout, perfil, isAdmin, isMedico, isAsistente } = useAuth()
  const { noLeidas } = useNotificaciones()

  // Normalizar rol para comparación
  const userRol = (perfil?.rol || '').toLowerCase().trim()

  // Definir items de navegación según rol
  const getNavItems = () => {
    const baseItems = [
      { label: 'Dashboard', icon: LayoutDashboard, path: '/dashboard', roles: ['admin', 'medico', 'asistente', 'super_admin'] },
      { label: 'Pacientes', icon: Users, path: '/pacientes', roles: ['admin', 'medico', 'asistente', 'super_admin'] },
      { label: 'Citas', icon: CalendarDays, path: '/citas', roles: ['admin', 'medico', 'asistente', 'super_admin'] },
    ]

    const medicoItems = [
      { label: 'Recetas', icon: FileText, path: '/recetas', roles: ['admin', 'medico', 'super_admin'] },
      { label: 'Buscar Medicamentos', icon: Pill, path: '/buscar-medicamentos', roles: ['admin', 'medico', 'super_admin'] },
      { label: 'Facturas', icon: DollarSign, path: '/facturas', roles: ['admin', 'medico', 'super_admin'] },
    ]

    const adminItems = [
      { label: 'Farmacias', icon: Pill, path: '/farmacias', roles: ['admin', 'medico', 'super_admin'] },
      { label: 'Reportes', icon: BarChart3, path: '/reportes', roles: ['admin', 'medico', 'super_admin'] },
      { label: 'Configuracion', icon: Settings, path: '/configuracion', roles: ['admin', 'super_admin'] },
    ]

    const allItems = [...baseItems, ...medicoItems, ...adminItems]

    return allItems.filter(item => item.roles.includes(userRol))
  }

  const navItems = getNavItems()

  return (
    <aside className="w-64 bg-[#1a2a3a] text-white flex flex-col h-screen sticky top-0">
      <div className="p-6 border-b border-white/10">
        <div className="flex items-center gap-3">
          <Stethoscope className="h-8 w-8 text-[#5BA8D1]" />
          <div>
            <h1 className="text-lg font-bold tracking-wide">EzPayConnect</h1>
            <p className="text-xs text-[#8a9aaa]">Software Medico</p>
          </div>
        </div>
      </div>

      {/* Badge de rol */}
      <div className="px-4 pt-4">
        <div className="flex items-center gap-2 px-4 py-2 rounded-lg bg-white/5">
          <Shield className="h-4 w-4 text-[#5BA8D1]" />
          <span className="text-xs font-medium text-[#B8D0E0] uppercase">
            {perfil?.rol || 'Usuario'}
          </span>
        </div>
      </div>

      {/* Campanita de notificaciones */}
      <div className="px-4 pt-2">
        <button
          onClick={() => navigate('/notificaciones')}
          className="w-full flex items-center justify-between px-4 py-3 rounded-lg text-sm transition-all text-[#8a9aaa] hover:bg-white/5 hover:text-white"
        >
          <div className="flex items-center gap-3">
            <Bell className="h-5 w-5" />
            Notificaciones
          </div>
          {noLeidas > 0 && (
            <span className="bg-red-500 text-white text-xs font-bold px-2 py-0.5 rounded-full">
              {noLeidas > 9 ? '9+' : noLeidas}
            </span>
          )}
        </button>
      </div>

      <nav className="flex-1 p-4 space-y-1">
        {navItems.map((item) => {
          const active = location.pathname === item.path
          return (
            <button
              key={item.path}
              onClick={() => navigate(item.path)}
              className={`w-full flex items-center gap-3 px-4 py-3 rounded-lg text-sm transition-all ${
                active
                  ? 'bg-[#1E5C8E] text-white'
                  : 'text-[#8a9aaa] hover:bg-white/5 hover:text-white'
              }`}
            >
              <item.icon className="h-5 w-5" />
              {item.label}
            </button>
          )
        })}
      </nav>

      <div className="p-4 border-t border-white/10">
        <div className="px-4 py-2 mb-3">
          <p className="text-sm font-medium">{perfil?.nombre_completo || 'Medico'}</p>
          <p className="text-xs text-[#8a9aaa]">{perfil?.email}</p>
        </div>
        <Button
          variant="ghost"
          className="w-full flex items-center gap-3 text-[#8a9aaa] hover:text-white hover:bg-white/5"
          onClick={logout}
        >
          <LogOut className="h-4 w-4" />
          Cerrar Sesion
        </Button>
      </div>
    </aside>
  )
}