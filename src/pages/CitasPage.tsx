// src/pages/CitasPage.tsx
// Dia 20: Citas Avanzado V2 - VERSION HIBRIDA FUNCIONAL
// Muestra citas existentes (medicos de perfiles) + Crea citas nuevas (medicos de tabla medicos)
// EzPayConnect

import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/hooks/useAuth'
import { usePaisFiltro } from '@/hooks/usePaisFiltro'
import {
  Calendar,
  Clock,
  User,
  Stethoscope,
  Bell,
  CheckCircle,
  AlertCircle,
  Plus,
  ChevronLeft,
  ChevronRight,
  Loader2,
  X,
  Play
} from 'lucide-react'

interface Cita {
  id: string
  fecha: string
  hora_inicio: string
  hora_fin: string
  estado: string
  motivo: string
  paciente_id: string
  medico_id: string
  paciente?: { nombre: string; telefono: string }
  medico?: { nombre: string; nombre_completo?: string }
}

interface Paciente {
  id: string
  nombre: string
  telefono: string
}

interface Medico {
  id: string
  nombre: string
  nombre_completo?: string
  especialidad?: string
}

interface Recordatorio {
  id: string
  cita_id: string
  estado: string
  tipo_recordatorio: string
}

export default function CitasPage() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const { paisId } = usePaisFiltro()
  const [citas, setCitas] = useState<Cita[]>([])
  const [recordatorios, setRecordatorios] = useState<Recordatorio[]>([])
  const [loading, setLoading] = useState(true)
  const [fechaSeleccionada, setFechaSeleccionada] = useState(new Date().toISOString().split('T')[0])
  const [vista, setVista] = useState<'dia' | 'semana' | 'mes'>('dia')
  const [programando, setProgramando] = useState<string | null>(null)

  // Modal nueva cita
  const [showModal, setShowModal] = useState(false)
  const [pacientes, setPacientes] = useState<Paciente[]>([])
  const [medicos, setMedicos] = useState<Medico[]>([])
  const [guardando, setGuardando] = useState(false)
  const [nuevaCita, setNuevaCita] = useState({
    paciente_id: '',
    medico_id: '',
    fecha: new Date().toISOString().split('T')[0],
    hora_inicio: '09:00',
    hora_fin: '10:00',
    motivo: '',
    notas: ''
  })

  useEffect(() => {
    cargarCitas()
    cargarRecordatorios()
    cargarPacientesYMedicos()
  }, [fechaSeleccionada])

  // CARGAR CITAS - Version hibrida: busca medicos en AMBAS tablas
  const cargarCitas = async () => {
    setLoading(true)

    // 1. Cargar citas sin join
    let citasQuery = supabase
      .from('citas')
      .select('*')
      .eq('fecha', fechaSeleccionada)
    if (paisId) citasQuery = citasQuery.eq('pais_id', paisId)
    const { data: citasData, error: citasError } = await citasQuery.order('hora_inicio')

    if (citasError) {
      console.error('Error cargando citas:', citasError)
      setCitas([])
      setLoading(false)
      return
    }

    if (!citasData || citasData.length === 0) {
      setCitas([])
      setLoading(false)
      return
    }

    // 2. Obtener IDs únicos
    const pacienteIds = [...new Set(citasData.map(c => c.paciente_id).filter(Boolean))]
    const medicoIds = [...new Set(citasData.map(c => c.medico_id).filter(Boolean))]

    // 3. Cargar pacientes
    let pacientesData: any[] = []
    if (pacienteIds.length > 0) {
      const { data: pacs } = await supabase
        .from('pacientes')
        .select('id, nombre, telefono')
        .in('id', pacienteIds)
      pacientesData = pacs || []
    }

    // 4. Cargar medicos de AMBAS tablas (perfiles + medicos)
    let medicosData: any[] = []
    if (medicoIds.length > 0) {
      // Intentar tabla medicos primero via RPC
      const { data: medsNuevos } = await supabase
        .rpc('obtener_medicos_por_ids', { p_medico_ids: medicoIds })

      // Intentar tabla perfiles como fallback
      const { data: medsViejos } = await supabase
        .from('perfiles')
        .select('id, nombre_completo, especialidad')
        .in('id', medicoIds)
        .eq('rol', 'medico')

      // Combinar: medicos nuevos tienen prioridad
      const medsNuevosMap = new Map((medsNuevos || []).map(m => [m.id, { ...m, nombre: m.nombre_completo }]))
      const medsViejosMap = new Map((medsViejos || []).map(m => [m.id, { ...m, nombre: m.nombre_completo }]))

      // Usar medicos nuevos si existen, sino los viejos
      medicosData = medicoIds.map(id => {
        const nuevo = medsNuevosMap.get(id)
        const viejo = medsViejosMap.get(id)
        return nuevo || viejo || { id, nombre: 'Medico no encontrado' }
      }).filter(Boolean)
    }

    // 5. Combinar datos
    const citasCompletas = citasData.map(cita => ({
      ...cita,
      paciente: pacientesData.find(p => String(p.id) === String(cita.paciente_id)) || null,
      medico: medicosData.find(m => String(m.id) === String(cita.medico_id)) || null
    }))

    setCitas(citasCompletas)
    setLoading(false)
  }

  const cargarRecordatorios = async () => {
    if (citas.length === 0) return
    const { data } = await supabase
      .from('recordatorios_programados')
      .select('*')
      .in('cita_id', citas.map(c => c.id))
    setRecordatorios(data || [])
  }

  // Cargar pacientes y medicos para el MODAL (solo tabla medicos)
  const cargarPacientesYMedicos = async () => {
    let pacsQuery = supabase
      .from('pacientes')
      .select('id, nombre, telefono')
      .order('nombre')
    if (paisId) pacsQuery = pacsQuery.eq('pais_id', paisId)
    const { data: pacs } = await pacsQuery

    const { data: meds } = await supabase
      .rpc('listar_medicos_por_pais', { p_pais_id: paisId || undefined })

    setPacientes(pacs || [])
    setMedicos(meds || [])
  }

  const guardarCita = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!nuevaCita.paciente_id || !nuevaCita.medico_id || !nuevaCita.fecha) {
      alert('Paciente, medico y fecha son obligatorios')
      return
    }

    setGuardando(true)
    try {
      const { data: citaCreada, error } = await supabase.from('citas').insert({
        paciente_id: parseInt(nuevaCita.paciente_id),
        medico_id: nuevaCita.medico_id,
        fecha: nuevaCita.fecha,
        hora_inicio: nuevaCita.hora_inicio,
        hora_fin: nuevaCita.hora_fin,
        motivo: nuevaCita.motivo,
        notas: nuevaCita.notas,
        estado: 'agendada',
        pais_id: paisId,
      }).select().single()

      if (error) throw error

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
          console.error('Error programando recordatorio:', recErr)
        }
      }

      alert('Cita creada exitosamente')
      setShowModal(false)
      setNuevaCita({
        paciente_id: '', medico_id: '', fecha: new Date().toISOString().split('T')[0],
        hora_inicio: '09:00', hora_fin: '10:00', motivo: '', notas: ''
      })
      cargarCitas()
    } catch (err: any) {
      alert('Error: ' + err.message)
    } finally {
      setGuardando(false)
    }
  }

  const programarRecordatorio = async (cita: Cita) => {
    setProgramando(cita.id)
    try {
      const { data: result, error: fnError } = await supabase.functions.invoke('programar-recordatorio', {
        body: {
          tipo: 'cita',
          referencia_id: cita.id,
          horas_antes: 24
        }
      })

      if (fnError) throw fnError

      if (result?.success) {
        alert('Recordatorio programado: ' + result.data.estado)
        cargarRecordatorios()
      } else {
        alert('Error: ' + result?.error)
      }
    } catch (err: any) {
      alert('Error: ' + err.message)
    } finally {
      setProgramando(null)
    }
  }

  const cambiarFecha = (dias: number) => {
    const fecha = new Date(fechaSeleccionada)
    fecha.setDate(fecha.getDate() + dias)
    setFechaSeleccionada(fecha.toISOString().split('T')[0])
  }

  const getRecordatoriosCita = (citaId: string) => {
    return recordatorios.filter(r => r.cita_id === citaId)
  }

  const getIconoEstado = (estado: string) => {
    switch (estado) {
      case 'completada':
      case 'atendida': return <CheckCircle size={16} className="text-green-500" />
      case 'cancelada': return <AlertCircle size={16} className="text-red-500" />
      case 'en_curso': return <Play size={16} className="text-amber-500" />
      case 'no_show': return <AlertCircle size={16} className="text-red-700" />
      default: return <Clock size={16} className="text-yellow-500" />
    }
  }

  if (loading) return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" />
    </div>
  )

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-[#1a2a3a] mb-2 flex items-center gap-3">
          <Calendar size={32} className="text-[#1E5C8E]" />
          Citas Avanzadas
        </h1>
        <p className="text-gray-500">Gestion de citas medicas con recordatorios automaticos</p>
      </div>

      <div className="flex items-center justify-between mb-6 bg-white p-4 rounded-lg shadow-sm">
        <div className="flex items-center gap-4">
          <button onClick={() => cambiarFecha(-1)} className="p-2 hover:bg-gray-100 rounded-lg">
            <ChevronLeft size={20} className="text-[#1E5C8E]" />
          </button>
          <div className="text-center">
            <p className="text-sm text-gray-500">Fecha seleccionada</p>
            <p className="text-lg font-semibold text-[#1a2a3a]">
              {new Date(fechaSeleccionada).toLocaleDateString('es-ES', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
            </p>
          </div>
          <button onClick={() => cambiarFecha(1)} className="p-2 hover:bg-gray-100 rounded-lg">
            <ChevronRight size={20} className="text-[#1E5C8E]" />
          </button>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => setFechaSeleccionada(new Date().toISOString().split('T')[0])}
            className="px-4 py-2 bg-gray-100 hover:bg-gray-200 rounded-lg text-sm font-medium"
          >
            Hoy
          </button>
          <input
            type="date"
            value={fechaSeleccionada}
            onChange={(e) => setFechaSeleccionada(e.target.value)}
            className="px-4 py-2 border border-gray-200 rounded-lg"
          />
        </div>
      </div>

      <div className="flex gap-2 mb-6">
        {['dia', 'semana', 'mes'].map(v => (
          <button
            key={v}
            onClick={() => setVista(v as any)}
            className={`px-4 py-2 rounded-lg font-medium capitalize transition-colors ${
              vista === v ? 'bg-[#1E5C8E] text-white' : 'bg-white text-gray-600 hover:bg-gray-100'
            }`}
          >
            {v === 'dia' ? 'Dia' : v === 'semana' ? 'Semana' : 'Mes'}
          </button>
        ))}
      </div>

      <div className="space-y-4">
        {citas.length === 0 ? (
          <div className="bg-white rounded-xl shadow-sm p-12 text-center text-gray-400">
            <Calendar size={48} className="mx-auto mb-4" />
            <p className="text-lg">No hay citas programadas para esta fecha</p>
            <button 
              onClick={() => setShowModal(true)}
              className="mt-4 px-4 py-2 bg-[#1E5C8E] text-white rounded-lg flex items-center gap-2 mx-auto hover:bg-[#3A8ABF] transition-colors"
            >
              <Plus size={18} /> Nueva Cita
            </button>
          </div>
        ) : (
          citas.map(cita => {
            const recs = getRecordatoriosCita(cita.id)
            const tieneRecordatorio = recs.length > 0
            const recordatorioEnviado = recs.some(r => r.estado === 'enviado')
            const recordatorioConfirmado = recs.some(r => r.estado === 'confirmado')

            return (
              <div key={cita.id} className={`bg-white rounded-xl shadow-sm border-l-4 overflow-hidden ${
                cita.estado === 'completada' || cita.estado === 'atendida' ? 'border-green-500' :
                cita.estado === 'cancelada' ? 'border-red-500' :
                cita.estado === 'en_curso' ? 'border-amber-500' :
                cita.estado === 'no_show' ? 'border-red-700' :
                'border-[#1E5C8E]'
              }`}>
                <div className="p-6">
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <div className="flex items-center gap-3 mb-2">
                        <div className="bg-[#1E5C8E]/10 p-2 rounded-lg">
                          <Clock size={20} className="text-[#1E5C8E]" />
                        </div>
                        <div>
                          <p className="text-lg font-semibold text-[#1a2a3a]">
                            {cita.hora_inicio} - {cita.hora_fin}
                          </p>
                          <span className={`inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium ${
                            cita.estado === 'completada' || cita.estado === 'atendida' ? 'bg-green-100 text-green-700' :
                            cita.estado === 'cancelada' ? 'bg-red-100 text-red-700' :
                            cita.estado === 'en_curso' ? 'bg-amber-100 text-amber-700' :
                            cita.estado === 'no_show' ? 'bg-red-200 text-red-800' :
                            'bg-yellow-100 text-yellow-700'
                          }`}>
                            {getIconoEstado(cita.estado)}
                            {cita.estado.replace('_', ' ')}
                          </span>
                        </div>
                      </div>

                      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4">
                        <div className="flex items-center gap-2">
                          <User size={16} className="text-gray-400" />
                          <div>
                            <p className="font-medium">{cita.paciente?.nombre || 'Paciente'}</p>
                            <p className="text-sm text-gray-500">{cita.paciente?.telefono || 'Sin telefono'}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Stethoscope size={16} className="text-gray-400" />
                          <p className="font-medium">
                            {cita.medico?.nombre_completo || cita.medico?.nombre || 'Medico'}
                            {cita.medico?.especialidad ? ` (${cita.medico.especialidad})` : ''}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-gray-500">Motivo:</p>
                          <p className="font-medium">{cita.motivo || 'No especificado'}</p>
                        </div>
                      </div>
                    </div>

                    <div className="flex flex-col gap-2">
                      {(cita.estado === 'solicitada' || cita.estado === 'agendada' || cita.estado === 'confirmada') && (
                        <button
                          onClick={() => navigate(`/consulta/${cita.id}`)}
                          className="px-4 py-2 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg text-sm font-medium flex items-center gap-2 transition-colors"
                        >
                          <Stethoscope size={16} />
                          Atender
                        </button>
                      )}

                      {cita.estado === 'en_curso' && (
                        <button
                          onClick={() => navigate(`/consulta/${cita.id}`)}
                          className="px-4 py-2 bg-amber-600 hover:bg-amber-700 text-white rounded-lg text-sm font-medium flex items-center gap-2 transition-colors"
                        >
                          <Play size={16} />
                          Continuar Consulta
                        </button>
                      )}

                      {!tieneRecordatorio && (cita.estado === 'solicitada' || cita.estado === 'agendada' || cita.estado === 'confirmada') && (
                        <button
                          onClick={() => programarRecordatorio(cita)}
                          disabled={programando === cita.id}
                          className="px-4 py-2 bg-white border border-[#1E5C8E] text-[#1E5C8E] hover:bg-[#1E5C8E]/5 rounded-lg text-sm font-medium flex items-center gap-2 transition-colors disabled:opacity-50"
                        >
                          {programando === cita.id ? (
                            <Loader2 size={16} className="animate-spin" />
                          ) : (
                            <Bell size={16} />
                          )}
                          {programando === cita.id ? 'Programando...' : 'Recordatorio'}
                        </button>
                      )}

                      {tieneRecordatorio && (
                        <div className="flex flex-col gap-1">
                          <span className={`inline-flex items-center gap-1 px-3 py-1 rounded-full text-xs font-medium ${
                            recordatorioConfirmado ? 'bg-green-100 text-green-700' :
                            recordatorioEnviado ? 'bg-blue-100 text-blue-700' :
                            'bg-yellow-100 text-yellow-700'
                          }`}>
                            {recordatorioConfirmado ? <CheckCircle size={12} /> :
                             recordatorioEnviado ? <Bell size={12} /> :
                             <Clock size={12} />}
                            {recordatorioConfirmado ? 'Confirmado' :
                             recordatorioEnviado ? 'Enviado' :
                             'Pendiente'}
                          </span>
                          <span className="text-xs text-gray-500">
                            {recs.length} recordatorio{recs.length > 1 ? 's' : ''}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            )
          })
        )}
      </div>

      <button
        onClick={() => setShowModal(true)}
        className="fixed bottom-8 right-8 px-6 py-4 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-full shadow-lg font-semibold flex items-center gap-2 transition-colors"
      >
        <Plus size={20} /> Nueva Cita
      </button>

      {showModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-lg w-full max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b border-gray-100 flex items-center justify-between">
              <h2 className="text-xl font-semibold text-[#1a2a3a]">Nueva Cita</h2>
              <button onClick={() => setShowModal(false)} className="p-2 hover:bg-gray-100 rounded-lg">
                <X size={20} className="text-gray-400" />
              </button>
            </div>

            <form onSubmit={guardarCita} className="p-6 space-y-4">
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Paciente *</label>
                <div className="relative">
                  <select
                    value={nuevaCita.paciente_id}
                    onChange={e => setNuevaCita({...nuevaCita, paciente_id: e.target.value})}
                    required
                    className="w-full p-3 border border-gray-200 rounded-lg appearance-none focus:outline-none focus:border-[#1E5C8E]"
                  >
                    <option value="">Seleccionar paciente</option>
                    {pacientes.map(p => (
                      <option key={p.id} value={p.id}>{p.nombre} - {p.telefono}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="text-sm text-gray-500 mb-1 block">Medico *</label>
                <div className="relative">
                  <select
                    value={nuevaCita.medico_id}
                    onChange={e => setNuevaCita({...nuevaCita, medico_id: e.target.value})}
                    required
                    className="w-full p-3 border border-gray-200 rounded-lg appearance-none focus:outline-none focus:border-[#1E5C8E]"
                  >
                    <option value="">Seleccionar medico</option>
                    {medicos.map(m => (
                      <option key={m.id} value={m.id}>
                        {m.nombre_completo || m.nombre} {m.especialidad ? `(${m.especialidad})` : ''}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="text-sm text-gray-500 mb-1 block">Fecha *</label>
                <input
                  type="date"
                  value={nuevaCita.fecha}
                  onChange={e => setNuevaCita({...nuevaCita, fecha: e.target.value})}
                  required
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Hora inicio *</label>
                  <input
                    type="time"
                    value={nuevaCita.hora_inicio}
                    onChange={e => setNuevaCita({...nuevaCita, hora_inicio: e.target.value})}
                    required
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Hora fin *</label>
                  <input
                    type="time"
                    value={nuevaCita.hora_fin}
                    onChange={e => setNuevaCita({...nuevaCita, hora_fin: e.target.value})}
                    required
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
              </div>

              <div>
                <label className="text-sm text-gray-500 mb-1 block">Motivo</label>
                <input
                  value={nuevaCita.motivo}
                  onChange={e => setNuevaCita({...nuevaCita, motivo: e.target.value})}
                  placeholder="Consulta general, control, etc."
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>

              <div>
                <label className="text-sm text-gray-500 mb-1 block">Notas</label>
                <textarea
                  value={nuevaCita.notas}
                  onChange={e => setNuevaCita({...nuevaCita, notas: e.target.value})}
                  rows={3}
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>

              <div className="flex gap-3 pt-4">
                <button
                  type="submit"
                  disabled={guardando}
                  className="flex-1 py-3 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
                >
                  {guardando ? <Loader2 size={18} className="animate-spin" /> : <Plus size={18} />}
                  {guardando ? 'Guardando...' : 'Crear Cita'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="px-6 py-3 bg-gray-100 hover:bg-gray-200 rounded-lg font-semibold transition-colors"
                >
                  Cancelar
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
