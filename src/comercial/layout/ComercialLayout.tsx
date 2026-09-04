import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { Briefcase, WifiOff, Users, CalendarCheck, UsersRound, LogOut } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useAuth } from '@/hooks/useAuth'

// Shell del módulo comercial: header compacto + outlet + nav inferior.
// Molde: VisitadorLayout (que a su vez salió de RepartidorLayout) — misma forma, cableado a
// useAuth en vez de useProveedorAuth.
//
// Por ahora una sola tab (Prospectos). La nav inferior queda igual porque la tanda 2 agrega la
// ficha y, según cómo quede, alguna vista más; y porque un shell de una tab es trivial de ampliar
// mientras que uno sin shell obliga a reescribir cada pantalla.
export default function ComercialLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const { perfil, logout } = useAuth()
  const [online, setOnline] = useState(typeof navigator !== 'undefined' ? navigator.onLine : true)

  const handleLogout = async () => {
    await logout()
    navigate('/login', { replace: true })
  }

  useEffect(() => {
    const on = () => setOnline(true)
    const off = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => {
      window.removeEventListener('online', on)
      window.removeEventListener('offline', off)
    }
  }, [])

  const enProspectos = location.pathname.startsWith('/comercial/prospectos')
  const enHoy = location.pathname.startsWith('/comercial/hoy') || location.pathname.startsWith('/comercial/visitas')
  const enEquipo = location.pathname.startsWith('/comercial/equipo')
  const esSupervisor = perfil?.rol === 'supervisor_comercial'

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      <header className="sticky top-0 z-10 bg-[#1E5C8E] text-white shadow">
        <div className="mx-auto w-full max-w-3xl px-4 py-3 flex items-center gap-2">
          <Briefcase className="h-5 w-5" />
          <span className="font-semibold">{esSupervisor ? 'Comercial · Supervisión' : 'Comercial'}</span>
          <div className="ml-auto flex items-center gap-3">
            {!online && (
              <span className="flex items-center gap-1 text-xs text-amber-200" title="Sin conexión">
                <WifiOff className="h-4 w-4" /> Offline
              </span>
            )}
            <button
              type="button"
              onClick={handleLogout}
              className="flex items-center gap-1 text-sm text-white/90 hover:text-white"
              title="Cerrar sesión"
            >
              <LogOut className="h-4 w-4" />
            </button>
          </div>
        </div>
      </header>

      <main className="flex-1 mx-auto w-full max-w-3xl px-4 py-4 pb-20">
        <Outlet />
      </main>

      <nav className="fixed bottom-0 inset-x-0 bg-white border-t shadow-sm">
        <div className="mx-auto w-full max-w-3xl flex">
          <button
            type="button"
            onClick={() => navigate('/comercial/hoy')}
            className={`flex-1 flex flex-col items-center gap-0.5 py-2 text-xs ${
              enHoy ? 'text-[#1E5C8E]' : 'text-gray-400'
            }`}
          >
            <CalendarCheck className="h-5 w-5" />
            Hoy
          </button>
          <button
            type="button"
            onClick={() => navigate('/comercial/prospectos')}
            className={`flex-1 flex flex-col items-center gap-0.5 py-2 text-xs ${
              enProspectos ? 'text-[#1E5C8E]' : 'text-gray-400'
            }`}
          >
            <Users className="h-5 w-5" />
            Prospectos
          </button>
          {esSupervisor && (
            <button
              type="button"
              onClick={() => navigate('/comercial/equipo')}
              className={`flex-1 flex flex-col items-center gap-0.5 py-2 text-xs ${
                enEquipo ? 'text-[#1E5C8E]' : 'text-gray-400'
              }`}
            >
              <UsersRound className="h-5 w-5" />
              Equipo
            </button>
          )}
        </div>
      </nav>
    </div>
  )
}
