import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

// Gate del PWA del visitador: solo cuentas_proveedor con rol_en_empresa='visitador_medico'.
// A diferencia del repartidor, NO se restringe por empresa?.tipo — los visitadores existen en
// labs y farmacias. SOLO enruta/oculta — la autorización real la imponen la RLS y los RPC
// SECURITY DEFINER (el confinamiento cuenta_proveedor_id=auth.uid() vive en el backend, migs 209-214).
export default function VisitadorPrivateRoute({ children }: { children: ReactNode }) {
  const { user, cuenta, loading } = useProveedorAuth()

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

  if (cuenta.rol_en_empresa !== 'visitador_medico') {
    // No es visitador: al panel de proveedor (no hay un dashboard de tipo específico acá).
    return <Navigate to="/proveedor/dashboard" replace />
  }

  return <>{children}</>
}
