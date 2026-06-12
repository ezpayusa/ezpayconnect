import { useState, useMemo } from 'react'
import { useLaboratorio, type OrdenExamen } from '@/laboratorio/hooks/useLaboratorio'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Textarea } from '@/components/ui/textarea'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ClipboardList, Loader2, RefreshCw, FlaskConical, User, Stethoscope, Clock, X, FileText } from 'lucide-react'

const ESTADO: Record<string, { label: string; color: string }> = {
  pendiente:  { label: 'Pendiente',   color: 'bg-amber-100 text-amber-700' },
  recibida:   { label: 'Recibida',    color: 'bg-blue-100 text-blue-700' },
  en_proceso: { label: 'En proceso',  color: 'bg-purple-100 text-purple-700' },
  completado: { label: 'Completada',  color: 'bg-green-100 text-green-700' },
  revision:   { label: 'En revisión', color: 'bg-slate-100 text-slate-700' },
}

const FILTROS = [
  { key: 'activas', label: 'Activas' },
  { key: 'pendiente', label: 'Pendientes' },
  { key: 'en_proceso', label: 'En proceso' },
  { key: 'completado', label: 'Completadas' },
  { key: 'todas', label: 'Todas' },
]

export default function LabOrdenesPage() {
  const { ordenes, loading, fetchOrdenes, cambiarEstado, subirResultado } = useLaboratorio()
  const [filtro, setFiltro] = useState('activas')
  const [modal, setModal] = useState<OrdenExamen | null>(null)
  const [resultado, setResultado] = useState('')
  const [archivoUrl, setArchivoUrl] = useState('')
  const [guardando, setGuardando] = useState(false)

  const lista = useMemo(() => {
    if (filtro === 'todas') return ordenes
    if (filtro === 'activas') return ordenes.filter((o) => o.estado !== 'completado')
    return ordenes.filter((o) => o.estado === filtro)
  }, [ordenes, filtro])

  const counts = useMemo(() => {
    const c: Record<string, number> = {}
    ordenes.forEach((o) => { c[o.estado] = (c[o.estado] || 0) + 1 })
    return c
  }, [ordenes])

  const abrirResultado = (o: OrdenExamen) => {
    setModal(o); setResultado(o.resultados || ''); setArchivoUrl(o.archivo_url || '')
  }

  const guardarResultado = async () => {
    if (!modal || !resultado.trim()) return
    setGuardando(true)
    const ok = await subirResultado(modal.id, resultado.trim(), archivoUrl.trim() || undefined)
    setGuardando(false)
    if (ok) setModal(null)
  }

  const nombrePaciente = (o: OrdenExamen) =>
    o.paciente_nombre || (o.paciente_id ? `Paciente #${o.paciente_id}` : 'Paciente')

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2 text-[#0c2a26]">
            <ClipboardList className="h-7 w-7 text-[#0E7C6B]" /> Órdenes de examen
          </h1>
          <p className="text-sm text-muted-foreground">Recibe órdenes de médicos y sube los resultados.</p>
        </div>
        <Button variant="outline" size="sm" onClick={fetchOrdenes}>
          <RefreshCw className="h-4 w-4 mr-1" /> Recargar
        </Button>
      </div>

      {/* Filtros */}
      <div className="flex gap-2 flex-wrap">
        {FILTROS.map((f) => {
          const n = f.key === 'todas' ? ordenes.length
            : f.key === 'activas' ? ordenes.filter((o) => o.estado !== 'completado').length
            : counts[f.key] || 0
          return (
            <button
              key={f.key}
              onClick={() => setFiltro(f.key)}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                filtro === f.key ? 'bg-[#0E7C6B] text-white' : 'bg-white border text-gray-600 hover:bg-gray-50'
              }`}
            >
              {f.label} <span className="opacity-70">({n})</span>
            </button>
          )
        })}
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><Loader2 className="h-8 w-8 animate-spin text-[#0E7C6B]" /></div>
      ) : lista.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-10 text-center text-muted-foreground">
            <FlaskConical className="h-10 w-10 mx-auto mb-3 text-gray-300" />
            No hay órdenes en esta vista.
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {lista.map((o) => {
            const est = ESTADO[o.estado] || ESTADO.pendiente
            return (
              <Card key={o.id} className={`border-l-4 ${o.prioridad === 'urgente' ? 'border-red-500' : 'border-[#0E7C6B]'}`}>
                <CardContent className="p-4 flex flex-col md:flex-row md:items-start gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap mb-1">
                      <Badge className={est.color}>{est.label}</Badge>
                      {o.prioridad === 'urgente' && <Badge className="bg-red-100 text-red-700">Urgente</Badge>}
                      {o.origen === 'walk_in' && <Badge variant="outline">Walk-in</Badge>}
                      <span className="text-xs text-muted-foreground flex items-center gap-1">
                        <Clock className="h-3 w-3" /> {o.fecha_solicitud}
                      </span>
                    </div>
                    <p className="font-semibold text-[#0c2a26]">{o.tipo}</p>
                    {o.descripcion && <p className="text-sm text-muted-foreground">{o.descripcion}</p>}
                    <div className="flex items-center gap-4 mt-2 text-sm flex-wrap">
                      <span className="flex items-center gap-1"><User className="h-4 w-4 text-gray-400" /> {nombrePaciente(o)}</span>
                      {o.medico_nombre && <span className="flex items-center gap-1 text-muted-foreground"><Stethoscope className="h-4 w-4 text-gray-400" /> {o.medico_nombre}</span>}
                      {o.clinica_nombre && <span className="text-muted-foreground">· {o.clinica_nombre}</span>}
                    </div>
                  </div>

                  {/* Acciones por estado */}
                  <div className="flex flex-col gap-2 min-w-[160px]">
                    {o.estado === 'pendiente' && (
                      <Button size="sm" className="bg-blue-600 hover:bg-blue-700" onClick={() => cambiarEstado(o.id, 'recibida')}>
                        Marcar recibida
                      </Button>
                    )}
                    {o.estado === 'recibida' && (
                      <Button size="sm" className="bg-purple-600 hover:bg-purple-700" onClick={() => cambiarEstado(o.id, 'en_proceso')}>
                        Iniciar proceso
                      </Button>
                    )}
                    {(o.estado === 'en_proceso' || o.estado === 'recibida') && (
                      <Button size="sm" className="bg-[#0E7C6B] hover:bg-[#0a5e51]" onClick={() => abrirResultado(o)}>
                        <FileText className="h-4 w-4 mr-1" /> Subir resultado
                      </Button>
                    )}
                    {o.estado === 'completado' && (
                      <Button size="sm" variant="outline" onClick={() => abrirResultado(o)}>
                        Ver resultado
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      {/* Modal resultado */}
      {modal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setModal(null)}>
          <Card className="w-full max-w-lg" onClick={(e) => e.stopPropagation()}>
            <CardContent className="p-6 space-y-4">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold flex items-center gap-2">
                  <FileText className="h-5 w-5 text-[#0E7C6B]" /> Resultado · {modal.tipo}
                </h2>
                <button onClick={() => setModal(null)}><X className="h-5 w-5 text-gray-400" /></button>
              </div>
              <p className="text-sm text-muted-foreground">Paciente: {nombrePaciente(modal)}</p>
              <div className="space-y-2">
                <Label>Resultado / valores *</Label>
                <Textarea rows={6} value={resultado} onChange={(e) => setResultado(e.target.value)}
                  placeholder="Escribe el resultado del examen…"
                  disabled={modal.estado === 'completado'} />
              </div>
              <div className="space-y-2">
                <Label>Enlace al archivo (PDF) — opcional</Label>
                <Input value={archivoUrl} onChange={(e) => setArchivoUrl(e.target.value)}
                  placeholder="https://…" disabled={modal.estado === 'completado'} />
              </div>
              {modal.estado !== 'completado' && (
                <div className="flex justify-end gap-2">
                  <Button variant="outline" onClick={() => setModal(null)}>Cancelar</Button>
                  <Button className="bg-[#0E7C6B] hover:bg-[#0a5e51]" onClick={guardarResultado} disabled={guardando || !resultado.trim()}>
                    {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null} Enviar resultado
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  )
}
