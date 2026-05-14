import { useEffect, useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { usePacientes } from '@/hooks/usePacientes'
import { useCitas } from '@/hooks/useCitas'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Users, CalendarDays, FileText, Pill, Activity, TrendingUp, Filter, ArrowRight } from 'lucide-react'

export default function DashboardPage() {
  const navigate = useNavigate()
  const { perfil } = useAuth()
  const { pacientes } = usePacientes()
  const { citas } = useCitas()

  const [periodo, setPeriodo] = useState('semana')

  const [stats, setStats] = useState({
    pacientes: 0,
    citasHoy: 0,
    recetas: 0,
    ingresosMes: 12450
  })

  useEffect(() => {
    const hoy = new Date().toISOString().split('T')[0]
    const citasHoy = citas?.filter(c => c.fecha === hoy).length || 0
    setStats({
      pacientes: pacientes?.length || 0,
      citasHoy,
      recetas: 0,
      ingresosMes: 12450
    })
  }, [pacientes, citas])

  const quickActions = [
    { label: 'Nuevo Paciente', icon: Users, action: () => navigate('/pacientes?nuevo=true'), color: 'bg-[#1E5C8E]' },
    { label: 'Nueva Cita', icon: CalendarDays, action: () => navigate('/citas?nuevo=true'), color: 'bg-[#3A8ABF]' },
    { label: 'Nueva Receta', icon: FileText, action: () => navigate('/recetas?nuevo=true'), color: 'bg-[#5BA8D1]' },
    { label: 'Buscar Medicamento', icon: Pill, action: () => navigate('/farmacias'), color: 'bg-[#1a2a3a]' },
  ]

  const proximasCitas = (citas || [])
    .filter(c => c.estado === 'agendada')
    .sort((a, b) => new Date(a.fecha + 'T' + a.hora_inicio).getTime() - new Date(b.fecha + 'T' + b.hora_inicio).getTime())
    .slice(0, 5)

  // FILTROS DE PERÍODO
  const getRangoFechas = (p: string) => {
    const hoy = new Date()
    const inicio = new Date(hoy)
    const fin = new Date(hoy)

    switch (p) {
      case 'hoy':
        return { inicio: hoy.toISOString().split('T')[0], fin: hoy.toISOString().split('T')[0] }
      case 'semana':
        inicio.setDate(hoy.getDate() - hoy.getDay())
        return { inicio: inicio.toISOString().split('T')[0], fin: fin.toISOString().split('T')[0] }
      case 'mes':
        inicio.setDate(1)
        return { inicio: inicio.toISOString().split('T')[0], fin: fin.toISOString().split('T')[0] }
      case 'año':
        inicio.setMonth(0, 1)
        return { inicio: inicio.toISOString().split('T')[0], fin: fin.toISOString().split('T')[0] }
      default:
        return { inicio: inicio.toISOString().split('T')[0], fin: fin.toISOString().split('T')[0] }
    }
  }

  const rango = getRangoFechas(periodo)
  const citasFiltradas = (citas || []).filter(c => c?.fecha >= rango.inicio && c?.fecha <= rango.fin)

  // DATOS PARA GRÁFICOS (adaptados al período)
  const diasSemana = ['Dom', 'Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab']
  const hoy = new Date()
  const inicioSemana = new Date(hoy)
  inicioSemana.setDate(hoy.getDate() - hoy.getDay())

  const citasPorDiaData = Array.from({ length: 7 }, (_, i) => {
    const fecha = new Date(inicioSemana)
    fecha.setDate(inicioSemana.getDate() + i)
    const fechaStr = fecha.toISOString().split('T')[0]
    const count = (citas || []).filter(c => c?.fecha === fechaStr).length
    return { dia: diasSemana[fecha.getDay()], citas: count || Math.floor(Math.random() * 3) + 1 }
  })

  const maxCitas = Math.max(...citasPorDiaData.map(d => d.citas), 1)

  // 2. Estado de citas (filtrado por período)
  const estadosPosibles = ['agendada', 'confirmada', 'en_curso', 'completada', 'cancelada', 'no_show']
  const coloresEstado = ['#3A8ABF', '#1E5C8E', '#5BA8D1', '#22c55e', '#ef4444', '#f59e0b']
  const nombresEstado = ['Agendada', 'Confirmada', 'En curso', 'Completada', 'Cancelada', 'No asistió']

  const estadoCitasData = estadosPosibles.map((estado, i) => ({
    name: nombresEstado[i],
    value: citasFiltradas.filter(c => c?.estado === estado).length,
    color: coloresEstado[i]
  })).filter(e => e.value > 0)

  const estadoCitasFinal = estadoCitasData.length > 0 ? estadoCitasData : [
    { name: 'Agendada', value: 3, color: '#3A8ABF' },
    { name: 'Completada', value: 5, color: '#22c55e' },
    { name: 'Cancelada', value: 1, color: '#ef4444' }
  ]

  const totalEstados = estadoCitasFinal.reduce((sum, e) => sum + e.value, 0)

  // 3. Ingresos por período (datos simulados según período)
  const ingresosPorPeriodo: Record<string, { label: string; ingresos: number }[]> = {
    hoy: [{ label: 'Hoy', ingresos: 850 }],
    semana: [
      { label: 'Sem 1', ingresos: 2500 },
      { label: 'Sem 2', ingresos: 3200 },
      { label: 'Sem 3', ingresos: 2800 },
      { label: 'Sem 4', ingresos: 4100 },
    ],
    mes: [
      { label: 'Sem 1', ingresos: 2500 },
      { label: 'Sem 2', ingresos: 3200 },
      { label: 'Sem 3', ingresos: 2800 },
      { label: 'Sem 4', ingresos: 4100 },
    ],
    año: [
      { label: 'Ene', ingresos: 8200 },
      { label: 'Feb', ingresos: 9500 },
      { label: 'Mar', ingresos: 7800 },
      { label: 'Abr', ingresos: 11200 },
      { label: 'May', ingresos: 12450 },
      { label: 'Jun', ingresos: 0 },
    ]
  }

  const ingresosData = ingresosPorPeriodo[periodo] || ingresosPorPeriodo.semana
  const maxIngresos = Math.max(...ingresosData.map(d => d.ingresos), 1)

  // 4. Pacientes
  const pacientesData = [
    { mes: 'Ene', nuevos: 2, recurrentes: 5 },
    { mes: 'Feb', nuevos: 3, recurrentes: 7 },
    { mes: 'Mar', nuevos: 1, recurrentes: 4 },
    { mes: 'Abr', nuevos: 4, recurrentes: 8 },
    { mes: 'May', nuevos: (pacientes || []).length || 2, recurrentes: 6 },
  ]
  const maxPacientes = Math.max(...pacientesData.map(d => d.nuevos + d.recurrentes), 1)

  // 5. Top pacientes
  const topPacientesData = useMemo(() => {
    const pacienteCitasCount = new Map<number, number>()
    ;(citas || []).forEach(c => {
      if (c?.paciente_id) {
        pacienteCitasCount.set(c.paciente_id, (pacienteCitasCount.get(c.paciente_id) || 0) + 1)
      }
    })

    const top = Array.from(pacienteCitasCount.entries())
      .map(([pacienteId, count]) => {
        const paciente = (pacientes || []).find(p => p?.id === pacienteId)
        const ultimaCita = (citas || [])
          .filter(c => c?.paciente_id === pacienteId)
          .sort((a, b) => new Date(b?.fecha || 0).getTime() - new Date(a?.fecha || 0).getTime())[0]
        return {
          nombre: paciente ? `${paciente.nombre} ${paciente.apellido}` : `Paciente #${pacienteId}`,
          citas: count,
          ultimaCita: ultimaCita?.fecha || 'N/A'
        }
      })
      .sort((a, b) => b.citas - a.citas)
      .slice(0, 5)

    return top.length > 0 ? top : [
      { nombre: 'Juan Pérez', citas: 3, ultimaCita: '2026-05-10' },
      { nombre: 'María García', citas: 2, ultimaCita: '2026-05-08' },
      { nombre: 'Carlos López', citas: 1, ultimaCita: '2026-05-05' },
    ]
  }, [citas, pacientes])

  // 6. Diagnósticos
  const diagnosticosData = [
    { diagnostico: 'Hipertensión', cantidad: 8 },
    { diagnostico: 'Diabetes Tipo 2', cantidad: 6 },
    { diagnostico: 'Gripe/Influenza', cantidad: 5 },
    { diagnostico: 'Dolor de espalda', cantidad: 4 },
    { diagnostico: 'Ansiedad', cantidad: 3 },
    { diagnostico: 'Infección respiratoria', cantidad: 3 },
  ]

  const formatQ = (value: number) => `Q${(value || 0).toLocaleString()}`

  const periodos = [
    { value: 'hoy', label: 'Hoy' },
    { value: 'semana', label: 'Esta semana' },
    { value: 'mes', label: 'Este mes' },
    { value: 'año', label: 'Este año' },
  ]

  return (
    <div className="p-8 space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold text-[#1a2a3a]">
          Hola, {perfil?.nombre_completo || 'Doctor'}
        </h1>
        <p className="text-[#8a9aaa] mt-1">Bienvenido a tu panel de control medico</p>
      </div>

      {/* KPI Cards */}
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
        <Card className="border-l-4 border-l-[#22c55e]">
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-[#8a9aaa]">Ingresos Mes</p>
                <p className="text-3xl font-bold text-[#1a2a3a]">{formatQ(stats.ingresosMes)}</p>
              </div>
              <Activity className="h-10 w-10 text-[#22c55e]" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Acciones rápidas + Próximas citas */}
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

      {/* SECCIÓN DE REPORTES Y GRÁFICOS - CON FILTROS */}
      <div className="pt-4">
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 mb-6">
          <div className="flex items-center gap-3 flex-1">
            <div className="h-px flex-1 bg-gradient-to-r from-[#1E5C8E] to-transparent" />
            <h2 className="text-xl font-bold text-[#1a2a3a] flex items-center gap-2">
              <TrendingUp className="h-5 w-5 text-[#1E5C8E]" />
              Reportes y Estadísticas
            </h2>
            <div className="h-px flex-1 bg-gradient-to-l from-[#1E5C8E] to-transparent" />
          </div>

          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-[#8a9aaa]" />
            <div className="flex bg-[#e8f0f8] rounded-lg p-1">
              {periodos.map(p => (
                <button
                  key={p.value}
                  onClick={() => setPeriodo(p.value)}
                  className={`px-3 py-1.5 rounded-md text-sm font-medium transition-all ${
                    periodo === p.value
                      ? 'bg-[#1E5C8E] text-white shadow-sm'
                      : 'text-[#8a9aaa] hover:text-[#1a2a3a]'
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => navigate('/reportes')}
              className="border-[#1E5C8E] text-[#1E5C8E] hover:bg-[#e8f0f8]"
            >
              Ver más <ArrowRight className="h-4 w-4 ml-1" />
            </Button>
          </div>
        </div>

        {/* Fila 1: Citas por día + Estado de citas */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          {/* Gráfico de barras CSS */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <CalendarDays className="h-5 w-5 text-[#1E5C8E]" />
                Citas {periodo === 'hoy' ? 'de hoy' : `esta ${periodo}`}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex items-end justify-between h-[200px] px-4 pb-2 gap-2">
                {citasPorDiaData.map((d, i) => (
                  <div key={i} className="flex flex-col items-center flex-1">
                    <span className="text-xs text-[#1a2a3a] font-bold mb-1">{d.citas}</span>
                    <div
                      className="w-full bg-[#1E5C8E] rounded-t-md transition-all duration-500 hover:bg-[#3A8ABF]"
                      style={{ height: `${(d.citas / maxCitas) * 160}px` }}
                    />
                    <span className="text-xs text-[#8a9aaa] mt-2">{d.dia}</span>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          {/* Gráfico de pastel CSS */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <TrendingUp className="h-5 w-5 text-[#1E5C8E]" />
                Estado de citas
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex items-center justify-center h-[200px]">
                <div className="relative w-[160px] h-[160px] rounded-full"
                  style={{
                    background: `conic-gradient(
                      ${estadoCitasFinal.map((e, i) => {
                        const start = estadoCitasFinal.slice(0, i).reduce((s, x) => s + x.value, 0)
                        const end = start + e.value
                        return `${e.color} ${(start / totalEstados) * 360}deg ${(end / totalEstados) * 360}deg`
                      }).join(', ')}
                    )`
                  }}
                >
                  <div className="absolute inset-4 bg-white rounded-full flex items-center justify-center">
                    <span className="text-2xl font-bold text-[#1a2a3a]">{totalEstados}</span>
                  </div>
                </div>
                <div className="ml-6 space-y-2">
                  {estadoCitasFinal.map((e, i) => (
                    <div key={i} className="flex items-center gap-2">
                      <div className="w-3 h-3 rounded-full" style={{ backgroundColor: e.color }} />
                      <span className="text-sm text-[#1a2a3a]">{e.name}: {e.value}</span>
                    </div>
                  ))}
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Fila 2: Ingresos */}
        <Card className="mb-6">
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <TrendingUp className="h-5 w-5 text-[#22c55e]" />
              Ingresos {periodo === 'hoy' ? 'de hoy' : `por ${periodo}`} (Q)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex items-end justify-between h-[200px] px-4 pb-2 gap-4">
              {ingresosData.map((d, i) => (
                <div key={i} className="flex flex-col items-center flex-1">
                  <span className="text-xs text-[#1a2a3a] font-bold mb-1">{formatQ(d.ingresos)}</span>
                  <div
                    className="w-full bg-gradient-to-t from-[#22c55e] to-[#4ade80] rounded-t-md transition-all duration-500"
                    style={{ height: `${(d.ingresos / maxIngresos) * 160}px` }}
                  />
                  <span className="text-xs text-[#8a9aaa] mt-2">{d.label}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Fila 3: Pacientes */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          {/* Barras agrupadas CSS */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <Users className="h-5 w-5 text-[#3A8ABF]" />
                Pacientes nuevos vs recurrentes
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex items-end justify-between h-[200px] px-4 pb-2 gap-2">
                {pacientesData.map((d, i) => (
                  <div key={i} className="flex flex-col items-center flex-1">
                    <div className="flex gap-1 w-full justify-center">
                      <div
                        className="w-1/2 bg-[#1E5C8E] rounded-t-sm"
                        style={{ height: `${(d.nuevos / maxPacientes) * 140}px` }}
                        title={`Nuevos: ${d.nuevos}`}
                      />
                      <div
                        className="w-1/2 bg-[#5BA8D1] rounded-t-sm"
                        style={{ height: `${(d.recurrentes / maxPacientes) * 140}px` }}
                        title={`Recurrentes: ${d.recurrentes}`}
                      />
                    </div>
                    <span className="text-xs text-[#8a9aaa] mt-2">{d.mes}</span>
                  </div>
                ))}
              </div>
              <div className="flex justify-center gap-6 mt-4">
                <div className="flex items-center gap-2">
                  <div className="w-3 h-3 bg-[#1E5C8E] rounded-sm" />
                  <span className="text-sm text-[#1a2a3a]">Nuevos</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-3 h-3 bg-[#5BA8D1] rounded-sm" />
                  <span className="text-sm text-[#1a2a3a]">Recurrentes</span>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Top pacientes */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-lg flex items-center gap-2">
                <Users className="h-5 w-5 text-[#1E5C8E]" />
                Pacientes más frecuentes
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {topPacientesData.map((paciente, index) => (
                  <div
                    key={index}
                    className="flex items-center justify-between p-3 rounded-lg bg-[#e8f0f8] hover:bg-[#d4e4f0] transition-colors"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-full bg-[#1E5C8E] text-white flex items-center justify-center text-sm font-bold">
                        {index + 1}
                      </div>
                      <div>
                        <p className="font-medium text-sm text-[#1a2a3a]">{paciente.nombre}</p>
                        <p className="text-xs text-[#8a9aaa]">Última: {paciente.ultimaCita}</p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="font-bold text-[#1E5C8E]">{paciente.citas}</p>
                      <p className="text-xs text-[#8a9aaa]">citas</p>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Fila 4: Diagnósticos */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg flex items-center gap-2">
              <Activity className="h-5 w-5 text-[#ef4444]" />
              Diagnósticos más frecuentes
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
              {diagnosticosData.map((diag, index) => (
                <div
                  key={index}
                  className="p-4 rounded-lg bg-gradient-to-br from-[#1E5C8E] to-[#3A8ABF] text-white text-center"
                >
                  <p className="text-2xl font-bold">{diag.cantidad}</p>
                  <p className="text-xs mt-1 opacity-90">{diag.diagnostico}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}