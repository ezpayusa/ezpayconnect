import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useProveedorStats } from '@/proveedor/hooks/useProveedorStats'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Link } from 'react-router-dom'
import {
  MapPin,
  Package,
  CalendarCheck,
  Megaphone,
  CreditCard,
  TrendingUp,
  AlertCircle,
  CalendarDays,
  Route,
  FileText,
  Loader2,
  Boxes,
  MapPinCheck,
  Banknote,
} from 'lucide-react'

export default function ProveedorDashboard() {
  const { empresa, cuenta } = useProveedorAuth()
  const { stats, loading } = useProveedorStats()
  const esVisitador = cuenta?.rol_en_empresa === 'visitador_medico'

  const modulesAdmin = [
    {
      title: 'Productos',
      desc: 'Gestiona tu catálogo de productos',
      icon: Package,
      path: '/proveedor/productos',
      color: 'bg-blue-50 text-blue-600',
    },
    {
      title: 'Visitador Médico',
      desc: 'Agenda visitas con médicos',
      icon: CalendarCheck,
      path: '/proveedor/visitador/planes',
      color: 'bg-emerald-50 text-emerald-600',
    },
    {
      title: 'Publicidad',
      desc: 'Crea y gestiona campañas',
      icon: Megaphone,
      path: '/proveedor/publicidad/planes',
      color: 'bg-amber-50 text-amber-600',
    },
    {
      title: 'Pagos',
      desc: 'Historial de pagos y comprobantes',
      icon: CreditCard,
      path: '/proveedor/pagos',
      color: 'bg-purple-50 text-purple-600',
    },
  ]

  const modulesVisitador = [
    {
      title: 'Mis Visitas',
      desc: 'Revisa tus visitas confirmadas y propuestas',
      icon: CalendarDays,
      path: '/proveedor/visitador/mis-visitas',
      color: 'bg-blue-50 text-blue-600',
    },
    {
      title: 'Agendar Visita',
      desc: 'Propón nuevas visitas con médicos',
      icon: CalendarCheck,
      path: '/proveedor/visitador/agendar',
      color: 'bg-emerald-50 text-emerald-600',
    },
    {
      title: 'Mi Ruta',
      desc: 'Visualiza tu ruta optimizada del día',
      icon: Route,
      path: '/proveedor/visitador/ruta',
      color: 'bg-amber-50 text-amber-600',
    },
    {
      title: 'Reporte',
      desc: 'Estadísticas de tus visitas completadas',
      icon: FileText,
      path: '/proveedor/visitador/reporte',
      color: 'bg-purple-50 text-purple-600',
    },
  ]

  const modules = esVisitador ? modulesVisitador : modulesAdmin

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
          <p className="text-sm text-muted-foreground">
            Bienvenido, {cuenta?.nombre_completo || 'Proveedor'}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {empresa?.estado === 'pendiente' && (
            <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-amber-50 text-amber-700 text-sm border border-amber-200">
              <AlertCircle className="h-4 w-4" />
              Cuenta en revisión
            </div>
          )}
          {empresa?.estado === 'activa' && (
            <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-emerald-50 text-emerald-700 text-sm border border-emerald-200">
              <TrendingUp className="h-4 w-4" />
              Cuenta activa
            </div>
          )}
        </div>
      </div>

      {/* Info empresa */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center gap-2">
            <MapPin className="h-5 w-5 text-[#1E5C8E]" />
            {empresa?.nombre_empresa || 'Empresa'}
          </CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <div>
            <p className="text-muted-foreground">Tipo</p>
            <p className="font-medium capitalize">{empresa?.tipo?.replace('_', ' ') || '-'}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Email</p>
            <p className="font-medium">{empresa?.email_contacto || '-'}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Teléfono</p>
            <p className="font-medium">{empresa?.telefono || '-'}</p>
          </div>
        </CardContent>
      </Card>

      {/* Módulos rápidos */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {modules.map((mod) => (
          <Link key={mod.path} to={mod.path}>
            <Card className="h-full hover:shadow-md transition-shadow cursor-pointer border hover:border-[#1E5C8E]/30">
              <CardContent className="p-6 flex flex-col items-start gap-4">
                <div className={`w-10 h-10 rounded-lg ${mod.color} flex items-center justify-center`}>
                  <mod.icon className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="font-semibold text-gray-900">{mod.title}</h3>
                  <p className="text-sm text-muted-foreground mt-1">{mod.desc}</p>
                </div>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>

      {/* Estadísticas reales */}
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" />
        </div>
      ) : stats ? (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">Resumen de actividad</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <Card>
              <CardContent className="p-5">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-muted-foreground">Productos activos</p>
                    <p className="text-2xl font-bold mt-1">{stats.productosActivos}</p>
                  </div>
                  <div className="w-10 h-10 rounded-lg bg-blue-50 text-blue-600 flex items-center justify-center">
                    <Boxes className="h-5 w-5" />
                  </div>
                </div>
                <p className="text-xs text-muted-foreground mt-2">de {stats.productosTotal} registrados</p>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-5">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-muted-foreground">Visitas esta semana</p>
                    <p className="text-2xl font-bold mt-1">{stats.visitasSemana}</p>
                  </div>
                  <div className="w-10 h-10 rounded-lg bg-emerald-50 text-emerald-600 flex items-center justify-center">
                    <MapPinCheck className="h-5 w-5" />
                  </div>
                </div>
                <p className="text-xs text-muted-foreground mt-2">
                  {stats.visitasHoy} hoy · {stats.visitasConfirmadas} confirmadas
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-5">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-muted-foreground">Campañas activas</p>
                    <p className="text-2xl font-bold mt-1">{stats.campanasAprobadas}</p>
                  </div>
                  <div className="w-10 h-10 rounded-lg bg-amber-50 text-amber-600 flex items-center justify-center">
                    <Megaphone className="h-5 w-5" />
                  </div>
                </div>
                <p className="text-xs text-muted-foreground mt-2">{stats.campanasEnviadas} en revisión</p>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-5">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-muted-foreground">Pagos pendientes</p>
                    <p className="text-2xl font-bold mt-1">{stats.pagosPendientes}</p>
                  </div>
                  <div className="w-10 h-10 rounded-lg bg-purple-50 text-purple-600 flex items-center justify-center">
                    <Banknote className="h-5 w-5" />
                  </div>
                </div>
                <p className="text-xs text-muted-foreground mt-2">{stats.pagosVerificados} verificados</p>
              </CardContent>
            </Card>
          </div>

          {/* Detalle de visitas */}
          {!esVisitador && (
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-base">Estado de visitas</CardTitle>
              </CardHeader>
              <CardContent className="pb-5">
                <div className="flex flex-wrap gap-2">
                  <Badge variant="secondary" className="bg-gray-100 text-gray-700">
                    Total: {stats.visitasTotal}
                  </Badge>
                  <Badge variant="secondary" className="bg-blue-50 text-blue-700">
                    Propuestas: {stats.visitasPropuestas}
                  </Badge>
                  <Badge variant="secondary" className="bg-emerald-50 text-emerald-700">
                    Confirmadas: {stats.visitasConfirmadas}
                  </Badge>
                  <Badge variant="secondary" className="bg-purple-50 text-purple-700">
                    Completadas: {stats.visitasCompletadas}
                  </Badge>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      ) : null}
    </div>
  )
}
