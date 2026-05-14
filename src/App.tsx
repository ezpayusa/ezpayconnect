import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { Sidebar } from '@/components/layout/Sidebar'
import LoginPage from '@/pages/LoginPage'
import DashboardPage from '@/pages/DashboardPage'
import PacientesPage from '@/pages/PacientesPage'
import PacienteDetallePage from '@/pages/PacienteDetallePage'
import CitasPage from '@/pages/CitasPage'
import RecetasPage from '@/pages/RecetasPage'
import FarmaciasPage from '@/pages/FarmaciasPage'
import ConfiguracionPage from '@/pages/ConfiguracionPage'
import FacturasPage from '@/pages/FacturasPage'
import ReportesPage from '@/pages/reportes/ReportesPage'

function PrivateLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <Sidebar />
      <main className="flex-1 ml-0 overflow-auto">
        {children}
      </main>
    </div>
  )
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<PrivateLayout><DashboardPage /></PrivateLayout>} />
        <Route path="/pacientes" element={<PrivateLayout><PacientesPage /></PrivateLayout>} />
        <Route path="/pacientes/:id/detalle" element={<PrivateLayout><PacienteDetallePage /></PrivateLayout>} />
        <Route path="/pacientes/:id" element={<PrivateLayout><PacientesPage /></PrivateLayout>} />
        <Route path="/citas" element={<PrivateLayout><CitasPage /></PrivateLayout>} />
        <Route path="/recetas" element={<PrivateLayout><RecetasPage /></PrivateLayout>} />
        <Route path="/facturas" element={<PrivateLayout><FacturasPage /></PrivateLayout>} />
        <Route path="/farmacias" element={<PrivateLayout><FarmaciasPage /></PrivateLayout>} />
        <Route path="/configuracion" element={<PrivateLayout><ConfiguracionPage /></PrivateLayout>} />
        <Route path="/reportes" element={<PrivateLayout><ReportesPage /></PrivateLayout>} />
      </Routes>
    </BrowserRouter>
  )
}

export default App