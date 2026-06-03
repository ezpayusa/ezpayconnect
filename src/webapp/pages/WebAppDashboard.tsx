import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useWebAppCitas } from '@/webapp/hooks/useWebAppCitas'
import { useWebAppRecetas } from '@/webapp/hooks/useWebAppRecetas'
import { useWebAppExamenes } from '@/webapp/hooks/useWebAppExamenes'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { useNavigate } from 'react-router-dom'
import {
  CalendarDays, FileText, FlaskConical, MessageCircle, Plus, Clock, Pill,
  Loader2
} from 'lucide-react'

export default function WebAppDashboard() {
  const { perfil } = useWebAppAuth()
  const navigate = useNavigate()

  const { proximas: citasProximas, loading: loadingCitas } = useWebAppCitas(perfil?.id)
  const { activas: recetasActivas, loading: loadingRecetas } = useWebAppRecetas(perfil?.id)
  const { pendientes: examenesPendientes, loading: loadingExamenes } = useWebAppExamenes(perfil?.id)

  const proximaCita = citasProximas[0]

  const getEstadoBadge = (estado: string) => {
    switch (estado) {
      case 'agendada': return <Badge variant="outline" className="bg-sky-50 text-sky-700 border-sky-200">Agendada</Badge>
      case 'confirmada': return <Badge variant="outline" className="bg-emerald-50 text-emerald-700 border-emerald-200">Confirmada</Badge>
      case 'en_curso': return <Badge variant="outline" className="bg-amber-50 text-amber-700 border-amber-200">En curso</Badge>
      case 'pendiente': return <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-200">Pendiente</Badge>
      default: return <Badge variant="outline">{estado}</Badge>
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">
          {perfil ? `Hola, ${perfil.nombre}` : 'Bienvenido'}
        </h1>
        <p className="text-slate-500 mt-1">Aquí está el resumen de tu salud</p>
      </div>

      {/* Stats cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card className="bg-white border-slate-100 hover:shadow-md transition-shadow cursor-pointer" onClick={() => navigate('/paciente/citas')}>
          <CardContent className="p-4 flex flex-col items-center text-center">
            <div className="w-10 h-10 rounded-full bg-sky-50 flex items-center justify-center mb-2">
              <CalendarDays className="h-5 w-5 text-sky-500" />
            </div>
            <p className="text-2xl font-bold text-slate-800">
              {loadingCitas ? <Loader2 className="h-5 w-5 animate-spin mx-auto" /> : citasProximas.length}
            </p>
            <p className="text-xs text-slate-500">Próximas citas</p>
          </CardContent>
        </Card>
        <Card className="bg-white border-slate-100 hover:shadow-md transition-shadow cursor-pointer" onClick={() => navigate('/paciente/recetas')}>
          <CardContent className="p-4 flex flex-col items-center text-center">
            <div className="w-10 h-10 rounded-full bg-emerald-50 flex items-center justify-center mb-2">
              <FileText className="h-5 w-5 text-emerald-500" />
            </div>
            <p className="text-2xl font-bold text-slate-800">
              {loadingRecetas ? <Loader2 className="h-5 w-5 animate-spin mx-auto" /> : recetasActivas.length}
            </p>
            <p className="text-xs text-slate-500">Recetas activas</p>
          </CardContent>
        </Card>
        <Card className="bg-white border-slate-100 hover:shadow-md transition-shadow cursor-pointer" onClick={() => navigate('/paciente/examenes')}>
          <CardContent className="p-4 flex flex-col items-center text-center">
            <div className="w-10 h-10 rounded-full bg-amber-50 flex items-center justify-center mb-2">
              <FlaskConical className="h-5 w-5 text-amber-500" />
            </div>
            <p className="text-2xl font-bold text-slate-800">
              {loadingExamenes ? <Loader2 className="h-5 w-5 animate-spin mx-auto" /> : examenesPendientes.length}
            </p>
            <p className="text-xs text-slate-500">Exámenes pendientes</p>
          </CardContent>
        </Card>
        <Card className="bg-white border-slate-100 hover:shadow-md transition-shadow cursor-pointer" onClick={() => navigate('/paciente/chat')}>
          <CardContent className="p-4 flex flex-col items-center text-center">
            <div className="w-10 h-10 rounded-full bg-indigo-50 flex items-center justify-center mb-2">
              <MessageCircle className="h-5 w-5 text-indigo-500" />
            </div>
            <p className="text-2xl font-bold text-slate-800">--</p>
            <p className="text-xs text-slate-500">Mensajes</p>
          </CardContent>
        </Card>
      </div>

      {/* Quick actions */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card className="bg-gradient-to-br from-sky-500 to-indigo-500 text-white border-0">
          <CardContent className="p-6">
            <h3 className="font-semibold text-lg">¿Necesitas una cita?</h3>
            <p className="text-sky-100 text-sm mt-1 mb-4">Agenda tu próxima consulta médica en minutos</p>
            <Button
              variant="secondary"
              size="sm"
              className="bg-white text-sky-600 hover:bg-sky-50"
              onClick={() => navigate('/paciente/citas')}
            >
              <Plus className="h-4 w-4 mr-1" /> Agendar cita
            </Button>
          </CardContent>
        </Card>
        <Card className="bg-white border-slate-100">
          <CardContent className="p-6">
            <h3 className="font-semibold text-slate-800">Próxima cita</h3>
            {proximaCita ? (
              <div className="mt-3 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-slate-700">
                    {proximaCita.motivo || 'Consulta médica'}
                  </span>
                  {getEstadoBadge(proximaCita.estado)}
                </div>
                <div className="flex items-center gap-2 text-slate-500 text-sm">
                  <CalendarDays className="h-4 w-4" />
                  <span>
                    {new Date(proximaCita.fecha).toLocaleDateString('es-GT', {
                      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
                    })}
                  </span>
                </div>
                <div className="flex items-center gap-2 text-slate-500 text-sm">
                  <Clock className="h-4 w-4" />
                  <span>{proximaCita.hora_inicio?.slice(0, 5)}</span>
                </div>
                <div className="flex items-center gap-2 text-slate-500 text-sm">
                  <Pill className="h-4 w-4" />
                  <span>Dr. {proximaCita.medico_nombre}</span>
                </div>
              </div>
            ) : (
              <div className="flex items-center gap-3 mt-3 text-slate-500">
                <Clock className="h-5 w-5" />
                <span className="text-sm">No tienes citas programadas</span>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
