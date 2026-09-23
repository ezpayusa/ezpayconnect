import { Link, useLocation } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Button } from '@/components/ui/button'
import { AlertCircle, Clock, PauseCircle, XCircle, Building2, CreditCard } from 'lucide-react'
import {
  accesoEmpresa,
  portalBase,
  RUTAS_ONBOARDING_POR_PORTAL,
} from '@/proveedor/lib/estadoEmpresa'

// Pantalla de estado para empresas NO activas. Es la salida cuando el guard corta el acceso al
// portal (onboarding o bloqueada). Se renderiza dentro de OnboardingShell (que aporta el logout).
// CORTESÍA: no consulta ninguna tabla operativa — lo que no puede leer, no lo pide. El mensaje se
// elige por el estado CRUDO; los botones de acción, por accesoEmpresa().
export default function EmpresaEstadoPage() {
  const { empresa } = useProveedorAuth()
  const location = useLocation()

  const base = portalBase(location.pathname)
  const estado = empresa?.estado
  const acceso = accesoEmpresa(estado)
  const sufijos = RUTAS_ONBOARDING_POR_PORTAL[base]

  const vista = (() => {
    switch (estado) {
      case 'pendiente':
        return {
          Icon: Clock,
          color: 'text-amber-600',
          bg: 'bg-amber-100',
          titulo: 'Cuenta en revisión',
          detalle:
            'Estamos revisando los datos de tu empresa. Mientras tanto podés completar el perfil y registrar tu pago con el comprobante. Te avisaremos cuando se active.',
        }
      case 'suspendida':
        return {
          Icon: PauseCircle,
          color: 'text-orange-600',
          bg: 'bg-orange-100',
          titulo: 'Cuenta suspendida',
          detalle:
            'Tu empresa está suspendida. Podés actualizar el perfil y regularizar tu pago. Si necesitás ayuda, contactá al administrador.',
        }
      case 'rechazada':
        return {
          Icon: XCircle,
          color: 'text-red-600',
          bg: 'bg-red-100',
          titulo: 'Solicitud rechazada',
          detalle:
            'Tu solicitud no fue aprobada, así que no tenés acceso al portal. Si creés que es un error, contactá al administrador.',
        }
      default:
        // null / undefined / valor desconocido → bloqueada (fail-closed).
        return {
          Icon: AlertCircle,
          color: 'text-slate-600',
          bg: 'bg-slate-100',
          titulo: 'Cuenta no disponible',
          detalle:
            'No pudimos verificar el estado de tu empresa. No tenés acceso al portal por ahora. Contactá al administrador.',
        }
    }
  })()

  const { Icon } = vista

  return (
    <div className="flex justify-center pt-6">
      <div className="max-w-md w-full bg-white rounded-xl border border-slate-200 p-8 text-center space-y-5">
        <div className={`w-14 h-14 rounded-full ${vista.bg} flex items-center justify-center mx-auto`}>
          <Icon className={`h-7 w-7 ${vista.color}`} />
        </div>

        <div className="space-y-2">
          <h1 className="text-xl font-bold text-slate-800">{vista.titulo}</h1>
          {empresa?.nombre_empresa && (
            <p className="text-sm font-medium text-slate-600">{empresa.nombre_empresa}</p>
          )}
          <p className="text-sm text-slate-500">{vista.detalle}</p>
        </div>

        {acceso === 'onboarding' && (
          <div className="flex flex-col gap-2 pt-2">
            <Link to={`${base}/perfil`}>
              <Button className="w-full bg-[#1E5C8E] hover:bg-[#17496f] text-white">
                <Building2 className="h-4 w-4 mr-2" /> Perfil de la empresa
              </Button>
            </Link>
            {sufijos.includes('pagos') && (
              <Link to={`${base}/pagos`}>
                <Button variant="outline" className="w-full">
                  <CreditCard className="h-4 w-4 mr-2" /> Pagar / Mis pagos
                </Button>
              </Link>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
