import BuscarMedicamentosPage from '@/pages/BuscarMedicamentosPage'
import VentasPage from '@/pages/admin-ezpay/VentasPage'
import AsignacionRolesPage from '@/pages/admin-ezpay/AsignacionRolesPage'
import PaisesPage from '@/pages/admin-ezpay/PaisesPage';
import NotificacionesPage from '@/pages/NotificacionesPage'
import NotificacionesAdminPage from '@/pages/admin-ezpay/NotificacionesPage'
import { BrowserRouter, Routes, Route, Navigate, useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { Sidebar } from '@/components/layout/Sidebar'
import LoginPage from '@/pages/LoginPage'
import DashboardPage from '@/pages/DashboardPage'
import PacientesPage from '@/pages/PacientesPage'
import PacienteDetallePage from '@/pages/PacienteDetallePage'
import CitasPage from '@/pages/CitasPage'
import RecetasPage from '@/pages/RecetasPage'
import RecetaDetallePage from '@/pages/RecetaDetallePage'
import FarmaciasPage from '@/pages/FarmaciasPage'
import DispensarRecetaPage from '@/pages/DispensarRecetaPage'
import ConfiguracionPage from '@/pages/ConfiguracionPage'
import FacturasPage from '@/pages/FacturasPage'

// === IMPORTS ADMIN EZPAY ===
import { useEffect } from 'react'
import { AdminLayout } from '@/components/admin-ezpay/layout/AdminLayout'
import AdminEzPayPage from '@/pages/admin-ezpay/AdminEzPayPage'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'

// === IMPORTS PLANES ===
import PlanesPage from '@/pages/planes/PlanesPage'
import PlanesConfigPage from '@/pages/planes/PlanesConfigPage'
import PlanesAsignacionesPage from '@/pages/planes/PlanesAsignacionesPage'
import PlanesExcepcionesPage from '@/pages/planes/PlanesExcepcionesPage'
import PlanesClinicaPage from '@/pages/planes/PlanesClinicaPage'
import PlanesClinicaConfigPage from '@/pages/planes/PlanesClinicaConfigPage'
import PlanesLabPage from '@/pages/planes/PlanesLabPage'
import PlanesLabConfigPage from '@/pages/planes/PlanesLabConfigPage'
import PlanesVisitadorPage from '@/pages/planes/PlanesVisitadorPage'
import PlanesVisitadorConfigPage from '@/pages/planes/PlanesVisitadorConfigPage'
import PlanesTodosPage from '@/pages/planes/PlanesTodosPage'
import PlanesFarmaceuticoConfigPage from '@/pages/planes/PlanesFarmaceuticoConfigPage'
import PlanesFarmaciaConfigPage from '@/pages/planes/PlanesFarmaciaConfigPage'
import PlanesPublicidadConfigPage from '@/pages/planes/PlanesPublicidadConfigPage'
import PlanesEmpresasAfinesConfigPage from '@/pages/planes/PlanesEmpresasAfinesConfigPage'

// === IMPORTS ADMIN ===
import FinanzasPage from '@/pages/admin-ezpay/FinanzasPage'
import RolesPage from '@/pages/admin-ezpay/RolesPage'
import UsuariosAdminPage from '@/pages/admin-ezpay/UsuariosAdminPage'
import AuditoriaPage from '@/pages/admin-ezpay/AuditoriaPage'

// === IMPORTS REPORTES (NUEVOS) ===
import ReportesPage from '@/pages/admin-ezpay/ReportesPage'
import ReportesEzPayPage from '@/pages/admin-ezpay/ReportesEzPayPage'
import ReportesEzPayPageV2 from '@/pages/admin-ezpay/ReportesEzPayPageV2'

// === IMPORTS UI GLOBAL ===
import { Toaster } from '@/components/ui/sonner'

function PrivateLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return <div className="min-h-screen flex items-center justify-center"><div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" /></div>
  if (!user) return <Navigate to="/login" replace />
  return <div className="flex min-h-screen bg-gray-50"><Sidebar /><main className="flex-1 ml-0 overflow-auto">{children}</main></div>
}

function AdminRoute({ children }: { children: React.ReactNode }) {
  const { isAdmin, loading } = useAdminAuth()
  const navigate = useNavigate()

  useEffect(() => {
    if (!loading && !isAdmin) {
      console.log('[AdminRoute] No es admin, redirigiendo a /dashboard')
      navigate('/dashboard')
    }
  }, [loading, isAdmin, navigate])

  if (loading) {
    console.log('[AdminRoute] Cargando...')
    return <div className="flex items-center justify-center h-screen">Cargando...</div>
  }

  if (!isAdmin) {
    console.log('[AdminRoute] isAdmin=false, mostrando null')
    return null
  }

  console.log('[AdminRoute] isAdmin=true, renderizando children')
  return <>{children}</>
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
        <Route path="/recetas/:id" element={<PrivateLayout><RecetaDetallePage /></PrivateLayout>} />
        <Route path="/facturas" element={<PrivateLayout><FacturasPage /></PrivateLayout>} />
        <Route path="/farmacias" element={<PrivateLayout><FarmaciasPage /></PrivateLayout>} />
        <Route path="/buscar-medicamentos" element={<PrivateLayout><BuscarMedicamentosPage /></PrivateLayout>} />
        <Route path="/dispensar-receta" element={<PrivateLayout><DispensarRecetaPage /></PrivateLayout>} />
        <Route path="/configuracion" element={<PrivateLayout><ConfiguracionPage /></PrivateLayout>} />

        {/* === RUTAS PLANES (PÚBLICAS / LANDING) === */}
        <Route path="/planes" element={<PlanesPage />} />
        <Route path="/planes-clinica" element={<PlanesClinicaPage />} />
        <Route path="/planes-lab" element={<PlanesLabPage />} />
        <Route path="/planes-visitador" element={<PlanesVisitadorPage />} />
        <Route path="/planes-todos" element={<Navigate to="/admin-ezpay/planes-todos" replace />} />

        {/* === RUTAS REPORTES MEDICOS (Panel Medico) === */}
        <Route path="/reportes" element={<PrivateLayout><ReportesPage /></PrivateLayout>} />

        {/* === RUTAS ADMIN EZPAY + PLANES (con AdminLayout) === */}
        <Route path="/admin-ezpay" element={<AdminRoute><AdminLayout /></AdminRoute>}>
          <Route path="ventas" element={<VentasPage />} />
          <Route index element={<AdminEzPayPage />} />
          <Route path="paises" element={<PaisesPage />} />
          <Route path="usuarios" element={<UsuariosAdminPage />} />
          <Route path="asignacion-roles" element={<AsignacionRolesPage />} />
          <Route path="planes-todos" element={<PlanesTodosPage />} />
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

          {/* === RUTAS REPORTES EZPAY === */}
          <Route path="reportes" element={<ReportesPage />} />
          <Route path="reportes-ezpay" element={<ReportesEzPayPage />} />
          <Route path="reportes-ezpay-v2" element={<ReportesEzPayPageV2 />} />

          <Route path="roles" element={<RolesPage />} />
          <Route path="auditoria" element={<AuditoriaPage />} />
          <Route path="notificaciones" element={<NotificacionesAdminPage />} />
        </Route>

        {/* === RUTAS ADMIN PLANES (con AdminLayout) — FIX: ahora tienen layout === */}
        <Route path="/admin/planes" element={<AdminRoute><AdminLayout /></AdminRoute>}>
          <Route path="configuracion" element={<PlanesConfigPage />} />
          <Route path="asignaciones" element={<PlanesAsignacionesPage />} />
          <Route path="excepciones" element={<PlanesExcepcionesPage />} />
          <Route path="clinica" element={<PlanesClinicaConfigPage />} />
          <Route path="lab" element={<PlanesLabConfigPage />} />
          <Route path="visitador" element={<PlanesVisitadorConfigPage />} />
          <Route path="farmaceutico" element={<PlanesFarmaceuticoConfigPage />} />
          <Route path="farmacia" element={<PlanesFarmaciaConfigPage />} />
          <Route path="publicidad" element={<PlanesPublicidadConfigPage />} />
          <Route path="empresas-afines" element={<PlanesEmpresasAfinesConfigPage />} />
        </Route>
      </Routes>
      <Toaster richColors position="top-right" />
    </BrowserRouter>
  )
}

export default App
