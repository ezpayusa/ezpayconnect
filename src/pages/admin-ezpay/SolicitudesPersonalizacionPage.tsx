import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import { Palette, Loader2, CheckCircle2, XCircle, Eye, ShieldAlert, Building2, Store } from 'lucide-react'
import { PreviewMaquetaPanel } from '@/components/personalizacion/PreviewMaquetaPanel'
import { TEMA_OFICIAL } from '@/components/theme/TenantThemeContext'

// Fila ya resuelta por la RPC DEFINER listar_solicitudes_personalizacion (mig 208): trae tenant_nombre
// y solicitante_nombre resueltos server-side.
interface SolicitudPers {
  id: string
  tenant_tipo: 'clinica' | 'empresa_proveedora'
  tenant_id: string
  tenant_nombre: string | null
  estado: 'pendiente' | 'aprobada' | 'rechazada'
  logo_url: string | null
  color_primario: string | null
  color_secundario: string | null
  color_fondo: string | null
  motivo_rechazo: string | null
  solicitante_nombre: string | null
  created_at: string
  revisado_at: string | null
}

const ESTADO_BADGE: Record<string, string> = {
  pendiente: 'bg-amber-100 text-amber-700',
  aprobada: 'bg-emerald-100 text-emerald-700',
  rechazada: 'bg-red-100 text-red-700',
}

// Swatch de color con su hex debajo.
function Swatch({ label, color }: { label: string; color: string | null }) {
  return (
    <div className="flex flex-col items-center gap-1">
      <div className="h-7 w-7 rounded border border-slate-200 shadow-sm" style={{ backgroundColor: color || '#ffffff' }} />
      <span className="text-[9px] text-slate-400">{label}</span>
    </div>
  )
}

export default function SolicitudesPersonalizacionPage() {
  const [solicitudes, setSolicitudes] = useState<SolicitudPers[]>([])
  const [loading, setLoading] = useState(true)
  const [noAutorizado, setNoAutorizado] = useState(false)
  const [estadoFiltro, setEstadoFiltro] = useState<'pendiente' | 'aprobada' | 'rechazada'>('pendiente')
  const [activa, setActiva] = useState<SolicitudPers | null>(null)
  const [modoRechazo, setModoRechazo] = useState(false)
  const [motivo, setMotivo] = useState('')
  const [procesando, setProcesando] = useState(false)

  const cargar = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase.rpc('listar_solicitudes_personalizacion', { p_estado: estadoFiltro })
    setLoading(false)
    if (error) {
      if (/no_autorizado/.test(error.message || '')) { setNoAutorizado(true); return }
      toast.error('Error cargando solicitudes: ' + error.message)
      return
    }
    setSolicitudes((Array.isArray(data) ? data : []) as SolicitudPers[])
  }, [estadoFiltro])

  useEffect(() => { cargar() }, [cargar])

  const abrir = (s: SolicitudPers) => { setActiva(s); setModoRechazo(false); setMotivo('') }
  const cerrar = () => { setActiva(null); setModoRechazo(false); setMotivo('') }

  const aprobar = async (s: SolicitudPers) => {
    setProcesando(true)
    const { error } = await supabase.rpc('aprobar_personalizacion', { p_solicitud_id: s.id })
    setProcesando(false)
    if (error) {
      const m = error.message || ''
      if (/PT005|ya_resuelta/.test(m)) toast.info('Esa solicitud ya fue resuelta por otro administrador.')
      else if (/no_autorizado|PT001/.test(m)) setNoAutorizado(true)
      else toast.error('Error: ' + m)
      await cargar()
      return
    }
    toast.success('Personalización aprobada y aplicada al tenant.')
    cerrar()
    await cargar()
  }

  const rechazar = async (s: SolicitudPers) => {
    const motivoLimpio = motivo.trim()
    if (!motivoLimpio) return // botón ya deshabilitado; guarda extra
    setProcesando(true)
    const { error } = await supabase.rpc('rechazar_personalizacion', { p_solicitud_id: s.id, p_motivo: motivoLimpio })
    setProcesando(false)
    if (error) {
      const m = error.message || ''
      if (/PT005|ya_resuelta/.test(m)) toast.info('Esa solicitud ya fue resuelta por otro administrador.')
      else if (/no_autorizado|PT001/.test(m)) setNoAutorizado(true)
      else toast.error('Error: ' + m)
      await cargar()
      return
    }
    toast.success('Solicitud rechazada.')
    cerrar()
    await cargar()
  }

  if (noAutorizado) {
    return (
      <div className="p-8">
        <div className="flex items-center gap-3 text-red-600 bg-red-50 border border-red-200 rounded-lg p-4 max-w-md">
          <ShieldAlert className="h-5 w-5 shrink-0" />
          <p className="text-sm">No autorizado: esta sección es solo para super administradores.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
            <Palette className="h-6 w-6 text-[#1E5C8E]" /> Solicitudes de personalización
          </h1>
          <p className="text-slate-500 mt-1">Logo y colores propuestos por clínicas y proveedores</p>
        </div>
        <select
          value={estadoFiltro}
          onChange={(e) => setEstadoFiltro(e.target.value as typeof estadoFiltro)}
          className="h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
        >
          <option value="pendiente">Pendientes</option>
          <option value="aprobada">Aprobadas</option>
          <option value="rechazada">Rechazadas</option>
        </select>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : solicitudes.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-slate-500">
            <Palette className="h-12 w-12 mx-auto mb-3 text-slate-300" />
            <p>No hay solicitudes {estadoFiltro === 'pendiente' ? 'pendientes' : estadoFiltro + 's'}.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {solicitudes.map((s) => {
            const TipoIcon = s.tenant_tipo === 'clinica' ? Building2 : Store
            return (
              <Card key={s.id} className="bg-white">
                <CardContent className="p-4 flex flex-col md:flex-row md:items-center gap-4">
                  <img
                    src={s.logo_url || TEMA_OFICIAL.logoUrl}
                    alt=""
                    className="h-12 w-12 rounded object-contain shrink-0 border border-slate-100 bg-slate-50"
                    onError={(e) => { (e.target as HTMLImageElement).src = TEMA_OFICIAL.logoUrl }}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-semibold text-slate-800 truncate">{s.tenant_nombre || '(sin nombre)'}</span>
                      <Badge variant="outline" className="text-[10px] flex items-center gap-1">
                        <TipoIcon className="h-3 w-3" /> {s.tenant_tipo === 'clinica' ? 'Clínica' : 'Proveedor'}
                      </Badge>
                      <Badge className={`text-[10px] ${ESTADO_BADGE[s.estado]}`}>{s.estado}</Badge>
                    </div>
                    <p className="text-xs text-slate-500 mt-1">
                      Solicitó: <span className="font-medium text-slate-700">{s.solicitante_nombre || 'Desconocido'}</span>
                      {' · '}{new Date(s.created_at).toLocaleString('es-GT')}
                    </p>
                  </div>
                  <div className="flex items-end gap-3 shrink-0">
                    <Swatch label="Prim." color={s.color_primario} />
                    <Swatch label="Sec." color={s.color_secundario} />
                    <Swatch label="Fondo" color={s.color_fondo} />
                  </div>
                  <Button size="sm" variant="outline" className="shrink-0" onClick={() => abrir(s)}>
                    <Eye className="h-4 w-4 mr-1" /> Ver detalle
                  </Button>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      {/* Modal de detalle */}
      <Dialog open={!!activa} onOpenChange={(o) => { if (!o) cerrar() }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Solicitud de personalización</DialogTitle>
          </DialogHeader>
          {activa && (
            <div className="space-y-4">
              <div className="flex justify-center">
                <PreviewMaquetaPanel
                  primario={activa.color_primario || TEMA_OFICIAL.primario}
                  secundario={activa.color_secundario || TEMA_OFICIAL.secundario}
                  logoUrl={activa.logo_url || TEMA_OFICIAL.logoUrl}
                />
              </div>

              <div className="grid grid-cols-2 gap-3 text-sm">
                <div>
                  <p className="font-medium text-slate-700">{activa.tenant_tipo === 'clinica' ? 'Clínica' : 'Proveedor'}</p>
                  <p className="text-slate-600">{activa.tenant_nombre || '(sin nombre)'}</p>
                </div>
                <div>
                  <p className="font-medium text-slate-700">Solicitó</p>
                  <p className="text-slate-600">{activa.solicitante_nombre || 'Desconocido'}</p>
                </div>
                <div><span className="font-medium">Primario:</span> <span className="font-mono text-slate-600">{activa.color_primario || '-'}</span></div>
                <div><span className="font-medium">Secundario:</span> <span className="font-mono text-slate-600">{activa.color_secundario || '-'}</span></div>
                <div><span className="font-medium">Fondo:</span> <span className="font-mono text-slate-600">{activa.color_fondo || '-'}</span></div>
                <div><span className="font-medium">Fecha:</span> {new Date(activa.created_at).toLocaleString('es-GT')}</div>
              </div>

              {activa.estado === 'rechazada' && activa.motivo_rechazo && (
                <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                  <span className="font-medium">Motivo del rechazo:</span> {activa.motivo_rechazo}
                </div>
              )}

              {/* Acciones: solo para pendientes */}
              {activa.estado === 'pendiente' && !modoRechazo && (
                <div className="flex gap-3 pt-2">
                  <Button variant="outline" className="flex-1" onClick={cerrar}>Cerrar</Button>
                  <Button
                    variant="outline" className="flex-1 text-red-600 hover:bg-red-50"
                    disabled={procesando}
                    onClick={() => { setModoRechazo(true); setMotivo('') }}
                  >
                    <XCircle className="h-4 w-4 mr-1" /> Rechazar
                  </Button>
                  <Button
                    className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white"
                    disabled={procesando}
                    onClick={() => aprobar(activa)}
                  >
                    {procesando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
                    Aprobar
                  </Button>
                </div>
              )}

              {/* Sub-form de rechazo con motivo OBLIGATORIO */}
              {activa.estado === 'pendiente' && modoRechazo && (
                <div className="space-y-2 pt-2 border-t">
                  <label className="text-sm font-medium">Motivo del rechazo <span className="text-red-500">*</span></label>
                  <Textarea
                    placeholder="Explicá por qué se rechaza (obligatorio)…"
                    value={motivo}
                    onChange={(e) => setMotivo(e.target.value)}
                    rows={3}
                  />
                  <div className="flex gap-3">
                    <Button variant="outline" className="flex-1" disabled={procesando} onClick={() => { setModoRechazo(false); setMotivo('') }}>
                      Volver
                    </Button>
                    <Button
                      className="flex-1 bg-red-600 hover:bg-red-700 text-white"
                      disabled={procesando || motivo.trim() === ''}
                      onClick={() => rechazar(activa)}
                    >
                      {procesando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <XCircle className="h-4 w-4 mr-1" />}
                      Confirmar rechazo
                    </Button>
                  </div>
                </div>
              )}

              {/* Resueltas: solo cerrar */}
              {activa.estado !== 'pendiente' && (
                <div className="pt-2">
                  <Button variant="outline" className="w-full" onClick={cerrar}>Cerrar</Button>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
