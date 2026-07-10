import { NavLink, useLocation } from 'react-router-dom'
import {
  LayoutDashboard,
  CalendarDays,
  FileText,
  FlaskConical,
  Clock,
  User,
  ShieldCheck,
  LogOut,
  Bell,
  Gift
} from 'lucide-react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'

const navItems = [
  { to: '/paciente/dashboard', icon: LayoutDashboard, label: 'Inicio' },
  { to: '/paciente/citas', icon: CalendarDays, label: 'Citas' },
  { to: '/paciente/recetas', icon: FileText, label: 'Recetas' },
  { to: '/paciente/examenes', icon: FlaskConical, label: 'Exámenes' },
  { to: '/paciente/historial', icon: Clock, label: 'Historial' },
  { to: '/paciente/premios', icon: Gift, label: 'Premios' },
  { to: '/paciente/perfil', icon: User, label: 'Perfil' },
  { to: '/paciente/autorizaciones', icon: ShieldCheck, label: 'Autorizaciones' },
]

export default function WebAppSidebar() {
  const { logout } = useWebAppAuth()
  const location = useLocation()

  return (
    <>
      {/* Sidebar desktop */}
      <aside className="hidden md:flex flex-col w-64 h-screen bg-white border-r border-slate-200 fixed left-0 top-0 z-40">
        <div className="p-6 flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-sky-500 to-indigo-500 flex items-center justify-center">
            <span className="text-white font-bold text-lg">E</span>
          </div>
          <div>
            <h1 className="font-bold text-slate-800 text-lg leading-tight">EzPayConnect</h1>
            <p className="text-xs text-slate-400">Portal del Paciente</p>
          </div>
        </div>

        <nav className="flex-1 px-4 space-y-1 overflow-y-auto">
          {navItems.map((item) => {
            const Icon = item.icon
            const isActive = location.pathname.startsWith(item.to)
            return (
              <NavLink
                key={item.to}
                to={item.to}
                className={`flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-sky-50 text-sky-600'
                    : 'text-slate-500 hover:bg-slate-50 hover:text-slate-700'
                }`}
              >
                <Icon className="h-5 w-5" />
                {item.label}
              </NavLink>
            )
          })}
        </nav>

        <div className="p-4 border-t border-slate-100">
          <button
            onClick={logout}
            className="flex items-center gap-3 px-4 py-3 w-full rounded-xl text-sm font-medium text-red-500 hover:bg-red-50 transition-colors"
          >
            <LogOut className="h-5 w-5" />
            Cerrar Sesión
          </button>
        </div>
      </aside>

      {/* Bottom nav mobile */}
      <nav className="md:hidden fixed bottom-0 left-0 right-0 bg-white border-t border-slate-200 z-50 px-2 pb-safe">
        <div className="flex justify-around items-center h-16">
          {navItems.slice(0, 5).map((item) => {
            const Icon = item.icon
            const isActive = location.pathname.startsWith(item.to)
            return (
              <NavLink
                key={item.to}
                to={item.to}
                className={`flex flex-col items-center gap-0.5 py-2 px-3 rounded-lg text-xs font-medium transition-colors ${
                  isActive ? 'text-sky-600' : 'text-slate-400'
                }`}
              >
                <Icon className="h-5 w-5" />
                <span className="text-[10px]">{item.label}</span>
              </NavLink>
            )
          })}
        </div>
      </nav>
    </>
  )
}
