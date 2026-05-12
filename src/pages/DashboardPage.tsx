import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { usePacientes } from '@/hooks/usePacientes'
import { useCitas } from '@/hooks/useCitas'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Users, CalendarDays, FileText, Pill, Activity } from 'lucide-react'

export default function DashboardPage() {
  const navigate = useNavigate()
  const { perfil } = useAuth()
  const { pacientes } = usePacientes()
  const { citas } = useCitas()
  const [stats, setStats] = useState({ pacientes: 0, citasHoy: 0, recetas: 0, medicamentos: 0 })

  useEffect(() => {
    const hoy = new Date().toISOString().split('T')[0]
    const citasHoy = citas.filter(c => c.fecha === hoy).length
    setStats({
      pacientes: pacientes.length,
      citasHoy,
      recetas: 0,
      medicamentos: 0
    })
  }, [pacientes, citas])

  const quickActions = [
    { label: 'Nuevo Paciente', icon: Users, action: () => navigate('/pacientes?nuevo=true'), color: 'bg-[#1E5C8E]' },
    { label: 'Nueva Cita', icon: CalendarDays, action: () => navigate('/citas?nuevo=true'), color: 'bg-[#3A8ABF]' },
    { label: 'Nueva Receta', icon: FileText, action: () => navigate('/recetas?nuevo=true'), color: 'bg-[#5BA8D1]' },
    { label: 'Buscar Medicamento', icon: Pill, action: () => navigate('/farmacias'), color: 'bg-[#1a2a3a]' },
  ]

  const proximasCitas = citas
    .filter(c => c.estado === 'agendada')
    .sort((a, b) => new Date(a.fecha + 'T' + a.hora_inicio).getTime() - new Date(b.fecha + 'T' + b.hora_inicio).getTime())
    .slice(0, 5)

  return (
    <div className="p-8 space-y-8">
      <div>
        <h1 className="text-3xl font-bold text-[#1a2a3a]">
          Hola, {perfil?.nombre_completo || 'Doctor'}
        </h1>
        <p className="text-[#8a9aaa] mt-1">Bienvenido a tu panel de control medico</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Pacientes</p>
                <p className="text-3xl font-bold text-[#1a2a3a]">{stats.pacientes}</p>
              </div>
              <Users className="h-10 w-10 text-[#1E5C8E]" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#3A8ABF]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Citas Hoy</p>
                <p className="text-3xl font-bold text-[#1a2a3a]">{stats.citasHoy}</p>
              </div>
              <CalendarDays className="h-10 w-10 text-[#3A8ABF]" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#5BA8D1]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Recetas</p>
                <p className="text-3xl font-bold text-[#1a2a3a]">{stats.recetas}</p>
              </div>
              <FileText className="h-10 w-10 text-[#5BA8D1]" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-[#1a2a3a]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Actividad</p>
                <p className="text-3xl font-bold text-[#1a2a3a]">Activa</p>
              </div>
              <Activity className="h-10 w-10 text-[#1a2a3a]" />
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Acciones Rapidas</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 gap-4">
                {quickActions.map((action) => (
                  <Button
                    key={action.label}
                    onClick={action.action}
                    className={`${action.color} hover:opacity-90 h-20 text-base flex flex-col items-center gap-2`}
                  >
                    <action.icon className="h-6 w-6" />
                    {action.label}
                  </Button>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <CalendarDays className="h-5 w-5 text-[#1E5C8E]" />
              Proximas Citas
            </CardTitle>
          </CardHeader>
          <CardContent>
            {proximasCitas.length === 0 ? (
              <p className="text-[#8a9aaa] text-sm text-center py-4">No hay citas programadas</p>
            ) : (
              <div className="space-y-3">
                {proximasCitas.map((cita) => (
                  <div key={cita.id} className="flex items-center gap-3 p-3 rounded-lg bg-[#e8f0f8]">
                    <div className="text-center min-w-[60px]">
                      <p className="text-xs text-[#8a9aaa]">{cita.fecha}</p>
                      <p className="font-bold text-[#1E5C8E]">{cita.hora_inicio}</p>
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm truncate">{cita.motivo || 'Consulta'}</p>
                      <p className="text-xs text-[#8a9aaa]">{cita.notas}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
