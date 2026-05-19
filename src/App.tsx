import AsignacionRolesPage from '@/pages/admin-ezpay/AsignacionRolesPage'
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

// === IMPORTS PLANES MÉDICO (DÍA 4) ===
import PlanesPage from '@/pages/planes/PlanesPage'
import PlanesConfigPage from '@/pages/planes/PlanesConfigPage'
import PlanesAsignacionesPage from '@/pages/planes/PlanesAsignacionesPage'
import PlanesExcepcionesPage from '@/pages/planes/PlanesExcepcionesPage'

// === IMPORTS PLANES CLÍNICA (DÍA 5) ===
import PlanesClinicaPage from '@/pages/planes/PlanesClinicaPage'
import PlanesClinicaConfigPage from '@/pages/planes/PlanesClinicaConfigPage'

// === IMPORTS PLANES LABORATORIO (DÍA 6) ===
import PlanesLabPage from '@/pages/planes/PlanesLabPage'
import PlanesLabConfigPage from '@/pages/planes/PlanesLabConfigPage'

// === IMPORTS PLANES VISITADOR (DÍA 7) ===
import PlanesVisitadorPage from '@/pages/planes/PlanesVisitadorPage'
import PlanesVisitadorConfigPage from '@/pages/planes/PlanesVisitadorConfigPage'

// === IMPORTS PLANES TODOS (DÍA 8) ===
import PlanesTodosPage from '@/pages/planes/PlanesTodosPage'

// === IMPORTS PLANES FALTANTES (DÍA 11.5) ===
import PlanesFarmaceuticoConfigPage from '@/pages/planes/PlanesFarmaceuticoConfigPage'
import PlanesFarmaciaConfigPage from '@/pages/planes/PlanesFarmaciaConfigPage'
import PlanesPublicidadConfigPage from '@/pages/planes/PlanesPublicidadConfigPage'
import PlanesEmpresasAfinesConfigPage from '@/pages/planes/PlanesEmpresasAfinesConfigPage'

// === IMPORTS FINANZAS (DÍA 9) ===
import FinanzasPage from '@/pages/admin-ezpay/FinanzasPage'

// === IMPORTS REPORTES EZPAY (DÍA 10) ===
import ReportesEzPayPageV2 from '@/pages/admin-ezpay/ReportesEzPayPageV2'

// === IMPORTS ROLES (DÍA 11) ===
import RolesPage from '@/pages/admin-ezpay/RolesPage'

// === IMPORTS USUARIOS (DÍA 12) ===
import UsuariosAdminPage from '@/pages/admin-ezpay/UsuariosAdminPage'

// === IMPORTS AUDITORÍA (DÍA 14) ===
import AuditoriaPage from '@/pages/admin-ezpay/AuditoriaPage'

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

        {/* === RUTAS PLANES MÉDICO (DÍA 4) === */}
        <Route path="/planes" element={<PlanesPage />} />
        <Route path="/admin/planes/configuracion" element={<AdminRoute><PlanesConfigPage /></AdminRoute>} />
        <Route path="/admin/planes/asignaciones" element={<AdminRoute><PlanesAsignacionesPage /></AdminRoute>} />
        <Route path="/admin/planes/excepciones" element={<AdminRoute><PlanesExcepcionesPage /></AdminRoute>} />

        {/* === RUTAS PLANES CLÍNICA (DÍA 5) === */}
        <Route path="/planes-clinica" element={<PlanesClinicaPage />} />
        <Route path="/admin/planes/clinica" element={<AdminRoute><PlanesClinicaConfigPage /></AdminRoute>} />

        {/* === RUTAS PLANES LABORATORIO (DÍA 6) === */}
        <Route path="/planes-lab" element={<PlanesLabPage />} />
        <Route path="/admin/planes/lab" element={<AdminRoute><PlanesLabConfigPage /></AdminRoute>} />

        {/* === RUTAS PLANES VISITADOR (DÍA 7) === */}
        <Route path="/planes-visitador" element={<PlanesVisitadorPage />} />
        <Route path="/admin/planes/visitador" element={<AdminRoute><PlanesVisitadorConfigPage /></AdminRoute>} />

        {/* === RUTA PLANES TODOS (DÍA 8) === */}
        <Route path="/planes-todos" element={<PlanesTodosPage />} />

        {/* === RUTAS PLANES FALTANTES (DÍA 11.5) === */}
        <Route path="/admin/planes/farmaceutico" element={<AdminRoute><PlanesFarmaceuticoConfigPage /></AdminRoute>} />
        <Route path="/admin/planes/farmacia" element={<AdminRoute><PlanesFarmaciaConfigPage /></AdminRoute>} />
        <Route path="/admin/planes/publicidad" element={<AdminRoute><PlanesPublicidadConfigPage /></AdminRoute>} />
        <Route path="/admin/planes/empresas-afines" element={<AdminRoute><PlanesEmpresasAfinesConfigPage /></AdminRoute>} />

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
          <Route path="usuarios" element={<UsuariosAdminPage />} />
          <Route path="asignacion-roles" element={<AsignacionRolesPage />} />
          <Route path="planes-todos" element={<Navigate to="/planes-todos" replace />} />
          <Route path="planes-medico" element={<Navigate to="/admin/planes/configuracion" replace />} />
          <Route path="planes-clinica" element={<Navigate to="/admin/planes/clinica" replace />} />
          <Route path="planes-lab" element={<Navigate to="/admin/planes/lab" replace />} />
          <Route path="planes-visitador" element={<Navigate to="/admin/planes/visitador" replace />} />
          <Route path="planes-farmaceutico" element={<Navigate to="/admin/planes/farmaceutico" replace />} />
          <Route path="planes-farmacia" element={<Navigate to="/admin/planes/farmacia" replace />} />
          <Route path="planes-publicidad" element={<Navigate to="/admin/planes/publicidad" replace />} />
          <Route path="planes-empresas-afines" element={<Navigate to="/admin/planes/empresas-afines" replace />} />
          <Route path="excepciones" element={<Navigate to="/admin/planes/excepciones" replace />} />
          <Route path="finanzas" element={<FinanzasPage />} />
          <Route path="reportes" element={<ReportesEzPayPageV2 />} />
          <Route path="roles" element={<RolesPage />} />
          <Route path="auditoria" element={<AuditoriaPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}

export default App
