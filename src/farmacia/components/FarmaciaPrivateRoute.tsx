import { Navigate } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import GateEstadoEmpresa from '@/proveedor/components/GateEstadoEmpresa'

// La farmacia-tenant reutiliza la cuenta de proveedor (cuentas_proveedor +
// empresas_proveedoras) pero solo entra a su portal si su empresa es tipo
// 'farmacia'. Este guard SOLO enruta/oculta; la autorización real la impone la
// RLS del Frente A (no depender de este guard para seguridad).
export default function FarmaciaPrivateRoute({ children }: { children: React.ReactNode }) {
  const { user, cuenta, empresa, loading } = useProveedorAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!user || !cuenta) {
    return <Navigate to="/farmacia/login" replace />
  }

  if (empresa?.tipo !== 'farmacia') {
    return <Navigate to="/proveedor/dashboard" replace />
  }

  // Empresa no activa → pantalla de estado / onboarding (CORTESÍA; la barrera real es la mig 322).
  return <GateEstadoEmpresa estado={empresa?.estado}>{children}</GateEstadoEmpresa>
}
