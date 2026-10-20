import { useState, useEffect, useRef } from 'react'
import type { VisitaTipo } from '@/proveedor/types/proveedor.types'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'
import { useMedicosDisponibles } from '@/proveedor/hooks/useMedicosDisponibles'
import ListaMedicosAgendar from '@/proveedor/components/ListaMedicosAgendar'
import { useVisitasAgendadas } from '@/proveedor/hooks/useVisitasAgendadas'
import { usePlanesVisitador } from '@/proveedor/hooks/usePlanesVisitador'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { MENSAJE_BOLSA_AGOTADA_VISITADOR, MENSAJE_SIN_BOLSA_VISITADOR, RUTA_COMPRA_PLANES_VISITADOR } from '@/proveedor/lib/compraPlanVisitador'
import { toast } from 'sonner'
import { useEnrolamiento } from '@/visitador/hooks/useEnrolamiento'
import { usePuedeEnrolar } from '@/visitador/hooks/usePuedeEnrolar'
import IndicadorPrioridad from '@/visitador/components/IndicadorPrioridad'
import { fechaBloqueadaPorPrioridad, semanasHasta, type PrioridadAgendar } from '@/visitador/lib/enrolamiento'
import {
  Search,
  CalendarDays,
  Clock,
  ArrowLeft,
  Loader2,
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
  // Comprar es de admin/editor (planes.contratar); el visitador solo avisa a su administrador.
  const { puede } = useProveedorAuth()
  const puedeComprar = puede('planes.contratar')
  // Enrolamiento (migs 375-380): la prioridad se consulta siempre que hay médico elegido; enrolar y solicitar alta
  // solo se ofrecen a un lab farmacéutico con el módulo (usePuedeEnrolar). La barrera real es la RPC.
  const { prioridadParaAgendar, enrolarMedico } = useEnrolamiento()
  const { puedeEnrolar } = usePuedeEnrolar()
  const [prioridad, setPrioridad] = useState<PrioridadAgendar | null>(null)
  const [enrolando, setEnrolando] = useState(false)
  const [buscado, setBuscado] = useState(false)
  // Médico vigente: descarta respuestas de prioridad de un médico que ya no está elegido.
  const medicoVigente = useRef<string | null>(null)

  const [query, setQuery] = useState('')
  const [medicoSeleccionado, setMedicoSeleccionado] = useState<string | null>(null)
  const [slotSeleccionado, setSlotSeleccionado] = useState<SlotGenerado | null>(null)
  const [tipoVisita, setTipoVisita] = useState<VisitaTipo>('presentacion_producto')
  const [notas, setNotas] = useState('')
  const [semanaOffset, setSemanaOffset] = useState(0)
  // estado_plan_visitas ahora devuelve UNA fila por país (bolsa pvc); [] = sin plan activo
  const [planEstado, setPlanEstado] = useState<Array<{
    pais_id: string; pais_nombre: string; tiene_pvc: boolean;
    incluidas: number | null; usadas: number; restante: number | null; ilimitado: boolean; fecha_fin: string
  }> | null>(null)

  useEffect(() => {
    supabase.rpc('estado_plan_visitas').then(({ data }) => {
      if (data) setPlanEstado(data as any)
    })
  }, [])
  const [slotsGenerados, setSlotsGenerados] = useState<SlotGenerado[]>([])
  const [cargandoSlots, setCargandoSlots] = useState(false)

  const handleBuscar = (e: React.FormEvent) => {
    e.preventDefault()
    setBuscado(true)
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

  // prioridad_para_agendar del médico. Con 'otro_laboratorio' la grilla salta a la semana de fecha_minima.
  // Si falla (PV026, red) no se muestra indicador: la regla igual la aplica el trigger al guardar (PV002).
  const cargarPrioridad = async (id: string, saltarSemana: boolean) => {
    const r = await prioridadParaAgendar(id)
    if (medicoVigente.current !== id) return
    const p = r.ok ? r.data : null
    setPrioridad(p)
    if (saltarSemana && p?.estado === 'otro_laboratorio' && p.fecha_minima) {
      setSemanaOffset(semanasHasta(p.fecha_minima, new Date()))
    }
  }

  const seleccionarMedico = async (id: string) => {
    medicoVigente.current = id
    setMedicoSeleccionado(id)
    setSlotSeleccionado(null)
    setPrioridad(null)
    cargarPrioridad(id, true)
    await fetchDisponibilidadMedico(id)
  }

  const deseleccionarMedico = () => {
    medicoVigente.current = null
    setMedicoSeleccionado(null)
    setSlotSeleccionado(null)
    setSlotsGenerados([])
    setPrioridad(null)
  }

  const handleEnrolar = async () => {
    if (!medicoSeleccionado) return
    setEnrolando(true)
    const r = await enrolarMedico(medicoSeleccionado)
    setEnrolando(false)
    if (!r.ok) {
      toast.error(r.error.mensaje) // PV013 (enrolado por otro lab), PV011, PV014…: mensaje del servidor
      return
    }
    toast.success(r.data === 'enrolado' ? 'Médico enrolado. Ahora tienes prioridad con él.' : 'Ya habías enrolado a este médico.')
    cargarPrioridad(medicoSeleccionado, false)
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
    if (fechaBloqueadaPorPrioridad(slotSeleccionado.fecha, prioridad)) {
      toast.error('Este horario está reservado para el laboratorio con prioridad. Elige otra fecha.')
      setSlotSeleccionado(null)
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
      // El toast de éxito lo da agendarVisita (uno solo; su texto depende del rol).
      navigate('/visitador/mis-visitas')
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
        <Button variant="ghost" size="icon" onClick={() => navigate('/visitador/planes')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Agendar Visita</h1>
          <p className="text-sm text-muted-foreground">Busca un médico y selecciona un horario</p>
        </div>
      </div>

      {/* Estado de la bolsa de visitas — POR PAÍS, desde pvc (única fuente: país + bolsa restante) */}
      {planEstado && (
        planEstado.length === 0 ? (
          <Card className="border-amber-300 bg-amber-50">
            <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div className="text-sm text-amber-800">
                <p className="font-semibold">Tu empresa no tiene un plan de visitas activo.</p>
                <p>{puedeComprar ? 'Contrata un plan para poder agendar visitas con médicos.' : MENSAJE_SIN_BOLSA_VISITADOR}</p>
              </div>
              {puedeComprar && (
                <Button className="bg-[#1E5C8E] hover:bg-[#164a70]" onClick={() => navigate(RUTA_COMPRA_PLANES_VISITADOR)}>
                  Ver planes
                </Button>
              )}
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-2">
            {planEstado.map((p) => {
              const agotada = !p.ilimitado && (p.restante ?? 0) <= 0
              return (
                <Card key={p.pais_id} className={agotada ? 'border-red-300 bg-red-50' : 'bg-slate-50'}>
                  <CardContent className="p-3 text-sm flex items-center justify-between">
                    <span>Bolsa {p.pais_nombre}: <strong>{p.ilimitado ? 'ilimitada' : `${p.restante} / ${p.incluidas} disponibles`}</strong></span>
                    {agotada && (puedeComprar ? (
                      <button type="button" className="text-red-600 font-medium underline" onClick={() => navigate(RUTA_COMPRA_PLANES_VISITADOR)}>
                        Bolsa agotada · compra más visitas
                      </button>
                    ) : (
                      <span className="text-red-600 font-medium">{MENSAJE_BOLSA_AGOTADA_VISITADOR}</span>
                    ))}
                  </CardContent>
                </Card>
              )
            })}
          </div>
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
        <ListaMedicosAgendar medicos={medicos} onSeleccionar={seleccionarMedico} />
      )}

      {/* Sin resultados: la búsqueda devolvió 0 filas */}
      {buscado && !loading && medicos.length === 0 && !medicoSeleccionado && (
        <Card className="bg-gray-50 border-dashed" data-testid="busqueda-sin-resultados">
          <CardContent className="p-6 text-center text-sm text-muted-foreground space-y-2">
            <p>No encontramos médicos con ese nombre.</p>
            {puedeEnrolar && (
              <button
                type="button"
                className="text-[#1E5C8E] font-medium underline"
                onClick={() => navigate('/visitador/solicitar-alta')}
              >
                ¿No encuentras al médico? Solicita su alta
              </button>
            )}
          </CardContent>
        </Card>
      )}

      {/* Disponibilidad del médico seleccionado */}
      {medicoSeleccionado && (
        <div className="space-y-4">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <h2 className="text-lg font-semibold">Horarios disponibles</h2>
            <Button variant="ghost" size="sm" onClick={deseleccionarMedico}>
              Cambiar médico
            </Button>
          </div>

          <IndicadorPrioridad
            prioridad={prioridad}
            puedeEnrolar={puedeEnrolar}
            enrolando={enrolando}
            onEnrolar={handleEnrolar}
          />

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
                    {slots.map((slot, idx) => {
                      // Antes de fecha_minima (prioridad de otro laboratorio) el turno no se puede elegir.
                      const reservado = !slot.ocupado && fechaBloqueadaPorPrioridad(slot.fecha, prioridad)
                      return (
                      <button
                        key={idx}
                        disabled={slot.ocupado || reservado}
                        data-reservado={reservado || undefined}
                        title={reservado ? 'Reservado para el laboratorio con prioridad' : undefined}
                        onClick={() => setSlotSeleccionado(slot)}
                        className={`w-full text-left p-2 rounded-lg text-sm border transition-colors ${
                          slot.ocupado || reservado
                            ? 'bg-gray-100 text-gray-400 border-gray-200 cursor-not-allowed'
                            : slotSeleccionado?.fecha === slot.fecha &&
                                slotSeleccionado?.inicio === slot.inicio
                              ? 'bg-[#1E5C8E] text-white border-[#1E5C8E]'
                              : 'bg-gray-50 hover:bg-gray-100 border-gray-200'
                        }`}
                      >
                        <div className="flex items-center justify-between">
                          <span className="flex items-center gap-2">
                            {(slot.ocupado || reservado) && <Lock className="h-3 w-3" />}
                            {slot.ocupado ? 'Ocupado' : `${slot.inicio} – ${slot.fin}`}
                          </span>
                          {!slot.ocupado &&
                            slotSeleccionado?.fecha === slot.fecha &&
                            slotSeleccionado?.inicio === slot.inicio && (
                              <CheckCircle className="h-4 w-4" />
                            )}
                        </div>
                        {!slot.ocupado && (
                          <div className="text-xs opacity-80">{reservado ? 'Reservado' : `${slot.duracion} min`}</div>
                        )}
                      </button>
                      )
                    })}
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
