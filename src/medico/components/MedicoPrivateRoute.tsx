import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { Loader2 } from 'lucide-react'

export default function MedicoPrivateRoute({ children }: { children: React.ReactNode }) {
  const { user, perfil, loading } = useAuth()
  const location = useLocation()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace state={{ from: location }} />
  }

  // Permitir también admin y super_admin para testing
  const rol = perfil?.rol || ''
  const permitidos = ['medico', 'admin', 'super_admin']
  if (!permitidos.includes(rol)) {
    return <Navigate to="/dashboard" replace />
  }

  return <>{children}</>
}
