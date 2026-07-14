import { useNavigate, useLocation } from 'react-router-dom'
import { useState } from 'react'
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
  Menu,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/sheet'

export function Sidebar() {
  const navigate = useNavigate()
  const location = useLocation()
  const { logout, perfil } = useAuth()
  const { noLeidas } = useNotificaciones({ realtime: true })
  const [open, setOpen] = useState(false) // drawer móvil

  // Normalizar rol para comparación
  const userRol = (perfil?.rol || '').toLowerCase().trim()

  // Definir items de navegación según rol
  const getNavItems = () => {
    // Si es admin_clinica, redirige a su panel
    if (userRol === 'admin_clinica') {
      return [
        { label: 'Mi Clínica', icon: LayoutDashboard, path: '/clinica', roles: ['admin_clinica'] },
        { label: 'Calendario', icon: CalendarDays, path: '/clinica/calendario', roles: ['admin_clinica'] },
        { label: 'Personal', icon: Users, path: '/clinica/personal', roles: ['admin_clinica'] },
      ]
    }

    // Si es medico, redirige a su portal dedicado
    if (userRol === 'medico') {
      return [
        { label: 'Portal Médico', icon: Stethoscope, path: '/medico', roles: ['medico'] },
        { label: 'Mis Citas', icon: CalendarDays, path: '/medico/citas', roles: ['medico'] },
        { label: 'Mis Pacientes', icon: Users, path: '/medico/pacientes', roles: ['medico'] },
        { label: 'Mis Recetas', icon: FileText, path: '/medico/recetas', roles: ['medico'] },
      ]
    }

    const baseItems = [
      { label: 'Dashboard', icon: LayoutDashboard, path: '/dashboard', roles: ['admin', 'medico', 'asistente', 'super_admin'] },
      { label: 'Pacientes', icon: Users, path: '/pacientes', roles: ['admin', 'medico', 'asistente', 'super_admin'] },
      { label: 'Citas', icon: CalendarDays, path: '/citas', roles: ['admin', 'medico', 'asistente', 'super_admin'] },
    ]

    const medicoItems = [
      { label: 'Recetas', icon: FileText, path: '/medico/recetas', roles: ['medico'] },
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

  // Navega y cierra el drawer móvil (inocuo en desktop).
  const go = (path: string) => { navigate(path); setOpen(false) }

  // Contenido compartido por el aside desktop y el drawer móvil.
  const body = (
    <>
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
          onClick={() => go('/notificaciones')}
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

      <nav className="flex-1 overflow-y-auto p-4 space-y-1">
        {navItems.map((item) => {
          const active = location.pathname === item.path
          return (
            <button
              key={item.path}
              onClick={() => go(item.path)}
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
          onClick={() => { setOpen(false); logout() }}
        >
          <LogOut className="h-4 w-4" />
          Cerrar Sesion
        </Button>
      </div>
    </>
  )

  return (
    <>
      {/* Desktop: aside fijo w-64 (sin cambios visuales) */}
      <aside className="hidden md:flex w-64 bg-[#1a2a3a] text-white flex-col h-screen sticky top-0">
        {body}
      </aside>

      {/* Móvil: topbar fijo con hamburguesa → drawer (Sheet). El aside no ocupa espacio en el flujo. */}
      <header className="md:hidden fixed top-0 inset-x-0 h-14 z-40 bg-[#1a2a3a] text-white flex items-center gap-3 px-4">
        <Sheet open={open} onOpenChange={setOpen}>
          <SheetTrigger asChild>
            <button aria-label="Abrir menú" className="p-1 -ml-1 text-white">
              <Menu className="h-6 w-6" />
            </button>
          </SheetTrigger>
          <SheetContent
            side="left"
            className="w-64 max-w-[80%] bg-[#1a2a3a] text-white border-0 p-0 gap-0 [&>button]:text-white"
          >
            <div className="flex flex-col h-full overflow-y-auto">{body}</div>
          </SheetContent>
        </Sheet>
        <div className="flex items-center gap-2">
          <Stethoscope className="h-6 w-6 text-[#5BA8D1]" />
          <span className="font-bold tracking-wide">EzPayConnect</span>
        </div>
      </header>
    </>
  )
}
