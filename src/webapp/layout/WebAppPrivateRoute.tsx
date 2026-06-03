import { Navigate } from 'react-router-dom'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'

export default function WebAppPrivateRoute({ children }: { children: React.ReactNode }) {
  const { user, perfil, loading } = useWebAppAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-sky-500" />
      </div>
    )
  }

  // No hay sesión → login
  if (!user) {
    return <Navigate to="/paciente/login" replace />
  }

  // Hay sesión pero NO es un paciente registrado (es médico, admin, etc.)
  // Esto evita que doctores entren al portal del paciente
  if (!perfil) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50 p-4">
        <div className="bg-white rounded-2xl shadow-xl p-8 max-w-md text-center space-y-4">
          <div className="w-16 h-16 mx-auto rounded-full bg-red-50 flex items-center justify-center">
            <span className="text-red-500 text-2xl font-bold">!</span>
          </div>
          <h2 className="text-xl font-bold text-slate-800">Acceso restringido</h2>
          <p className="text-slate-500">
            Esta cuenta no está registrada como paciente. Si eres médico, usa el{' '}
            <a href="/dashboard" className="text-sky-600 font-medium hover:underline">panel médico</a>.
          </p>
          <p className="text-sm text-slate-400">
            Si crees que esto es un error, contacta a tu clínica.
          </p>
        </div>
      </div>
    )
  }

  return <>{children}</>
}
