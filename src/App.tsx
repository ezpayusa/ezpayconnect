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
import DisponibilidadVisitasPage from '@/pages/DisponibilidadVisitasPage'
import ConsultaPage from '@/pages/ConsultaPage'

// === IMPORTS PORTAL PACIENTE ===
import WebAppLayout from '@/webapp/layout/WebAppLayout'
import WebAppPrivateRoute from '@/webapp/layout/WebAppPrivateRoute'
import WebAppLoginPage from '@/webapp/pages/WebAppLoginPage'
import WebAppRegistroPage from '@/webapp/pages/WebAppRegistroPage'
import WebAppDashboard from '@/webapp/pages/WebAppDashboard'
import WebAppCitas from '@/webapp/pages/WebAppCitas'
import WebAppRecetas from '@/webapp/pages/WebAppRecetas'
import WebAppExamenes from '@/webapp/pages/WebAppExamenes'
import WebAppHistorial from '@/webapp/pages/WebAppHistorial'
import WebAppChat from '@/webapp/pages/WebAppChat'
import WebAppPerfil from '@/webapp/pages/WebAppPerfil'

// === IMPORTS ADMIN EZPAY ===
import { useEffect } from 'react'
import { AdminLayout } from '@/components/admin-ezpay/layout/AdminLayout'
import AdminEzPayPage from '@/pages/admin-ezpay/AdminEzPayPage'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'

// === IMPORTS PORTAL PROVEEDORES ===
import ProveedorLayout from '@/proveedor/layout/ProveedorLayout'
import ProveedorPrivateRoute from '@/proveedor/components/ProveedorPrivateRoute'
import ProveedorLogin from '@/proveedor/pages/ProveedorLogin'
import ProveedorRegistro from '@/proveedor/pages/ProveedorRegistro'
import ProveedorRegistroVisitador from '@/proveedor/pages/visitador/ProveedorRegistroVisitador'
import ProveedorDashboard from '@/proveedor/pages/ProveedorDashboard'
import ProductosListPage from '@/proveedor/pages/productos/ProductosListPage'
import ProductoFormPage from '@/proveedor/pages/productos/ProductoFormPage'
import VisitadorPlanesPage from '@/proveedor/pages/visitador/VisitadorPlanesPage'
import VisitadorAgendarPage from '@/proveedor/pages/visitador/VisitadorAgendarPage'
import VisitadorMisVisitasPage from '@/proveedor/pages/visitador/VisitadorMisVisitasPage'
import VisitadorRutaPage from '@/proveedor/pages/visitador/VisitadorRutaPage'
import ProveedorReporteVisitasPage from '@/proveedor/pages/visitador/ProveedorReporteVisitasPage'
import AdminAprobarVisitasPage from '@/proveedor/pages/visitador/AdminAprobarVisitasPage'
import AdminVisitadoresPage from '@/proveedor/pages/visitador/AdminVisitadoresPage'
import AdminUbicacionesMedicosPage from '@/proveedor/pages/visitador/AdminUbicacionesMedicosPage'
import PublicidadPlanesPage from '@/proveedor/pages/publicidad/PublicidadPlanesPage'
import PublicidadCampanasPage from '@/proveedor/pages/publicidad/PublicidadCampanasPage'
import PublicidadCampanaFormPage from '@/proveedor/pages/publicidad/PublicidadCampanaFormPage'
import PublicidadMetricasPage from '@/proveedor/pages/publicidad/PublicidadMetricasPage'
import ProveedorPerfilPage from '@/proveedor/pages/cuenta/ProveedorPerfilPage'
import ProveedorPagosPage from '@/proveedor/pages/cuenta/ProveedorPagosPage'
import PagoCheckoutPage from '@/proveedor/pages/PagoCheckoutPage'

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
import CampanasPublicitariasPage from '@/pages/admin-ezpay/CampanasPublicitariasPage'
import SolicitudesCampanaPage from '@/pages/admin-ezpay/SolicitudesCampanaPage'
import PagosProveedoresPage from '@/pages/admin-ezpay/PagosProveedoresPage'
import AdminVisitasProveedoresPage from '@/pages/admin-ezpay/AdminVisitasProveedoresPage'
import EmpresasProveedorasPage from '@/pages/admin-ezpay/EmpresasProveedorasPage'

// === IMPORTS REPORTES (NUEVOS) ===
import ReportesPage from '@/pages/admin-ezpay/ReportesPage'
import ReportesEzPayPage from '@/pages/admin-ezpay/ReportesEzPayPage'
import ReportesEzPayPageV2 from '@/pages/admin-ezpay/ReportesEzPayPageV2'

// === IMPORTS UI GLOBAL ===
import { Toaster } from '@/components/ui/sonner'
import { PaisProvider } from '@/contexts/PaisContext'
import PaisDashboardPage from '@/pages/admin-ezpay/PaisDashboardPage'
import InvitacionesMedicosPage from '@/pages/admin-ezpay/InvitacionesMedicosPage'
import InvitacionesClinicasPage from '@/pages/admin-ezpay/InvitacionesClinicasPage'
import RegistroMedicoPage from '@/pages/RegistroMedicoPage'
import RegistroClinicaPage from '@/pages/RegistroClinicaPage'
import { ClinicaLayout } from '@/clinica/layout/ClinicaLayout'
import ClinicaDashboardPage from '@/clinica/pages/ClinicaDashboardPage'
import ClinicaPersonalPage from '@/clinica/pages/ClinicaPersonalPage'
import ClinicaInvitarMedicoPage from '@/clinica/pages/ClinicaInvitarMedicoPage'
import ClinicaInvitarStaffPage from '@/clinica/pages/ClinicaInvitarStaffPage'

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
    <PaisProvider>
    <BrowserRouter>
      <Routes>
        <Route path="/notificaciones" element={<PrivateLayout><NotificacionesPage /></PrivateLayout>} />
        <Route path="/registro-medico" element={<RegistroMedicoPage />} />
        <Route path="/registro-clinica" element={<RegistroClinicaPage />} />
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
        <Route path="/disponibilidad-visitas" element={<PrivateLayout><DisponibilidadVisitasPage /></PrivateLayout>} />
        <Route path="/consulta/:citaId" element={<PrivateLayout><ConsultaPage /></PrivateLayout>} />

        {/* === RUTAS PORTAL DEL PACIENTE === */}
        <Route path="/paciente/login" element={<WebAppLoginPage />} />
        <Route path="/paciente/registro" element={<WebAppRegistroPage />} />
        <Route path="/paciente" element={<WebAppPrivateRoute><WebAppLayout /></WebAppPrivateRoute>}>
          <Route index element={<Navigate to="/paciente/dashboard" replace />} />
          <Route path="dashboard" element={<WebAppDashboard />} />
          <Route path="citas" element={<WebAppCitas />} />
          <Route path="recetas" element={<WebAppRecetas />} />
          <Route path="examenes" element={<WebAppExamenes />} />
          <Route path="historial" element={<WebAppHistorial />} />
          <Route path="chat" element={<WebAppChat />} />
          <Route path="perfil" element={<WebAppPerfil />} />
        </Route>

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
          <Route path="pais/:paisId" element={<PaisDashboardPage />} />
          <Route path="pais/:paisId/invitaciones-medicos" element={<InvitacionesMedicosPage />} />
          <Route path="pais/:paisId/invitaciones-clinicas" element={<InvitacionesClinicasPage />} />
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
          <Route path="campanas-publicitarias" element={<CampanasPublicitariasPage />} />
          <Route path="planes-publicidad-config" element={<PlanesPublicidadConfigPage />} />
          <Route path="solicitudes-campana" element={<SolicitudesCampanaPage />} />
          <Route path="pagos-proveedores" element={<PagosProveedoresPage />} />
          <Route path="visitas-proveedores" element={<AdminVisitasProveedoresPage />} />
          <Route path="empresas-proveedoras" element={<EmpresasProveedorasPage />} />
        </Route>

        {/* === RUTAS CLÍNICA === */}
        <Route path="/clinica" element={<ClinicaLayout />}>
          <Route index element={<ClinicaDashboardPage />} />
          <Route path="personal" element={<ClinicaPersonalPage />} />
          <Route path="invitar-medico" element={<ClinicaInvitarMedicoPage />} />
          <Route path="invitar-staff" element={<ClinicaInvitarStaffPage />} />
        </Route>

        {/* === RUTAS PORTAL PROVEEDORES === */}
        <Route path="/proveedor/login" element={<ProveedorLogin />} />
        <Route path="/proveedor/registro" element={<ProveedorRegistro />} />
        <Route path="/proveedor/registro-visitador" element={<ProveedorRegistroVisitador />} />
        <Route path="/proveedor/*" element={<ProveedorPrivateRoute><ProveedorLayout /></ProveedorPrivateRoute>}>
          <Route index element={<Navigate to="/proveedor/dashboard" replace />} />
          <Route path="dashboard" element={<ProveedorDashboard />} />
          <Route path="productos" element={<ProductosListPage />} />
          <Route path="productos/nuevo" element={<ProductoFormPage />} />
          <Route path="productos/:id/editar" element={<ProductoFormPage />} />
          <Route path="visitador/planes" element={<VisitadorPlanesPage />} />
          <Route path="visitador/agendar" element={<VisitadorAgendarPage />} />
          <Route path="visitador/mis-visitas" element={<VisitadorMisVisitasPage />} />
          <Route path="visitador/ruta" element={<VisitadorRutaPage />} />
          <Route path="visitador/reporte" element={<ProveedorReporteVisitasPage />} />
          <Route path="visitador/aprobar" element={<AdminAprobarVisitasPage />} />
          <Route path="visitador/ubicaciones-medicos" element={<AdminUbicacionesMedicosPage />} />
          <Route path="visitadores" element={<AdminVisitadoresPage />} />
          <Route path="publicidad/planes" element={<PublicidadPlanesPage />} />
          <Route path="publicidad/campanas" element={<PublicidadCampanasPage />} />
          <Route path="publicidad/campanas/nueva" element={<PublicidadCampanaFormPage />} />
          <Route path="publicidad/metricas" element={<PublicidadMetricasPage />} />
          <Route path="perfil" element={<ProveedorPerfilPage />} />
          <Route path="pagos" element={<ProveedorPagosPage />} />
          <Route path="checkout" element={<PagoCheckoutPage />} />
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
    </PaisProvider>
  )
}

export default App
