import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { Stethoscope, WifiOff, CalendarPlus, ListChecks, Route as RouteIcon, Wallet, LogOut } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

// Shell móvil del visitador (PWA de campo): header compacto + outlet + nav inferior de 4 tabs
// (Agendar / Visitas / Ruta / Planes). Molde: RepartidorLayout.
export default function VisitadorLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const { logout } = useProveedorAuth()
  const [online, setOnline] = useState(typeof navigator !== 'undefined' ? navigator.onLine : true)

  const handleLogout = async () => {
    await logout()
    navigate('/proveedor/login', { replace: true })
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

  const enAgendar = location.pathname.startsWith('/visitador/agendar')
  const enVisitas = location.pathname.startsWith('/visitador/mis-visitas')
  const enRuta = location.pathname.startsWith('/visitador/ruta')
  const enPlanes = location.pathname.startsWith('/visitador/planes')

  const navBtn = (activo: boolean, onClick: () => void, Icon: typeof ListChecks, label: string) => (
    <button
      type="button"
      onClick={onClick}
      className={`flex-1 flex flex-col items-center gap-0.5 py-2 text-xs ${activo ? 'text-[#1E5C8E]' : 'text-gray-400'}`}
    >
      <Icon className="h-5 w-5" />
      {label}
    </button>
  )

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      <header className="sticky top-0 z-10 bg-[#1E5C8E] text-white shadow">
        <div className="mx-auto w-full max-w-md px-4 py-3 flex items-center gap-2">
          <Stethoscope className="h-5 w-5" />
          <span className="font-semibold">Visitador</span>
          <div className="ml-auto flex items-center gap-3">
            {!online && (
              <span className="flex items-center gap-1 text-xs text-amber-200" title="Sin conexión">
                <WifiOff className="h-4 w-4" /> Offline
              </span>
            )}
            <button
              type="button"
              onClick={handleLogout}
              className="flex items-center gap-1 text-xs text-white/80 hover:text-white"
              title="Cerrar sesión"
            >
              <LogOut className="h-4 w-4" /> Salir
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-md flex-1 p-4 pb-24">
        <Outlet />
      </main>

      {/* Nav inferior fija (4 tabs) */}
      <nav className="fixed bottom-0 inset-x-0 bg-white border-t border-gray-200">
        <div className="mx-auto w-full max-w-md flex">
          {navBtn(enAgendar, () => navigate('/visitador/agendar'), CalendarPlus, 'Agendar')}
          {navBtn(enVisitas, () => navigate('/visitador/mis-visitas'), ListChecks, 'Visitas')}
          {navBtn(enRuta, () => navigate('/visitador/ruta'), RouteIcon, 'Ruta')}
          {navBtn(enPlanes, () => navigate('/visitador/planes'), Wallet, 'Planes')}
        </div>
      </nav>
    </div>
  )
}
