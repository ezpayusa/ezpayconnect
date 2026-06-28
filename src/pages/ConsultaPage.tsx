import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate, useLocation } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { openSignedUrl } from '@/lib/signedUrl'
import { useAuth } from '@/hooks/useAuth'
import { useConsultas } from '@/hooks/useConsultas'
import { useCitas } from '@/hooks/useCitas'
import { useSignosVitalesCita } from '@/hooks/useSignosVitalesCita'
import { FormularioVitales, VITALES_VACIO } from '@/clinica/components/FormularioVitales'
import type { VitalesValues } from '@/clinica/components/FormularioVitales'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import DictadoVoz from '@/components/consulta/DictadoVoz'
import BibliotecaMedica from '@/components/consulta/BibliotecaMedica'
import AsistenteIA from '@/components/consulta/AsistenteIA'
import RecetaModal from '@/components/consulta/RecetaModal'
import { FotoPacienteAvatar } from '@/components/FotoPacienteAvatar'
import { toast } from 'sonner'
import type { Paciente, Cita } from '@/types'
import {
  ArrowLeft,
  User,
  Activity,
  FileText,
  Pill,
  FlaskConical,
  Clock,
  CheckCircle2,
  Loader2,
  AlertTriangle,
  Save,
  Stethoscope,
  ClipboardList,
  BookOpen,
  Brain,
  ChevronDown,
  ChevronUp,
} from 'lucide-react'

function calcularEdad(fechaNacimiento: string | null): number | null {
  if (!fechaNacimiento) return null
  const hoy = new Date()
  const nac = new Date(fechaNacimiento)
  let edad = hoy.getFullYear() - nac.getFullYear()
  const m = hoy.getMonth() - nac.getMonth()
  if (m < 0 || (m === 0 && hoy.getDate() < nac.getDate())) edad--
  return edad
}

export default function ConsultaPage() {
  const { citaId } = useParams<{ citaId: string }>()
  const navigate = useNavigate()
  const location = useLocation()
  // Prefijo de panel: si la consulta se abre dentro del portal del médico,
  // toda la navegación interna se queda dentro de /medico (no saca al médico de su panel).
  const base = location.pathname.startsWith('/medico') ? '/medico' : ''
  const { perfil } = useAuth()
  const { updateCita } = useCitas()
  const {
    loading: loadingConsulta,
    saving,
    fetchConsultaPorCita,
    crearOActualizarConsulta,
  } = useConsultas()

  const [cita, setCita] = useState<Cita | null>(null)
  const [paciente, setPaciente] = useState<Paciente | null>(null)
  const [consultaId, setConsultaId] = useState<number | undefined>()
  const [cargando, setCargando] = useState(true)

  // Nota SOAP
  const [soap, setSoap] = useState({
    motivo_consulta: '',
    subjetivo: '',
    objetivo: '',
    analisis: '',
    plan: '',
    diagnostico: '',
  })

  // Ola 3: signos vitales = SERIE de la cita (fuente única signos_vitales, vía RPC DEFINER).
  // El médico ve la serie pre-capturada, valida cada toma y agrega la suya. Append-only.
  const { serie, cargando: cargandoSerie, validarToma, agregarToma } = useSignosVitalesCita(cita?.id ?? 0)
  const [formMedico, setFormMedico] = useState<VitalesValues>(VITALES_VACIO)
  const [guardandoToma, setGuardandoToma] = useState(false)
  const [validandoId, setValidandoId] = useState<number | null>(null)

  // Paneles desplegables
  const [mostrarBiblioteca, setMostrarBiblioteca] = useState(false)
  const [mostrarAsistenteIA, setMostrarAsistenteIA] = useState(false)

  // Exámenes del paciente (para verlos durante la consulta / reconsulta)
  const [examenesPaciente, setExamenesPaciente] = useState<any[]>([])
  const [mostrarExamenes, setMostrarExamenes] = useState(false)

  useEffect(() => {
    if (!paciente?.id) return
    supabase
      .from('examenes')
      .select('id, tipo, estado, resultados, archivo_url, fecha_solicitud, fecha_resultado')
      .eq('paciente_id', paciente.id)
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        const list = data || []
        setExamenesPaciente(list)
        if (list.some((e: any) => e.estado === 'completado')) setMostrarExamenes(true)
      })
  }, [paciente?.id])
  const [modalReceta, setModalReceta] = useState(false)
  const [modalExamen, setModalExamen] = useState(false)
  const [examenForm, setExamenForm] = useState({ tipo: '', descripcion: '' })
  const [guardandoExamen, setGuardandoExamen] = useState(false)

  // Laboratorios para dirigir la orden (afiliados a la clínica + lab de confianza del médico)
  type LabOpcion = { id: string; nombre_empresa: string; ciudad: string | null; afiliado: boolean; es_preferido: boolean }
  const [labs, setLabs] = useState<LabOpcion[]>([])
  const [labSel, setLabSel] = useState<string>('')

  // Hoja de orden: catálogo del lab elegido + selección + "otros"
  type CatItem = { id: string; nombre: string; categoria: string | null }
  const [catalogoLab, setCatalogoLab] = useState<CatItem[]>([])
  const [examenesSel, setExamenesSel] = useState<Set<string>>(new Set())
  const [otrosExamenes, setOtrosExamenes] = useState('')

  useEffect(() => {
    if (!modalExamen) return
    supabase.rpc('laboratorios_para_medico').then(({ data }) => {
      const list = (data || []) as LabOpcion[]
      setLabs(list)
      setLabSel((prev) => prev || (list.find((l) => l.es_preferido)?.id || list.find((l) => l.afiliado)?.id || ''))
    })
  }, [modalExamen])

  // Cargar el catálogo del laboratorio seleccionado
  useEffect(() => {
    if (!labSel) { setCatalogoLab([]); setExamenesSel(new Set()); return }
    supabase.from('examenes_catalogo')
      .select('id, nombre, categoria')
      .eq('laboratorio_id', labSel)
      .eq('activo', true)
      .order('categoria', { nullsFirst: false })
      .order('nombre')
      .then(({ data }) => { setCatalogoLab((data || []) as CatItem[]); setExamenesSel(new Set()) })
  }, [labSel])

  const toggleExamenSel = (nombre: string) =>
    setExamenesSel((prev) => { const n = new Set(prev); n.has(nombre) ? n.delete(nombre) : n.add(nombre); return n })

  const examenesElegidos = () => [
    ...examenesSel,
    ...otrosExamenes.split('\n').map((s) => s.trim()).filter(Boolean),
  ]

  const handleCrearExamen = async () => {
    if (!paciente) return
    // Exámenes elegidos: del catálogo + "otros". Si no hay lab/catálogo, el campo libre "tipo".
    const lista = labSel ? examenesElegidos() : examenesElegidos().concat(examenForm.tipo.trim() ? [examenForm.tipo.trim()] : [])
    if (lista.length === 0) {
      toast.error('Selecciona o escribe al menos un examen')
      return
    }
    setGuardandoExamen(true)

    const { data: clinicaRows } = await supabase.rpc('mi_clinica_medico')
    const clinica = (clinicaRows || [])[0] as { clinica_id: string; clinica_nombre: string } | undefined
    const labElegido = labs.find((l) => l.id === labSel)
    const pacienteNombre = `${paciente.nombre} ${paciente.apellido}`.trim()
    const instrucciones = examenForm.descripcion.trim() || null

    // 1. Cabecera de la orden
    const { data: orden, error: oErr } = await supabase.from('ordenes_examen').insert({
      laboratorio_id: labSel || null,
      clinica_id: clinica?.clinica_id || null,
      medico_id: perfil?.id,
      paciente_id: paciente.id,
      origen: 'medico',
      instrucciones,
      paciente_nombre: pacienteNombre,
      medico_nombre: perfil?.nombre_completo || null,
      clinica_nombre: clinica?.clinica_nombre || null,
    }).select('id').single()

    if (oErr || !orden) {
      setGuardandoExamen(false)
      toast.error('Error al crear la orden: ' + (oErr?.message || ''))
      return
    }

    // 2. Un ítem (fila examenes) por examen
    const filas = lista.map((tipo) => ({
      orden_id: orden.id,
      paciente_id: paciente.id,
      medico_id: perfil?.id,
      tipo,
      descripcion: instrucciones,
      estado: 'pendiente',
      laboratorio_id: labSel || null,
      clinica_id: clinica?.clinica_id || null,
      origen: 'medico',
      paciente_nombre: pacienteNombre,
      medico_nombre: perfil?.nombre_completo || null,
      clinica_nombre: clinica?.clinica_nombre || null,
    }))
    const { error } = await supabase.from('examenes').insert(filas)
    setGuardandoExamen(false)
    if (error) {
      toast.error('Error al crear los exámenes: ' + error.message)
      return
    }

    // Camino ÚNICO server-side gateado: notificar_orden_lab(orden.id) UNA vez al finalizar la orden.
    // Deriva lab + paciente + count de los exámenes de la orden, compone el resumen ('N exámenes')
    // server-side y crea 1 notif paciente + fan-out al lab + web-push. Reemplaza notificar_paciente +
    // notificar_laboratorio + enviar-push (gate = médico de la orden; cero target/contenido del caller).
    try {
      await supabase.rpc('notificar_orden_lab', { p_orden_id: orden.id })
    } catch (e) { console.error('Error notificar_orden_lab:', e) }
    toast.success(
      labElegido
        ? `Orden (${lista.length}) enviada a ${labElegido.nombre_empresa}. El paciente también la verá en su portal.`
        : `Orden de examen creada (${lista.length}). El paciente la verá en su portal.`
    )
    setModalExamen(false)
    setExamenForm({ tipo: '', descripcion: '' })
    setLabSel('')
    setExamenesSel(new Set())
    setOtrosExamenes('')
  }

  // Cargar cita, paciente y consulta existente
  useEffect(() => {
    const cargar = async () => {
      if (!citaId) return
      setCargando(true)

      const id = parseInt(citaId)

      // Cargar cita
      const { data: citaData, error: citaError } = await supabase
        .from('citas')
        .select('*')
        .eq('id', id)
        .single()

      if (citaError) {
        console.error('Error cargando cita:', citaError)
      }

      if (!citaData) {
        toast.error('Cita no encontrada')
        navigate(`${base}/citas`)
        return
      }

      setCita(citaData as Cita)

      // Cargar paciente por separado
      const { data: pacienteData, error: pacienteError } = await supabase
        .from('pacientes')
        .select('*')
        .eq('id', citaData.paciente_id)
        .single()

      if (pacienteError) {
        console.error('Error cargando paciente:', pacienteError)
      }

      if (!pacienteData) {
        console.warn('Paciente no encontrado para cita', citaData.paciente_id)
        // Intentar crear un paciente fantasma con los datos que tenemos
        setPaciente({
          id: citaData.paciente_id,
          nombre: 'Paciente',
          apellido: `#${citaData.paciente_id}`,
          medico_id: citaData.medico_id,
          clinica_id: null,
          fecha_nacimiento: null,
          genero: null,
          telefono: null,
          email: null,
          direccion: null,
          emergencia_nombre: null,
          emergencia_telefono: null,
          alergias: null,
          notas: null,
          tipo_sangre: null,
          antecedentes_personales: null,
          antecedentes_familiares: null,
          medicamentos_en_uso: null,
          foto_path: null,
          activo: true,
          created_at: citaData.created_at,
        } as Paciente)
        toast.warning('Paciente no encontrado en base de datos, pero puede continuar la consulta')
      } else {
        setPaciente(pacienteData as Paciente)
      }

      // Cargar consulta existente
      const consultaExistente = await fetchConsultaPorCita(id)
      if (consultaExistente) {
        setConsultaId(consultaExistente.id)
        setSoap({
          motivo_consulta: consultaExistente.motivo_consulta || '',
          subjetivo: consultaExistente.subjetivo || '',
          objetivo: consultaExistente.objetivo || '',
          analisis: consultaExistente.analisis || '',
          plan: consultaExistente.plan || '',
          diagnostico: consultaExistente.diagnostico || '',
        })
      } else {
        // Pre-llenar motivo con el de la cita
        setSoap(prev => ({ ...prev, motivo_consulta: citaData.motivo || '' }))
      }

      setCargando(false)
    }

    cargar()
  }, [citaId, fetchConsultaPorCita, navigate])

  const guardarNotaSOAP = async () => {
    if (!cita || !paciente) return

    const result = await crearOActualizarConsulta(
      {
        cita_id: cita.id,
        paciente_id: paciente.id,
        ...soap,
      },
      consultaId
    )

    if (result.error) {
      toast.error('Error al guardar: ' + result.error)
    } else {
      toast.success('Consulta guardada correctamente')
      if (result.data) setConsultaId(result.data.id)
    }
  }

  const cambiarEstadoCita = async (nuevoEstado: Cita['estado']) => {
    if (!cita) return
    const { error } = await updateCita(cita.id, { estado: nuevoEstado })
    if (error) {
      toast.error('Error: ' + error.message)
    } else {
      setCita({ ...cita, estado: nuevoEstado })
      toast.success(`Cita marcada como ${nuevoEstado.replace('_', ' ')}`)
    }
  }

  const handleAgregarToma = async () => {
    if (!cita || !paciente) return
    const medicoId = perfil?.id
    if (!medicoId) { toast.error('Sin médico en sesión'); return }
    setGuardandoToma(true)
    const ok = await agregarToma(formMedico, paciente.id, medicoId)
    setGuardandoToma(false)
    if (ok) setFormMedico(VITALES_VACIO)
  }

  if (cargando || loadingConsulta) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    )
  }

  if (!cita || !paciente) {
    return (
      <div className="container mx-auto px-4 py-8 text-center">
        <p className="text-muted-foreground">Cita no encontrada</p>
        <Button onClick={() => navigate(`${base}/citas`)} className="mt-4">
          <ArrowLeft className="h-4 w-4 mr-2" /> Volver a Citas
        </Button>
      </div>
    )
  }

  const edad = calcularEdad(paciente.fecha_nacimiento)
  const ultimaToma = serie.length ? serie[serie.length - 1] : null

  const getEstadoColor = (estado: Cita['estado']) => {
    const map: Record<string, string> = {
      agendada: 'bg-gray-100 text-gray-700',
      confirmada: 'bg-blue-100 text-blue-700',
      en_curso: 'bg-amber-100 text-amber-700',
      completada: 'bg-green-100 text-green-700',
      cancelada: 'bg-red-100 text-red-700',
      no_show: 'bg-red-200 text-red-800',
    }
    return map[estado] || 'bg-gray-100'
  }

  return (
    <div className="min-h-screen bg-slate-50">
      {/* Header */}
      <div className="bg-white border-b px-4 py-3 flex items-center justify-between sticky top-0 z-30">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate(`${base}/citas`)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-lg font-bold flex items-center gap-2">
              <Stethoscope className="h-5 w-5 text-[#1E5C8E]" />
              Consulta Médica
            </h1>
            <p className="text-xs text-muted-foreground">
              {new Date(cita.fecha).toLocaleDateString('es-ES')} · {cita.hora_inicio} — {paciente.nombre} {paciente.apellido}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Badge className={getEstadoColor(cita.estado)}>
            {cita.estado.replace('_', ' ').toUpperCase()}
          </Badge>
          {cita.estado === 'confirmada' && (
            <Button size="sm" variant="outline" onClick={() => cambiarEstadoCita('en_curso')}>
              <Clock className="h-4 w-4 mr-1" /> En Sala
            </Button>
          )}
          {cita.estado === 'en_curso' && (
            <Button size="sm" className="bg-green-600 hover:bg-green-700" onClick={() => cambiarEstadoCita('completada')}>
              <CheckCircle2 className="h-4 w-4 mr-1" /> Finalizar
            </Button>
          )}
          <Button size="sm" onClick={guardarNotaSOAP} disabled={saving} className="bg-[#1E5C8E]">
            <Save className="h-4 w-4 mr-1" /> {saving ? 'Guardando...' : 'Guardar'}
          </Button>
        </div>
      </div>

      {/* Alergias alerta */}
      {paciente.alergias && (
        <div className="bg-red-50 border-b border-red-200 px-4 py-2 flex items-center gap-2">
          <AlertTriangle className="h-4 w-4 text-red-600" />
          <span className="text-sm text-red-700 font-medium">
            Alergias: {paciente.alergias}
          </span>
        </div>
      )}

      {/* Main layout */}
      <div className="p-4 grid grid-cols-1 lg:grid-cols-12 gap-4 max-w-[1600px] mx-auto">
        {/* COLUMNA IZQUIERDA: Info paciente + Signos vitales */}
        <div className="lg:col-span-3 space-y-4">
          {/* Info paciente */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm flex items-center gap-2">
                <User className="h-4 w-4 text-[#1E5C8E]" />
                Paciente
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <div className="flex items-center gap-3">
                <FotoPacienteAvatar
                  pacienteId={paciente.id}
                  fotoPath={paciente.foto_path}
                  editable
                  size="lg"
                  onUpdated={(p) => setPaciente(prev => prev ? { ...prev, foto_path: p } : prev)}
                />
                <p className="font-bold text-lg">{paciente.nombre} {paciente.apellido}</p>
              </div>
              <div className="grid grid-cols-2 gap-2 text-muted-foreground">
                <div>Edad: <span className="text-slate-700 font-medium">{edad ?? '—'} años</span></div>
                <div>Género: <span className="text-slate-700 font-medium">{paciente.genero || '—'}</span></div>
                <div>Tel: <span className="text-slate-700">{paciente.telefono || '—'}</span></div>
                <div>Tipo Sangre: <span className="text-slate-700 font-medium">{paciente.tipo_sangre || '—'}</span></div>
              </div>
              {paciente.medicamentos_en_uso && (
                <div className="bg-blue-50 p-2 rounded text-xs">
                  <span className="font-medium text-blue-700">Medicación habitual:</span>
                  <p className="text-blue-600 mt-0.5">{paciente.medicamentos_en_uso}</p>
                </div>
              )}
              {paciente.antecedentes_personales && (
                <div className="text-xs text-muted-foreground">
                  <span className="font-medium">Antecedentes:</span> {paciente.antecedentes_personales}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Signos vitales de la cita (serie append-only; fuente única signos_vitales vía RPC) */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm flex items-center gap-2">
                <Activity className="h-4 w-4 text-emerald-600" />
                Signos vitales de la cita
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {cargandoSerie ? (
                <div className="flex justify-center p-3"><Loader2 className="h-5 w-5 animate-spin text-[#1E5C8E]" /></div>
              ) : serie.length === 0 ? (
                <p className="text-sm text-gray-400 py-2">Sin tomas registradas</p>
              ) : (
                serie.map((t) => (
                  <div key={t.id} className="border rounded p-2 text-xs bg-slate-50">
                    <div className="flex justify-between items-center gap-2 mb-1">
                      <span className="text-muted-foreground">
                        {new Date(t.fecha_toma).toLocaleString('es-ES', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })}
                        {' · tomado por '}{t.capturado_por_nombre || '—'}
                      </span>
                      {t.estado === 'capturado' && (
                        <Button size="sm" variant="outline" className="h-6 text-xs shrink-0"
                          disabled={validandoId === t.id}
                          onClick={async () => { setValidandoId(t.id); await validarToma(t.id); setValidandoId(null) }}>
                          {validandoId === t.id ? <Loader2 className="h-3 w-3 animate-spin" /> : 'Validar'}
                        </Button>
                      )}
                      {t.estado === 'validado' && (
                        <Badge className="h-6 text-xs bg-emerald-100 text-emerald-700 flex items-center gap-1 shrink-0">
                          <CheckCircle2 className="h-3 w-3" /> Validado{t.validado_at ? ' · ' + new Date(t.validado_at).toLocaleDateString('es-ES') : ''}
                        </Badge>
                      )}
                      {(t.estado === 'declarado' || t.estado === 'corregido') && (
                        <Badge variant="secondary" className="h-6 text-xs shrink-0">{t.estado}</Badge>
                      )}
                    </div>
                    <div className="flex flex-wrap gap-x-3 gap-y-1">
                      {t.presion_arterial && <span>PA {t.presion_arterial}</span>}
                      {t.frecuencia_cardiaca != null && <span>FC {t.frecuencia_cardiaca}</span>}
                      {t.frecuencia_respiratoria != null && <span>FR {t.frecuencia_respiratoria}</span>}
                      {t.temperatura != null && <span>T {t.temperatura}°</span>}
                      {t.peso_kg != null && <span>{t.peso_kg}kg</span>}
                      {t.talla_cm != null && <span>{t.talla_cm}cm</span>}
                      {t.imc != null && <span>IMC {t.imc}</span>}
                      {t.saturacion_o2 != null && <span>SpO2 {t.saturacion_o2}%</span>}
                      {t.glucosa != null && <span>Gluc {t.glucosa}</span>}
                      {t.notas && <span className="italic">{t.notas}</span>}
                    </div>
                  </div>
                ))
              )}
            </CardContent>
          </Card>

          {/* Agregar mi toma (médico) */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm flex items-center gap-2">
                <Activity className="h-4 w-4 text-[#1E5C8E]" />
                Agregar mi toma
              </CardTitle>
            </CardHeader>
            <CardContent>
              <FormularioVitales values={formMedico} onChange={(c, v) => setFormMedico(f => ({ ...f, [c]: v }))} onSubmit={handleAgregarToma} loading={guardandoToma} />
            </CardContent>
          </Card>
        </div>

        {/* COLUMNA CENTRO: Nota SOAP */}
        <div className="lg:col-span-6">
          <Card className="h-full flex flex-col">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm flex items-center gap-2">
                <ClipboardList className="h-4 w-4 text-[#1E5C8E]" />
                Nota Clínica SOAP
              </CardTitle>
            </CardHeader>
            <CardContent className="flex-1">
              <Tabs defaultValue="subjetivo" className="h-full flex flex-col">
                <TabsList className="grid grid-cols-5 mb-4">
                  <TabsTrigger value="motivo">Motivo</TabsTrigger>
                  <TabsTrigger value="subjetivo">Subjetivo</TabsTrigger>
                  <TabsTrigger value="objetivo">Objetivo</TabsTrigger>
                  <TabsTrigger value="analisis">Análisis</TabsTrigger>
                  <TabsTrigger value="plan">Plan</TabsTrigger>
                </TabsList>

                <TabsContent value="motivo" className="flex-1 flex flex-col gap-2">
                  <Label>Motivo de consulta</Label>
                  <DictadoVoz
                    pacienteId={paciente.id}
                    onTranscript={text => setSoap(p => ({ ...p, motivo_consulta: text }))}
                    placeholder="Dicta el motivo de consulta..."
                  />
                  <Textarea
                    value={soap.motivo_consulta}
                    onChange={e => setSoap(p => ({ ...p, motivo_consulta: e.target.value }))}
                    placeholder="Ej: Dolor de cabeza intenso desde hace 3 días..."
                    className="flex-1 min-h-[200px]"
                  />
                </TabsContent>

                <TabsContent value="subjetivo" className="flex-1 flex flex-col gap-2">
                  <Label>Subjetivo — Lo que refiere el paciente</Label>
                  <DictadoVoz
                    pacienteId={paciente.id}
                    onTranscript={text => setSoap(p => ({ ...p, subjetivo: text }))}
                    placeholder="Dicta lo que el paciente cuenta..."
                  />
                  <Textarea
                    value={soap.subjetivo}
                    onChange={e => setSoap(p => ({ ...p, subjetivo: e.target.value }))}
                    placeholder="Ej: Paciente refiere cefalea frontal pulsátil de intensidad 8/10, acompañada de náuseas..."
                    className="flex-1 min-h-[200px]"
                  />
                </TabsContent>

                <TabsContent value="objetivo" className="flex-1 flex flex-col gap-2">
                  <Label>Objetivo — Hallazgos de exploración física</Label>
                  <DictadoVoz
                    pacienteId={paciente.id}
                    onTranscript={text => setSoap(p => ({ ...p, objetivo: text }))}
                    placeholder="Dicta los hallazgos de la exploración..."
                  />
                  <Textarea
                    value={soap.objetivo}
                    onChange={e => setSoap(p => ({ ...p, objetivo: e.target.value }))}
                    placeholder="Ej: Consciente, orientado. Pupilas isocóricas. Faringe eritematosa. Auscultación cardiopulmonar normal..."
                    className="flex-1 min-h-[200px]"
                  />
                </TabsContent>

                <TabsContent value="analisis" className="flex-1 flex flex-col gap-2">
                  <Label>Análisis — Diagnóstico e interpretación</Label>
                  <DictadoVoz
                    pacienteId={paciente.id}
                    onTranscript={text => setSoap(p => ({ ...p, analisis: text }))}
                    placeholder="Dicta tu análisis diagnóstico..."
                  />
                  <Textarea
                    value={soap.analisis}
                    onChange={e => setSoap(p => ({ ...p, analisis: e.target.value }))}
                    placeholder="Ej: Cefalea tensional probablemente relacionada con estrés laboral. Se descartan signos de alarma..."
                    className="flex-1 min-h-[200px]"
                  />
                </TabsContent>

                <TabsContent value="plan" className="flex-1 flex flex-col gap-2">
                  <Label>Plan — Tratamiento, estudios, indicaciones</Label>
                  <DictadoVoz
                    pacienteId={paciente.id}
                    onTranscript={text => setSoap(p => ({ ...p, plan: text }))}
                    placeholder="Dicta el plan de tratamiento..."
                  />
                  <Textarea
                    value={soap.plan}
                    onChange={e => setSoap(p => ({ ...p, plan: e.target.value }))}
                    placeholder="Ej: 1. Paracetamol 500mg c/8h x 5 días. 2. Hidratación abundante. 3. Reposo. 4. Control en 7 días..."
                    className="flex-1 min-h-[200px]"
                  />
                </TabsContent>
              </Tabs>

              {/* Diagnóstico general */}
              <div className="mt-4 pt-4 border-t">
                <Label className="text-xs text-muted-foreground">Diagnóstico (para receta y reportes)</Label>
                <Input
                  value={soap.diagnostico}
                  onChange={e => setSoap(p => ({ ...p, diagnostico: e.target.value }))}
                  placeholder="Diagnóstico principal (ej: Cefalea tensional)"
                  className="mt-1"
                />
              </div>
            </CardContent>
          </Card>
        </div>

        {/* COLUMNA DERECHA: Acciones rápidas */}
        <div className="lg:col-span-3 space-y-4">
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm">Acciones</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <Button
                className="w-full justify-start bg-[#1E5C8E] hover:bg-[#164a70]"
                onClick={() => setModalReceta(true)}
              >
                <FileText className="h-4 w-4 mr-2" /> Nueva Receta
              </Button>
              <Button
                variant="outline"
                className="w-full justify-start"
                onClick={() => navigate(`${base}/buscar-medicamentos`)}
              >
                <Pill className="h-4 w-4 mr-2" /> Buscar Medicamentos
              </Button>
              <Button
                variant="outline"
                className="w-full justify-start"
                onClick={() => { setExamenForm({ tipo: '', descripcion: '' }); setModalExamen(true) }}
              >
                <FlaskConical className="h-4 w-4 mr-2" /> Orden de Examen
              </Button>
              <Button
                variant="outline"
                className="w-full justify-start"
                onClick={() => navigate(`${base}/pacientes/${paciente.id}/detalle`)}
              >
                <User className="h-4 w-4 mr-2" /> Ver Expediente
              </Button>
            </CardContent>
          </Card>

          {/* Exámenes de laboratorio del paciente */}
          <Card>
            <CardHeader className="pb-3 cursor-pointer" onClick={() => setMostrarExamenes(!mostrarExamenes)}>
              <CardTitle className="text-sm flex items-center justify-between">
                <span className="flex items-center gap-2">
                  <FlaskConical className="h-4 w-4 text-[#1E5C8E]" />
                  Exámenes de laboratorio
                  {examenesPaciente.length > 0 && (
                    <span className="bg-[#1E5C8E] text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full">
                      {examenesPaciente.length}
                    </span>
                  )}
                </span>
                {mostrarExamenes ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
              </CardTitle>
            </CardHeader>
            {mostrarExamenes && (
              <CardContent className="space-y-2 max-h-72 overflow-y-auto">
                {examenesPaciente.length === 0 ? (
                  <p className="text-xs text-muted-foreground">Este paciente no tiene exámenes registrados.</p>
                ) : (
                  examenesPaciente.map((ex: any) => {
                    const completado = ex.estado === 'completado'
                    return (
                      <div key={ex.id} className={`p-2 rounded-lg border-l-4 text-sm ${completado ? 'border-green-500 bg-green-50/50' : 'border-slate-300 bg-slate-50'}`}>
                        <div className="flex items-center justify-between gap-2">
                          <span className="font-medium">{ex.tipo}</span>
                          <span className={`text-[10px] px-1.5 py-0.5 rounded ${completado ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}`}>
                            {completado ? 'Listo' : ex.estado}
                          </span>
                        </div>
                        {ex.resultados && <p className="text-xs text-gray-600 mt-1 whitespace-pre-wrap line-clamp-4">{ex.resultados}</p>}
                        {ex.archivo_url && (
                          <div className="flex gap-3 mt-1">
                            <button type="button" onClick={() => openSignedUrl('resultados-examenes', ex.archivo_url)} className="text-xs text-[#1E5C8E] hover:underline">Ver archivo</button>
                            <button type="button" onClick={() => openSignedUrl('resultados-examenes', ex.archivo_url, { download: true })} className="text-xs text-gray-500 hover:underline">Descargar</button>
                          </div>
                        )}
                      </div>
                    )
                  })
                )}
              </CardContent>
            )}
          </Card>

          {/* Biblioteca Médica */}
          <Card>
            <CardHeader className="pb-3 cursor-pointer" onClick={() => setMostrarBiblioteca(!mostrarBiblioteca)}>
              <CardTitle className="text-sm flex items-center justify-between">
                <span className="flex items-center gap-2">
                  <BookOpen className="h-4 w-4 text-blue-600" />
                  Biblioteca Médica
                </span>
                {mostrarBiblioteca ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
              </CardTitle>
            </CardHeader>
            {mostrarBiblioteca && (
              <CardContent>
                <BibliotecaMedica onCopiar={texto => setSoap(p => ({ ...p, plan: p.plan + '\n\n[Referencia bibliográfica]\n' + texto }))} />
              </CardContent>
            )}
          </Card>

          {/* Asistente IA */}
          <Card>
            <CardHeader className="pb-3 cursor-pointer" onClick={() => setMostrarAsistenteIA(!mostrarAsistenteIA)}>
              <CardTitle className="text-sm flex items-center justify-between">
                <span className="flex items-center gap-2">
                  <Brain className="h-4 w-4 text-purple-600" />
                  Asistente IA
                </span>
                {mostrarAsistenteIA ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
              </CardTitle>
            </CardHeader>
            {mostrarAsistenteIA && (
              <CardContent>
                <AsistenteIA
                  pacienteId={paciente.id}
                  contexto={{
                    edad,
                    genero: paciente?.genero,
                    peso_kg: ultimaToma?.peso_kg != null ? String(ultimaToma.peso_kg) : '',
                    motivo_consulta: soap.motivo_consulta,
                    subjetivo: soap.subjetivo,
                    objetivo: soap.objetivo,
                    presion_arterial: ultimaToma?.presion_arterial ?? '',
                    temperatura: ultimaToma?.temperatura != null ? String(ultimaToma.temperatura) : '',
                    frecuencia_cardiaca: ultimaToma?.frecuencia_cardiaca != null ? String(ultimaToma.frecuencia_cardiaca) : '',
                    alergias: paciente?.alergias,
                    medicamentos_en_uso: paciente?.medicamentos_en_uso,
                    antecedentes: paciente?.antecedentes_personales,
                  }}
                  onCopiarSugerencia={texto => setSoap(p => ({ ...p, analisis: p.analisis + '\n\n[Sugerencia IA]\n' + texto }))}
                />
              </CardContent>
            )}
          </Card>
        </div>
      </div>

      <RecetaModal
        open={modalReceta}
        onOpenChange={setModalReceta}
        pacienteIdPreseleccionado={paciente ? String(paciente.id) : undefined}
        citaId={cita?.id}
        onSuccess={() => {
          toast.success('Receta creada desde la consulta')
        }}
      />

      {/* Modal: nueva orden de examen */}
      {modalExamen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-lg overflow-hidden flex flex-col max-h-[90vh]">
            <div className="flex items-center justify-between p-4 border-b">
              <h3 className="font-semibold flex items-center gap-2">
                <FlaskConical className="h-5 w-5 text-[#1E5C8E]" /> Nueva orden de examen
              </h3>
              <button
                onClick={() => { if (!guardandoExamen) setModalExamen(false) }}
                className="text-slate-400 hover:text-slate-600 text-lg leading-none"
              >
                ✕
              </button>
            </div>
            <div className="p-4 space-y-3 overflow-y-auto">
              {/* Laboratorio (define el catálogo que se muestra) */}
              <div>
                <Label>Laboratorio clínico</Label>
                <select
                  value={labSel}
                  onChange={(e) => setLabSel(e.target.value)}
                  className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
                >
                  <option value="">— Sin asignar (el paciente elige) —</option>
                  {labs.length > 0 && (
                    <>
                      <optgroup label="Afiliados a tu clínica">
                        {labs.filter((l) => l.afiliado).map((l) => (
                          <option key={l.id} value={l.id}>
                            {l.nombre_empresa}{l.ciudad ? ` · ${l.ciudad}` : ''}{l.es_preferido ? ' ⭐' : ''}
                          </option>
                        ))}
                      </optgroup>
                      <optgroup label="Otros laboratorios del país">
                        {labs.filter((l) => !l.afiliado).map((l) => (
                          <option key={l.id} value={l.id}>
                            {l.nombre_empresa}{l.ciudad ? ` · ${l.ciudad}` : ''}{l.es_preferido ? ' ⭐' : ''}
                          </option>
                        ))}
                      </optgroup>
                    </>
                  )}
                </select>
                {labSel && !labs.find((l) => l.id === labSel)?.es_preferido && (
                  <button
                    type="button"
                    onClick={async () => {
                      const { error } = await supabase.from('perfiles').update({ laboratorio_preferido_id: labSel }).eq('id', perfil?.id)
                      if (error) { toast.error('No se pudo guardar'); return }
                      setLabs((prev) => prev.map((l) => ({ ...l, es_preferido: l.id === labSel })))
                      toast.success('Laboratorio de confianza actualizado')
                    }}
                    className="text-xs text-[#1E5C8E] hover:underline mt-1"
                  >
                    ⭐ Marcar como mi laboratorio de confianza
                  </button>
                )}
              </div>

              {/* Hoja de exámenes */}
              {labSel ? (
                <div>
                  <Label>Exámenes a solicitar *</Label>
                  {catalogoLab.length > 0 ? (
                    <div className="mt-1 border rounded-lg divide-y max-h-56 overflow-y-auto">
                      {Object.entries(
                        catalogoLab.reduce((acc: Record<string, CatItem[]>, c) => {
                          (acc[c.categoria || 'Sin categoría'] ||= []).push(c); return acc
                        }, {})
                      ).map(([cat, items]) => (
                        <div key={cat} className="p-2">
                          <p className="text-[11px] font-semibold text-muted-foreground uppercase mb-1">{cat}</p>
                          {items.map((c) => (
                            <label key={c.id} className="flex items-center gap-2 px-1 py-1 rounded hover:bg-gray-50 cursor-pointer text-sm">
                              <input type="checkbox" checked={examenesSel.has(c.nombre)} onChange={() => toggleExamenSel(c.nombre)} className="accent-[#1E5C8E] h-4 w-4" />
                              {c.nombre}
                            </label>
                          ))}
                        </div>
                      ))}
                    </div>
                  ) : (
                    <p className="text-xs text-amber-600 mt-1">Este laboratorio aún no publicó su catálogo. Escribe los exámenes en "Otros".</p>
                  )}
                  <div className="mt-2">
                    <Label className="text-xs">Otros exámenes (uno por línea)</Label>
                    <Textarea value={otrosExamenes} onChange={(e) => setOtrosExamenes(e.target.value)} rows={2}
                      placeholder="Examen no listado…" />
                  </div>
                </div>
              ) : (
                <div>
                  <Label>Tipo de examen *</Label>
                  <Input
                    value={examenForm.tipo}
                    onChange={(e) => setExamenForm((p) => ({ ...p, tipo: e.target.value }))}
                    placeholder="Ej: Hemograma, Glucosa, Radiografía de tórax"
                    list="examenes-comunes"
                  />
                  <datalist id="examenes-comunes">
                    <option value="Hemograma completo" />
                    <option value="Glucosa en ayunas" />
                    <option value="Perfil lipídico" />
                    <option value="Examen general de orina" />
                    <option value="Radiografía de tórax" />
                  </datalist>
                  <p className="text-xs text-muted-foreground mt-1">Elige un laboratorio para ver su hoja de exámenes con casillas.</p>
                </div>
              )}

              <div>
                <Label>Instrucciones / observaciones</Label>
                <Textarea
                  value={examenForm.descripcion}
                  onChange={(e) => setExamenForm((p) => ({ ...p, descripcion: e.target.value }))}
                  rows={2}
                  placeholder="Indicaciones especiales para el laboratorio…"
                />
              </div>
            </div>
            <div className="flex items-center justify-end gap-2 p-4 border-t">
              <Button variant="outline" onClick={() => setModalExamen(false)} disabled={guardandoExamen}>
                Cancelar
              </Button>
              <Button
                className="bg-[#1E5C8E] hover:bg-[#164a70]"
                onClick={handleCrearExamen}
                disabled={guardandoExamen || (labSel ? examenesElegidos().length === 0 : !examenForm.tipo.trim())}
              >
                {guardandoExamen ? 'Creando…' : 'Crear orden'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
