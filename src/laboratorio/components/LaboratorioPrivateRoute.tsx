import { Navigate } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

// El laboratorio clínico reutiliza la cuenta de proveedor (cuentas_proveedor +
// empresas_proveedoras), pero solo accede a su portal si su empresa es de tipo
// 'laboratorio_clinico'. Cualquier otro proveedor se va a su portal normal.
export default function LaboratorioPrivateRoute({ children }: { children: React.ReactNode }) {
  const { user, cuenta, empresa, loading } = useProveedorAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!user || !cuenta) {
    return <Navigate to="/laboratorio/login" replace />
  }

  if (empresa?.tipo !== 'laboratorio_clinico') {
    return <Navigate to="/proveedor/dashboard" replace />
  }

  return <>{children}</>
}
