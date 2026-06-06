import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Link } from 'react-router-dom'
import {
  Building2,
  Package,
  CalendarCheck,
  Megaphone,
  CreditCard,
  TrendingUp,
  AlertCircle,
  CalendarDays,
  Route,
  FileText,
} from 'lucide-react'

export default function ProveedorDashboard() {
  const { empresa, cuenta } = useProveedorAuth()
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
            <Building2 className="h-5 w-5 text-[#1E5C8E]" />
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

      {/* Placeholder para estadísticas futuras */}
      <Card className="bg-gray-50 border-dashed">
        <CardContent className="p-8 text-center">
          <TrendingUp className="h-10 w-10 text-gray-300 mx-auto mb-3" />
          <h3 className="text-lg font-semibold text-gray-700">Estadísticas próximamente</h3>
          <p className="text-sm text-muted-foreground max-w-md mx-auto mt-1">
            Aquí verás métricas de tus productos, visitas agendadas y campañas publicitarias.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
