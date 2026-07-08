import { useState, useEffect, useMemo, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { CalendarDays, Clock, FileText, StickyNote, X, Loader2, User, MapPin, ChevronLeft, ChevronRight, Stethoscope, Search, Star, Check } from 'lucide-react'
import { toast } from 'sonner'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { format, parseISO } from 'date-fns'
import { es } from 'date-fns/locale'

interface MedicoOption {
  id: string
  nombre_completo: string
  especialidad: string | null
  especialidad_id: string | null
  proximo_turno: string | null   // timestamptz ISO string (o null si no hay turno próximo)
  foto_url: string | null
}

interface ClinicaOption {
  id: string
  nombre: string
}

interface EspecialidadOption {
  id: string
  nombre: string
}

// Formatea el próximo turno mostrando SOLO la fecha (ej: "6 jul"), nunca la hora.
// Work item de zona horaria pendiente: la hora tendría corrimiento para países no-UTC,
// así que tomamos solo la parte de fecha del ISO (YYYY-MM-DD) para evitar cualquier shift de TZ.
function formatProximoTurno(iso: string | null): string | null {
  if (!iso) return null
  try {
    return format(parseISO(iso.slice(0, 10)), 'd MMM', { locale: es })
  } catch {
    return null
  }
}

interface Props {
  pacienteId: number | undefined
  pacienteNombre?: string
  paisIdProp?: string
  open: boolean
  onClose: () => void
  onSuccess?: () => void
}

// Sinónimos básicos de especialidades
const SINONIMOS_ESPECIALIDAD: Record<string, string[]> = {
  'cardiologia': ['corazon', 'corazón', 'cardiaco', 'cardíaco', 'corazonada'],
  'pediatria': ['niños', 'ninos', 'bebes', 'bebés', 'infantil', 'pediatra'],
  'dermatologia': ['piel', 'acne', 'acné', 'manchas', 'dermatitis'],
  'ginecologia': ['mujer', 'embarazo', 'obstetricia', 'ginecologa', 'ginecóloga'],
  'neurologia': ['cabeza', 'cerebro', 'nervios', 'migrana', 'migraña', 'neurologo'],
  'ortopedia': ['huesos', 'fracturas', 'rodilla', 'cadera', 'traumatologia', 'traumatología'],
  'psicologia': ['mente', 'ansiedad', 'depresion', 'depresión', 'terapia', 'psicologo', 'psicólogo'],
  'odontologia': ['dientes', 'dental', 'muela', 'ortodoncia', 'dentista'],
  'oftalmologia': ['ojos', 'vista', 'lentes', 'glaucoma', 'oftalmologo'],
  'urologia': ['riñon', 'riñón', 'prostata', 'próstata', 'orina'],
  'endocrinologia': ['tiroides', 'diabetes', 'hormonas', 'metabolismo'],
  'gastroenterologia': ['estomago', 'estómago', 'colon', 'higado', 'hígado', 'digestivo'],
  'nefrologia': ['riñon', 'riñón', 'dialisis', 'diálisis'],
  'oncologia': ['cancer', 'cáncer', 'tumor', 'quimioterapia'],
  'neumologia': ['pulmon', 'pulmón', 'tos', 'asma', 'respiratorio'],
}

function normalizarTexto(texto: string): string {
  return texto
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
}

function buscarSinonimos(query: string): string[] {
  const q = normalizarTexto(query)
  const resultados = [q]

  for (const [especialidad, sinonimos] of Object.entries(SINONIMOS_ESPECIALIDAD)) {
    if (sinonimos.includes(q) || especialidad.includes(q)) {
      resultados.push(especialidad)
      resultados.push(...sinonimos)
    }
  }

  return [...new Set(resultados)]
}

export default function AgendarCitaModal({ pacienteId, pacienteNombre, paisIdProp, open, onClose, onSuccess }: Props) {
  const [paso, setPaso] = useState<1 | 2>(1)
  const [medicos, setMedicos] = useState<MedicoOption[]>([])
  const [clinicas, setClinicas] = useState<ClinicaOption[]>([])
  const [clinicasFiltradas, setClinicasFiltradas] = useState<ClinicaOption[]>([])
  const [cargandoOpciones, setCargandoOpciones] = useState(false)

  // Filtro server-side por especialidad (Select). '' = todas las especialidades.
  const [especialidades, setEspecialidades] = useState<EspecialidadOption[]>([])
  const [especialidadSel, setEspecialidadSel] = useState('')
  const [cargandoMedicos, setCargandoMedicos] = useState(false)

  const [medicoId, setMedicoId] = useState<string | null>(null)
  const [clinicaId, setClinicaId] = useState<string | null>(null)

  // Búsqueda inteligente
  const [busquedaMedico, setBusquedaMedico] = useState('')
  const [busquedaFocus, setBusquedaFocus] = useState(false)

  // Preferencias del paciente
  const [medicoPrimarioId, setMedicoPrimarioId] = useState<string | null>(null)
  const [clinicaPrimariaId, setClinicaPrimariaId] = useState<string | null>(null)
  const [recordarPreferencia, setRecordarPreferencia] = useState(false)

  const [form, setForm] = useState({
    fecha: '',
    hora_inicio: '',
    motivo: '',
    notas: '',
  })

  // Slots de disponibilidad del médico (contexto paciente)
  const [dispPac, setDispPac] = useState<any[]>([])
  const [ocupados, setOcupados] = useState<Set<string>>(new Set())
  const [slotSel, setSlotSel] = useState<{ fecha: string; hora: string; dur: number } | null>(null)
  const [cargandoSlots, setCargandoSlots] = useState(false)

  const { perfil } = useWebAppAuth()
  const paisId = paisIdProp || perfil?.pais_id
  const [guardando, setGuardando] = useState(false)

  // Debounce para búsqueda
  const [busquedaDebounced, setBusquedaDebounced] = useState('')
  useEffect(() => {
    const timer = setTimeout(() => setBusquedaDebounced(busquedaMedico), 300)
    return () => clearTimeout(timer)
  }, [busquedaMedico])

  // Filtrar médicos por búsqueda
  const medicosFiltrados = useMemo(() => {
    if (!busquedaDebounced.trim()) {
      // Sin búsqueda: mostrar solo médicos con preferencia o top 5
      if (medicoPrimarioId) {
        const primero = medicos.find(m => m.id === medicoPrimarioId)
        const otros = medicos.filter(m => m.id !== medicoPrimarioId).slice(0, 4)
        return primero ? [primero, ...otros] : medicos.slice(0, 5)
      }
      return medicos.slice(0, 5)
    }

    // La búsqueda por especialidad ahora la maneja el Select (filtro duro server-side).
    // El buscador de texto filtra SOLO por nombre del médico.
    const terminos = buscarSinonimos(busquedaDebounced)

    return medicos.filter((m) => {
      const nombre = normalizarTexto(m.nombre_completo)
      return terminos.some(term => nombre.includes(term))
    }).slice(0, 7)
  }, [busquedaDebounced, medicos, medicoPrimarioId])

  // Cargar médicos vía buscar_medicos_paciente (país derivado server-side del auth.uid();
  // NO recibe p_pais_id). p_especialidad_id = filtro duro opcional (null = sin filtro).
  const cargarMedicos = useCallback(async (espId: string | null) => {
    setCargandoMedicos(true)
    try {
      const { data, error } = await supabase
        .rpc('buscar_medicos_paciente', { p_especialidad_id: espId })
      if (error) console.error('Error cargando médicos via RPC:', error?.message ?? error?.code)
      setMedicos(data || [])
    } finally {
      setCargandoMedicos(false)
    }
  }, [])

  // Cargar médicos, clínicas, especialidades y preferencias del paciente al abrir
  useEffect(() => {
    if (!open || !paisId || !pacienteId) return

    const cargarDatos = async () => {
      setCargandoOpciones(true)
      try {
        // Médicos: carga inicial sin filtro de especialidad
        await cargarMedicos(null)

        // Especialidades activas del país (para el Select) — deriva país server-side
        const { data: espData, error: espError } = await supabase
          .rpc('listar_especialidades_activas')

        if (espError) {
          console.error('Error cargando especialidades via RPC:', espError?.message ?? espError?.code)
        }

        // Cargar clínicas via RPC (bypass PostgREST schema cache)
        const { data: clinicsData, error: clinicsError } = await supabase
          .rpc('listar_clinicas_por_pais', { p_pais_id: paisId })

        if (clinicsError) {
          console.error('Error cargando clínicas via RPC:', clinicsError?.message ?? clinicsError?.code)
        }

        // Cargar preferencias del paciente
        const { data: pacienteData } = await supabase
          .from('pacientes')
          .select('medico_primario_id, clinica_primaria_id')
          .eq('id', pacienteId)
          .single()

        const clinicasData = clinicsData || []

        setEspecialidades(espData || [])
        setClinicas(clinicasData)
        setClinicasFiltradas(clinicasData)

        // Pre-cargar preferencias
        if (pacienteData?.medico_primario_id) {
          setMedicoPrimarioId(pacienteData.medico_primario_id)
          setMedicoId(pacienteData.medico_primario_id)
        }
        if (pacienteData?.clinica_primaria_id) {
          setClinicaPrimariaId(pacienteData.clinica_primaria_id)
          setClinicaId(pacienteData.clinica_primaria_id)
        }
      } catch (err) {
        console.error('Error cargando datos:', err?.message ?? err?.code)
      } finally {
        setCargandoOpciones(false)
      }
    }

    cargarDatos()
  }, [open, paisId, pacienteId, cargarMedicos])

  // Filtrar clínicas según médico seleccionado
  useEffect(() => {
    if (!medicoId) {
      setClinicasFiltradas(clinicas)
      return
    }

    const filtrar = async () => {
      const { data: rels } = await supabase
        .rpc('obtener_clinicas_medico', { p_medico_id: medicoId })

      const clinicaIds = rels?.map(r => r.clinica_id) || []

      if (clinicaIds.length === 0) {
        // Médico no tiene clínicas asignadas, mostrar todas
        setClinicasFiltradas(clinicas)
      } else {
        const filtradas = clinicas.filter(c => clinicaIds.includes(c.id))
        setClinicasFiltradas(filtradas)

        // Si hay clínicas disponibles, asegurar que haya una seleccionada
        if (filtradas.length === 1) {
          if (clinicaId !== filtradas[0].id) { setClinicaId(filtradas[0].id) }
        } else if (filtradas.length > 1) {
          // Si la clínica seleccionada no está en la lista, preseleccionar la primera
          if (!clinicaId || !filtradas.find(c => c.id === clinicaId)) {
            setClinicaId(filtradas[0].id)
          }
        }
      }
    }

    filtrar()
  }, [medicoId, clinicas, clinicaId])

  // Cargar disponibilidad (contexto paciente) + slots ocupados al elegir médico
  useEffect(() => {
    if (!medicoId) { setDispPac([]); setOcupados(new Set()); setSlotSel(null); return }
    let cancel = false
    ;(async () => {
      setCargandoSlots(true)
      setSlotSel(null)
      setForm((f) => ({ ...f, fecha: '', hora_inicio: '' }))
      const fmt = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
      const hoy = new Date()
      const hasta = new Date(); hasta.setDate(hasta.getDate() + 21)
      const [{ data: disp }, { data: occ }] = await Promise.all([
        supabase.from('disponibilidad_medico').select('*').eq('medico_id', medicoId).eq('activo', true).eq('contexto', 'paciente'),
        supabase.rpc('slots_ocupados_cita', { p_medico_id: medicoId, p_desde: fmt(hoy), p_hasta: fmt(hasta) }),
      ])
      if (cancel) return
      setDispPac(disp || [])
      const set = new Set<string>()
      ;(occ || []).forEach((o: any) => set.add(`${o.fecha}|${(o.hora_inicio || '').slice(0, 5)}`))
      setOcupados(set)
      setCargandoSlots(false)
    })()
    return () => { cancel = true }
  }, [medicoId])

  // Generar slots disponibles por día (próximos 21 días)
  const slotsPorDia = useMemo(() => {
    if (dispPac.length === 0) return [] as { fecha: string; fechaLabel: string; slots: { hora: string; dur: number; ocupado: boolean }[] }[]
    const ahora = new Date()
    const out: { fecha: string; fechaLabel: string; slots: { hora: string; dur: number; ocupado: boolean }[] }[] = []
    for (let i = 0; i < 21; i++) {
      const d = new Date(); d.setDate(d.getDate() + i); d.setHours(0, 0, 0, 0)
      const dow = d.getDay()
      const fecha = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
      const slots: { hora: string; dur: number; ocupado: boolean }[] = []
      dispPac.filter((x) => x.dia_semana === dow).forEach((x) => {
        const dur = x.duracion_slot || 30
        const [hi, mi] = String(x.hora_inicio).split(':').map(Number)
        const [hf, mf] = String(x.hora_fin).split(':').map(Number)
        let cur = hi * 60 + mi
        const fin = hf * 60 + mf
        while (cur + dur <= fin) {
          const hora = `${String(Math.floor(cur / 60)).padStart(2, '0')}:${String(cur % 60).padStart(2, '0')}`
          const sd = new Date(d); sd.setHours(Math.floor(cur / 60), cur % 60, 0, 0)
          if (sd > ahora) slots.push({ hora, dur, ocupado: ocupados.has(`${fecha}|${hora}`) })
          cur += dur
        }
      })
      if (slots.length) {
        slots.sort((a, b) => a.hora.localeCompare(b.hora))
        out.push({ fecha, fechaLabel: d.toLocaleDateString('es-GT', { weekday: 'short', day: '2-digit', month: '2-digit' }), slots })
      }
    }
    return out
  }, [dispPac, ocupados])

  // Resetear al cerrar
  useEffect(() => {
    if (!open) {
      setPaso(1)
      setMedicoId(null)
      setClinicaId(null)
      setSlotSel(null)
      setForm({ fecha: '', hora_inicio: '', motivo: '', notas: '' })
      setBusquedaMedico('')
      setBusquedaDebounced('')
      setRecordarPreferencia(false)
      setMedicoPrimarioId(null)
      setClinicaPrimariaId(null)
      setEspecialidadSel('')
      setEspecialidades([])
    }
  }, [open])

  if (!open) return null

  const canAvanzar = paso === 1 || (form.fecha && form.hora_inicio)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!pacienteId || !form.fecha || !form.hora_inicio) {
      toast.error('Completa fecha y hora obligatorias')
      return
    }

    try {
      setGuardando(true)

      // Calcular hora_fin según la duración del slot elegido por el médico
      const dur = slotSel?.dur || 30
      const [h, m] = form.hora_inicio.split(':').map(Number)
      const finDate = new Date()
      finDate.setHours(h, m + dur)
      const hora_fin = `${String(finDate.getHours()).padStart(2, '0')}:${String(finDate.getMinutes()).padStart(2, '0')}:00`

      // Toda cita creada desde el portal del paciente nace 'solicitada'
      // (pendiente de aprobación por la clínica), tenga médico o no.
      const estado = 'solicitada'

      // Garantizar clinica_id: si eligió médico pero no hay clínica resuelta,
      // derivar la clínica del médico para que la cita sea visible en el panel
      // de la clínica (el RPC obtener_citas_clinica filtra por clinica_id).
      let clinicaIdFinal = clinicaId
      if (!clinicaIdFinal && medicoId) {
        const { data: relsClinica } = await supabase
          .rpc('obtener_clinicas_medico', { p_medico_id: medicoId })
        clinicaIdFinal = relsClinica?.[0]?.clinica_id || null
      }

      // Asegurar que paisId sea null si está vacío
      const paisIdUuid = paisId || null

      // Usar RPC para saltar el bug de PostgREST schema cache con clinica_id
      const { data: citaIdCreada, error } = await supabase.rpc('crear_cita', {
        p_paciente_id: pacienteId,
        p_medico_id: medicoId,
        p_clinica_id: clinicaIdFinal,
        p_fecha: form.fecha,
        p_hora_inicio: form.hora_inicio,
        p_hora_fin: hora_fin,
        p_motivo: form.motivo || 'Consulta general',
        p_notas: form.notas || null,
        p_estado: estado,
        p_pais_id: paisIdUuid,
      })

      if (error) throw error

      const citaCreada = citaIdCreada ? { id: citaIdCreada } : null

      // Guardar preferencias si el usuario lo pidió
      if (recordarPreferencia && (medicoId || clinicaId)) {
        const updates: any = {}
        if (medicoId) updates.medico_primario_id = medicoId
        if (clinicaId) updates.clinica_primaria_id = clinicaId

        await supabase
          .from('pacientes')
          .update(updates)
          .eq('id', pacienteId)
      }

      // Camino ÚNICO server-side gateado: notificar_cita_solicitada(cita.id) UNA vez al crear la cita.
      // Deriva destinatarios de la cita (médico + admins de la clínica), compone contenido server-side
      // (PHI mínimo, sin motivo) y crea las notif in-app + web-push. Reemplaza los 2 enviar-notificacion
      // (médico + loop admins) + enviar-push (gate = paciente dueño; cero recipient/contenido del caller).
      if (citaCreada?.id) {
        try {
          await supabase.rpc('notificar_cita_solicitada', { p_cita_id: citaCreada.id })
        } catch (notifErr) {
          console.error('Error notificar_cita_solicitada:', notifErr?.message ?? notifErr?.code)
          // No fallar la cita si la notificación falla
        }
      }

      // Programar recordatorio automático 24h antes
      if (citaCreada?.id) {
        try {
          await supabase.functions.invoke('programar-recordatorio', {
            body: {
              tipo: 'cita',
              referencia_id: citaCreada.id,
              horas_antes: 24,
            },
          })
        } catch (recErr) {
          console.error('Error programando recordatorio:', recErr?.message ?? recErr?.code)
        }
      }

      toast.success('Cita solicitada. La clínica la revisará y confirmará.')
      onClose()
      onSuccess?.()
    } catch (err: any) {
      console.error('Error agendando cita:', err?.message ?? err?.code)
      toast.error('Error: ' + (err.message || 'No se pudo agendar la cita'))
    } finally {
      setGuardando(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-lg overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-slate-100 shrink-0">
          <div className="flex items-center gap-2">
            {paso === 2 && (
              <button
                onClick={() => setPaso(1)}
                className="p-1 rounded-lg hover:bg-slate-100 text-slate-400 transition-colors"
              >
                <ChevronLeft className="h-5 w-5" />
              </button>
            )}
            <h2 className="text-lg font-semibold text-slate-800">
              {paso === 1 ? 'Selecciona médico y clínica' : 'Detalles de la cita'}
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-slate-100 text-slate-400 transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto p-4">
          {paso === 1 ? (
            <div className="space-y-6">
              {/* Preferencias del paciente */}
              {(medicoPrimarioId || clinicaPrimariaId) && (
                <div className="bg-sky-50 border border-sky-100 rounded-xl p-3 text-sm">
                  <p className="font-medium text-sky-700 flex items-center gap-2">
                    <Star className="h-4 w-4 fill-sky-500 text-sky-500" />
                    Preferencias guardadas
                  </p>
                  {medicoPrimarioId && (
                    <p className="text-sky-600">
                      Médico: {medicos.find(m => m.id === medicoPrimarioId)?.nombre_completo || '—'}
                    </p>
                  )}
                  {clinicaPrimariaId && (
                    <p className="text-sky-600">
                      Clínica: {clinicas.find(c => c.id === clinicaPrimariaId)?.nombre || '—'}
                    </p>
                  )}
                </div>
              )}

              {/* Búsqueda de médicos */}
              <div className="space-y-3">
                <div className="flex items-center gap-2">
                  <Stethoscope className="h-4 w-4 text-sky-500" />
                  <Label className="text-sm font-medium text-slate-700">Médico (opcional)</Label>
                </div>

                {/* Select de especialidad (filtro duro server-side) */}
                <Select
                  value={especialidadSel || '__all__'}
                  onValueChange={(val) => {
                    const esp = val === '__all__' ? null : val
                    setEspecialidadSel(esp || '')
                    cargarMedicos(esp)
                  }}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Todas las especialidades" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__all__">Todas las especialidades</SelectItem>
                    {especialidades.map((e) => (
                      <SelectItem key={e.id} value={e.id}>{e.nombre}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                {/* Input de búsqueda (solo por nombre) */}
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input
                    placeholder="Buscar por nombre del médico..."
                    value={busquedaMedico}
                    onChange={(e) => setBusquedaMedico(e.target.value)}
                    onFocus={() => setBusquedaFocus(true)}
                    onBlur={() => setTimeout(() => setBusquedaFocus(false), 200)}
                    className="pl-9"
                  />
                </div>

                {cargandoOpciones || cargandoMedicos ? (
                  <div className="flex items-center justify-center py-4">
                    <Loader2 className="h-5 w-5 animate-spin text-sky-500" />
                  </div>
                ) : (
                  <div className="space-y-2">
                    {/* Sin preferencia */}
                    <button
                      type="button"
                      onClick={() => setMedicoId(null)}
                      className={`flex items-center gap-3 p-3 rounded-xl border text-left transition-all w-full ${
                        medicoId === null
                          ? 'border-sky-500 bg-sky-50 ring-1 ring-sky-500'
                          : 'border-slate-200 hover:border-slate-300 bg-white'
                      }`}
                    >
                      <div className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center shrink-0">
                        <User className="h-5 w-5 text-slate-400" />
                      </div>
                      <div>
                        <p className="text-sm font-medium text-slate-800">Sin preferencia</p>
                        <p className="text-xs text-slate-500">Te asignaremos un médico disponible</p>
                      </div>
                    </button>

                    {/* Resultados de búsqueda */}
                    {medicosFiltrados.map((med) => {
                      const proximoTurno = formatProximoTurno(med.proximo_turno)
                      return (
                      <button
                        key={med.id}
                        type="button"
                        onClick={() => setMedicoId(med.id)}
                        className={`flex items-center gap-3 p-3 rounded-xl border text-left transition-all w-full ${
                          medicoId === med.id
                            ? 'border-sky-500 bg-sky-50 ring-1 ring-sky-500'
                            : 'border-slate-200 hover:border-slate-300 bg-white'
                        }`}
                      >
                        <div className="w-10 h-10 rounded-full bg-sky-100 flex items-center justify-center shrink-0">
                          {med.foto_url ? (
                            <img src={med.foto_url} alt="" className="w-10 h-10 rounded-full object-cover" />
                          ) : (
                            <User className="h-5 w-5 text-sky-500" />
                          )}
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-slate-800">
                            {med.nombre_completo?.match(/^Dr\.?\s|^Dra\.?\s/i) ? '' : 'Dr. '}{med.nombre_completo}
                            {med.id === medicoPrimarioId && (
                              <Star className="h-3 w-3 inline ml-1 fill-amber-400 text-amber-400" />
                            )}
                          </p>
                          <p className="text-xs text-slate-500">{med.especialidad || 'Médico general'}</p>
                          {proximoTurno ? (
                            <p className="text-xs font-medium text-emerald-600 flex items-center gap-1">
                              <CalendarDays className="h-3 w-3" />
                              Próximo turno: {proximoTurno}
                            </p>
                          ) : (
                            <p className="text-xs text-slate-400">Sin turnos próximos</p>
                          )}
                        </div>
                        {medicoId === med.id && (
                          <Check className="h-5 w-5 text-sky-500 shrink-0" />
                        )}
                      </button>
                      )
                    })}

                    {medicosFiltrados.length === 0 && busquedaDebounced && (
                      <p className="text-sm text-muted-foreground text-center py-2">
                        No se encontraron médicos para &quot;{busquedaDebounced}&quot;
                      </p>
                    )}
                  </div>
                )}
              </div>

              {/* Clínicas filtradas por médico */}
              <div className="space-y-3">
                <div className="flex items-center gap-2">
                  <MapPin className="h-4 w-4 text-sky-500" />
                  <Label className="text-sm font-medium text-slate-700">
                    Clínica {medicoId && clinicasFiltradas.length > 0 ? `(${clinicasFiltradas.length} disponible${clinicasFiltradas.length !== 1 ? 's' : ''})` : '*'}
                  </Label>
                </div>

                {cargandoOpciones ? (
                  <div className="flex items-center justify-center py-4">
                    <Loader2 className="h-5 w-5 animate-spin text-sky-500" />
                  </div>
                ) : (
                  <div className="space-y-2">
                    {clinicasFiltradas.map((cli) => (
                      <button
                        key={cli.id}
                        type="button"
                        onClick={() => setClinicaId(cli.id)}
                        className={`flex items-center gap-3 p-3 rounded-xl border text-left transition-all w-full ${
                          clinicaId === cli.id
                            ? 'border-sky-500 bg-sky-50 ring-1 ring-sky-500'
                            : 'border-slate-200 hover:border-slate-300 bg-white'
                        }`}
                      >
                        <div className="w-10 h-10 rounded-full bg-emerald-100 flex items-center justify-center shrink-0">
                          <MapPin className="h-5 w-5 text-emerald-600" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-slate-800">
                            {cli.nombre}
                            {cli.id === clinicaPrimariaId && (
                              <Star className="h-3 w-3 inline ml-1 fill-amber-400 text-amber-400" />
                            )}
                          </p>
                        </div>
                        {clinicaId === cli.id && (
                          <Check className="h-5 w-5 text-sky-500 shrink-0" />
                        )}
                      </button>
                    ))}

                    {clinicasFiltradas.length === 0 && medicoId && (
                      <p className="text-sm text-amber-600 text-center py-2">
                        Este médico no tiene clínicas asignadas.
                      </p>
                    )}
                  </div>
                )}
              </div>

              {/* Checkbox recordar preferencia */}
              {(medicoId || clinicaId) && (
                <label className="flex items-center gap-2 cursor-pointer p-3 bg-gray-50 rounded-lg">
                  <input
                    type="checkbox"
                    checked={recordarPreferencia}
                    onChange={(e) => setRecordarPreferencia(e.target.checked)}
                    className="h-4 w-4 rounded border-gray-300 text-sky-600 focus:ring-sky-500"
                  />
                  <span className="text-sm text-gray-700">
                    Recordar como mi preferencia para futuras citas
                  </span>
                </label>
              )}
            </div>
          ) : (
            <form id="cita-form" onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-1.5">
                <Label className="text-xs text-slate-500 flex items-center gap-1">
                  <CalendarDays className="h-3.5 w-3.5" />
                  Elige un horario disponible *
                </Label>
                {!medicoId ? (
                  <p className="text-sm text-amber-600">Selecciona un médico primero para ver sus horarios.</p>
                ) : cargandoSlots ? (
                  <p className="text-sm text-slate-500">Cargando horarios…</p>
                ) : slotsPorDia.length === 0 ? (
                  <p className="text-sm text-amber-600">
                    Este médico no tiene horarios disponibles para pacientes por ahora. Intenta con otro médico.
                  </p>
                ) : (
                  <div className="max-h-64 overflow-y-auto space-y-3 border rounded-lg p-2">
                    {slotsPorDia.map((d) => (
                      <div key={d.fecha}>
                        <p className="text-xs font-semibold text-slate-600 mb-1 capitalize">{d.fechaLabel}</p>
                        <div className="flex flex-wrap gap-1.5">
                          {d.slots.map((s) => {
                            const sel = slotSel?.fecha === d.fecha && slotSel?.hora === s.hora
                            return (
                              <button
                                key={s.hora}
                                type="button"
                                disabled={s.ocupado}
                                onClick={() => {
                                  setSlotSel({ fecha: d.fecha, hora: s.hora, dur: s.dur })
                                  setForm((f) => ({ ...f, fecha: d.fecha, hora_inicio: s.hora }))
                                }}
                                className={`text-xs px-2 py-1 rounded border transition ${
                                  s.ocupado
                                    ? 'opacity-40 line-through cursor-not-allowed'
                                    : sel
                                    ? 'bg-[#1E5C8E] text-white border-[#1E5C8E]'
                                    : 'hover:bg-slate-100 border-slate-200'
                                }`}
                              >
                                {s.hora}
                              </button>
                            )
                          })}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className="space-y-1.5">
                <Label className="text-xs text-slate-500 flex items-center gap-1">
                  <FileText className="h-3.5 w-3.5" />
                  Motivo de consulta
                </Label>
                <Input
                  placeholder="Ej: Dolor de cabeza, control general..."
                  value={form.motivo}
                  onChange={(e) => setForm({ ...form, motivo: e.target.value })}
                  className="h-9 text-sm"
                />
              </div>

              <div className="space-y-1.5">
                <Label className="text-xs text-slate-500 flex items-center gap-1">
                  <StickyNote className="h-3.5 w-3.5" />
                  Notas adicionales
                </Label>
                <textarea
                  placeholder="Síntomas, medicamentos actuales, etc."
                  value={form.notas}
                  onChange={(e) => setForm({ ...form, notas: e.target.value })}
                  className="w-full rounded-md border border-slate-200 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-transparent"
                  rows={3}
                />
              </div>

              {medicoId && (
                <div className="bg-sky-50 border border-sky-100 rounded-lg p-3 text-sm text-sky-700">
                  <p className="font-medium">Médico seleccionado:</p>
                  <p className="text-sky-600">
                    {(() => {
                      const nombre = medicos.find(m => m.id === medicoId)?.nombre_completo || '—'
                      return nombre.match(/^Dr\.?\s|^Dra\.?\s/i) ? nombre : `Dr. ${nombre}`
                    })()}
                  </p>
                </div>
              )}

              {clinicaId && (
                <div className="bg-emerald-50 border border-emerald-100 rounded-lg p-3 text-sm text-emerald-700">
                  <p className="font-medium">Clínica seleccionada:</p>
                  <p className="text-emerald-600">
                    {clinicas.find(c => c.id === clinicaId)?.nombre || '—'}
                  </p>
                </div>
              )}
            </form>
          )}
        </div>

        {/* Footer */}
        <div className="flex gap-2 p-4 border-t border-slate-100 shrink-0">
          <Button type="button" variant="outline" className="flex-1" onClick={onClose}>
            Cancelar
          </Button>
          {paso === 1 ? (
            <Button
              type="button"
              className="flex-1 bg-sky-500 hover:bg-sky-600"
              onClick={() => setPaso(2)}
              disabled={cargandoOpciones || !clinicaId}
            >
              Continuar
              <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          ) : (
            <Button
              type="submit"
              form="cita-form"
              className="flex-1 bg-sky-500 hover:bg-sky-600"
              disabled={guardando || !form.fecha || !form.hora_inicio}
            >
              {guardando ? (
                <Loader2 className="h-4 w-4 animate-spin mr-1" />
              ) : (
                <CalendarDays className="h-4 w-4 mr-1" />
              )}
              {medicoId ? 'Agendar cita' : 'Solicitar cita'}
            </Button>
          )}
        </div>
      </div>
    </div>
  )
}
