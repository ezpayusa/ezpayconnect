import { useNavigate } from 'react-router-dom'
import { useMedicoStats } from '@/medico/hooks/useMedicoStats'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  CalendarDays,
  Clock,
  Users,
  FileText,
  Stethoscope,
  AlertCircle,
  ChevronRight,
  Loader2,
} from 'lucide-react'

export default function MedicoDashboardPage() {
  const navigate = useNavigate()
  const { stats, loading } = useMedicoStats()

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  const statCards = [
    {
      title: 'Citas hoy',
      value: stats.citasHoy,
      icon: CalendarDays,
      color: 'bg-sky-50 text-sky-600',
      path: '/medico/citas',
    },
    {
      title: 'Pendientes',
      value: stats.pendientesCount,
      icon: AlertCircle,
      color: 'bg-amber-50 text-amber-600',
      path: '/medico/citas',
      alert: stats.pendientesCount > 0,
    },
    {
      title: 'Pacientes (mes)',
      value: stats.pacientesMes,
      icon: Users,
      color: 'bg-emerald-50 text-emerald-600',
      path: '/medico/pacientes',
    },
    {
      title: 'Recetas (mes)',
      value: stats.recetasMes,
      icon: FileText,
      color: 'bg-violet-50 text-violet-600',
      path: '/medico/recetas',
    },
  ]

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-[#1a2a3a] flex items-center gap-2">
          <Stethoscope className="h-7 w-7 text-[#1E5C8E]" />
          Portal del Médico
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Bienvenido de vuelta. Aquí está el resumen de tu actividad.
        </p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {statCards.map((card) => {
          const Icon = card.icon
          return (
            <Card
              key={card.title}
              className={`cursor-pointer transition-shadow hover:shadow-md ${card.alert ? 'ring-2 ring-amber-400' : ''}`}
              onClick={() => navigate(card.path)}
            >
              <CardContent className="p-5">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-muted-foreground">{card.title}</p>
                    <p className="text-3xl font-bold mt-1">{card.value}</p>
                  </div>
                  <div className={`p-3 rounded-lg ${card.color}`}>
                    <Icon className="w-6 h-6" />
                  </div>
                </div>
              </CardContent>
            </Card>
          )
        })}
      </div>

      {/* Próxima cita + Acciones rápidas */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Próxima cita */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <Clock className="h-5 w-5 text-[#1E5C8E]" />
              Próxima cita
            </CardTitle>
          </CardHeader>
          <CardContent>
            {stats.proximaCita ? (
              <div className="flex items-start justify-between">
                <div className="space-y-2">
                  <div className="flex items-center gap-3">
                    <Badge className="bg-blue-100 text-blue-700">
                      {new Date(stats.proximaCita.fecha).toLocaleDateString('es-GT', {
                        weekday: 'long', day: 'numeric', month: 'long',
                      })}
                    </Badge>
                    <Badge variant="outline">{stats.proximaCita.hora_inicio?.slice(0, 5)}</Badge>
                  </div>
                  <p className="text-lg font-semibold">
                    {stats.proximaCita.paciente
                      ? `${stats.proximaCita.paciente.nombre} ${stats.proximaCita.paciente.apellido}`
                      : 'Paciente'}
                  </p>
                  <p className="text-sm text-muted-foreground">
                    {stats.proximaCita.motivo || 'Consulta general'}
                  </p>
                  {stats.proximaCita.paciente?.telefono && (
                    <p className="text-sm text-muted-foreground">
                      Tel: {stats.proximaCita.paciente.telefono}
                    </p>
                  )}
                </div>
                <div className="flex flex-col gap-2">
                  <Button
                    size="sm"
                    className="bg-[#1E5C8E] hover:bg-[#164a70]"
                    onClick={() => navigate(`/consulta/${stats.proximaCita!.id}`)}
                  >
                    <Stethoscope className="h-4 w-4 mr-1" />
                    Atender
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => navigate('/medico/citas')}
                  >
                    Ver agenda
                    <ChevronRight className="h-4 w-4 ml-1" />
                  </Button>
                </div>
              </div>
            ) : (
              <div className="text-center py-8 text-muted-foreground">
                <CalendarDays className="h-10 w-10 mx-auto mb-3 text-gray-300" />
                <p>No tienes citas próximas programadas</p>
                <Button
                  variant="outline"
                  className="mt-3"
                  onClick={() => navigate('/medico/citas')}
                >
                  Ver mis citas
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Acciones rápidas */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Acciones rápidas</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={() => navigate('/medico/citas')}
            >
              <CalendarDays className="h-4 w-4 mr-2 text-sky-500" />
              Gestionar citas
            </Button>
            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={() => navigate('/medico/pacientes')}
            >
              <Users className="h-4 w-4 mr-2 text-emerald-500" />
              Ver pacientes
            </Button>
            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={() => navigate('/medico/recetas')}
            >
              <FileText className="h-4 w-4 mr-2 text-violet-500" />
              Nueva receta
            </Button>
            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={() => navigate('/medico/disponibilidad')}
            >
              <Clock className="h-4 w-4 mr-2 text-amber-500" />
              Configurar horarios
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
