import { useMemo, useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { Calendar, dateFnsLocalizer, Views } from 'react-big-calendar'
import { format, parse, startOfWeek, getDay, addMinutes, startOfMonth, endOfMonth, eachDayOfInterval, isSameDay, isSameMonth, addMonths } from 'date-fns'
import { es } from 'date-fns/locale'
import { ChevronLeft, ChevronRight, Plus, X, CheckCircle2, Phone, FileText, Building2, Loader2, Stethoscope, CalendarDays } from 'lucide-react'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { useAuth } from '@/hooks/useAuth'
import { useCalendarioClinica, type ModoCalendario, type MedicoColumna, type CitaCalendario, type VisitaCalendario } from '@/clinica/hooks/useCalendarioClinica'
import { combinar } from '@/lib/fecha'
import NuevaCitaModal from '@/clinica/components/NuevaCitaModal'
import { FotoPacienteAvatar } from '@/components/FotoPacienteAvatar'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'
import 'react-big-calendar/lib/css/react-big-calendar.css'
import './clinica-calendario.css'

const localizer = dateFnsLocalizer({ format, parse, startOfWeek, getDay, locales: { es } })

// ── helpers de fecha/hora en LOCAL ── (parseFechaLocal/combinar movidos a @/lib/fecha)
function horaCorta(hora: string | null): string {
  if (!hora) return ''
  const [h, m] = hora.split(':')
  return `${h}:${m}`
}
function iniciales(nombre: string): string {
  const p = nombre.trim().split(/\s+/)
  return ((p[0]?.[0] || '') + (p[1]?.[0] || '')).toUpperCase() || '?'
}

// ── color por estado ──
function colorCita(estado: string): { bar: string; bg: string; text: string } {
  switch (estado) {
    case 'confirmada': case 'agendada': return { bar: '#10b981', bg: '#ecfdf5', text: '#065f46' }
    case 'en_espera': return { bar: '#f97316', bg: '#fff7ed', text: '#9a3412' }
    case 'solicitada': case 'pendiente': return { bar: '#f59e0b', bg: '#fffbeb', text: '#92400e' }
    case 'cancelada': return { bar: '#ef4444', bg: '#fef2f2', text: '#991b1b' }
    case 'completada': case 'atendida': return { bar: '#0ea5e9', bg: '#f0f9ff', text: '#075985' }
    default: return { bar: '#64748b', bg: '#f8fafc', text: '#334155' }
  }
}
function colorVisita(estado: string): { bar: string; bg: string; text: string } {
  switch (estado) {
    case 'aprobada': case 'confirmada': return { bar: '#10b981', bg: '#ecfdf5', text: '#065f46' }
    case 'propuesta': case 'pendiente': return { bar: '#f59e0b', bg: '#fffbeb', text: '#92400e' }
    case 'cancelada': case 'rechazada': return { bar: '#ef4444', bg: '#fef2f2', text: '#991b1b' }
    default: return { bar: '#8b5cf6', bg: '#f5f3ff', text: '#5b21b6' }
  }
}

interface EventoRBC {
  id: string
  title: string
  start: Date
  end: Date
  resourceId: string
  tipo: ModoCalendario
  raw: CitaCalendario | VisitaCalendario
}

function useMediaQuery(query: string): boolean {
  const [match, setMatch] = useState(() => typeof window !== 'undefined' && window.matchMedia(query).matches)
  useEffect(() => {
    const mq = window.matchMedia(query)
    const h = () => setMatch(mq.matches)
    mq.addEventListener('change', h)
    return () => mq.removeEventListener('change', h)
  }, [query])
  return match
}

// ── mini-calendario mensual ──
function MiniMes({ fecha, onPick }: { fecha: Date; onPick: (d: Date) => void }) {
  const [mesVista, setMesVista] = useState(startOfMonth(fecha))
  useEffect(() => { setMesVista(startOfMonth(fecha)) }, [fecha])
  const dias = useMemo(() => {
    const ini = startOfWeek(startOfMonth(mesVista), { weekStartsOn: 1 })
    const fin = endOfMonth(mesVista)
    return eachDayOfInterval({ start: ini, end: fin })
  }, [mesVista])
  return (
    <div className="bg-white rounded-xl border border-slate-200 p-3 w-full">
      <div className="flex items-center justify-between mb-2">
        <button onClick={() => setMesVista(addMonths(mesVista, -1))} className="p-1 rounded hover:bg-slate-100"><ChevronLeft className="h-4 w-4" /></button>
        <span className="text-sm font-semibold capitalize text-slate-700">{format(mesVista, 'MMMM yyyy', { locale: es })}</span>
        <button onClick={() => setMesVista(addMonths(mesVista, 1))} className="p-1 rounded hover:bg-slate-100"><ChevronRight className="h-4 w-4" /></button>
      </div>
      <div className="grid grid-cols-7 gap-0.5 text-center text-[10px] text-slate-400 mb-1">
        {['L', 'M', 'M', 'J', 'V', 'S', 'D'].map((d, i) => <span key={i}>{d}</span>)}
      </div>
      <div className="grid grid-cols-7 gap-0.5">
        {dias.map((d) => {
          const sel = isSameDay(d, fecha)
          const otroMes = !isSameMonth(d, mesVista)
          return (
            <button
              key={d.toISOString()}
              onClick={() => onPick(d)}
              className={`h-7 rounded-md text-xs transition-colors ${sel ? 'bg-[#1E5C8E] text-white font-semibold' : otroMes ? 'text-slate-300 hover:bg-slate-50' : 'text-slate-700 hover:bg-slate-100'}`}
            >
              {d.getDate()}
            </button>
          )
        })}
      </div>
    </div>
  )
}

// ── header de columna de médico ──
function HeaderMedico({ resource }: { resource: MedicoColumna }) {
  return (
    <div className="flex items-center gap-2 px-2 py-2">
      <div className="h-9 w-9 rounded-full bg-[#1E5C8E]/10 text-[#1E5C8E] flex items-center justify-center text-xs font-bold shrink-0">
        {iniciales(resource.nombre_completo)}
      </div>
      <div className="min-w-0 text-left">
        <p className="text-sm font-semibold text-slate-800 truncate">{resource.nombre_completo}</p>
        <p className="text-[11px] text-emerald-600 flex items-center gap-1">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 inline-block" /> Disponible
        </p>
      </div>
    </div>
  )
}

// ── contenido de un evento ──
function EventoContenido({ event }: { event: EventoRBC }) {
  const presente = event.tipo === 'visita' && (event.raw as VisitaCalendario).confirmado_presente_clinica_at
  return (
    <div className="px-1.5 py-1 text-[11px] leading-tight h-full overflow-hidden">
      <div className="font-semibold truncate flex items-center gap-1">
        {presente && <CheckCircle2 className="h-3 w-3 text-emerald-600 shrink-0" />}
        {event.tipo === 'visita' && <Building2 className="h-3 w-3 opacity-60 shrink-0" />}
        <span className="truncate">{event.title}</span>
      </div>
      <div className="opacity-70 truncate">{format(event.start, 'HH:mm')}–{format(event.end, 'HH:mm')}</div>
    </div>
  )
}

// ── shell de popup (bottom-sheet en mobile, card centrado en desktop) ──
function Popup({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div
        className="bg-white w-full sm:max-w-md sm:rounded-2xl rounded-t-2xl shadow-xl max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>
  )
}

function BadgeEstado({ estado, tipo }: { estado: string; tipo: ModoCalendario }) {
  const c = tipo === 'cita' ? colorCita(estado) : colorVisita(estado)
  // Solo en_espera necesita label (evita "En_espera" del capitalize sobre el crudo); el resto queda igual.
  const label = estado === 'en_espera' ? 'En espera' : estado
  return <span className="px-2 py-0.5 rounded-full text-xs font-medium capitalize" style={{ backgroundColor: c.bg, color: c.text }}>{label}</span>
}

export default function ClinicaCalendarioPage() {
  const navigate = useNavigate()
  const { clinica, loading: loadingClinica } = useClinicaAuth()
  const { perfil } = useAuth()
  const isMobile = useMediaQuery('(max-width: 767px)')

  // Enfermería ve el calendario pero NO crea citas (crear_cita rama c la excluye) → se oculta el alta.
  const puedeCrearCita = perfil?.rol !== 'enfermeria'

  const [fecha, setFecha] = useState<Date>(() => new Date())
  const [modo, setModo] = useState<ModoCalendario>('citas')
  const [medicoSel, setMedicoSel] = useState<string | null>(null)
  const [popup, setPopup] = useState<EventoRBC | null>(null)
  const [marcando, setMarcando] = useState(false)
  const [nuevaCita, setNuevaCita] = useState<{ medicoId?: string; fecha: Date; horaInicio?: string } | null>(null)

  const { medicos, citas, visitas, loading, marcarPresente, buscarPacientes, crearPaciente, crearCita } = useCalendarioClinica(clinica?.id, fecha, modo)

  // En mobile, si no hay médico seleccionado (o cambió la lista), fijar el primero.
  useEffect(() => {
    if (isMobile && medicos.length && !medicos.some((m) => m.medico_id === medicoSel)) {
      setMedicoSel(medicos[0].medico_id)
    }
  }, [isMobile, medicos, medicoSel])

  // Columnas: TODAS en desktop; SOLO la seleccionada en mobile (una sola implementación del calendario).
  const recursos = useMemo(() => {
    if (isMobile) return medicos.filter((m) => m.medico_id === medicoSel)
    return medicos
  }, [isMobile, medicos, medicoSel])

  const eventos = useMemo<EventoRBC[]>(() => {
    if (modo === 'citas') {
      return citas
        .filter((c) => c.medico_id) // sin médico no se puede ubicar en columna
        .map((c) => ({
          id: `cita-${c.cita_id}`,
          title: `${c.paciente_nombre} ${c.paciente_apellido}`.trim() || 'Paciente',
          start: combinar(c.fecha, c.hora_inicio),
          end: c.hora_fin ? combinar(c.fecha, c.hora_fin) : addMinutes(combinar(c.fecha, c.hora_inicio), 30),
          resourceId: c.medico_id as string,
          tipo: 'citas' as ModoCalendario,
          raw: c,
        }))
    }
    return visitas.map((v) => ({
      id: `visita-${v.visita_id}`,
      title: v.empresa_nombre || 'Visita',
      start: combinar(v.fecha_visita, v.hora_inicio),
      end: v.hora_fin ? combinar(v.fecha_visita, v.hora_fin) : addMinutes(combinar(v.fecha_visita, v.hora_inicio), 30),
      resourceId: v.medico_id,
      tipo: 'visitas' as ModoCalendario,
      raw: v,
    }))
  }, [modo, citas, visitas])

  const eventPropGetter = (event: EventoRBC) => {
    const c = event.tipo === 'citas' ? colorCita((event.raw as CitaCalendario).estado) : colorVisita((event.raw as VisitaCalendario).estado)
    return { style: { backgroundColor: c.bg, borderLeft: `4px solid ${c.bar}`, color: c.text } }
  }

  const minTime = useMemo(() => { const d = new Date(fecha); d.setHours(6, 0, 0, 0); return d }, [fecha])
  const maxTime = useMemo(() => { const d = new Date(fecha); d.setHours(21, 0, 0, 0); return d }, [fecha])
  const scrollTo = useMemo(() => { const d = new Date(fecha); d.setHours(8, 0, 0, 0); return d }, [fecha])

  const abrirNuevaCita = (medicoId?: string, cuando?: Date, horaInicio?: string) => {
    setNuevaCita({ medicoId: medicoId || recursos[0]?.medico_id || medicos[0]?.medico_id, fecha: cuando || fecha, horaInicio: horaInicio || '09:00' })
  }

  const handleMarcarPresente = async (v: VisitaCalendario, presente: boolean) => {
    setMarcando(true)
    const res = await marcarPresente(v.visita_id, presente)
    setMarcando(false)
    if (res?.error) { toast.error('No se pudo actualizar: ' + res.error.message); return }
    // Sincronizar el popup abierto con el nuevo estado.
    setPopup((p) => p && p.id === `visita-${v.visita_id}`
      ? { ...p, raw: { ...v, confirmado_presente_clinica_at: res!.data!.at, confirmado_presente_clinica_por: res!.data!.por } }
      : p)
    toast.success(presente ? 'Visitador marcado como presente' : 'Marca de presencia quitada')
  }

  if (loadingClinica) {
    return <div className="flex items-center justify-center h-64"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
  }
  if (!clinica) {
    return <div className="p-6 text-slate-500">No se encontró la clínica asociada a tu usuario.</div>
  }

  return (
    <div className="p-4 sm:p-6">
      {/* Barra superior */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <div className="flex items-center gap-2">
          <CalendarDays className="h-6 w-6 text-[#1E5C8E]" />
          <h1 className="text-xl font-bold text-slate-800">Calendario</h1>
        </div>

        {/* Navegación de día */}
        <div className="flex items-center gap-1 ml-auto">
          <button onClick={() => setFecha((f) => addMinutes(f, -24 * 60))} className="p-1.5 rounded-lg hover:bg-slate-100"><ChevronLeft className="h-5 w-5" /></button>
          <span className="text-sm font-semibold text-slate-700 capitalize min-w-[9rem] text-center">{format(fecha, "EEE d 'de' MMM", { locale: es })}</span>
          <button onClick={() => setFecha((f) => addMinutes(f, 24 * 60))} className="p-1.5 rounded-lg hover:bg-slate-100"><ChevronRight className="h-5 w-5" /></button>
          <Button variant="outline" size="sm" className="ml-1" onClick={() => setFecha(new Date())}>Hoy</Button>
        </div>

        {/* Toggle Citas | Visitas */}
        <div className="inline-flex rounded-lg border border-slate-200 overflow-hidden">
          <button onClick={() => setModo('citas')} className={`px-3 py-1.5 text-sm font-medium ${modo === 'citas' ? 'bg-[#1E5C8E] text-white' : 'bg-white text-slate-600 hover:bg-slate-50'}`}>Citas de Pacientes</button>
          <button onClick={() => setModo('visitas')} className={`px-3 py-1.5 text-sm font-medium ${modo === 'visitas' ? 'bg-[#1E5C8E] text-white' : 'bg-white text-slate-600 hover:bg-slate-50'}`}>Visitas de Visitador</button>
        </div>

        {/* Nueva cita (solo en modo citas + roles que crean; en mobile va el FAB) */}
        {modo === 'citas' && puedeCrearCita && !isMobile && (
          <Button size="sm" onClick={() => abrirNuevaCita()} className="bg-[#1E5C8E] hover:bg-[#164a70] text-white"><Plus className="h-4 w-4 mr-1" /> Nueva cita</Button>
        )}
      </div>

      {/* Chips de médicos (solo mobile) */}
      {isMobile && medicos.length > 0 && (
        <div className="flex gap-2 overflow-x-auto pb-2 mb-3 -mx-1 px-1">
          {medicos.map((m) => {
            const sel = m.medico_id === medicoSel
            return (
              <button
                key={m.medico_id}
                onClick={() => setMedicoSel(m.medico_id)}
                className={`flex items-center gap-2 shrink-0 rounded-full pl-1 pr-3 py-1 border ${sel ? 'border-[#1E5C8E] bg-[#1E5C8E]/10' : 'border-slate-200 bg-white'}`}
              >
                <span className="h-7 w-7 rounded-full bg-[#1E5C8E]/10 text-[#1E5C8E] flex items-center justify-center text-[10px] font-bold">{iniciales(m.nombre_completo)}</span>
                <span className={`text-xs font-medium truncate max-w-[7rem] ${sel ? 'text-[#1E5C8E]' : 'text-slate-600'}`}>{m.nombre_completo}</span>
              </button>
            )
          })}
        </div>
      )}

      <div className="flex gap-4">
        {/* Mini-mes lateral (desktop) */}
        <div className="hidden lg:block w-64 shrink-0">
          <MiniMes fecha={fecha} onPick={setFecha} />
        </div>

        {/* Calendario */}
        <div className="flex-1 min-w-0 cal-clinica relative" style={{ height: 'calc(100vh - 200px)' }}>
          {medicos.length === 0 && !loading ? (
            <div className="h-full flex flex-col items-center justify-center text-slate-400 gap-2 border border-dashed border-slate-200 rounded-xl">
              <Stethoscope className="h-8 w-8" />
              <p className="text-sm">Esta clínica aún no tiene médicos asociados.</p>
            </div>
          ) : (
            <Calendar
              localizer={localizer}
              events={eventos}
              date={fecha}
              onNavigate={(d) => setFecha(d)}
              view={Views.DAY}
              views={[Views.DAY]}
              onView={() => {}}
              toolbar={false}
              popup={false}
              resources={recursos}
              resourceIdAccessor={(r: MedicoColumna) => r.medico_id}
              resourceTitleAccessor={(r: MedicoColumna) => r.nombre_completo}
              min={minTime}
              max={maxTime}
              scrollToTime={scrollTo}
              step={15}
              timeslots={2}
              components={{ event: EventoContenido as any, resourceHeader: HeaderMedico as any }}
              eventPropGetter={eventPropGetter as any}
              onSelectEvent={(e: EventoRBC) => setPopup(e)}
              selectable={modo === 'citas' && puedeCrearCita}
              onSelectSlot={(slot: any) => abrirNuevaCita(slot.resourceId, slot.start, format(slot.start, 'HH:mm'))}
              formats={{ timeGutterFormat: 'HH:mm' }}
            />
          )}
          {loading && (
            <div className="absolute top-2 right-2"><Loader2 className="h-4 w-4 animate-spin text-slate-400" /></div>
          )}
        </div>
      </div>

      {/* FAB mobile (nueva cita) */}
      {isMobile && modo === 'citas' && puedeCrearCita && (
        <button onClick={() => abrirNuevaCita()} className="fixed bottom-6 right-6 z-40 h-14 w-14 rounded-full bg-[#1E5C8E] text-white shadow-lg flex items-center justify-center hover:bg-[#164a70]">
          <Plus className="h-6 w-6" />
        </button>
      )}

      {/* Modal Nueva cita (búsqueda → alta de paciente → detalle → crear_cita) */}
      {nuevaCita && (
        <NuevaCitaModal
          clinicaPaisId={clinica.pais_id}
          medicos={medicos}
          prefill={nuevaCita}
          buscarPacientes={buscarPacientes}
          crearPaciente={crearPaciente}
          crearCita={crearCita}
          onClose={() => setNuevaCita(null)}
          onCreated={() => { /* crearCita ya recarga la vista */ }}
        />
      )}

      {/* Popups */}
      {popup && popup.tipo === 'citas' && (() => {
        const c = popup.raw as CitaCalendario
        return (
          <Popup onClose={() => setPopup(null)}>
            <div className="p-5 space-y-4">
              <div className="flex items-start justify-between">
                <h2 className="text-lg font-bold text-slate-800">Cita</h2>
                <button onClick={() => setPopup(null)} className="p-1 rounded hover:bg-slate-100"><X className="h-5 w-5 text-slate-400" /></button>
              </div>
              <div className="flex items-center gap-4">
                <FotoPacienteAvatar pacienteId={c.paciente_id} fotoPath={c.foto_path} size="lg" />
                <div>
                  <p className="font-semibold text-slate-800">{c.paciente_nombre} {c.paciente_apellido}</p>
                  <div className="mt-1"><BadgeEstado estado={c.estado} tipo="cita" /></div>
                </div>
              </div>
              <div className="space-y-2 text-sm text-slate-600">
                <p className="flex items-center gap-2"><CalendarDays className="h-4 w-4 text-slate-400" /> {format(combinar(c.fecha, c.hora_inicio), "EEE d MMM", { locale: es })} · {horaCorta(c.hora_inicio)}{c.hora_fin ? `–${horaCorta(c.hora_fin)}` : ''}</p>
                {c.paciente_telefono && <p className="flex items-center gap-2"><Phone className="h-4 w-4 text-slate-400" /> {c.paciente_telefono}</p>}
                {c.motivo && <p className="flex items-center gap-2"><FileText className="h-4 w-4 text-slate-400" /> {c.motivo}</p>}
                {c.notas && <p className="text-slate-500 bg-slate-50 rounded-lg p-2">{c.notas}</p>}
              </div>
              <div className="flex gap-2 pt-2">
                <Button variant="outline" className="flex-1" onClick={() => setPopup(null)}>Cerrar</Button>
                <Button className="flex-1 bg-[#1E5C8E] hover:bg-[#164a70] text-white" onClick={() => navigate(`/clinica/admision?paciente_id=${c.paciente_id}&cita_id=${c.cita_id}`)}>Ir a la ficha</Button>
              </div>
            </div>
          </Popup>
        )
      })()}

      {popup && popup.tipo === 'visitas' && (() => {
        const v = popup.raw as VisitaCalendario
        const presente = !!v.confirmado_presente_clinica_at
        return (
          <Popup onClose={() => setPopup(null)}>
            <div className="p-5 space-y-4">
              <div className="flex items-start justify-between">
                <h2 className="text-lg font-bold text-slate-800">Visita de visitador</h2>
                <button onClick={() => setPopup(null)} className="p-1 rounded hover:bg-slate-100"><X className="h-5 w-5 text-slate-400" /></button>
              </div>
              <div className="space-y-2 text-sm text-slate-600">
                <p className="flex items-center gap-2"><Building2 className="h-4 w-4 text-slate-400" /> {v.empresa_nombre || 'Empresa'}</p>
                <p className="flex items-center gap-2"><Stethoscope className="h-4 w-4 text-slate-400" /> {v.medico_nombre}</p>
                <p className="flex items-center gap-2"><CalendarDays className="h-4 w-4 text-slate-400" /> {format(combinar(v.fecha_visita, v.hora_inicio), 'EEE d MMM', { locale: es })} · {horaCorta(v.hora_inicio)}{v.hora_fin ? `–${horaCorta(v.hora_fin)}` : ''}</p>
                <div className="flex items-center gap-2"><span className="text-slate-400">Estado:</span> <BadgeEstado estado={v.estado} tipo="visitas" /></div>
              </div>

              {/* Presencia del visitador (registro de la clínica; no toca el estado real de la visita) */}
              <div className="border-t border-slate-100 pt-3">
                {presente ? (
                  <div className="flex items-center justify-between gap-2">
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-emerald-50 text-emerald-700 text-sm font-medium">
                      <CheckCircle2 className="h-4 w-4" /> Visitador presente {v.confirmado_presente_clinica_at ? `· ${format(new Date(v.confirmado_presente_clinica_at), 'HH:mm')}` : ''}
                    </span>
                    <Button variant="ghost" size="sm" disabled={marcando} onClick={() => handleMarcarPresente(v, false)}>Quitar</Button>
                  </div>
                ) : (
                  <div className="flex items-center justify-between gap-2">
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-slate-100 text-slate-500 text-sm">No confirmado</span>
                    <Button size="sm" disabled={marcando} className="bg-[#1E5C8E] hover:bg-[#164a70] text-white" onClick={() => handleMarcarPresente(v, true)}>
                      {marcando ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Marcar visitador presente'}
                    </Button>
                  </div>
                )}
              </div>

              <Button variant="outline" className="w-full" onClick={() => setPopup(null)}>Cerrar</Button>
            </div>
          </Popup>
        )
      })()}
    </div>
  )
}
