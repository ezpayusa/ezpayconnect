import { lazy, Suspense, useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate, useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'

// === LAYOUTS / GUARDS (eager: shells compartidos y lógica de routing) ===
import { Sidebar } from '@/components/layout/Sidebar'
import { AdminLayout } from '@/components/admin-ezpay/layout/AdminLayout'
import WebAppLayout from '@/webapp/layout/WebAppLayout'
import WebAppPrivateRoute from '@/webapp/layout/WebAppPrivateRoute'
import ProveedorLayout from '@/proveedor/layout/ProveedorLayout'
import ProveedorPrivateRoute from '@/proveedor/components/ProveedorPrivateRoute'
import LaboratorioLayout from '@/laboratorio/layout/LaboratorioLayout'
import LaboratorioPrivateRoute from '@/laboratorio/components/LaboratorioPrivateRoute'
import FarmaciaLayout from '@/farmacia/layout/FarmaciaLayout'
import FarmaciaPrivateRoute from '@/farmacia/components/FarmaciaPrivateRoute'
import RepartidorPrivateRoute from '@/repartidor/components/RepartidorPrivateRoute'
import RepartidorLayout from '@/repartidor/layout/RepartidorLayout'
import ColaPage from '@/repartidor/pages/ColaPage'
import EntregaDetallePage from '@/repartidor/pages/EntregaDetallePage'
import PerfilPage from '@/repartidor/pages/PerfilPage'
import VisitadorPrivateRoute from '@/visitador/components/VisitadorPrivateRoute'
import VisitadorLayout from '@/visitador/layout/VisitadorLayout'
import { MedicoLayout } from '@/medico/layout/MedicoLayout'
import MedicoPrivateRoute from '@/medico/components/MedicoPrivateRoute'
import { ClinicaLayout } from '@/clinica/layout/ClinicaLayout'
import { RequiereRolClinica } from '@/clinica/components/RequiereRolClinica'
import MustChangePasswordGuard from '@/components/MustChangePasswordGuard'

// === UI GLOBAL (eager) ===
import { Toaster } from '@/components/ui/sonner'
import { PaisProvider } from '@/contexts/PaisContext'

// ============================================================
// PÁGINAS (lazy: cada ruta se descarga en su propio chunk)
// ============================================================
const BuscarMedicamentosPage = lazy(() => import('@/pages/BuscarMedicamentosPage'))
const NotificacionesPage = lazy(() => import('@/pages/NotificacionesPage'))
const LoginPage = lazy(() => import('@/pages/LoginPage'))
const SetPasswordPage = lazy(() => import('@/pages/SetPasswordPage'))
const ConfirmarRecetaPage = lazy(() => import('@/pages/ConfirmarRecetaPage'))
const DashboardPage = lazy(() => import('@/pages/DashboardPage'))
const PacientesPage = lazy(() => import('@/pages/PacientesPage'))
const PacienteDetallePage = lazy(() => import('@/pages/PacienteDetallePage'))
const CitasPage = lazy(() => import('@/pages/CitasPage'))
const RecetasPage = lazy(() => import('@/pages/RecetasPage'))
const RedirectRecetas = lazy(() => import('@/components/RedirectRecetas'))
const RecetaDetallePage = lazy(() => import('@/pages/RecetaDetallePage'))
const FarmaciasPage = lazy(() => import('@/pages/FarmaciasPage'))
const DispensarRecetaPage = lazy(() => import('@/pages/DispensarRecetaPage'))
const ConfiguracionPage = lazy(() => import('@/pages/ConfiguracionPage'))
const FacturasPage = lazy(() => import('@/pages/FacturasPage'))
const DisponibilidadVisitasPage = lazy(() => import('@/pages/DisponibilidadVisitasPage'))
const ConsultaPage = lazy(() => import('@/pages/ConsultaPage'))
const RegistroMedicoPage = lazy(() => import('@/pages/RegistroMedicoPage'))
const RegistroClinicaPage = lazy(() => import('@/pages/RegistroClinicaPage'))
const NotFoundPage = lazy(() => import('@/pages/NotFoundPage'))

// === PORTAL PACIENTE ===
const WebAppLoginPage = lazy(() => import('@/webapp/pages/WebAppLoginPage'))
const WebAppRegistroPage = lazy(() => import('@/webapp/pages/WebAppRegistroPage'))
const WebAppDashboard = lazy(() => import('@/webapp/pages/WebAppDashboard'))
const WebAppCitas = lazy(() => import('@/webapp/pages/WebAppCitas'))
const WebAppRecetas = lazy(() => import('@/webapp/pages/WebAppRecetas'))
const WebAppExamenes = lazy(() => import('@/webapp/pages/WebAppExamenes'))
const WebAppHistorial = lazy(() => import('@/webapp/pages/WebAppHistorial'))
const WebAppChat = lazy(() => import('@/webapp/pages/WebAppChat'))
const WebAppPerfil = lazy(() => import('@/webapp/pages/WebAppPerfil'))
const WebAppAutorizaciones = lazy(() => import('@/webapp/pages/WebAppAutorizaciones'))
const WebAppPremios = lazy(() => import('@/webapp/pages/WebAppPremios'))

// === ADMIN EZPAY ===
const AdminEzPayPage = lazy(() => import('@/pages/admin-ezpay/AdminEzPayPage'))
const VentasPage = lazy(() => import('@/pages/admin-ezpay/VentasPage'))
const AsignacionRolesPage = lazy(() => import('@/pages/admin-ezpay/AsignacionRolesPage'))
const PaisesPage = lazy(() => import('@/pages/admin-ezpay/PaisesPage'))
const NotificacionesAdminPage = lazy(() => import('@/pages/admin-ezpay/NotificacionesPage'))
const PaisDashboardPage = lazy(() => import('@/pages/admin-ezpay/PaisDashboardPage'))
const InvitacionesMedicosPage = lazy(() => import('@/pages/admin-ezpay/InvitacionesMedicosPage'))
const InvitacionesClinicasPage = lazy(() => import('@/pages/admin-ezpay/InvitacionesClinicasPage'))
const FinanzasPage = lazy(() => import('@/pages/admin-ezpay/FinanzasPage'))
const CuentasBancariasPage = lazy(() => import('@/pages/admin-ezpay/CuentasBancariasPage'))
const RolesPage = lazy(() => import('@/pages/admin-ezpay/RolesPage'))
const UsuariosAdminPage = lazy(() => import('@/pages/admin-ezpay/UsuariosAdminPage'))
const AuditoriaPage = lazy(() => import('@/pages/admin-ezpay/AuditoriaPage'))
const CampanasPublicitariasPage = lazy(() => import('@/pages/admin-ezpay/CampanasPublicitariasPage'))
const SolicitudesCampanaPage = lazy(() => import('@/pages/admin-ezpay/SolicitudesCampanaPage'))
const PagosProveedoresPage = lazy(() => import('@/pages/admin-ezpay/PagosProveedoresPage'))
const AdminVisitasProveedoresPage = lazy(() => import('@/pages/admin-ezpay/AdminVisitasProveedoresPage'))
const EmpresasProveedorasPage = lazy(() => import('@/pages/admin-ezpay/EmpresasProveedorasPage'))
const ReportesPage = lazy(() => import('@/pages/admin-ezpay/ReportesPage'))
const ReportesEzPayPage = lazy(() => import('@/pages/admin-ezpay/ReportesEzPayPage'))
const ReportesEzPayPageV2 = lazy(() => import('@/pages/admin-ezpay/ReportesEzPayPageV2'))
const CanjesPendientesPage = lazy(() => import('@/pages/admin-ezpay/CanjesPendientesPage'))
const EspecialidadesPropuestasPage = lazy(() => import('@/pages/admin-ezpay/EspecialidadesPropuestasPage'))
const SolicitudesPersonalizacionPage = lazy(() => import('@/pages/admin-ezpay/SolicitudesPersonalizacionPage'))
const MedicamentosClasificacionPage = lazy(() => import('@/pages/admin-ezpay/MedicamentosClasificacionPage'))

// === PROVEEDORES ===
const ProveedorLogin = lazy(() => import('@/proveedor/pages/ProveedorLogin'))
const ProveedorRegistro = lazy(() => import('@/proveedor/pages/ProveedorRegistro'))
const ProveedorRegistroVisitador = lazy(() => import('@/proveedor/pages/visitador/ProveedorRegistroVisitador'))
const ProveedorDashboard = lazy(() => import('@/proveedor/pages/ProveedorDashboard'))
const ProductosListPage = lazy(() => import('@/proveedor/pages/productos/ProductosListPage'))
const ProductoFormPage = lazy(() => import('@/proveedor/pages/productos/ProductoFormPage'))
const EquipoRolesPage = lazy(() => import('@/proveedor/pages/EquipoRolesPage'))
const VisitadorPlanesPage = lazy(() => import('@/proveedor/pages/visitador/VisitadorPlanesPage'))
const VisitadorAgendarPage = lazy(() => import('@/proveedor/pages/visitador/VisitadorAgendarPage'))
const VisitadorMisVisitasPage = lazy(() => import('@/proveedor/pages/visitador/VisitadorMisVisitasPage'))
const VisitadorRutaPage = lazy(() => import('@/proveedor/pages/visitador/VisitadorRutaPage'))
const ProveedorReporteVisitasPage = lazy(() => import('@/proveedor/pages/visitador/ProveedorReporteVisitasPage'))
const AdminAprobarVisitasPage = lazy(() => import('@/proveedor/pages/visitador/AdminAprobarVisitasPage'))
const AdminVisitadoresPage = lazy(() => import('@/proveedor/pages/visitador/AdminVisitadoresPage'))
const VisitadorDetallePage = lazy(() => import('@/proveedor/pages/visitador/VisitadorDetallePage'))
const EquiposPage = lazy(() => import('@/proveedor/pages/visitador/EquiposPage'))
const MensajesPage = lazy(() => import('@/proveedor/pages/MensajesPage'))
const AdminUbicacionesMedicosPage = lazy(() => import('@/proveedor/pages/visitador/AdminUbicacionesMedicosPage'))
const PublicidadPlanesPage = lazy(() => import('@/proveedor/pages/publicidad/PublicidadPlanesPage'))
const PublicidadCampanasPage = lazy(() => import('@/proveedor/pages/publicidad/PublicidadCampanasPage'))
const PublicidadCampanaFormPage = lazy(() => import('@/proveedor/pages/publicidad/PublicidadCampanaFormPage'))
const PublicidadMetricasPage = lazy(() => import('@/proveedor/pages/publicidad/PublicidadMetricasPage'))
const ProveedorPerfilPage = lazy(() => import('@/proveedor/pages/cuenta/ProveedorPerfilPage'))
const ProveedorPagosPage = lazy(() => import('@/proveedor/pages/cuenta/ProveedorPagosPage'))
const ProveedorNotificacionesPage = lazy(() => import('@/proveedor/pages/ProveedorNotificacionesPage'))
const PagoCheckoutPage = lazy(() => import('@/proveedor/pages/PagoCheckoutPage'))

// === PORTAL LABORATORIO CLÍNICO ===
const LabLogin = lazy(() => import('@/laboratorio/pages/LabLogin'))
const LabRegistro = lazy(() => import('@/laboratorio/pages/LabRegistro'))
const LabDashboard = lazy(() => import('@/laboratorio/pages/LabDashboard'))
const LabOrdenesPage = lazy(() => import('@/laboratorio/pages/LabOrdenesPage'))
const LabCatalogoPage = lazy(() => import('@/laboratorio/pages/LabCatalogoPage'))
const LabWalkInPage = lazy(() => import('@/laboratorio/pages/LabWalkInPage'))
const LabAfiliacionesPage = lazy(() => import('@/laboratorio/pages/LabAfiliacionesPage'))
const LabPersonalPage = lazy(() => import('@/laboratorio/pages/LabPersonalPage'))
const LabPerfilPage = lazy(() => import('@/laboratorio/pages/LabPerfilPage'))
const FarmaciaLogin = lazy(() => import('@/farmacia/pages/FarmaciaLogin'))
const FarmaciaRegistro = lazy(() => import('@/farmacia/pages/FarmaciaRegistro'))
const FarmaciaDashboard = lazy(() => import('@/farmacia/pages/FarmaciaDashboard'))
const FarmaciaInventarioPage = lazy(() => import('@/farmacia/pages/FarmaciaInventarioPage'))
const FarmaciaRecetasPage = lazy(() => import('@/farmacia/pages/FarmaciaRecetasPage'))
const EntregasMonitoreoPage = lazy(() => import('@/farmacia/pages/EntregasMonitoreoPage'))
const FarmaciaReportesPage = lazy(() => import('@/farmacia/pages/FarmaciaReportesPage'))
const FarmaciaComisionesPage = lazy(() => import('@/farmacia/pages/FarmaciaComisionesPage'))
const FarmaciaPersonalPage = lazy(() => import('@/farmacia/pages/FarmaciaPersonalPage'))
const FarmaciaSucursalesPage = lazy(() => import('@/farmacia/pages/FarmaciaSucursalesPage'))

// === PLANES ===
const PlanesPage = lazy(() => import('@/pages/planes/PlanesPage'))
const PlanesConfigPage = lazy(() => import('@/pages/planes/PlanesConfigPage'))
const PlanesAsignacionesPage = lazy(() => import('@/pages/planes/PlanesAsignacionesPage'))
const PlanesExcepcionesPage = lazy(() => import('@/pages/planes/PlanesExcepcionesPage'))
const PlanesClinicaPage = lazy(() => import('@/pages/planes/PlanesClinicaPage'))
const PlanesClinicaConfigPage = lazy(() => import('@/pages/planes/PlanesClinicaConfigPage'))
const PlanesLabPage = lazy(() => import('@/pages/planes/PlanesLabPage'))
const PlanesLabConfigPage = lazy(() => import('@/pages/planes/PlanesLabConfigPage'))
const PlanesVisitadorPage = lazy(() => import('@/pages/planes/PlanesVisitadorPage'))
const PlanesVisitadorConfigPage = lazy(() => import('@/pages/planes/PlanesVisitadorConfigPage'))
const PlanesTodosPage = lazy(() => import('@/pages/planes/PlanesTodosPage'))
const PlanesFarmaceuticoConfigPage = lazy(() => import('@/pages/planes/PlanesFarmaceuticoConfigPage'))
const PlanesFarmaciaConfigPage = lazy(() => import('@/pages/planes/PlanesFarmaciaConfigPage'))
const PlanesPublicidadConfigPage = lazy(() => import('@/pages/planes/PlanesPublicidadConfigPage'))
const PlanesEmpresasAfinesConfigPage = lazy(() => import('@/pages/planes/PlanesEmpresasAfinesConfigPage'))

// === CLÍNICA ===
const ClinicaDashboardPage = lazy(() => import('@/clinica/pages/ClinicaDashboardPage'))
const ClinicaPersonalPage = lazy(() => import('@/clinica/pages/ClinicaPersonalPage'))
const ClinicaInvitarMedicoPage = lazy(() => import('@/clinica/pages/ClinicaInvitarMedicoPage'))
const ClinicaInvitarLaboratorioPage = lazy(() => import('@/clinica/pages/ClinicaInvitarLaboratorioPage'))
const ClinicaInvitarStaffPage = lazy(() => import('@/clinica/pages/ClinicaInvitarStaffPage'))
const ClinicaCitasPage = lazy(() => import('@/clinica/pages/ClinicaCitasPage'))
const ClinicaCalendarioPage = lazy(() => import('@/clinica/pages/ClinicaCalendarioPage'))
const ClinicaConfiguracionPage = lazy(() => import('@/clinica/pages/ClinicaConfiguracionPage'))
const ClinicaHorariosMedicosPage = lazy(() => import('@/clinica/pages/ClinicaHorariosMedicosPage'))
const ClinicaAdmisionPage = lazy(() => import('@/clinica/pages/ClinicaAdmisionPage'))

// === PORTAL MÉDICO ===
const MedicoDashboardPage = lazy(() => import('@/medico/pages/MedicoDashboardPage'))
const MedicoCitasPage = lazy(() => import('@/medico/pages/MedicoCitasPage'))
const MedicoPacientesPage = lazy(() => import('@/medico/pages/MedicoPacientesPage'))
const MedicoRecetasPage = lazy(() => import('@/medico/pages/MedicoRecetasPage'))
const MedicoDisponibilidadPage = lazy(() => import('@/medico/pages/MedicoDisponibilidadPage'))
const MedicoChatPage = lazy(() => import('@/medico/pages/MedicoChatPage'))

function Spinner() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
    </div>
  )
}

function PrivateLayout({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return <Spinner />
  if (!user) return <Navigate to="/login" replace />
  return <div className="flex min-h-screen bg-gray-50"><Sidebar /><main className="flex-1 ml-0 overflow-auto pt-14 md:pt-0">{children}</main></div>
}

function AdminRoute({ children }: { children: React.ReactNode }) {
  const { isAdmin, isSuperAdmin, isAdminPais, adminUser, loading } = useAdminAuth()
  const navigate = useNavigate()
  const location = useLocation()

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

  // ENFORCEMENT "modo país" (deny-by-default, solo navegación/UX — la seguridad real de datos es la
  // RLS de la pieza siguiente). Un admin_pais (no super) solo puede estar bajo su propio
  // /admin-ezpay/pais/{su pais_id}: cualquier otra ruta (país ajeno O ruta global) redirige a su
  // dashboard. super_admin queda igual que hoy. Si pais_id fuese null (imposible: el CHECK de mig 216
  // lo impide) la cuenta está rota → deny total a /dashboard (fail-closed), no al panel global.
  if (isAdminPais && !isSuperAdmin) {
    if (!adminUser?.pais_id) return <Navigate to="/dashboard" replace />
    const propio = `/admin-ezpay/pais/${adminUser.pais_id}`
    const enPropio = location.pathname === propio || location.pathname.startsWith(propio + '/')
    if (!enPropio) return <Navigate to={propio} replace />
  }

  console.log('[AdminRoute] isAdmin=true, renderizando children')
  return <>{children}</>
}

function App() {
  return (
    <PaisProvider>
    <BrowserRouter>
      <Suspense fallback={<Spinner />}>
      <MustChangePasswordGuard />
      <Routes>
        <Route path="/notificaciones" element={<PrivateLayout><NotificacionesPage /></PrivateLayout>} />
        <Route path="/registro-medico" element={<RegistroMedicoPage />} />
        <Route path="/registro-clinica" element={<RegistroClinicaPage />} />
        <Route path="/login" element={<LoginPage />} />
        <Route path="/set-password" element={<SetPasswordPage />} />
        <Route path="/confirmar-receta" element={<ConfirmarRecetaPage />} />
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<PrivateLayout><DashboardPage /></PrivateLayout>} />
        <Route path="/pacientes" element={<PrivateLayout><PacientesPage /></PrivateLayout>} />
        <Route path="/pacientes/:id/detalle" element={<PrivateLayout><PacienteDetallePage /></PrivateLayout>} />
        <Route path="/pacientes/:id" element={<PrivateLayout><PacientesPage /></PrivateLayout>} />
        <Route path="/citas" element={<PrivateLayout><CitasPage /></PrivateLayout>} />
        <Route path="/recetas" element={<RedirectRecetas />} />
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
          <Route path="autorizaciones" element={<WebAppAutorizaciones />} />
          <Route path="premios" element={<WebAppPremios />} />
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
          {/* Dual-mount de 4 páginas globales bajo /pais/:paisId (mismo componente lazy; páginas agnósticas de URL). */}
          <Route path="pais/:paisId/canjes" element={<CanjesPendientesPage />} />
          <Route path="pais/:paisId/especialidades" element={<EspecialidadesPropuestasPage />} />
          <Route path="pais/:paisId/solicitudes-personalizacion" element={<SolicitudesPersonalizacionPage />} />
          <Route path="pais/:paisId/reportes-ezpay-v2" element={<ReportesEzPayPageV2 />} />
          <Route path="pais/:paisId/empresas-proveedoras" element={<EmpresasProveedorasPage />} />
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
          <Route path="cuentas-bancarias" element={<CuentasBancariasPage />} />

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
          <Route path="canjes" element={<CanjesPendientesPage />} />
          <Route path="especialidades" element={<EspecialidadesPropuestasPage />} />
          <Route path="solicitudes-personalizacion" element={<SolicitudesPersonalizacionPage />} />
          <Route path="medicamentos" element={<MedicamentosClasificacionPage />} />
        </Route>

        {/* === RUTAS MÉDICO === */}
        <Route path="/medico" element={<MedicoPrivateRoute><MedicoLayout /></MedicoPrivateRoute>}>
          <Route index element={<MedicoDashboardPage />} />
          <Route path="citas" element={<MedicoCitasPage />} />
          <Route path="pacientes" element={<MedicoPacientesPage />} />
          <Route path="recetas" element={<MedicoRecetasPage />} />
          <Route path="disponibilidad" element={<MedicoDisponibilidadPage />} />
          <Route path="consulta/:citaId" element={<ConsultaPage />} />
          <Route path="buscar-medicamentos" element={<BuscarMedicamentosPage />} />
          <Route path="chat" element={<MedicoChatPage />} />
          <Route path="pacientes/:id/detalle" element={<PacienteDetallePage />} />
          <Route path="notificaciones" element={<NotificacionesPage />} />
        </Route>

        {/* === RUTAS CLÍNICA === */}
        <Route path="/clinica" element={<ClinicaLayout />}>
          {/* Admisión: cola de citas de hoy + captura de vitales (serie). Roles de captura + admin. */}
          <Route path="admision" element={
            <RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente', 'asistente_medico', 'enfermeria', 'secretaria']}>
              <ClinicaAdmisionPage />
            </RequiereRolClinica>
          } />
          {/* Superficies administrativas: gate por página (defensa vs URL directa). Un rol de captura
              que entra por URL es redirigido a /clinica/admision. roles = los admin de clínica. */}
          <Route index element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaDashboardPage /></RequiereRolClinica>} />
          <Route path="citas" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaCitasPage /></RequiereRolClinica>} />
          <Route path="calendario" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente', 'asistente_medico', 'enfermeria', 'secretaria']}><ClinicaCalendarioPage /></RequiereRolClinica>} />
          <Route path="personal" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaPersonalPage /></RequiereRolClinica>} />
          <Route path="horarios-medicos" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaHorariosMedicosPage /></RequiereRolClinica>} />
          <Route path="invitar-medico" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaInvitarMedicoPage /></RequiereRolClinica>} />
          <Route path="invitar-laboratorio" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaInvitarLaboratorioPage /></RequiereRolClinica>} />
          <Route path="invitar-staff" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaInvitarStaffPage /></RequiereRolClinica>} />
          <Route path="configuracion" element={<RequiereRolClinica roles={['admin_clinica', 'admin', 'super_admin', 'gerente']}><ClinicaConfiguracionPage /></RequiereRolClinica>} />
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
          {/* Contratación del módulo (audiencia admin/supervisor). Las 3 páginas de campo del
              visitador (agendar/mis-visitas/ruta) se mudaron al PWA /visitador/*. planes queda
              dual-mount acá para que admin/supervisor (permiso planes.contratar, no son
              visitador_medico) puedan seguir contratando. */}
          <Route path="visitador/planes" element={<VisitadorPlanesPage />} />
          <Route path="visitador/reporte" element={<ProveedorReporteVisitasPage />} />
          <Route path="visitador/aprobar" element={<AdminAprobarVisitasPage />} />
          <Route path="visitador/ubicaciones-medicos" element={<AdminUbicacionesMedicosPage />} />
          <Route path="visitadores" element={<AdminVisitadoresPage />} />
          <Route path="visitadores/:id" element={<VisitadorDetallePage />} />
          <Route path="equipos" element={<EquiposPage />} />
          <Route path="mensajes" element={<MensajesPage />} />
          <Route path="publicidad/planes" element={<PublicidadPlanesPage />} />
          <Route path="publicidad/campanas" element={<PublicidadCampanasPage />} />
          <Route path="publicidad/campanas/nueva" element={<PublicidadCampanaFormPage />} />
          <Route path="publicidad/metricas" element={<PublicidadMetricasPage />} />
          <Route path="perfil" element={<ProveedorPerfilPage />} />
          <Route path="equipo" element={<EquipoRolesPage />} />
          <Route path="pagos" element={<ProveedorPagosPage />} />
          <Route path="notificaciones" element={<ProveedorNotificacionesPage />} />
          <Route path="checkout" element={<PagoCheckoutPage />} />
        </Route>

        {/* === RUTAS PORTAL LABORATORIO CLÍNICO === */}
        <Route path="/laboratorio/login" element={<LabLogin />} />
        <Route path="/laboratorio/registro" element={<LabRegistro />} />
        <Route path="/laboratorio/*" element={<LaboratorioPrivateRoute><LaboratorioLayout /></LaboratorioPrivateRoute>}>
          <Route index element={<Navigate to="/laboratorio/dashboard" replace />} />
          <Route path="dashboard" element={<LabDashboard />} />
          <Route path="ordenes" element={<LabOrdenesPage />} />
          <Route path="catalogo" element={<LabCatalogoPage />} />
          <Route path="walk-in" element={<LabWalkInPage />} />
          <Route path="afiliaciones" element={<LabAfiliacionesPage />} />
          <Route path="personal" element={<LabPersonalPage />} />
          <Route path="perfil" element={<LabPerfilPage />} />
          <Route path="notificaciones" element={<ProveedorNotificacionesPage />} />
        </Route>

        {/* === PWA REPARTIDOR (delivery; guard por rol_en_empresa='delivery') === */}
        <Route path="/repartidor/*" element={<RepartidorPrivateRoute><RepartidorLayout /></RepartidorPrivateRoute>}>
          <Route index element={<ColaPage />} />
          <Route path="entrega/:id" element={<EntregaDetallePage />} />
          <Route path="perfil" element={<PerfilPage />} />
        </Route>

        {/* === PWA VISITADOR (guard por rol_en_empresa='visitador_medico') === */}
        <Route path="/visitador/*" element={<VisitadorPrivateRoute><VisitadorLayout /></VisitadorPrivateRoute>}>
          <Route index element={<Navigate to="/visitador/agendar" replace />} />
          <Route path="agendar" element={<VisitadorAgendarPage />} />
          <Route path="mis-visitas" element={<VisitadorMisVisitasPage />} />
          <Route path="ruta" element={<VisitadorRutaPage />} />
          <Route path="planes" element={<VisitadorPlanesPage />} />
        </Route>

        {/* === PORTAL FARMACIA (tenant; guard por tipo='farmacia') === */}
        <Route path="/farmacia/login" element={<FarmaciaLogin />} />
        <Route path="/farmacia/registro" element={<FarmaciaRegistro />} />
        <Route path="/farmacia/*" element={<FarmaciaPrivateRoute><FarmaciaLayout /></FarmaciaPrivateRoute>}>
          <Route index element={<Navigate to="/farmacia/dashboard" replace />} />
          <Route path="dashboard" element={<FarmaciaDashboard />} />
          <Route path="inventario" element={<FarmaciaInventarioPage />} />
          <Route path="recetas" element={<FarmaciaRecetasPage />} />
          <Route path="entregas" element={<EntregasMonitoreoPage />} />
          <Route path="reportes" element={<FarmaciaReportesPage />} />
          <Route path="comisiones" element={<FarmaciaComisionesPage />} />
          <Route path="personal" element={<FarmaciaPersonalPage />} />
          <Route path="sucursales" element={<FarmaciaSucursalesPage />} />
          <Route path="pagos" element={<ProveedorPagosPage />} />
          <Route path="perfil" element={<ProveedorPerfilPage />} />
          <Route path="notificaciones" element={<ProveedorNotificacionesPage />} />
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

        {/* Catch-all 404: cualquier URL no matcheada (ej. /medico/paciente/23/detalle mal tipeada) */}
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
      </Suspense>
      <Toaster richColors position="top-right" />
    </BrowserRouter>
    </PaisProvider>
  )
}

export default App
