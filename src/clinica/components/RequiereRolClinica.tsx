import { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { Loader2 } from 'lucide-react'

/**
 * Gate por PÁGINA dentro de /clinica (defensa contra URL directa).
 * ClinicaLayout ya controla la ENTRADA al panel (incluye asistente_medico/enfermeria);
 * este componente confina cada superficie administrativa a los roles permitidos. Un rol de
 * captura que escribe /clinica/personal en la URL es redirigido a /clinica/admision.
 *
 * NOTA: esto es UX + defensa en profundidad. La autorización REAL está en el backend
 * (mig 163 cerró por rol las RPC/edge administrativas; las lecturas/escrituras igual fallan
 * server-side para un rol no autorizado aunque alguien fuerce el render).
 */
export function RequiereRolClinica({ roles, children }: { roles: string[]; children: ReactNode }) {
  const { perfil, loading } = useAuth()

  if (loading) {
    return (
      <div className="flex items-center justify-center p-12">
        <Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  if (!roles.includes(perfil?.rol || '')) {
    return <Navigate to="/clinica/admision" replace />
  }

  return <>{children}</>
}
