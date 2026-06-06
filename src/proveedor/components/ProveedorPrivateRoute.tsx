import { Navigate } from 'react-router-dom'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'

export default function ProveedorPrivateRoute({ children }: { children: React.ReactNode }) {
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

  return <>{children}</>
}
