import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { openSignedUrl } from '@/lib/signedUrl'
import { usePaisFiltro } from '@/hooks/usePaisFiltro'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import {
  Megaphone,
  CheckCircle,
  XCircle,
  Loader2,
  Eye,
  Filter,
  CreditCard,
  ExternalLink,
  AlertTriangle,
} from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

interface PagoCampana {
  id: string
  monto: number
  moneda: string
  estado: string
  comprobante_url: string | null
  metodo_pago: string | null
  referencia_id: string | null
}

interface SolicitudConEmpresa {
  id: string
  titulo: string
  descripcion: string | null
  tipo: string
  imagen_url: string | null
  link_url: string | null
  fecha_inicio: string
  fecha_fin: string
  condicion_filtro: string | null
  genero_filtro: string | null
  edad_min: number | null
  edad_max: number | null
  estado: string
  monto_pagado: number | null
  comprobante_pago_url: string | null
  notas_admin: string | null
  created_at: string
  empresa: { nombre_empresa: string; email_contacto: string } | null
  plan_publicidad_id: number | null
}

export default function SolicitudesCampanaPage() {
  const [solicitudes, setSolicitudes] = useState<SolicitudConEmpresa[]>([])
  const [pagosMap, setPagosMap] = useState<Record<string, PagoCampana>>({})
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState('')
  const [estadoFiltro, setEstadoFiltro] = useState('enviada')
  const [solicitudActiva, setSolicitudActiva] = useState<SolicitudConEmpresa | null>(null)
  const [notasAdmin, setNotasAdmin] = useState('')
  const [procesando, setProcesando] = useState(false)
  const { paisId } = usePaisFiltro()

  const fetchSolicitudes = async () => {
    setLoading(true)
    let q = supabase
      .from('solicitudes_campana')
      .select('*, empresa:empresa_id(nombre_empresa, email_contacto)')
      .order('created_at', { ascending: false })

    if (estadoFiltro) q = q.eq('estado', estadoFiltro)
    if (paisId) q = q.eq('pais_id', paisId)

    const { data, error } = await q

    if (error) {
      toast.error('Error cargando solicitudes')
      console.error(error)
    } else {
      setSolicitudes((data || []) as SolicitudConEmpresa[])
    }

    // Traer pagos asociados a campañas
    const { data: pagosData } = await supabase
      .from('pagos_proveedor')
      .select('id, monto, moneda, estado, comprobante_url, metodo_pago, referencia_id')
      .eq('tipo', 'campana')

    const map: Record<string, PagoCampana> = {}
    ;(pagosData || []).forEach((p: any) => {
      if (p.referencia_id) {
        map[p.referencia_id] = p
      }
    })
    setPagosMap(map)

    setLoading(false)
  }

  useEffect(() => {
    fetchSolicitudes()
  }, [estadoFiltro])

  // Avisar a los usuarios de la empresa proveedora (campanita del portal).
  // RPC gateado: deriva destinatarios + contenido (incl. notas_admin YA persistidas en el ref) del estado de la
  // solicitud; aprobar/rechazar persisten estado+notas ANTES de llamar (ver aprobar()/rechazar()).
  const notificarProveedor = async (solicitud: SolicitudConEmpresa, _resultado: 'aprobada' | 'rechazada') => {
    await supabase.rpc('notificar_campana_resultado', { p_solicitud_id: solicitud.id })
  }

  const aprobar = async (solicitud: SolicitudConEmpresa) => {
    const pago = pagosMap[solicitud.id]
    if (!pago || pago.estado !== 'verificado') {
      toast.error('No se puede aprobar: el pago no está verificado. Verificalo primero en "Pagos de Proveedores".')
      return
    }

    setProcesando(true)

    // Publicar vía RPC SECURITY DEFINER (revalida super_admin server-side):
    // inserta la campaña + marca la solicitud 'publicada' atómicamente.
    const { error: rpcError } = await supabase.rpc('aprobar_solicitud_campana', {
      p_solicitud_id: solicitud.id,
      p_notas_admin: notasAdmin || null,
    })

    if (rpcError) {
      toast.error('Error publicando campaña')
      console.error(rpcError)
      setProcesando(false)
      return
    }

    toast.success('Campaña aprobada y publicada')
    await notificarProveedor(solicitud, 'aprobada')
    setSolicitudActiva(null)
    setNotasAdmin('')
    fetchSolicitudes()
    setProcesando(false)
  }

  const rechazar = async (solicitud: SolicitudConEmpresa) => {
    setProcesando(true)
    const { error } = await supabase
      .from('solicitudes_campana')
      .update({ estado: 'rechazada', notas_admin: notasAdmin || null })
      .eq('id', solicitud.id)

    if (error) {
      toast.error('Error rechazando solicitud')
      console.error(error)
    } else {
      toast.success('Campaña rechazada')
      await notificarProveedor(solicitud, 'rechazada')
      setSolicitudActiva(null)
      setNotasAdmin('')
      fetchSolicitudes()
    }
    setProcesando(false)
  }

  const estadoColor: Record<string, string> = {
    borrador: 'bg-slate-100 text-slate-700',
    enviada: 'bg-blue-100 text-blue-700',
    en_revision: 'bg-amber-100 text-amber-700',
    aprobada: 'bg-emerald-100 text-emerald-700',
    rechazada: 'bg-red-100 text-red-700',
    publicada: 'bg-purple-100 text-purple-700',
  }

  const pagoEstadoColor = (estado: string) => {
    switch (estado) {
      case 'verificado': return 'bg-emerald-100 text-emerald-700'
      case 'pendiente': return 'bg-amber-100 text-amber-700'
      case 'rechazado': return 'bg-red-100 text-red-700'
      default: return 'bg-slate-100 text-slate-700'
    }
  }

  const formatMoneda = (monto: number, moneda: string) =>
    new Intl.NumberFormat('es-GT', { style: 'currency', currency: moneda || 'GTQ' }).format(monto)

  const filtradas = solicitudes.filter((s) =>
    s.titulo.toLowerCase().includes(filtro.toLowerCase()) ||
    s.empresa?.nombre_empresa?.toLowerCase().includes(filtro.toLowerCase())
  )

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
            <Megaphone className="h-6 w-6 text-rose-500" />
            Solicitudes de Campaña
          </h1>
          <p className="text-slate-500 mt-1">Revisa contenido y estado de pago antes de publicar</p>
        </div>
      </div>

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Filter className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input
            placeholder="Buscar por título o empresa..."
            value={filtro}
            onChange={(e) => setFiltro(e.target.value)}
            className="pl-9"
          />
        </div>
        <select
          value={estadoFiltro}
          onChange={(e) => setEstadoFiltro(e.target.value)}
          className="h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
        >
          <option value="enviada">Enviada (por revisar)</option>
          <option value="en_revision">En revisión</option>
          <option value="aprobada">Aprobada</option>
          <option value="rechazada">Rechazada</option>
          <option value="publicada">Publicada</option>
          <option value="borrador">Borrador (sin pagar)</option>
          <option value="">Todas</option>
        </select>
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : filtradas.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-slate-500">
            <Megaphone className="h-12 w-12 mx-auto mb-3 text-slate-300" />
            <p>No hay solicitudes en este estado</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtradas.map((s) => {
            const pago = pagosMap[s.id]
            return (
              <Card key={s.id} className="overflow-hidden">
                <div className="h-32 bg-slate-100 relative">
                  {s.imagen_url ? (
                    <img
                      src={s.imagen_url}
                      alt={s.titulo}
                      className="w-full h-full object-cover"
                      onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                    />
                  ) : (
                    <div className="flex items-center justify-center h-full">
                      <Megaphone className="h-8 w-8 text-slate-300" />
                    </div>
                  )}
                </div>
                <CardContent className="p-4">
                  <div className="flex items-center gap-2 mb-2 flex-wrap">
                    <Badge className={estadoColor[s.estado] || estadoColor.borrador}>{s.estado}</Badge>
                    {pago ? (
                      <Badge className={pagoEstadoColor(pago.estado)}>
                        <CreditCard className="h-3 w-3 mr-1" />
                        Pago {pago.estado}
                      </Badge>
                    ) : s.estado !== 'borrador' ? (
                      <Badge className="bg-red-100 text-red-700">
                        <AlertTriangle className="h-3 w-3 mr-1" />
                        Sin pago
                      </Badge>
                    ) : null}
                    <span className="text-xs text-slate-400 ml-auto">{s.tipo}</span>
                  </div>
                  <h3 className="font-semibold text-slate-800">{s.titulo}</h3>
                  <p className="text-sm text-slate-500">{s.empresa?.nombre_empresa}</p>
                  <p className="text-xs text-slate-400 mt-1">{s.fecha_inicio} → {s.fecha_fin}</p>
                  {pago && (
                    <p className="text-xs text-slate-500 mt-1">
                      Monto: {formatMoneda(pago.monto, pago.moneda)}
                    </p>
                  )}
                  {s.notas_admin && (
                    <p className="text-xs text-amber-600 mt-2 bg-amber-50 p-2 rounded">
                      Nota: {s.notas_admin}
                    </p>
                  )}
                  <div className="flex gap-2 mt-3">
                    <Button size="sm" variant="outline" className="flex-1" onClick={() => { setSolicitudActiva(s); setNotasAdmin('') }}>
                      <Eye className="h-3.5 w-3.5 mr-1" />
                      {s.estado === 'publicada' || s.estado === 'rechazada' ? 'Ver detalle' : 'Revisar'}
                    </Button>
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      {/* Modal de revisión */}
      <Dialog open={!!solicitudActiva} onOpenChange={() => { setSolicitudActiva(null); setNotasAdmin('') }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Revisar campaña</DialogTitle>
          </DialogHeader>
          {solicitudActiva && (
            <div className="space-y-4">
              {solicitudActiva.imagen_url && (
                <img src={solicitudActiva.imagen_url} alt="" className="w-full h-40 object-cover rounded-lg" />
              )}

              <div className="grid grid-cols-2 gap-3 text-sm">
                <div>
                  <p className="font-medium text-slate-700">Título</p>
                  <p className="text-slate-600">{solicitudActiva.titulo}</p>
                </div>
                <div>
                  <p className="font-medium text-slate-700">Empresa</p>
                  <p className="text-slate-600">{solicitudActiva.empresa?.nombre_empresa}</p>
                  <p className="text-xs text-slate-400">{solicitudActiva.empresa?.email_contacto}</p>
                </div>
                <div className="col-span-2">
                  <p className="font-medium text-slate-700">Descripción</p>
                  <p className="text-slate-600">{solicitudActiva.descripcion || '-'}</p>
                </div>
                <div><span className="font-medium">Tipo:</span> {solicitudActiva.tipo}</div>
                <div><span className="font-medium">Link:</span> {solicitudActiva.link_url || '-'}</div>
                <div><span className="font-medium">Inicio:</span> {solicitudActiva.fecha_inicio}</div>
                <div><span className="font-medium">Fin:</span> {solicitudActiva.fecha_fin}</div>
                <div><span className="font-medium">Condición:</span> {solicitudActiva.condicion_filtro || '-'}</div>
                <div><span className="font-medium">Género:</span> {solicitudActiva.genero_filtro || '-'}</div>
                <div><span className="font-medium">Edad:</span> {solicitudActiva.edad_min ?? '-'} - {solicitudActiva.edad_max ?? '-'}</div>
              </div>

              {/* Información de pago */}
              <div className="border rounded-lg p-3 space-y-2 bg-slate-50">
                <p className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                  <CreditCard className="h-4 w-4" />
                  Información de pago
                </p>
                {(() => {
                  const pago = pagosMap[solicitudActiva.id]
                  if (!pago) {
                    return (
                      <div className="flex items-center gap-2 text-sm text-red-600">
                        <AlertTriangle className="h-4 w-4" />
                        <span>No se ha registrado ningún pago para esta campaña.</span>
                      </div>
                    )
                  }
                  return (
                    <div className="space-y-2 text-sm">
                      <div className="flex items-center justify-between">
                        <span className="text-slate-500">Estado del pago</span>
                        <Badge className={pagoEstadoColor(pago.estado)}>{pago.estado}</Badge>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-slate-500">Monto</span>
                        <span className="font-medium">{formatMoneda(pago.monto, pago.moneda)}</span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-slate-500">Método</span>
                        <span className="font-medium capitalize">{pago.metodo_pago || '-'}</span>
                      </div>
                      {pago.comprobante_url && (
                        <div className="pt-1">
                          <button
                            type="button"
                            onClick={() => openSignedUrl('comprobantes', pago.comprobante_url)}
                            className="inline-flex items-center gap-1 text-blue-600 hover:underline text-sm"
                          >
                            <ExternalLink className="h-3.5 w-3.5" />
                            Ver comprobante de pago
                          </button>
                        </div>
                      )}
                    </div>
                  )
                })()}
              </div>

              <div className="space-y-2">
                <label className="text-sm font-medium">Nota para el proveedor (opcional)</label>
                <Input
                  value={notasAdmin}
                  onChange={(e) => setNotasAdmin(e.target.value)}
                  placeholder="Motivo de aprobación o rechazo..."
                />
              </div>

              <div className="flex gap-3 pt-2">
                <Button
                  variant="outline"
                  className="flex-1"
                  onClick={() => { setSolicitudActiva(null); setNotasAdmin('') }}
                >
                  Cerrar
                </Button>
                {solicitudActiva.estado !== 'publicada' && solicitudActiva.estado !== 'rechazada' && (
                  <>
                    <Button
                      variant="outline"
                      className="flex-1 text-red-600 hover:bg-red-50"
                      disabled={procesando}
                      onClick={() => rechazar(solicitudActiva)}
                    >
                      <XCircle className="h-4 w-4 mr-1" />
                      Rechazar
                    </Button>
                    <Button
                      className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white"
                      disabled={procesando || !pagosMap[solicitudActiva.id] || pagosMap[solicitudActiva.id].estado !== 'verificado'}
                      onClick={() => aprobar(solicitudActiva)}
                    >
                      <CheckCircle className="h-4 w-4 mr-1" />
                      Aprobar
                    </Button>
                  </>
                )}
              </div>
              {solicitudActiva.estado !== 'publicada' && solicitudActiva.estado !== 'rechazada' && (!pagosMap[solicitudActiva.id] || pagosMap[solicitudActiva.id].estado !== 'verificado') && (
                <p className="text-xs text-center text-red-500">
                  Solo se puede aprobar si el pago está verificado en "Pagos de Proveedores".
                </p>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
