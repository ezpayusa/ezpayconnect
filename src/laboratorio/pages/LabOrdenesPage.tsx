import { useState, useMemo } from 'react'
import { openSignedUrl } from '@/lib/signedUrl'
import { useLaboratorio, type OrdenExamen, type OrdenAgrupada } from '@/laboratorio/hooks/useLaboratorio'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import { ClipboardList, Loader2, RefreshCw, FlaskConical, User, Stethoscope, Clock, X, FileText, MessageSquare } from 'lucide-react'

const ESTADO: Record<string, { label: string; color: string }> = {
  pendiente:  { label: 'Pendiente',   color: 'bg-amber-100 text-amber-700' },
  recibida:   { label: 'Recibida',    color: 'bg-blue-100 text-blue-700' },
  en_proceso: { label: 'En proceso',  color: 'bg-purple-100 text-purple-700' },
  completado: { label: 'Completada',  color: 'bg-green-100 text-green-700' },
  revision:   { label: 'En revisión', color: 'bg-slate-100 text-slate-700' },
}

const FILTROS = [
  { key: 'activas', label: 'Activas' },
  { key: 'completadas', label: 'Completadas' },
  { key: 'todas', label: 'Todas' },
]

const ordenCompletada = (o: OrdenAgrupada) => o.items.every((i) => i.estado === 'completado')

export default function LabOrdenesPage() {
  const { ordenes, loading, fetchOrdenes, cambiarEstado, subirResultado } = useLaboratorio()
  const [filtro, setFiltro] = useState('activas')
  const [modal, setModal] = useState<OrdenExamen | null>(null)
  const [resultado, setResultado] = useState('')
  const [archivoFile, setArchivoFile] = useState<File | null>(null)
  const [guardando, setGuardando] = useState(false)

  const lista = useMemo(() => {
    if (filtro === 'todas') return ordenes
    if (filtro === 'completadas') return ordenes.filter(ordenCompletada)
    return ordenes.filter((o) => !ordenCompletada(o))
  }, [ordenes, filtro])

  const abrirResultado = (i: OrdenExamen) => {
    setModal(i); setResultado(i.resultados || ''); setArchivoFile(null)
  }
  const guardarResultado = async () => {
    if (!modal || !resultado.trim()) return
    setGuardando(true)
    const ok = await subirResultado(modal.id, resultado.trim(), archivoFile, modal.tipo)
    setGuardando(false)
    if (ok) setModal(null)
  }

  const nombrePaciente = (o: OrdenAgrupada) =>
    o.paciente_nombre || (o.paciente_id ? `Paciente #${o.paciente_id}` : 'Paciente')

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2 text-[#0c2a26]">
            <ClipboardList className="h-7 w-7 text-[#0E7C6B]" /> Órdenes de examen
          </h1>
          <p className="text-sm text-muted-foreground">Cada orden agrupa los exámenes solicitados. Sube el resultado de cada examen.</p>
        </div>
        <Button variant="outline" size="sm" onClick={fetchOrdenes}>
          <RefreshCw className="h-4 w-4 mr-1" /> Recargar
        </Button>
      </div>

      <div className="flex gap-2 flex-wrap">
        {FILTROS.map((f) => {
          const n = f.key === 'todas' ? ordenes.length
            : f.key === 'completadas' ? ordenes.filter(ordenCompletada).length
            : ordenes.filter((o) => !ordenCompletada(o)).length
          return (
            <button key={f.key} onClick={() => setFiltro(f.key)}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                filtro === f.key ? 'bg-[#0E7C6B] text-white' : 'bg-white border text-gray-600 hover:bg-gray-50'
              }`}>
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
            <FlaskConical className="h-10 w-10 mx-auto mb-3 text-gray-300" /> No hay órdenes en esta vista.
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {lista.map((o, idx) => (
            <Card key={o.orden_id || `legacy-${idx}`} className={`border-l-4 ${o.prioridad === 'urgente' ? 'border-red-500' : 'border-[#0E7C6B]'}`}>
              <CardContent className="p-4">
                {/* Cabecera de la orden */}
                <div className="flex items-start justify-between flex-wrap gap-2 mb-3">
                  <div>
                    <div className="flex items-center gap-2 flex-wrap mb-1">
                      <span className="font-semibold text-[#0c2a26] flex items-center gap-1">
                        <User className="h-4 w-4 text-gray-400" /> {nombrePaciente(o)}
                      </span>
                      {o.prioridad === 'urgente' && <Badge className="bg-red-100 text-red-700">Urgente</Badge>}
                      {o.origen === 'walk_in' && <Badge variant="outline">Walk-in</Badge>}
                      <span className="text-xs text-muted-foreground flex items-center gap-1">
                        <Clock className="h-3 w-3" /> {new Date(o.fecha).toLocaleDateString('es-GT')}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 text-sm text-muted-foreground flex-wrap">
                      {o.medico_nombre && <span className="flex items-center gap-1"><Stethoscope className="h-4 w-4 text-gray-400" /> {o.medico_nombre}</span>}
                      {o.clinica_nombre && <span>· {o.clinica_nombre}</span>}
                    </div>
                  </div>
                  <Badge variant="outline" className="text-xs">{o.items.length} examen{o.items.length !== 1 ? 'es' : ''}</Badge>
                </div>

                {/* Instrucciones */}
                {o.instrucciones && (
                  <div className="flex items-start gap-2 text-sm bg-amber-50 border border-amber-200 rounded-lg p-2 mb-3">
                    <MessageSquare className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
                    <span className="text-amber-800">{o.instrucciones}</span>
                  </div>
                )}

                {/* Ítems */}
                <div className="space-y-2">
                  {o.items.map((i) => {
                    const est = ESTADO[i.estado] || ESTADO.pendiente
                    return (
                      <div key={i.id} className="flex items-center justify-between gap-3 p-2 bg-gray-50 rounded-lg">
                        <div className="min-w-0">
                          <span className="font-medium text-sm">{i.tipo}</span>
                          <Badge className={`ml-2 ${est.color}`}>{est.label}</Badge>
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          {i.estado === 'pendiente' && (
                            <Button size="sm" variant="outline" onClick={() => cambiarEstado(i.id, 'recibida')}>Recibir</Button>
                          )}
                          {i.estado === 'recibida' && (
                            <Button size="sm" variant="outline" onClick={() => cambiarEstado(i.id, 'en_proceso')}>En proceso</Button>
                          )}
                          {(i.estado === 'recibida' || i.estado === 'en_proceso') && (
                            <Button size="sm" className="bg-[#0E7C6B] hover:bg-[#0a5e51]" onClick={() => abrirResultado(i)}>
                              <FileText className="h-4 w-4 mr-1" /> Resultado
                            </Button>
                          )}
                          {i.estado === 'completado' && (
                            <Button size="sm" variant="ghost" onClick={() => abrirResultado(i)}>Ver</Button>
                          )}
                        </div>
                      </div>
                    )
                  })}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Modal resultado por examen */}
      {modal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setModal(null)}>
          <Card className="w-full max-w-lg bg-white shadow-xl" onClick={(e) => e.stopPropagation()}>
            <CardContent className="p-6 space-y-4">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold flex items-center gap-2">
                  <FileText className="h-5 w-5 text-[#0E7C6B]" /> Resultado · {modal.tipo}
                </h2>
                <button onClick={() => setModal(null)}><X className="h-5 w-5 text-gray-400" /></button>
              </div>
              <div className="space-y-2">
                <Label>Resultado / valores *</Label>
                <Textarea rows={6} value={resultado} onChange={(e) => setResultado(e.target.value)}
                  placeholder="Escribe el resultado del examen…" disabled={modal.estado === 'completado'} />
              </div>

              {/* Archivo ya subido (si existe) */}
              {modal.archivo_url && (
                <button type="button" onClick={() => openSignedUrl('resultados-examenes', modal.archivo_url)}
                  className="flex items-center gap-2 text-sm text-[#0E7C6B] hover:underline">
                  <FileText className="h-4 w-4" /> Ver archivo adjunto actual
                </button>
              )}

              {modal.estado !== 'completado' && (
                <div className="space-y-2">
                  <Label>Adjuntar archivo (PDF o imagen) — opcional</Label>
                  <input
                    type="file"
                    accept=".pdf,image/*"
                    onChange={(e) => setArchivoFile(e.target.files?.[0] || null)}
                    className="block w-full text-sm text-gray-600 file:mr-3 file:py-2 file:px-3 file:rounded-lg file:border-0 file:bg-[#0E7C6B] file:text-white hover:file:bg-[#0a5e51] file:cursor-pointer"
                  />
                  {archivoFile && <p className="text-xs text-muted-foreground">Seleccionado: {archivoFile.name}</p>}
                </div>
              )}

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
