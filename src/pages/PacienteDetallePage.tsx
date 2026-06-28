// src/pages/PacienteDetallePage.tsx
// Dia 17: Paciente Detalle Avanzado - Usa supabase.functions.invoke (evita CORS)
// EzPayConnect

import { useState, useEffect } from 'react'
import { useParams, useNavigate, useLocation } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { openSignedUrl } from '@/lib/signedUrl'
import { useAuth } from '@/hooks/useAuth'
import { FotoPacienteAvatar } from '@/components/FotoPacienteAvatar'
import { DocumentosPaciente } from '@/components/DocumentosPaciente'
import {
  ArrowLeft,
  User,
  Calendar,
  FileText,
  History,
  Stethoscope,
  AlertCircle,
  Loader2,
  QrCode,
  Download,
  FlaskConical,
  Bell,
  X,
  Activity,
  ClipboardList,
  HeartPulse,
  Thermometer,
  Scale,
  Ruler,
  Droplets,
  Gauge,
  Wind,
} from 'lucide-react'

interface Paciente {
  id: string
  nombre: string
  apellido: string
  telefono: string
  email?: string
  fecha_nacimiento?: string
  created_at: string
  foto_path?: string | null
}

interface HistorialEvento {
  id: string
  tipo_evento: string
  titulo: string
  descripcion: string
  fecha_evento: string
  metadata?: any
}

interface RecetaAvanzada {
  id: string
  codigo_qr: string
  firma_digital: string
  estado_dispensacion: string
  created_at: string
}

interface Cita {
  id: string
  fecha: string
  hora: string
  estado: string
  motivo?: string
}

export default function PacienteDetallePage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const location = useLocation()
  const base = location.pathname.startsWith('/medico') ? '/medico' : ''
  const { user } = useAuth()
  const [activeTab, setActiveTab] = useState<'info' | 'historial' | 'consultas' | 'signos_vitales' | 'recetas' | 'citas' | 'examenes'>('info')
  const [paciente, setPaciente] = useState<Paciente | null>(null)
  const [historial, setHistorial] = useState<HistorialEvento[]>([])
  const [recetas, setRecetas] = useState<RecetaAvanzada[]>([])
  const [citas, setCitas] = useState<Cita[]>([])
  const [consultas, setConsultas] = useState<any[]>([])
  const [signosVitales, setSignosVitales] = useState<any[]>([])
  const [examenes, setExamenes] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const [showRecetaModal, setShowRecetaModal] = useState(false)
  const [recetaData, setRecetaData] = useState<any>(null)
  const [generandoReceta, setGenerandoReceta] = useState(false)

  useEffect(() => {
    if (id) {
      cargarPaciente()
      cargarHistorial()
      cargarRecetas()
      cargarCitas()
      cargarConsultas()
      cargarSignosVitales()
      cargarExamenes()
    }
  }, [id])

  const cargarExamenes = async () => {
    const { data } = await supabase
      .from('examenes')
      .select('id, tipo, descripcion, estado, resultados, archivo_url, fecha_solicitud, fecha_resultado, orden_id, laboratorio_id')
      .eq('paciente_id', id)
      .order('created_at', { ascending: false })
    setExamenes(data || [])
  }

  const cargarPaciente = async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('pacientes')
      .select('*')
      .eq('id', id)
      .single()

    if (error) {
      setError('Error cargando paciente')
      console.error(error)
    } else {
      setPaciente(data)
    }
    setLoading(false)
  }

  const cargarHistorial = async () => {
    const { data } = await supabase
      .from('historial_medico')
      .select('*')
      .eq('paciente_id', id)
      .order('fecha_evento', { ascending: false })
    setHistorial(data || [])
  }

  const cargarRecetas = async () => {
    // NO traer dispatch_token / dispatch_token_expira_at al cliente médico (es el secreto
    // del QR del paciente; no se muestra ni se usa aquí). Lista explícita en vez de '*'.
    const { data } = await supabase
      .from('recetas_avanzadas')
      .select('id, receta_base_id, paciente_id, medico_id, codigo_qr, firma_digital, estado_dispensacion, farmacia_id, fecha_dispensacion, pdf_url, created_at, updated_at')
      .eq('paciente_id', id)
      .order('created_at', { ascending: false })
    setRecetas(data || [])
  }

  const cargarCitas = async () => {
    const { data } = await supabase
      .from('citas')
      .select('*')
      .eq('paciente_id', id)
      .order('fecha', { ascending: false })
    setCitas(data || [])
  }

  const cargarConsultas = async () => {
    const { data } = await supabase
      .from('expediente_notas')
      .select('*, perfiles(nombre_completo)')
      .eq('paciente_id', id)
      .order('created_at', { ascending: false })
    setConsultas(data || [])
  }

  const cargarSignosVitales = async () => {
    const { data } = await supabase
      .from('signos_vitales')
      .select('*')
      .eq('paciente_id', id)
      .order('fecha_toma', { ascending: false })
      .limit(20)
    setSignosVitales(data || [])
  }

  const generarRecetaAvanzada = async () => {
    if (!paciente || !user) return
    setGenerandoReceta(true)

    try {
      // Obtener receta base
      const { data: recetaBase } = await supabase
        .from('recetas')
        .select('*')
        .eq('paciente_id', id)
        .order('created_at', { ascending: false })
        .limit(1)
        .single()

      // Usar supabase.functions.invoke en lugar de fetch (evita CORS)
      const { data: result, error: fnError } = await supabase.functions.invoke('generar-pdf-receta', {
        body: {
          receta_id: recetaBase?.id || 'nueva',
          paciente_id: id,
          medico_id: user.id,
          medicamentos: recetaBase?.medicamentos || ['Paracetamol 500mg'],
          diagnostico: recetaBase?.diagnostico || 'Consulta general',
          indicaciones: recetaBase?.indicaciones || 'Tomar cada 8 horas'
        }
      })

      if (fnError) throw fnError

      if (result?.success) {
        setRecetaData(result.data)
        setShowRecetaModal(true)
        cargarRecetas()
        alert('Receta avanzada generada con QR')
      } else {
        alert('Error: ' + (result?.error || 'Error desconocido'))
      }
    } catch (err: any) {
      console.error('Error generando receta:', err)
      alert('Error: ' + (err.message || 'Error de conexion'))
    } finally {
      setGenerandoReceta(false)
    }
  }

  const enviarRecordatorio = async (citaId: string) => {
    try {
      const { data: result, error: fnError } = await supabase.functions.invoke('enviar-recordatorio', {
        body: {
          cita_id: citaId,
          tipo_recordatorio: 'whatsapp'
        }
      })

      if (fnError) throw fnError

      if (result?.success) {
        alert(`Recordatorio programado para: ${new Date(result.data.fecha_programada).toLocaleString('es-ES')}`)
      } else {
        alert('Error: ' + (result?.error || 'Error desconocido'))
      }
    } catch (err: any) {
      console.error('Error enviando recordatorio:', err)
      alert('Error: ' + (err.message || 'Error de conexion'))
    }
  }

  const descargarHTML = () => {
    if (!recetaData?.html) return
    const blob = new Blob([recetaData.html], { type: 'text/html' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `receta_${recetaData.receta_avanzada_id || 'descarga'}.html`
    document.body.appendChild(a)
    a.click()
    URL.revokeObjectURL(url)
    document.body.removeChild(a)
  }

  const getIconoEvento = (tipo: string) => {
    switch (tipo) {
      case 'cita': return <Calendar size={18} className="text-[#1E5C8E]" />
      case 'receta': return <FileText size={18} className="text-green-600" />
      case 'diagnostico': return <Stethoscope size={18} className="text-yellow-600" />
      default: return <History size={18} className="text-gray-400" />
    }
  }

  if (loading) return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" />
    </div>
  )

  if (error || !paciente) return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center text-red-500">
      <AlertCircle size={48} className="mr-2" /> {error || 'Paciente no encontrado'}
    </div>
  )

  // Cita "activa" del paciente para entrar directo a la consulta (dictado/IA/biblioteca).
  // Prioriza una en curso; si no, una confirmada.
  const citaActiva =
    citas.find((c: any) => c.estado === 'en_curso') ||
    citas.find((c: any) => c.estado === 'confirmada')

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      {/* Header */}
      <div className="flex items-center gap-4 mb-8">
        <button
          onClick={() => navigate(`${base}/pacientes`)}
          className="p-2 bg-white rounded-lg hover:bg-gray-100 transition-colors shadow-sm"
        >
          <ArrowLeft size={24} className="text-[#1E5C8E]" />
        </button>
        <FotoPacienteAvatar pacienteId={Number(paciente.id)} fotoPath={paciente.foto_path ?? null} size="lg" />
        <div className="flex-1">
          <h1 className="text-3xl font-bold text-[#1a2a3a] flex items-center gap-3">
            <User size={32} className="text-[#1E5C8E]" />
            {paciente.nombre} {paciente.apellido}
          </h1>
          <p className="text-gray-500">{paciente.telefono} {paciente.email && `| ${paciente.email}`}</p>
        </div>
        {citaActiva && (
          <button
            onClick={() => navigate(`${base}/consulta/${citaActiva.id}`)}
            className="flex items-center gap-2 px-5 py-3 bg-[#1E5C8E] hover:bg-[#164a70] text-white rounded-lg font-medium shadow-sm transition-colors"
          >
            <Stethoscope size={20} />
            {citaActiva.estado === 'en_curso' ? 'Continuar consulta' : 'Iniciar consulta'}
          </button>
        )}
      </div>

      {/* Tabs */}
      <div className="flex gap-2 mb-6 overflow-x-auto bg-white p-2 rounded-lg shadow-sm">
        {[
          { key: 'info', label: 'Informacion', icon: User },
          { key: 'historial', label: 'Historial Medico', icon: History },
          { key: 'consultas', label: 'Consultas', icon: ClipboardList },
          { key: 'signos_vitales', label: 'Signos Vitales', icon: Activity },
          { key: 'recetas', label: 'Recetas Avanzadas', icon: FileText },
          { key: 'examenes', label: 'Exámenes', icon: FlaskConical },
          { key: 'citas', label: 'Citas', icon: Calendar },
        ].map(tab => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key as any)}
            className={`px-5 py-3 rounded-lg font-semibold flex items-center gap-2 whitespace-nowrap transition-all ${
              activeTab === tab.key
                ? 'bg-[#1E5C8E] text-white'
                : 'bg-transparent text-gray-600 hover:bg-gray-100'
            }`}
          >
            <tab.icon size={18} />
            {tab.label}
          </button>
        ))}
      </div>

      {/* === TAB: INFORMACION === */}
      {activeTab === 'info' && (
        <div className="bg-white rounded-xl shadow-sm p-6">
          <h2 className="text-xl font-semibold text-[#1a2a3a] mb-6">Datos del Paciente</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="bg-gray-50 p-4 rounded-lg">
              <label className="text-sm text-gray-500">Nombre completo</label>
              <p className="text-lg font-medium text-[#1a2a3a]">{paciente.nombre} {paciente.apellido}</p>
            </div>
            <div className="bg-gray-50 p-4 rounded-lg">
              <label className="text-sm text-gray-500">Telefono</label>
              <p className="text-lg font-medium text-[#1a2a3a]">{paciente.telefono}</p>
            </div>
            {paciente.email && (
              <div className="bg-gray-50 p-4 rounded-lg">
                <label className="text-sm text-gray-500">Email</label>
                <p className="text-lg font-medium text-[#1a2a3a]">{paciente.email}</p>
              </div>
            )}
            {paciente.fecha_nacimiento && (
              <div className="bg-gray-50 p-4 rounded-lg">
                <label className="text-sm text-gray-500">Fecha de nacimiento</label>
                <p className="text-lg font-medium text-[#1a2a3a]">{paciente.fecha_nacimiento}</p>
              </div>
            )}
            <div className="bg-gray-50 p-4 rounded-lg">
              <label className="text-sm text-gray-500">Tipo de sangre</label>
              <p className="text-lg font-medium text-[#1a2a3a]">{paciente.tipo_sangre || 'No registrado'}</p>
            </div>
            <div className="bg-gray-50 p-4 rounded-lg">
              <label className="text-sm text-gray-500">Registrado desde</label>
              <p className="text-lg font-medium text-[#1a2a3a]">{new Date(paciente.created_at).toLocaleDateString('es-ES')}</p>
            </div>
            {(paciente.alergias || paciente.antecedentes_personales || paciente.antecedentes_familiares || paciente.medicamentos_en_uso) && (
              <div className="md:col-span-2 bg-amber-50 p-4 rounded-lg border border-amber-200">
                <h3 className="text-sm font-semibold text-amber-800 mb-2 flex items-center gap-2">
                  <AlertCircle size={16} />
                  Informacion Clinica Relevante
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                  {paciente.alergias && (
                    <div>
                      <span className="font-medium text-amber-700">Alergias:</span>
                      <p className="text-amber-600">{paciente.alergias}</p>
                    </div>
                  )}
                  {paciente.antecedentes_personales && (
                    <div>
                      <span className="font-medium text-amber-700">Antecedentes personales:</span>
                      <p className="text-amber-600">{paciente.antecedentes_personales}</p>
                    </div>
                  )}
                  {paciente.antecedentes_familiares && (
                    <div>
                      <span className="font-medium text-amber-700">Antecedentes familiares:</span>
                      <p className="text-amber-600">{paciente.antecedentes_familiares}</p>
                    </div>
                  )}
                  {paciente.medicamentos_en_uso && (
                    <div>
                      <span className="font-medium text-amber-700">Medicacion habitual:</span>
                      <p className="text-amber-600">{paciente.medicamentos_en_uso}</p>
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* === DOCUMENTOS DEL PACIENTE (plomería base — siempre visible para QA staff) === */}
      <div className="bg-white rounded-xl shadow-sm p-6">
        <h2 className="text-xl font-semibold text-[#1a2a3a] mb-4 flex items-center gap-2">
          <FileText size={22} className="text-[#1E5C8E]" /> Documentos
        </h2>
        <DocumentosPaciente pacienteId={Number(paciente.id)} editable />
      </div>

      {/* === TAB: HISTORIAL MEDICO === */}
      {activeTab === 'historial' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className="p-6 border-b border-gray-100">
            <h2 className="text-xl font-semibold text-[#1a2a3a] flex items-center gap-2">
              <History size={22} className="text-[#1E5C8E]" />
              Historial Medico
            </h2>
          </div>
          <div className="p-6">
            {historial.length === 0 ? (
              <div className="text-center text-gray-400 py-12">No hay eventos en el historial</div>
            ) : (
              <div className="space-y-4">
                {historial.map(evento => (
                  <div key={evento.id} className="flex gap-4 bg-gray-50 p-4 rounded-lg border-l-4 border-[#1E5C8E]">
                    <div className="mt-1">{getIconoEvento(evento.tipo_evento)}</div>
                    <div className="flex-1">
                      <div className="flex items-center justify-between mb-1">
                        <h3 className="font-semibold text-[#1a2a3a]">{evento.titulo}</h3>
                        <span className="text-sm text-gray-400">{new Date(evento.fecha_evento).toLocaleDateString('es-ES')}</span>
                      </div>
                      <p className="text-gray-600 text-sm">{evento.descripcion}</p>
                      {evento.metadata?.estado && (
                        <div className="mt-2">
                          <span className={`px-2 py-1 rounded text-xs font-medium ${
                            evento.metadata.estado === 'atendida' ? 'bg-green-100 text-green-700' :
                            evento.metadata.estado === 'cancelada' ? 'bg-red-100 text-red-700' :
                            'bg-yellow-100 text-yellow-700'
                          }`}>
                            {evento.metadata.estado}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* === TAB: CONSULTAS === */}
      {activeTab === 'consultas' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className="p-6 border-b border-gray-100">
            <h2 className="text-xl font-semibold text-[#1a2a3a] flex items-center gap-2">
              <ClipboardList size={22} className="text-[#1E5C8E]" />
              Historial de Consultas
            </h2>
          </div>
          <div className="p-6">
            {consultas.length === 0 ? (
              <div className="text-center text-gray-400 py-12">No hay consultas registradas</div>
            ) : (
              <div className="space-y-4">
                {consultas.map((consulta: any) => (
                  <div key={consulta.id} className="bg-gray-50 p-4 rounded-lg border-l-4 border-[#1E5C8E]">
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-sm font-medium text-[#1a2a3a]">
                        {new Date(consulta.created_at).toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' })}
                      </span>
                      <span className="text-xs text-gray-400">
                        Dr. {consulta.perfiles?.nombre_completo || 'Medico'}
                      </span>
                    </div>
                    {consulta.motivo_consulta && (
                      <p className="text-sm text-gray-600 mb-1"><span className="font-medium">Motivo:</span> {consulta.motivo_consulta}</p>
                    )}
                    {consulta.diagnostico && (
                      <p className="text-sm text-gray-600 mb-1"><span className="font-medium">Diagnostico:</span> {consulta.diagnostico}</p>
                    )}
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mt-3">
                      {consulta.presion_arterial && (
                        <div className="bg-white p-2 rounded text-center">
                          <HeartPulse size={14} className="mx-auto text-red-500 mb-1" />
                          <p className="text-xs text-gray-500">PA</p>
                          <p className="text-sm font-medium">{consulta.presion_arterial}</p>
                        </div>
                      )}
                      {consulta.temperatura && (
                        <div className="bg-white p-2 rounded text-center">
                          <Thermometer size={14} className="mx-auto text-orange-500 mb-1" />
                          <p className="text-xs text-gray-500">Temp</p>
                          <p className="text-sm font-medium">{consulta.temperatura}°C</p>
                        </div>
                      )}
                      {consulta.peso_kg && (
                        <div className="bg-white p-2 rounded text-center">
                          <Scale size={14} className="mx-auto text-blue-500 mb-1" />
                          <p className="text-xs text-gray-500">Peso</p>
                          <p className="text-sm font-medium">{consulta.peso_kg} kg</p>
                        </div>
                      )}
                      {consulta.imc && (
                        <div className="bg-white p-2 rounded text-center">
                          <Gauge size={14} className="mx-auto text-emerald-500 mb-1" />
                          <p className="text-xs text-gray-500">IMC</p>
                          <p className="text-sm font-medium">{consulta.imc}</p>
                        </div>
                      )}
                    </div>
                    {(consulta.subjetivo || consulta.objetivo || consulta.analisis || consulta.plan) && (
                      <div className="mt-3 space-y-1 text-xs text-gray-600">
                        {consulta.subjetivo && <p><span className="font-medium">S:</span> {consulta.subjetivo.substring(0, 100)}{consulta.subjetivo.length > 100 ? '...' : ''}</p>}
                        {consulta.objetivo && <p><span className="font-medium">O:</span> {consulta.objetivo.substring(0, 100)}{consulta.objetivo.length > 100 ? '...' : ''}</p>}
                        {consulta.analisis && <p><span className="font-medium">A:</span> {consulta.analisis.substring(0, 100)}{consulta.analisis.length > 100 ? '...' : ''}</p>}
                        {consulta.plan && <p><span className="font-medium">P:</span> {consulta.plan.substring(0, 100)}{consulta.plan.length > 100 ? '...' : ''}</p>}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* === TAB: SIGNOS VITALES === */}
      {activeTab === 'signos_vitales' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className="p-6 border-b border-gray-100">
            <h2 className="text-xl font-semibold text-[#1a2a3a] flex items-center gap-2">
              <Activity size={22} className="text-[#1E5C8E]" />
              Evolucion de Signos Vitales
            </h2>
          </div>
          <div className="p-6">
            {signosVitales.length === 0 ? (
              <div className="text-center text-gray-400 py-12">No hay signos vitales registrados</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="bg-gray-50 text-gray-500">
                      <th className="px-4 py-3 text-left">Fecha</th>
                      <th className="px-4 py-3 text-center">PA</th>
                      <th className="px-4 py-3 text-center">FC</th>
                      <th className="px-4 py-3 text-center">Temp</th>
                      <th className="px-4 py-3 text-center">Peso</th>
                      <th className="px-4 py-3 text-center">Talla</th>
                      <th className="px-4 py-3 text-center">IMC</th>
                      <th className="px-4 py-3 text-center">SpO2</th>
                      <th className="px-4 py-3 text-center">Glucosa</th>
                    </tr>
                  </thead>
                  <tbody>
                    {signosVitales.map((sv: any) => (
                      <tr key={sv.id} className="border-t border-gray-100 hover:bg-gray-50">
                        <td className="px-4 py-3">{new Date(sv.fecha_toma).toLocaleDateString('es-ES')}</td>
                        <td className="px-4 py-3 text-center font-medium">{sv.presion_arterial || '-'}</td>
                        <td className="px-4 py-3 text-center">{sv.frecuencia_cardiaca || '-'}</td>
                        <td className="px-4 py-3 text-center">{sv.temperatura ? `${sv.temperatura}°C` : '-'}</td>
                        <td className="px-4 py-3 text-center">{sv.peso_kg ? `${sv.peso_kg} kg` : '-'}</td>
                        <td className="px-4 py-3 text-center">{sv.talla_cm ? `${sv.talla_cm} cm` : '-'}</td>
                        <td className="px-4 py-3 text-center font-medium text-[#1E5C8E]">{sv.imc || '-'}</td>
                        <td className="px-4 py-3 text-center">{sv.saturacion_o2 ? `${sv.saturacion_o2}%` : '-'}</td>
                        <td className="px-4 py-3 text-center">{sv.glucosa || '-'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      )}

      {/* === TAB: RECETAS AVANZADAS === */}
      {activeTab === 'recetas' && (
        <div>
          <div className="flex justify-between items-center mb-6">
            <h2 className="text-xl font-semibold text-[#1a2a3a] flex items-center gap-2">
              <FileText size={22} className="text-[#1E5C8E]" />
              Recetas Avanzadas
            </h2>
            <button
              onClick={generarRecetaAvanzada}
              disabled={generandoReceta}
              className="px-4 py-2 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold flex items-center gap-2 transition-colors disabled:opacity-50"
            >
              <QrCode size={18} />
              {generandoReceta ? 'Generando...' : 'Generar Receta con QR'}
            </button>
          </div>

          {recetas.length === 0 ? (
            <div className="bg-white rounded-xl shadow-sm p-12 text-center text-gray-400">
              No hay recetas avanzadas generadas
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {recetas.map(receta => (
                <div key={receta.id} className="bg-white rounded-xl shadow-sm p-6">
                  <div className="flex items-center justify-between mb-4">
                    <QrCode size={28} className="text-[#1E5C8E]" />
                    <span className={`px-2 py-1 rounded text-xs font-medium ${
                      receta.estado_dispensacion === 'dispensada' ? 'bg-green-100 text-green-700' :
                      receta.estado_dispensacion === 'pendiente' ? 'bg-yellow-100 text-yellow-700' :
                      'bg-red-100 text-red-700'
                    }`}>
                      {receta.estado_dispensacion}
                    </span>
                  </div>
                  <p className="text-xs text-gray-500 mb-1">Firma Digital</p>
                  <p className="text-sm text-gray-600 truncate">{receta.firma_digital}</p>
                  <p className="text-xs text-gray-400 mt-4">{new Date(receta.created_at).toLocaleDateString('es-ES')}</p>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* === TAB: EXÁMENES === */}
      {activeTab === 'examenes' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className="p-6 border-b border-gray-100">
            <h2 className="text-xl font-semibold text-[#1a2a3a] flex items-center gap-2">
              <FlaskConical size={22} className="text-[#1E5C8E]" /> Exámenes de laboratorio
            </h2>
          </div>
          <div className="p-6">
            {examenes.length === 0 ? (
              <div className="text-center text-gray-400 py-12">No hay exámenes ordenados</div>
            ) : (
              <div className="space-y-3">
                {examenes.map((ex: any) => {
                  const completado = ex.estado === 'completado'
                  return (
                    <div key={ex.id} className={`p-4 rounded-lg border-l-4 ${completado ? 'border-green-500 bg-green-50/40' : 'border-[#1E5C8E] bg-gray-50'}`}>
                      <div className="flex items-start justify-between gap-3 flex-wrap">
                        <div className="min-w-0">
                          <p className="font-medium text-[#1a2a3a]">{ex.tipo}</p>
                          <p className="text-xs text-gray-500">
                            Solicitado: {ex.fecha_solicitud}
                            {ex.fecha_resultado ? ` · Resultado: ${ex.fecha_resultado}` : ''}
                          </p>
                        </div>
                        <span className={`px-2 py-1 rounded text-xs font-medium ${
                          completado ? 'bg-green-100 text-green-700' :
                          ex.estado === 'en_proceso' ? 'bg-purple-100 text-purple-700' :
                          ex.estado === 'recibida' ? 'bg-blue-100 text-blue-700' :
                          'bg-amber-100 text-amber-700'
                        }`}>
                          {ex.estado === 'completado' ? 'Resultado listo' : ex.estado}
                        </span>
                      </div>
                      {ex.resultados && (
                        <div className="mt-3 bg-white border rounded-lg p-3">
                          <p className="text-xs text-gray-500 mb-1">Resultado</p>
                          <p className="text-sm text-gray-700 whitespace-pre-wrap">{ex.resultados}</p>
                        </div>
                      )}
                      {ex.archivo_url && (
                        <div className="mt-3 flex gap-2">
                          <button type="button" onClick={() => openSignedUrl('resultados-examenes', ex.archivo_url)}
                            className="inline-flex items-center gap-1 text-sm text-[#1E5C8E] hover:underline">
                            <FileText size={16} /> Ver archivo
                          </button>
                          <button type="button" onClick={() => openSignedUrl('resultados-examenes', ex.archivo_url, { download: true })}
                            className="inline-flex items-center gap-1 text-sm text-gray-600 hover:underline">
                            <Download size={16} /> Descargar
                          </button>
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        </div>
      )}

      {/* === TAB: CITAS === */}
      {activeTab === 'citas' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className="p-6 border-b border-gray-100">
            <h2 className="text-xl font-semibold text-[#1a2a3a] flex items-center gap-2">
              <Calendar size={22} className="text-[#1E5C8E]" />
              Citas Programadas
            </h2>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-gray-50 text-gray-500 text-sm">
                  <th className="px-6 py-4 text-left">Fecha</th>
                  <th className="px-6 py-4 text-left">Hora</th>
                  <th className="px-6 py-4 text-center">Estado</th>
                  <th className="px-6 py-4 text-left">Motivo</th>
                  <th className="px-6 py-4 text-center">Accion</th>
                </tr>
              </thead>
              <tbody>
                {citas.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="px-6 py-12 text-center text-gray-400">No hay citas programadas</td>
                  </tr>
                ) : (
                  citas.map(cita => (
                    <tr key={cita.id} className="border-t border-gray-100 hover:bg-gray-50 transition-colors">
                      <td className="px-6 py-4">{cita.fecha}</td>
                      <td className="px-6 py-4">{cita.hora}</td>
                      <td className="px-6 py-4 text-center">
                        <span className={`px-2 py-1 rounded text-xs font-medium ${
                          cita.estado === 'completada' ? 'bg-green-100 text-green-700' :
                          cita.estado === 'en_curso' ? 'bg-purple-100 text-purple-700' :
                          cita.estado === 'confirmada' ? 'bg-blue-100 text-blue-700' :
                          (cita.estado === 'cancelada' || cita.estado === 'no_show') ? 'bg-red-100 text-red-700' :
                          'bg-yellow-100 text-yellow-700'
                        }`}>
                          {cita.estado}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-gray-500">{cita.motivo || '-'}</td>
                      <td className="px-6 py-4">
                        <div className="flex items-center justify-center gap-2">
                          {(cita.estado === 'confirmada' || cita.estado === 'en_curso') && (
                            <button
                              onClick={() => navigate(`${base}/consulta/${cita.id}`)}
                              className="flex items-center gap-1 px-3 py-2 bg-[#1E5C8E] hover:bg-[#164a70] text-white rounded-lg text-sm font-medium transition-colors"
                              title="Abrir consulta (dictado, IA, biblioteca)"
                            >
                              <Stethoscope size={15} />
                              {cita.estado === 'en_curso' ? 'Continuar' : 'Atender'}
                            </button>
                          )}
                          {cita.estado === 'completada' && (
                            <button
                              onClick={() => navigate(`${base}/consulta/${cita.id}`)}
                              className="flex items-center gap-1 px-3 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg text-sm font-medium transition-colors"
                              title="Ver consulta"
                            >
                              <FileText size={15} />
                              Ver
                            </button>
                          )}
                          <button
                            onClick={() => enviarRecordatorio(cita.id)}
                            className="p-2 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
                            title="Enviar recordatorio"
                          >
                            <Bell size={16} className="text-[#1E5C8E]" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* === MODAL: RECETA CON QR === */}
      {showRecetaModal && recetaData && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto shadow-xl">
            <div className="p-6 border-b border-gray-100 flex items-center justify-between">
              <h2 className="text-xl font-semibold text-[#1a2a3a] flex items-center gap-2">
                <QrCode size={22} className="text-[#1E5C8E]" />
                Receta Generada
              </h2>
              <button onClick={() => setShowRecetaModal(false)} className="p-2 hover:bg-gray-100 rounded-lg transition-colors">
                <X size={20} className="text-gray-400" />
              </button>
            </div>

            <div className="p-6 space-y-6">
              <div className="bg-gray-50 p-4 rounded-lg text-center">
                <p className="text-sm text-gray-500 mb-2">Codigo QR de Verificacion</p>
                <div className="inline-block bg-white p-4 rounded-lg shadow-sm">
                  <QrCode size={120} className="text-[#1E5C8E]" />
                </div>
                <p className="text-xs text-gray-500 mt-2">El QR escaneable está en el PDF descargable de la receta.</p>
              </div>

              <div className="bg-gray-50 p-4 rounded-lg">
                <p className="text-sm text-gray-500 mb-1">Firma Digital</p>
                <p className="text-sm text-gray-700">{recetaData.firma_digital}</p>
              </div>

              <div className="flex gap-3">
                <button
                  onClick={descargarHTML}
                  className="flex-1 px-4 py-3 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold flex items-center justify-center gap-2 transition-colors"
                >
                  <Download size={18} />
                  Descargar Receta (HTML)
                </button>
                <button
                  onClick={() => setShowRecetaModal(false)}
                  className="px-4 py-3 bg-gray-100 hover:bg-gray-200 rounded-lg font-semibold transition-colors"
                >
                  Cerrar
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
