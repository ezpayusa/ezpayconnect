import { Navigate, Outlet } from 'react-router-dom'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { ClinicaSidebar } from './ClinicaSidebar'

export function ClinicaLayout({ children }: { children: React.ReactNode }) {
  const { isAdminClinica, loading } = useClinicaAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  // Permitir cualquier usuario logueado para testing
  // TODO: Restaurar guard cuando se terminen las pruebas
  // if (!isAdminClinica) {
  //   return <Navigate to="/dashboard" replace />
  // }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <ClinicaSidebar />
      <main className="flex-1 overflow-auto p-6"><Outlet /></main>
    </div>
  )
}
