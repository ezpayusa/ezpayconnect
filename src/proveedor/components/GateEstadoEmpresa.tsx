import { Navigate, useLocation } from 'react-router-dom'
import OnboardingShell from '@/proveedor/components/OnboardingShell'
import {
  accesoEmpresa,
  rutaEstado,
  rutaPermitidaEnOnboarding,
} from '@/proveedor/lib/estadoEmpresa'

// Gate de estado de empresa, COMPARTIDO por los 3 portales de proveedor (proveedor/farmacia/lab).
// Va DESPUÉS de los chequeos de sesión/tipo de cada guard. CORTESÍA: la barrera real es la mig 322.
//
//  - operativa  → renderiza el portal operativo normal (children = su Layout).
//  - onboarding → solo las rutas de onboarding, dentro del shell mínimo (sin montar el Layout
//                 operativo → sin queries a tablas operativas). El resto redirige a la pantalla de estado.
//  - bloqueada  → solo la propia pantalla de estado; cualquier otra ruta redirige a ella.
export default function GateEstadoEmpresa({
  estado,
  children,
}: {
  estado: string | null | undefined
  children: React.ReactNode
}) {
  const { pathname } = useLocation()
  const acceso = accesoEmpresa(estado)

  if (acceso === 'operativa') return <>{children}</>

  if (acceso === 'onboarding' && rutaPermitidaEnOnboarding(pathname)) {
    return <OnboardingShell />
  }

  if (acceso === 'bloqueada' && pathname === rutaEstado(pathname)) {
    return <OnboardingShell />
  }

  return <Navigate to={rutaEstado(pathname)} replace />
}
