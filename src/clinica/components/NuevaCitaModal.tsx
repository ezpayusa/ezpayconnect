import { useState, useEffect, useMemo } from 'react'
import { X, Search, UserPlus, Loader2, ChevronLeft, CalendarPlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { usePaisesRegistro } from '@/hooks/usePaisesRegistro'
import { fechaLocalISO, type MedicoColumna, type PacienteBusqueda, type NuevoPacienteDatos, type NuevaCitaDatos } from '@/clinica/hooks/useCalendarioClinica'
import { toast } from 'sonner'

interface PacienteSel { id: number; nombre: string }

interface Props {
  clinicaPaisId: string | null
  medicos: MedicoColumna[]
  prefill: { medicoId?: string; fecha: Date; horaInicio?: string }
  buscarPacientes: (texto: string) => Promise<PacienteBusqueda[]>
  crearPaciente: (d: NuevoPacienteDatos) => Promise<{ id?: number; error?: any }>
  crearCita: (d: NuevaCitaDatos) => Promise<{ id?: number; error?: any }>
  onClose: () => void
  onCreated: () => void
}

function sumar30(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number)
  const t = new Date(); t.setHours(h || 0, (m || 0) + 30, 0, 0)
  return `${String(t.getHours()).padStart(2, '0')}:${String(t.getMinutes()).padStart(2, '0')}`
}

export default function NuevaCitaModal({ clinicaPaisId, medicos, prefill, buscarPacientes, crearPaciente, crearCita, onClose, onCreated }: Props) {
  const { paises } = usePaisesRegistro()
  const [paso, setPaso] = useState<'paciente' | 'detalle'>('paciente')
  const [paciente, setPaciente] = useState<PacienteSel | null>(null)

  // Búsqueda
  const [query, setQuery] = useState('')
  const [resultados, setResultados] = useState<PacienteBusqueda[]>([])
  const [buscando, setBuscando] = useState(false)
  const [mostrarForm, setMostrarForm] = useState(false)

  // Alta de paciente nuevo
  const [nuevo, setNuevo] = useState({ nombre: '', apellido: '', telefono: '', fecha_nacimiento: '', genero: '', email: '', pais_id: '' })
  const [creandoPac, setCreandoPac] = useState(false)

  // Detalle de la cita
  const horaIni0 = prefill.horaInicio || '09:00'
  const [detalle, setDetalle] = useState({
    medico_id: prefill.medicoId || medicos[0]?.medico_id || '',
    fecha: fechaLocalISO(prefill.fecha),
    hora_inicio: horaIni0,
    hora_fin: sumar30(horaIni0),
    motivo: '',
  })
  const [creandoCita, setCreandoCita] = useState(false)

  // País por defecto = el de la clínica.
  useEffect(() => { if (clinicaPaisId) setNuevo((n) => n.pais_id ? n : { ...n, pais_id: clinicaPaisId }) }, [clinicaPaisId])

  // Debounce de búsqueda.
  useEffect(() => {
    if (query.trim().length < 2) { setResultados([]); return }
    setBuscando(true)
    const t = setTimeout(async () => {
      const r = await buscarPacientes(query)
      setResultados(r)
      setBuscando(false)
    }, 300)
    return () => clearTimeout(t)
  }, [query, buscarPacientes])

  const nombreMedico = useMemo(() => medicos.find((m) => m.medico_id === detalle.medico_id)?.nombre_completo || '', [medicos, detalle.medico_id])

  const seleccionar = (p: PacienteBusqueda) => {
    setPaciente({ id: p.paciente_id, nombre: `${p.nombre} ${p.apellido}`.trim() })
    setPaso('detalle')
  }

  const handleCrearPaciente = async () => {
    if (!nuevo.nombre.trim() || !nuevo.apellido.trim()) { toast.error('Nombre y apellido son obligatorios'); return }
    setCreandoPac(true)
    const res = await crearPaciente({
      nombre: nuevo.nombre, apellido: nuevo.apellido, telefono: nuevo.telefono || null,
      fecha_nacimiento: nuevo.fecha_nacimiento || null, genero: nuevo.genero || null,
      email: nuevo.email || null, pais_id: nuevo.pais_id || null,
    })
    setCreandoPac(false)
    if (res.error) { toast.error('No se pudo crear el paciente: ' + res.error.message); return }
    setPaciente({ id: res.id!, nombre: `${nuevo.nombre} ${nuevo.apellido}`.trim() })
    toast.success('Paciente registrado')
    setPaso('detalle')
  }

  const handleCrearCita = async () => {
    if (!paciente) return
    if (!detalle.medico_id || !detalle.fecha || !detalle.hora_inicio) { toast.error('Médico, fecha y hora son obligatorios'); return }
    setCreandoCita(true)
    const res = await crearCita({
      paciente_id: paciente.id, medico_id: detalle.medico_id, fecha: detalle.fecha,
      hora_inicio: detalle.hora_inicio, hora_fin: detalle.hora_fin || null, motivo: detalle.motivo || null,
      pais_id: clinicaPaisId,
    })
    setCreandoCita(false)
    if (res.error) { toast.error('No se pudo crear la cita: ' + res.error.message); return }
    toast.success('Cita creada')
    onCreated()
    onClose()
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="bg-white w-full sm:max-w-lg sm:rounded-2xl rounded-t-2xl shadow-xl max-h-[92vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="flex items-center justify-between p-5 border-b border-slate-100 sticky top-0 bg-white">
          <div className="flex items-center gap-2">
            {paso === 'detalle' && !mostrarForm && (
              <button onClick={() => setPaso('paciente')} className="p-1 rounded hover:bg-slate-100"><ChevronLeft className="h-5 w-5 text-slate-500" /></button>
            )}
            <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2"><CalendarPlus className="h-5 w-5 text-[#1E5C8E]" /> Nueva cita</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-slate-100"><X className="h-5 w-5 text-slate-400" /></button>
        </div>

        <div className="p-5 space-y-4">
          {/* PASO 1: PACIENTE */}
          {paso === 'paciente' && !mostrarForm && (
            <>
              <div className="relative">
                <Search className="h-4 w-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                <Input autoFocus placeholder="Buscar paciente por nombre o teléfono…" className="pl-9" value={query} onChange={(e) => setQuery(e.target.value)} />
              </div>

              {buscando && <p className="text-sm text-slate-400 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Buscando…</p>}

              {!buscando && query.trim().length >= 2 && (
                <div className="space-y-1 max-h-64 overflow-y-auto">
                  {resultados.length === 0 && <p className="text-sm text-slate-400 py-2">Sin resultados en esta clínica.</p>}
                  {resultados.map((p) => (
                    <button key={p.paciente_id} onClick={() => seleccionar(p)} className="w-full text-left px-3 py-2 rounded-lg hover:bg-slate-50 border border-transparent hover:border-slate-200">
                      <p className="font-medium text-slate-800">{p.nombre} {p.apellido}</p>
                      {p.telefono && <p className="text-xs text-slate-500">{p.telefono}</p>}
                    </button>
                  ))}
                </div>
              )}

              <Button variant="outline" className="w-full" onClick={() => setMostrarForm(true)}>
                <UserPlus className="h-4 w-4 mr-2" /> Registrar paciente nuevo
              </Button>
            </>
          )}

          {/* PASO 1b: FORM DE ALTA DE PACIENTE */}
          {paso === 'paciente' && mostrarForm && (
            <>
              <div className="flex items-center gap-2">
                <button onClick={() => setMostrarForm(false)} className="p-1 rounded hover:bg-slate-100"><ChevronLeft className="h-5 w-5 text-slate-500" /></button>
                <p className="font-semibold text-slate-700">Registrar paciente nuevo</p>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1"><Label>Nombre *</Label><Input value={nuevo.nombre} onChange={(e) => setNuevo({ ...nuevo, nombre: e.target.value })} /></div>
                <div className="space-y-1"><Label>Apellido *</Label><Input value={nuevo.apellido} onChange={(e) => setNuevo({ ...nuevo, apellido: e.target.value })} /></div>
                <div className="space-y-1"><Label>Teléfono</Label><Input value={nuevo.telefono} onChange={(e) => setNuevo({ ...nuevo, telefono: e.target.value })} /></div>
                <div className="space-y-1"><Label>Fecha de nacimiento</Label><Input type="date" value={nuevo.fecha_nacimiento} onChange={(e) => setNuevo({ ...nuevo, fecha_nacimiento: e.target.value })} /></div>
                <div className="space-y-1">
                  <Label>Género</Label>
                  <select className="w-full h-9 rounded-md border border-slate-200 px-2 text-sm" value={nuevo.genero} onChange={(e) => setNuevo({ ...nuevo, genero: e.target.value })}>
                    <option value="">—</option>
                    <option value="femenino">Femenino</option>
                    <option value="masculino">Masculino</option>
                    <option value="otro">Otro</option>
                  </select>
                </div>
                <div className="space-y-1">
                  <Label>País</Label>
                  <select className="w-full h-9 rounded-md border border-slate-200 px-2 text-sm" value={nuevo.pais_id} onChange={(e) => setNuevo({ ...nuevo, pais_id: e.target.value })}>
                    <option value="">—</option>
                    {paises.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
                  </select>
                </div>
                <div className="space-y-1 col-span-2"><Label>Email</Label><Input type="email" value={nuevo.email} onChange={(e) => setNuevo({ ...nuevo, email: e.target.value })} /></div>
              </div>
              <Button className="w-full bg-[#1E5C8E] hover:bg-[#164a70] text-white" disabled={creandoPac} onClick={handleCrearPaciente}>
                {creandoPac ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Registrar y continuar'}
              </Button>
            </>
          )}

          {/* PASO 2: DETALLE DE LA CITA */}
          {paso === 'detalle' && paciente && (
            <>
              <div className="bg-slate-50 rounded-lg px-3 py-2">
                <p className="text-xs text-slate-500">Paciente</p>
                <p className="font-semibold text-slate-800">{paciente.nombre}</p>
              </div>
              <div className="space-y-1">
                <Label>Médico</Label>
                <select className="w-full h-9 rounded-md border border-slate-200 px-2 text-sm" value={detalle.medico_id} onChange={(e) => setDetalle({ ...detalle, medico_id: e.target.value })}>
                  {medicos.map((m) => <option key={m.medico_id} value={m.medico_id}>{m.nombre_completo}</option>)}
                </select>
              </div>
              <div className="grid grid-cols-3 gap-3">
                <div className="space-y-1"><Label>Fecha</Label><Input type="date" value={detalle.fecha} onChange={(e) => setDetalle({ ...detalle, fecha: e.target.value })} /></div>
                <div className="space-y-1"><Label>Inicio</Label><Input type="time" value={detalle.hora_inicio} onChange={(e) => setDetalle({ ...detalle, hora_inicio: e.target.value, hora_fin: sumar30(e.target.value) })} /></div>
                <div className="space-y-1"><Label>Fin</Label><Input type="time" value={detalle.hora_fin} onChange={(e) => setDetalle({ ...detalle, hora_fin: e.target.value })} /></div>
              </div>
              <div className="space-y-1">
                <Label>Motivo</Label>
                <textarea className="w-full rounded-md border border-slate-200 px-2 py-1.5 text-sm min-h-[64px]" value={detalle.motivo} onChange={(e) => setDetalle({ ...detalle, motivo: e.target.value })} placeholder="Motivo de la consulta (opcional)" />
              </div>
              {nombreMedico && <p className="text-xs text-slate-400">Se agenda con {nombreMedico}.</p>}
              <Button className="w-full bg-[#1E5C8E] hover:bg-[#164a70] text-white" disabled={creandoCita} onClick={handleCrearCita}>
                {creandoCita ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Crear cita'}
              </Button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
