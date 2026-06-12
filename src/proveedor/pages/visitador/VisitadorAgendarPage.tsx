import { useState, useEffect } from 'react'
import type { VisitaTipo } from '@/proveedor/types/proveedor.types'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'
import { useMedicosDisponibles } from '@/proveedor/hooks/useMedicosDisponibles'
import { useVisitasAgendadas } from '@/proveedor/hooks/useVisitasAgendadas'
import { usePlanesVisitador } from '@/proveedor/hooks/usePlanesVisitador'
import { toast } from 'sonner'
import {
  Search,
  CalendarDays,
  Clock,
  ArrowLeft,
  Loader2,
  Stethoscope,
  CheckCircle,
  ChevronLeft,
  ChevronRight,
  Lock,
  Send,
} from 'lucide-react'
import { Label } from '@/components/ui/label'
import { startOfWeek, addDays, format, startOfDay } from 'date-fns'
import { es } from 'date-fns/locale'

const DIAS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']
const TIPOS_VISITA = [
  { value: 'presentacion_producto', label: 'Presentación de producto' },
  { value: 'capacitacion', label: 'Capacitación' },
  { value: 'muestra_gratis', label: 'Muestra gratis' },
  { value: 'pedido', label: 'Toma de pedido' },
  { value: 'otro', label: 'Otro' },
]

interface SlotGenerado {
  fecha: string // yyyy-MM-dd
  fechaVisual: string // Lun 09/06
  diaSemana: number
  inicio: string // HH:mm
  fin: string // HH:mm
  duracion: number
  ocupado: boolean
}

export default function VisitadorAgendarPage() {
  const navigate = useNavigate()
  const { medicos, disponibilidad, loading, buscarMedicos, fetchDisponibilidadMedico } = useMedicosDisponibles()
  const { agendarVisita, saving, fetchSlotsOcupados } = useVisitasAgendadas()
  const { visitasDisponibles } = usePlanesVisitador()

  const [query, setQuery] = useState('')
  const [medicoSeleccionado, setMedicoSeleccionado] = useState<string | null>(null)
  const [slotSeleccionado, setSlotSeleccionado] = useState<SlotGenerado | null>(null)
  const [tipoVisita, setTipoVisita] = useState<VisitaTipo>('presentacion_producto')
  const [notas, setNotas] = useState('')
  const [semanaOffset, setSemanaOffset] = useState(0)
  const [planEstado, setPlanEstado] = useState<{ tiene_plan: boolean; cupo: number; ilimitado: boolean; usadas_mes: number } | null>(null)

  useEffect(() => {
    supabase.rpc('estado_plan_visitas').then(({ data }) => {
      if (data && data[0]) setPlanEstado(data[0])
    })
  }, [])
  const [slotsGenerados, setSlotsGenerados] = useState<SlotGenerado[]>([])
  const [cargandoSlots, setCargandoSlots] = useState(false)

  const handleBuscar = (e: React.FormEvent) => {
    e.preventDefault()
    buscarMedicos(query)
  }

  const generarSlots = async (medicoId: string, disp: typeof disponibilidad, offset: number) => {
    setCargandoSlots(true)

    const hoy = new Date()
    const lunes = startOfWeek(addDays(hoy, offset * 7), { weekStartsOn: 1 })
    const domingo = addDays(lunes, 6)

    const fechaInicioStr = format(lunes, 'yyyy-MM-dd')
    const fechaFinStr = format(domingo, 'yyyy-MM-dd')

    const ocupados = await fetchSlotsOcupados(medicoId, fechaInicioStr, fechaFinStr)

    const slots: SlotGenerado[] = []

    for (let i = 0; i < 7; i++) {
      const fecha = addDays(lunes, i)
      // No mostrar slots de fechas pasadas (antes de hoy)
      if (fecha < startOfDay(hoy)) continue
      const diaSemana = fecha.getDay()
      const dispDia = disp.filter((d) => d.dia_semana === diaSemana && d.activo)
      const fechaStr = format(fecha, 'yyyy-MM-dd')
      const fechaVisual = format(fecha, 'EEE dd/MM', { locale: es })

      for (const d of dispDia) {
        const [hInicio, mInicio] = d.hora_inicio.split(':').map(Number)
        const [hFin, mFin] = d.hora_fin.split(':').map(Number)
        const inicioMin = hInicio * 60 + mInicio
        const finMin = hFin * 60 + mFin
        const duracion = d.duracion_slot

        for (let t = inicioMin; t < finMin; t += duracion) {
          const slotInicio = `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`
          const slotFin = `${String(Math.floor((t + duracion) / 60)).padStart(2, '0')}:${String((t + duracion) % 60).padStart(2, '0')}`

          const estaOcupado = ocupados.some(
            (o) => o.fecha_visita === fechaStr && o.hora_inicio === slotInicio && o.hora_fin === slotFin
          )

          slots.push({
            fecha: fechaStr,
            fechaVisual: fechaVisual.charAt(0).toUpperCase() + fechaVisual.slice(1),
            diaSemana,
            inicio: slotInicio,
            fin: slotFin,
            duracion,
            ocupado: estaOcupado,
          })
        }
      }
    }

    setSlotsGenerados(slots)
    setCargandoSlots(false)
  }

  const seleccionarMedico = async (id: string) => {
    setMedicoSeleccionado(id)
    setSlotSeleccionado(null)
    await fetchDisponibilidadMedico(id)
  }

  const cambiarSemana = async (direccion: number) => {
    const nuevoOffset = semanaOffset + direccion
    setSemanaOffset(nuevoOffset)
    if (medicoSeleccionado && disponibilidad.length > 0) {
      await generarSlots(medicoSeleccionado, disponibilidad, nuevoOffset)
    }
  }



  const handleAgendar = async () => {
    if (!medicoSeleccionado || !slotSeleccionado) {
      toast.error('Selecciona un horario')
      return
    }

    // El visitador propone; el admin confirma. No bloqueamos por visitasDisponibles aquí.
    const ok = await agendarVisita({
      medico_id: medicoSeleccionado,
      fecha_visita: slotSeleccionado.fecha,
      hora_inicio: slotSeleccionado.inicio,
      hora_fin: slotSeleccionado.fin,
      tipo_visita: tipoVisita,
      notas_empresa: notas,
    })

    if (ok) {
      toast.success('Visita propuesta. Tu administrador la revisará pronto.')
      navigate('/proveedor/visitador/mis-visitas')
    } else {
      // Pudo haber sido tomado por otro proveedor: limpiar selección y refrescar slots.
      setSlotSeleccionado(null)
      if (medicoSeleccionado) generarSlots(medicoSeleccionado, disponibilidad, semanaOffset)
    }
  }

  // Regenerar slots cuando cambia disponibilidad
  useEffect(() => {
    if (medicoSeleccionado && disponibilidad.length > 0) {
      generarSlots(medicoSeleccionado, disponibilidad, semanaOffset)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [disponibilidad, medicoSeleccionado, semanaOffset])

  const slotsPorFecha = slotsGenerados.reduce((acc: Record<string, SlotGenerado[]>, s) => {
    if (!acc[s.fechaVisual]) acc[s.fechaVisual] = []
    acc[s.fechaVisual].push(s)
    return acc
  }, {})

  const lunesActual = startOfWeek(addDays(new Date(), semanaOffset * 7), { weekStartsOn: 1 })
  const domingoActual = addDays(lunesActual, 6)
  const rangoTexto = `${format(lunesActual, 'dd/MM')} – ${format(domingoActual, 'dd/MM')}`

  return (
    <div className="space-y-6 max-w-5xl mx-auto">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/proveedor/visitador/planes')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Agendar Visita</h1>
          <p className="text-sm text-muted-foreground">Busca un médico y selecciona un horario</p>
        </div>
      </div>

      {/* Estado del plan de visitas */}
      {planEstado && (
        planEstado.tiene_plan ? (
          !planEstado.ilimitado && (
            <Card className={planEstado.usadas_mes >= planEstado.cupo ? 'border-red-300 bg-red-50' : 'bg-slate-50'}>
              <CardContent className="p-3 text-sm flex items-center justify-between">
                <span>Visitas de este mes: <strong>{planEstado.usadas_mes} / {planEstado.cupo}</strong></span>
                {planEstado.usadas_mes >= planEstado.cupo && (
                  <span className="text-red-600 font-medium">Límite alcanzado · mejora tu plan</span>
                )}
              </CardContent>
            </Card>
          )
        ) : (
          <Card className="border-amber-300 bg-amber-50">
            <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div className="text-sm text-amber-800">
                <p className="font-semibold">Tu empresa no tiene un plan de visitas activo.</p>
                <p>Contrata un plan para poder agendar visitas con médicos.</p>
              </div>
              <Button className="bg-[#1E5C8E] hover:bg-[#164a70]" onClick={() => navigate('/proveedor/visitador/planes')}>
                Ver planes
              </Button>
            </CardContent>
          </Card>
        )
      )}

      {/* Buscador médicos */}
      <Card>
        <CardContent className="pt-6">
          <form onSubmit={handleBuscar} className="flex gap-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Nombre del médico..."
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="pl-9"
              />
            </div>
            <Button type="submit" disabled={loading} className="bg-[#1E5C8E] hover:bg-[#164a70]">
              {loading ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Search className="h-4 w-4 mr-1" />}
              Buscar
            </Button>
          </form>
        </CardContent>
      </Card>

      {/* Lista médicos */}
      {medicos.length > 0 && !medicoSeleccionado && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {medicos.map((m) => (
            <Card
              key={m.id}
              className="cursor-pointer hover:border-[#1E5C8E] transition-colors"
              onClick={() => seleccionarMedico(m.id)}
            >
              <CardContent className="p-4 flex items-center justify-between gap-4">
                <div className="flex items-center gap-4 min-w-0">
                  <div className="w-12 h-12 rounded-full bg-[#1E5C8E]/10 flex items-center justify-center flex-shrink-0">
                    <Stethoscope className="h-6 w-6 text-[#1E5C8E]" />
                  </div>
                  <div className="min-w-0">
                    <h3 className="font-semibold truncate">{m.nombre_completo}</h3>
                    <p className="text-sm text-muted-foreground truncate">{m.email}</p>
                  </div>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  className="flex-shrink-0"
                  onClick={(e) => {
                    e.stopPropagation()
                    seleccionarMedico(m.id)
                  }}
                >
                  Seleccionar
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Disponibilidad del médico seleccionado */}
      {medicoSeleccionado && (
        <div className="space-y-4">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <h2 className="text-lg font-semibold">Horarios disponibles</h2>
            <Button variant="ghost" size="sm" onClick={() => { setMedicoSeleccionado(null); setSlotSeleccionado(null); setSlotsGenerados([]) }}>
              Cambiar médico
            </Button>
          </div>

          {/* Navegación de semanas */}
          <div className="flex items-center justify-between bg-white rounded-lg border p-3">
            <Button variant="outline" size="sm" onClick={() => cambiarSemana(-1)}>
              <ChevronLeft className="h-4 w-4 mr-1" />
              Semana anterior
            </Button>
            <div className="flex items-center gap-2 text-sm font-medium">
              <CalendarDays className="h-4 w-4 text-[#1E5C8E]" />
              {rangoTexto}
            </div>
            <Button variant="outline" size="sm" onClick={() => cambiarSemana(1)}>
              Semana siguiente
              <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          </div>

          {disponibilidad.length === 0 ? (
            <Card className="bg-gray-50 border-dashed">
              <CardContent className="p-6 text-center text-muted-foreground">
                <Clock className="h-8 w-8 mx-auto mb-2 text-gray-300" />
                Este médico no tiene horarios configurados para visitas.
              </CardContent>
            </Card>
          ) : cargandoSlots ? (
            <div className="flex justify-center py-12">
              <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
            </div>
          ) : slotsGenerados.length === 0 ? (
            <Card className="bg-gray-50 border-dashed">
              <CardContent className="p-6 text-center text-muted-foreground">
                <CalendarDays className="h-8 w-8 mx-auto mb-2 text-gray-300" />
                <p>No hay horarios disponibles en esta semana.</p>
                <p className="text-sm mt-1">Prueba con <strong>"Semana siguiente"</strong> arriba.</p>
              </CardContent>
            </Card>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              {Object.entries(slotsPorFecha).map(([fechaVisual, slots]) => (
                <Card key={fechaVisual}>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium flex items-center gap-2">
                      <CalendarDays className="h-4 w-4 text-[#1E5C8E]" />
                      {fechaVisual}
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-2 pt-0">
                    {slots.map((slot, idx) => (
                      <button
                        key={idx}
                        disabled={slot.ocupado}
                        onClick={() => setSlotSeleccionado(slot)}
                        className={`w-full text-left p-2 rounded-lg text-sm border transition-colors ${
                          slot.ocupado
                            ? 'bg-gray-100 text-gray-400 border-gray-200 cursor-not-allowed'
                            : slotSeleccionado?.fecha === slot.fecha &&
                                slotSeleccionado?.inicio === slot.inicio
                              ? 'bg-[#1E5C8E] text-white border-[#1E5C8E]'
                              : 'bg-gray-50 hover:bg-gray-100 border-gray-200'
                        }`}
                      >
                        <div className="flex items-center justify-between">
                          <span className="flex items-center gap-2">
                            {slot.ocupado && <Lock className="h-3 w-3" />}
                            {slot.ocupado ? 'Ocupado' : `${slot.inicio} – ${slot.fin}`}
                          </span>
                          {!slot.ocupado &&
                            slotSeleccionado?.fecha === slot.fecha &&
                            slotSeleccionado?.inicio === slot.inicio && (
                              <CheckCircle className="h-4 w-4" />
                            )}
                        </div>
                        {!slot.ocupado && (
                          <div className="text-xs opacity-80">{slot.duracion} min</div>
                        )}
                      </button>
                    ))}
                  </CardContent>
                </Card>
              ))}
            </div>
          )}

          {/* Formulario de agendamiento */}
          {slotSeleccionado && (
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Proponer visita</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-sm text-amber-800">
                  <p>📋 Esta visita se enviará como <strong>propuesta</strong> a tu administrador para su aprobación.</p>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Fecha y horario seleccionado</Label>
                    <div className="p-3 bg-gray-50 rounded-lg text-sm flex items-center gap-2">
                      <CalendarDays className="h-4 w-4 text-[#1E5C8E]" />
                      {slotSeleccionado.fechaVisual} · {slotSeleccionado.inicio} – {slotSeleccionado.fin}
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label>Tipo de visita</Label>
                    <select
                      value={tipoVisita}
                      onChange={(e) => setTipoVisita(e.target.value as VisitaTipo)}
                      className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                    >
                      {TIPOS_VISITA.map((t) => (
                        <option key={t.value} value={t.value}>
                          {t.label}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Notas para el administrador</Label>
                  <Input
                    value={notas}
                    onChange={(e) => setNotas(e.target.value)}
                    placeholder="Productos a presentar, motivo de la visita, observaciones..."
                  />
                </div>
                <div className="flex gap-3 pt-2">
                  <Button variant="outline" className="flex-1" onClick={() => setSlotSeleccionado(null)}>
                    Cambiar horario
                  </Button>
                  <Button
                    className="flex-1 bg-[#1E5C8E] hover:bg-[#164a70]"
                    disabled={saving}
                    onClick={handleAgendar}
                  >
                    {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Send className="h-4 w-4 mr-1" />}
                    Enviar propuesta
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
