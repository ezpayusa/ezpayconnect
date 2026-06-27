import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { ClinicaSidebar } from './ClinicaSidebar'
import { Loader2 } from 'lucide-react'

// Roles autorizados a ENTRAR al panel de clínica. Los de captura (asistente_medico/enfermeria)
// entran pero quedan confinados a Admisión por el sidebar (filtro por rol) y el gate por página
// <RequiereRolClinica> en App.tsx. El gate fino de cada superficie administrativa es defensa en
// profundidad: el backend ya está cerrado por rol (mig 163).
const ROLES_PERMITIDOS = ['admin_clinica', 'admin', 'super_admin', 'gerente', 'asistente_medico', 'enfermeria']

export function ClinicaLayout() {
  const { user, perfil, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  if (!ROLES_PERMITIDOS.includes(perfil?.rol || '')) {
    return <Navigate to="/dashboard" replace />
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <ClinicaSidebar />
      <main className="flex-1 overflow-auto p-6"><Outlet /></main>
    </div>
  )
}
