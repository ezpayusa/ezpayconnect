import { useNavigate, useLocation } from 'react-router-dom'
import { useState, useEffect, useCallback } from 'react'
import { useAuth } from '@/hooks/useAuth'
import { useMedicoStats } from '@/medico/hooks/useMedicoStats'
import { supabase } from '@/lib/supabase'
import {
  LayoutDashboard,
  CalendarDays,
  Users,
  FileText,
  Clock,
  Stethoscope,
  Pill,
  MessageCircle,
  LogOut,
  ChevronLeft,
  Bell,
  Menu,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/sheet'

export function MedicoSidebar() {
  const navigate = useNavigate()
  const location = useLocation()
  const { logout, perfil } = useAuth()
  const { stats } = useMedicoStats()
  const [open, setOpen] = useState(false) // drawer móvil

  // Badge de mensajes sin leer: suma de no_leidos de todos los hilos (patrón liviano, como pendientesCount)
  const [mensajesNoLeidos, setMensajesNoLeidos] = useState(0)
  const recount = useCallback(async () => {
    const { data, error } = await supabase.rpc('listar_hilos_chat_medico')
    if (error || !data) return
    setMensajesNoLeidos((data as any[]).reduce((acc, h) => acc + Number(h.no_leidos ?? 0), 0))
  }, [])
  // Re-cuenta al cambiar de ruta Y al volver el foco a la ventana (cubre marcar-leído dentro de /medico/chat,
  // misma ruta → el pathname no cambia). focus listener es más barato que polling.
  useEffect(() => {
    recount()
    window.addEventListener('focus', recount)
    return () => window.removeEventListener('focus', recount)
  }, [recount, location.pathname])

  const navItems = [
    { label: 'Dashboard', icon: LayoutDashboard, path: '/medico' },
    {
      label: 'Mis Citas',
      icon: CalendarDays,
      path: '/medico/citas',
      badge: stats.pendientesCount > 0 ? stats.pendientesCount : undefined,
    },
    { label: 'Mis Pacientes', icon: Users, path: '/medico/pacientes' },
    {
      label: 'Mensajes',
      icon: MessageCircle,
      path: '/medico/chat',
      badge: mensajesNoLeidos > 0 ? mensajesNoLeidos : undefined,
    },
    { label: 'Mis Recetas', icon: FileText, path: '/medico/recetas' },
    { label: 'Buscar Medicamentos', icon: Pill, path: '/medico/buscar-medicamentos' },
    { label: 'Mi Disponibilidad', icon: Clock, path: '/medico/disponibilidad' },
  ]

  const isActive = (path: string) => {
    if (path === '/medico') return location.pathname === '/medico'
    return location.pathname.startsWith(path)
  }

  // Navega y cierra el drawer móvil (inocuo en desktop).
  const go = (path: string) => { navigate(path); setOpen(false) }

  // Contenido compartido por el aside desktop y el drawer móvil.
  const body = (
    <>
      {/* Header */}
      <div className="p-6 border-b border-white/10">
        <div className="flex items-center gap-3">
          <Stethoscope className="h-8 w-8 text-[#5BA8D1]" />
          <div>
            <h1 className="text-lg font-bold tracking-wide">EzPayConnect</h1>
            <p className="text-xs text-[#8a9aaa]">Portal del Médico</p>
          </div>
        </div>
      </div>

      {/* Rol badge */}
      <div className="px-4 pt-4">
        <div className="flex items-center gap-2 px-4 py-2 rounded-lg bg-white/5">
          <span className="text-xs font-medium text-[#B8D0E0] uppercase">
            {perfil?.rol === 'medico' ? 'Médico' : perfil?.rol}
          </span>
        </div>
      </div>

      {/* Notificaciones */}
      <div className="px-4 pt-2">
        <button
          onClick={() => go('/medico/notificaciones')}
          className="w-full flex items-center justify-between px-4 py-3 rounded-lg text-sm transition-all text-[#8a9aaa] hover:bg-white/5 hover:text-white"
        >
          <div className="flex items-center gap-3">
            <Bell className="h-5 w-5" />
            Notificaciones
          </div>
        </button>
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto py-4 px-3 space-y-1">
        {navItems.map((item) => {
          const Icon = item.icon
          const active = isActive(item.path)
          return (
            <button
              key={item.path}
              onClick={() => go(item.path)}
              className={`w-full flex items-center justify-between px-3 py-2.5 rounded-lg text-sm font-medium transition-all ${
                active
                  ? 'bg-[#5BA8D1] text-white shadow-sm'
                  : 'text-white/80 hover:bg-white/10 hover:text-white'
              }`}
            >
              <div className="flex items-center gap-3">
                <Icon className="w-5 h-5" />
                <span>{item.label}</span>
              </div>
              {item.badge !== undefined && (
                <span className="bg-red-500 text-white text-[10px] font-bold px-2 py-0.5 rounded-full min-w-[20px] text-center">
                  {item.badge}
                </span>
              )}
            </button>
          )
        })}
      </nav>

      {/* Footer */}
      <div className="p-4 border-t border-white/10 space-y-3">
        {perfil && (
          <div className="px-3 py-2 bg-white/10 rounded-lg">
            <p className="text-sm font-medium truncate">{perfil.nombre_completo}</p>
            <p className="text-xs text-white/60 truncate">{perfil.email}</p>
          </div>
        )}
        <Button
          variant="ghost"
          className="w-full justify-start text-white/80 hover:text-white hover:bg-white/10"
          onClick={() => go('/dashboard')}
        >
          <ChevronLeft className="w-4 h-4 mr-2" />
          Volver al Sistema
        </Button>
        <Button
          variant="ghost"
          className="w-full justify-start text-white/80 hover:text-white hover:bg-white/10"
          onClick={async () => {
            setOpen(false)
            await logout()
            navigate('/login')
          }}
        >
          <LogOut className="w-4 h-4 mr-2" />
          Cerrar Sesión
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
