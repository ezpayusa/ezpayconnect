import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
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
} from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

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
}

export default function SolicitudesCampanaPage() {
  const [solicitudes, setSolicitudes] = useState<SolicitudConEmpresa[]>([])
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState('')
  const [estadoFiltro, setEstadoFiltro] = useState('')
  const [solicitudActiva, setSolicitudActiva] = useState<SolicitudConEmpresa | null>(null)
  const [notasAdmin, setNotasAdmin] = useState('')
  const [procesando, setProcesando] = useState(false)

  const fetchSolicitudes = async () => {
    setLoading(true)
    let q = supabase
      .from('solicitudes_campana')
      .select('*, empresa:empresa_id(nombre_empresa, email_contacto)')
      .order('created_at', { ascending: false })

    if (estadoFiltro) q = q.eq('estado', estadoFiltro)

    const { data, error } = await q

    if (error) {
      toast.error('Error cargando solicitudes')
      console.error(error)
    } else {
      setSolicitudes((data || []) as SolicitudConEmpresa[])
    }
    setLoading(false)
  }

  useEffect(() => {
    fetchSolicitudes()
  }, [estadoFiltro])

  const aprobar = async (solicitud: SolicitudConEmpresa) => {
    setProcesando(true)

    // 1. Insertar en campanas_publicitarias
    const { error: insertError } = await supabase.from('campanas_publicitarias').insert({
      titulo: solicitud.titulo,
      descripcion: solicitud.descripcion,
      tipo: solicitud.tipo,
      imagen_url: solicitud.imagen_url,
      link_url: solicitud.link_url,
      fecha_inicio: solicitud.fecha_inicio,
      fecha_fin: solicitud.fecha_fin,
      activa: true,
      condicion_filtro: solicitud.condicion_filtro,
      genero_filtro: solicitud.genero_filtro,
      edad_min: solicitud.edad_min,
      edad_max: solicitud.edad_max,
    })

    if (insertError) {
      toast.error('Error publicando campaña')
      console.error(insertError)
      setProcesando(false)
      return
    }

    // 2. Actualizar solicitud
    const { error: updateError } = await supabase
      .from('solicitudes_campana')
      .update({ estado: 'publicada', notas_admin: notasAdmin || null })
      .eq('id', solicitud.id)

    if (updateError) {
      toast.error('Error actualizando solicitud')
      console.error(updateError)
    } else {
      toast.success('Campaña aprobada y publicada')
      setSolicitudActiva(null)
      setNotasAdmin('')
      fetchSolicitudes()
    }
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
          <p className="text-slate-500 mt-1">Revisa, aprueba o rechaza campañas publicitarias de proveedores</p>
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
          <option value="">Todos los estados</option>
          <option value="enviada">Enviada</option>
          <option value="en_revision">En revisión</option>
          <option value="aprobada">Aprobada</option>
          <option value="rechazada">Rechazada</option>
          <option value="publicada">Publicada</option>
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
            <p>No hay solicitudes pendientes</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtradas.map((s) => (
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
                <div className="flex items-center gap-2 mb-2">
                  <Badge className={estadoColor[s.estado] || estadoColor.borrador}>{s.estado}</Badge>
                  <span className="text-xs text-slate-400 ml-auto">{s.tipo}</span>
                </div>
                <h3 className="font-semibold text-slate-800">{s.titulo}</h3>
                <p className="text-sm text-slate-500">{s.empresa?.nombre_empresa}</p>
                <p className="text-xs text-slate-400 mt-1">{s.fecha_inicio} → {s.fecha_fin}</p>
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
          ))}
        </div>
      )}

      {/* Modal de revisión */}
      <Dialog open={!!solicitudActiva} onOpenChange={() => { setSolicitudActiva(null); setNotasAdmin('') }}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Revisar campaña</DialogTitle>
          </DialogHeader>
          {solicitudActiva && (
            <div className="space-y-4">
              {solicitudActiva.imagen_url && (
                <img src={solicitudActiva.imagen_url} alt="" className="w-full h-40 object-cover rounded-lg" />
              )}
              <div>
                <p className="text-sm font-medium">Título</p>
                <p className="text-sm text-slate-600">{solicitudActiva.titulo}</p>
              </div>
              <div>
                <p className="text-sm font-medium">Empresa</p>
                <p className="text-sm text-slate-600">{solicitudActiva.empresa?.nombre_empresa} ({solicitudActiva.empresa?.email_contacto})</p>
              </div>
              <div>
                <p className="text-sm font-medium">Descripción</p>
                <p className="text-sm text-slate-600">{solicitudActiva.descripcion || '-'}</p>
              </div>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div><span className="font-medium">Tipo:</span> {solicitudActiva.tipo}</div>
                <div><span className="font-medium">Link:</span> {solicitudActiva.link_url || '-'}</div>
                <div><span className="font-medium">Inicio:</span> {solicitudActiva.fecha_inicio}</div>
                <div><span className="font-medium">Fin:</span> {solicitudActiva.fecha_fin}</div>
                <div><span className="font-medium">Condición:</span> {solicitudActiva.condicion_filtro || '-'}</div>
                <div><span className="font-medium">Género:</span> {solicitudActiva.genero_filtro || '-'}</div>
                <div><span className="font-medium">Edad:</span> {solicitudActiva.edad_min ?? '-'} - {solicitudActiva.edad_max ?? '-'}</div>
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
                      disabled={procesando}
                      onClick={() => aprobar(solicitudActiva)}
                    >
                      <CheckCircle className="h-4 w-4 mr-1" />
                      Aprobar
                    </Button>
                  </>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
