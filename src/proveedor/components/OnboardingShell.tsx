import { Link, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Button } from '@/components/ui/button'
import { ArrowLeft, LogOut } from 'lucide-react'
import { portalBase } from '@/proveedor/lib/estadoEmpresa'

// Chrome MÍNIMO para las páginas de onboarding (perfil / pagos / checkout) de una empresa NO activa.
// Reemplaza al layout operativo: sin sidebar operativo y —clave para (d)— sin montar sus hooks
// (notificaciones/capacidades/push), así una empresa no operativa NO dispara queries a tablas
// operativas. Solo ofrece volver a la pantalla de estado y cerrar sesión.
export default function OnboardingShell() {
  const { empresa, logout } = useProveedorAuth()
  const location = useLocation()
  const navigate = useNavigate()
  const base = portalBase(location.pathname)

  const enEstado = location.pathname === `${base}/estado`

  const handleLogout = async () => {
    await logout()
    navigate(`${base}/login`)
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      <header className="bg-white border-b border-slate-200">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            {!enEstado && (
              <Link
                to={`${base}/estado`}
                className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800 shrink-0"
              >
                <ArrowLeft className="h-4 w-4" /> Estado
              </Link>
            )}
            <span className="text-sm font-medium text-slate-700 truncate">
              {empresa?.nombre_empresa || 'Mi empresa'}
            </span>
          </div>
          <Button variant="ghost" size="sm" className="text-slate-500 shrink-0" onClick={handleLogout}>
            <LogOut className="h-4 w-4 mr-2" /> Cerrar sesión
          </Button>
        </div>
      </header>

      <main className="flex-1">
        <div className="max-w-3xl mx-auto p-4 md:p-8">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
