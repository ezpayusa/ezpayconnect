import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import {
  LayoutDashboard,
  Users,
  CalendarDays,
  FileText,
  Pill,
  Settings,
  LogOut,
  Stethoscope
} from 'lucide-react'
import { Button } from '@/components/ui/button'

const navItems = [
  { label: 'Dashboard', icon: LayoutDashboard, path: '/dashboard' },
  { label: 'Pacientes', icon: Users, path: '/pacientes' },
  { label: 'Citas', icon: CalendarDays, path: '/citas' },
  { label: 'Recetas', icon: FileText, path: '/recetas' },
  { label: 'Farmacias', icon: Pill, path: '/farmacias' },
  { label: 'Configuracion', icon: Settings, path: '/configuracion' },
]

export function Sidebar() {
  const navigate = useNavigate()
  const location = useLocation()
  const { logout, perfil } = useAuth()

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
