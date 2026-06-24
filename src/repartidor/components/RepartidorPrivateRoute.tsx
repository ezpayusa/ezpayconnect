import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

// Gate del portal del repartidor: solo cuentas_proveedor con rol_en_empresa='delivery'
// (en una empresa tipo 'farmacia'). SOLO enruta/oculta — la autorización real la imponen
// la RLS y los RPC SECURITY DEFINER (el confinamiento delivery_id=auth.uid() es del backend).
export default function RepartidorPrivateRoute({ children }: { children: ReactNode }) {
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

  if (cuenta.rol_en_empresa !== 'delivery' || empresa?.tipo !== 'farmacia') {
    // No es repartidor: lo mandamos al portal que corresponde (la farmacia o el proveedor).
    return <Navigate to={empresa?.tipo === 'farmacia' ? '/farmacia/dashboard' : '/proveedor/dashboard'} replace />
  }

  return <>{children}</>
}
