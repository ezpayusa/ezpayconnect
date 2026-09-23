import { Navigate } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import GateEstadoEmpresa from '@/proveedor/components/GateEstadoEmpresa'

export default function ProveedorPrivateRoute({ children }: { children: React.ReactNode }) {
  const { user, cuenta, empresa, loading } = useProveedorAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!user || !cuenta) {
    return <Navigate to="/proveedor/login" replace />
  }

  // Empresa no activa → pantalla de estado / onboarding (CORTESÍA; la barrera real es la mig 322).
  return <GateEstadoEmpresa estado={empresa?.estado}>{children}</GateEstadoEmpresa>
}
