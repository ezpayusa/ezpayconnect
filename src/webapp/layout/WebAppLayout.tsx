import { Outlet } from 'react-router-dom'
import WebAppSidebar from './WebAppSidebar'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { Bell, Menu } from 'lucide-react'
import { useState } from 'react'

export default function WebAppLayout() {
  const { perfil, notificacionesNoLeidas } = useWebAppAuth()
  const [menuOpen, setMenuOpen] = useState(false)

  return (
    <div className="min-h-screen bg-slate-50">
      <WebAppSidebar />

      {/* Header mobile */}
      <header className="md:hidden fixed top-0 left-0 right-0 bg-white border-b border-slate-200 z-40 px-4 h-14 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-sky-500 to-indigo-500 flex items-center justify-center">
            <span className="text-white font-bold text-sm">E</span>
          </div>
          <span className="font-semibold text-slate-800 text-sm">EzPayConnect</span>
        </div>
        <div className="flex items-center gap-3">
          <button className="relative p-2 text-slate-500">
            <Bell className="h-5 w-5" />
            {notificacionesNoLeidas > 0 && (
              <span className="absolute top-1 right-1 h-4 w-4 bg-red-500 rounded-full text-white text-[10px] flex items-center justify-center">
                {notificacionesNoLeidas}
              </span>
            )}
          </button>
        </div>
      </header>

      {/* Header desktop */}
      <header className="hidden md:flex fixed top-0 left-64 right-0 bg-white border-b border-slate-200 z-30 px-8 h-16 items-center justify-between">
        <h2 className="text-lg font-semibold text-slate-800">
          {perfil ? `Hola, ${perfil.nombre}` : 'Portal del Paciente'}
        </h2>
        <div className="flex items-center gap-4">
          <button className="relative p-2 text-slate-500 hover:bg-slate-100 rounded-lg transition-colors">
            <Bell className="h-5 w-5" />
            {notificacionesNoLeidas > 0 && (
              <span className="absolute top-1 right-1 h-4 w-4 bg-red-500 rounded-full text-white text-[10px] flex items-center justify-center">
                {notificacionesNoLeidas}
              </span>
            )}
          </button>
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-gradient-to-br from-sky-500 to-indigo-500 flex items-center justify-center text-white font-semibold text-sm">
              {perfil ? `${perfil.nombre?.charAt(0)}${perfil.apellido?.charAt(0)}` : '?'}
            </div>
            <div className="hidden lg:block">
              <p className="text-sm font-medium text-slate-700">
                {perfil ? `${perfil.nombre} ${perfil.apellido}` : 'Paciente'}
              </p>
              <p className="text-xs text-slate-400">Paciente</p>
            </div>
          </div>
        </div>
      </header>

      {/* Main content */}
      <main className="md:ml-64 md:pt-16 pt-14 pb-20 md:pb-8 px-4 md:px-8 min-h-screen">
        <Outlet />
      </main>
    </div>
  )
}
