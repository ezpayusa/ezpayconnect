import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import {
  LayoutDashboard,
  Users,
  Stethoscope,
  UserPlus,
  Settings,
  LogOut,
  ChevronLeft,
  CalendarDays,
  Clock,
  FlaskConical,
  ClipboardList,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import ClinicaNotificacionesDropdown from '@/clinica/layout/ClinicaNotificacionesDropdown'
import { useTema } from '@/components/theme/TenantThemeContext'

export function ClinicaSidebar() {
  const navigate = useNavigate()
  const location = useLocation()
  const { logout, perfil } = useAuth()
  const { clinica } = useClinicaAuth()
  const { logoUrl } = useTema()  // logo del tenant (o fallback oficial); item activo usa var(--tenant-primario)

  // Roles administrativos (ven todo el panel). Los de captura solo ven Admisión.
  const ROLES_ADMIN = ['admin_clinica', 'admin', 'super_admin', 'gerente']

  // `roles` declara quién ve cada item. Item sin `roles` = visible a todos (compat hacia atrás).
  const navItems = [
    { label: 'Dashboard', icon: LayoutDashboard, path: '/clinica', roles: ROLES_ADMIN },
    { label: 'Admisión', icon: ClipboardList, path: '/clinica/admision', roles: [...ROLES_ADMIN, 'asistente_medico', 'enfermeria'] },
    { label: 'Citas', icon: CalendarDays, path: '/clinica/citas', roles: ROLES_ADMIN },
    { label: 'Personal', icon: Users, path: '/clinica/personal', roles: ROLES_ADMIN },
    { label: 'Horarios Médicos', icon: Clock, path: '/clinica/horarios-medicos', roles: ROLES_ADMIN },
    { label: 'Invitar Médico', icon: Stethoscope, path: '/clinica/invitar-medico', roles: ROLES_ADMIN },
    { label: 'Invitar Laboratorio', icon: FlaskConical, path: '/clinica/invitar-laboratorio', roles: ROLES_ADMIN },
    { label: 'Invitar Staff', icon: UserPlus, path: '/clinica/invitar-staff', roles: ROLES_ADMIN },
    { label: 'Configuración', icon: Settings, path: '/clinica/configuracion', roles: ROLES_ADMIN },
  ]

  const visibleItems = navItems.filter((item) => !item.roles || item.roles.includes(perfil?.rol || ''))

  const isActive = (path: string) => location.pathname === path

  return (
    <aside className="w-64 bg-[#1a2a3a] text-white flex flex-col h-screen sticky top-0">
      <div className="p-6 border-b border-white/10">
        <div className="flex items-center gap-3">
          <img src={logoUrl} alt="" className="h-8 w-8 rounded object-contain shrink-0" />
          <div className="flex-1 min-w-0">
            <h1 className="text-lg font-bold tracking-wide truncate">{clinica?.nombre || 'Clínica'}</h1>
            <p className="text-xs text-[#8a9aaa]">Panel Administrativo</p>
          </div>
          <ClinicaNotificacionesDropdown />
        </div>
      </div>

      <div className="px-4 pt-4">
        <div className="flex items-center gap-2 px-4 py-2 rounded-lg bg-white/5">
          <span className="text-xs font-medium text-[#B8D0E0] uppercase">
            Admin de Clínica
          </span>
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto py-4 px-3 space-y-1">
        {visibleItems.map((item) => {
          const Icon = item.icon
          const active = isActive(item.path)
          return (
            <button
              key={item.path}
              onClick={() => navigate(item.path)}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all ${
                active
                  ? 'bg-[var(--tenant-primario)] text-white shadow-sm'
                  : 'text-white/80 hover:bg-white/10 hover:text-white'
              }`}
            >
              <Icon className="w-5 h-5" />
              <span>{item.label}</span>
            </button>
          )
        })}
      </nav>

      <div className="p-4 border-t border-white/10 space-y-3">
        {perfil && (
          <div className="px-3 py-2 bg-white/10 rounded-lg">
            <p className="text-sm font-medium">{perfil.nombre_completo}</p>
            <p className="text-xs text-white/60">{perfil.email}</p>
          </div>
        )}
        <Button
          variant="ghost"
          className="w-full justify-start text-white/80 hover:text-white hover:bg-white/10"
          onClick={() => navigate('/dashboard')}
        >
          <ChevronLeft className="w-4 h-4 mr-2" />
          Volver al Sistema
        </Button>
        <Button
          variant="ghost"
          className="w-full justify-start text-white/80 hover:text-white hover:bg-white/10"
          onClick={async () => {
            await logout()
            navigate('/login')
          }}
        >
          <LogOut className="w-4 h-4 mr-2" />
          Cerrar Sesión
        </Button>
      </div>
    </aside>
  )
}
