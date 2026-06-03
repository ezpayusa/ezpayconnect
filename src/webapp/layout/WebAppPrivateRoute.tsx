import { Navigate } from 'react-router-dom'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'

export default function WebAppPrivateRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useWebAppAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-sky-500" />
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/paciente/login" replace />
  }

  return <>{children}</>
}
