import { Outlet, useNavigate } from 'react-router-dom'
import { Truck, LogOut, WifiOff } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

// Shell móvil del repartidor: header compacto + outlet. Pensado para teléfono (max-w sm, full-height).
export default function RepartidorLayout() {
  const navigate = useNavigate()
  const { cuenta, logout } = useProveedorAuth()
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

  const handleLogout = async () => {
    await logout()
    navigate('/farmacia/login', { replace: true })
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      <header className="sticky top-0 z-10 bg-[#1E5C8E] text-white shadow">
        <div className="mx-auto w-full max-w-md px-4 py-3 flex items-center justify-between">
          <button
            type="button"
            onClick={() => navigate('/repartidor')}
            className="flex items-center gap-2 font-semibold"
          >
            <Truck className="h-5 w-5" />
            <span>Mis entregas</span>
          </button>
          <div className="flex items-center gap-3">
            {!online && (
              <span className="flex items-center gap-1 text-xs text-amber-200" title="Sin conexión">
                <WifiOff className="h-4 w-4" /> Offline
              </span>
            )}
            <span className="text-xs opacity-80 truncate max-w-[8rem]">{cuenta?.nombre_completo}</span>
            <button type="button" onClick={handleLogout} aria-label="Salir" className="opacity-90 hover:opacity-100">
              <LogOut className="h-5 w-5" />
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-md flex-1 p-4">
        <Outlet />
      </main>
    </div>
  )
}
