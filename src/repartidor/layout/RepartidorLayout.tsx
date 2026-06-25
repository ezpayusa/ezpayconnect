import { Outlet, useNavigate, useLocation } from 'react-router-dom'
import { Truck, WifiOff, ListChecks, User } from 'lucide-react'
import { useEffect, useState } from 'react'

// Shell móvil del repartidor: header compacto + outlet + nav inferior (Cola / Perfil).
export default function RepartidorLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const [online, setOnline] = useState(typeof navigator !== 'undefined' ? navigator.onLine : true)

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

  const enPerfil = location.pathname.startsWith('/repartidor/perfil')
  const enCola = !enPerfil

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
          <Truck className="h-5 w-5" />
          <span className="font-semibold">Repartidor</span>
          {!online && (
            <span className="ml-auto flex items-center gap-1 text-xs text-amber-200" title="Sin conexión">
              <WifiOff className="h-4 w-4" /> Offline
            </span>
          )}
        </div>
      </header>

      <main className="mx-auto w-full max-w-md flex-1 p-4 pb-24">
        <Outlet />
      </main>

      {/* Nav inferior fija */}
      <nav className="fixed bottom-0 inset-x-0 bg-white border-t border-gray-200">
        <div className="mx-auto w-full max-w-md flex">
          {navBtn(enCola, () => navigate('/repartidor'), ListChecks, 'Cola')}
          {navBtn(enPerfil, () => navigate('/repartidor/perfil'), User, 'Perfil')}
        </div>
      </nav>
    </div>
  )
}
