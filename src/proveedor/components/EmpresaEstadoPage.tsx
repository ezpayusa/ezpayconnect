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
// Rechazada: muestra el motivo y la fecha de revisión (migs 386/388). Vienen en el mismo empresa:empresa_id(*) de
// useProveedorAuth: la policy "Proveedor ve su propia empresa" deja leer la fila propia en cualquier estado.

// El tipo compartido no declara las columnas de revisión; el embed (*) sí las trae.
type EmpresaConRevision = { motivo_rechazo?: string | null; revisado_at?: string | null }

const fechaRevision = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' }) : null

export default function EmpresaEstadoPage() {
  const { empresa } = useProveedorAuth()
  const location = useLocation()
  const revision = (empresa ?? {}) as EmpresaConRevision
  const motivoRechazo = revision.motivo_rechazo?.trim() || null
  const revisadaEl = fechaRevision(revision.revisado_at)

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
            'Estamos revisando los datos de tu empresa. Mientras tanto puedes completar el perfil y registrar tu pago con el comprobante. Te avisaremos cuando se active.',
        }
      case 'suspendida':
        return {
          Icon: PauseCircle,
          color: 'text-orange-600',
          bg: 'bg-orange-100',
          titulo: 'Cuenta suspendida',
          detalle:
            'Tu empresa está suspendida. Puedes actualizar el perfil y regularizar tu pago. Si necesitas ayuda, contacta al administrador.',
        }
      case 'rechazada':
        return {
          Icon: XCircle,
          color: 'text-red-600',
          bg: 'bg-red-100',
          titulo: 'Solicitud rechazada',
          detalle:
            'Tu solicitud no fue aprobada, así que no tienes acceso al portal. Si crees que es un error, contacta al administrador.',
        }
      default:
        // null / undefined / valor desconocido → bloqueada (fail-closed).
        return {
          Icon: AlertCircle,
          color: 'text-slate-600',
          bg: 'bg-slate-100',
          titulo: 'Cuenta no disponible',
          detalle:
            'No pudimos verificar el estado de tu empresa. No tienes acceso al portal por ahora. Contacta al administrador.',
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

        {estado === 'rechazada' && (motivoRechazo || revisadaEl) && (
          <div className="text-left bg-red-50 border border-red-200 rounded-lg p-4 space-y-1">
            {motivoRechazo && (
              <>
                <p className="text-sm font-medium text-red-800">Motivo del rechazo</p>
                <p className="text-sm text-red-700 whitespace-pre-wrap break-words">{motivoRechazo}</p>
              </>
            )}
            {revisadaEl && <p className="text-xs text-red-600">Revisamos tu solicitud el {revisadaEl}.</p>}
          </div>
        )}

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
