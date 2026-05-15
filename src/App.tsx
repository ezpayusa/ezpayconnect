import PaisesPage from '@/pages/admin-ezpay/PaisesPage';
import NotificacionesPage from '@/pages/NotificacionesPage'
import { BrowserRouter, Routes, Route, Navigate, useNavigate } from 'react-router-dom'
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

// === IMPORTS ADMIN EZPAY ===
import { useEffect } from 'react'
import { AdminLayout } from '@/components/admin-ezpay/layout/AdminLayout'
import AdminEzPayPage from '@/pages/admin-ezpay/AdminEzPayPage'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'

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

// === COMPONENTE PROTECCIÓN RUTAS ADMIN ===
function AdminRoute({ children }: { children: React.ReactNode }) {
  const { isAdmin, loading } = useAdminAuth()
  const navigate = useNavigate()

  useEffect(() => {
    if (!loading && !isAdmin) {
      navigate('/dashboard')
    }
  }, [loading, isAdmin, navigate])

  if (loading) {
    return <div className="flex items-center justify-center h-screen">Cargando...</div>
  }

  return isAdmin ? <>{children}</> : null
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/notificaciones" element={<PrivateLayout><NotificacionesPage /></PrivateLayout>} />
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

        {/* === RUTAS ADMIN EZPAY === */}
        <Route
          path="/admin-ezpay"
          element={
            <AdminRoute>
              <AdminLayout />
            </AdminRoute>
          }
        >
          <Route index element={<AdminEzPayPage />} />
          <Route path="paises" element={<PaisesPage />} />
          <Route path="planes-medico" element={<div className="p-8 text-center text-gray-500">Planes Médico - Próximo Día 4</div>} />
          <Route path="planes-clinica" element={<div className="p-8 text-center text-gray-500">Planes Clínica - Próximo Día 5</div>} />
          <Route path="planes-lab" element={<div className="p-8 text-center text-gray-500">Planes Lab - Próximo Día 6</div>} />
          <Route path="planes-visitador" element={<div className="p-8 text-center text-gray-500">Planes Visitador - Próximo Día 7</div>} />
          <Route path="excepciones" element={<div className="p-8 text-center text-gray-500">Excepciones - Próximo Día 8</div>} />
          <Route path="finanzas" element={<div className="p-8 text-center text-gray-500">Finanzas - Próximo Día 9</div>} />
          <Route path="reportes" element={<div className="p-8 text-center text-gray-500">Reportes - Próximo Día 10</div>} />
          <Route path="roles" element={<div className="p-8 text-center text-gray-500">Roles - Próximo Día 11</div>} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}

export default App