import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { openSignedUrl } from '@/lib/signedUrl'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { CreditCard, CheckCircle, XCircle, Loader2, Filter, Eye } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'

interface PagoConEmpresa {
  id: string
  empresa_id: string
  tipo: string
  referencia_id: string | null
  monto: number
  moneda: string
  metodo_pago: string | null
  comprobante_url: string | null
  estado: string
  fecha_pago: string | null
  created_at: string
  empresa: { nombre_empresa: string; email_contacto: string } | null
}

export default function PagosProveedoresPage() {
  const [pagos, setPagos] = useState<PagoConEmpresa[]>([])
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState('')
  const [estadoFiltro, setEstadoFiltro] = useState('')
  const [pagoActivo, setPagoActivo] = useState<PagoConEmpresa | null>(null)
  const [procesando, setProcesando] = useState(false)

  const fetchPagos = useCallback(async () => {
    setLoading(true)
    let q = supabase
      .from('pagos_proveedor')
      .select('*, empresa:empresa_id(nombre_empresa, email_contacto)')
      .order('created_at', { ascending: false })

    if (estadoFiltro) q = q.eq('estado', estadoFiltro)

    const { data, error } = await q

    if (error) {
      toast.error('Error cargando pagos')
      console.error(error)
    } else {
      setPagos((data || []) as PagoConEmpresa[])
    }
    setLoading(false)
  }, [estadoFiltro])

  useEffect(() => {
    fetchPagos()
  }, [fetchPagos])

  const verificar = async (id: string, estado: 'verificado' | 'rechazado') => {
    setProcesando(true)
    const { data: { user } } = await supabase.auth.getUser()

    if (estado === 'verificado') {
      // Obtener datos del pago para procesar según tipo
      const { data: pagoData } = await supabase.from('pagos_proveedor').select('*').eq('id', id).single()

      if (pagoData?.tipo === 'plan_visitador' && pagoData.referencia_id) {
        // Leer configuración del plan desde el sistema unificado
        const { data: planConfig } = await supabase
          .from('planes_configuracion')
          .select('*, plan_base:plan_base_id(*)')
          .eq('id', pagoData.referencia_id)
          .single()

        if (planConfig) {
          const atributos = planConfig.plan_base?.atributos || {}
          const duracionDias = atributos.duracion_dias || 30
          const hoy = new Date()
          const fin = new Date()
          fin.setDate(hoy.getDate() + duracionDias)
          const dia = (d: Date) => d.toISOString().split('T')[0] // pvc fechas son DATE

          // Visitas = BOLSA por país en pvc (única fuente; super_admin la provisiona al verificar el pago).
          // incluidas = atributos.visitas_incluidas; null/0-ausente → ilimitado (NULL).
          const incluidas = atributos.visitas_incluidas ?? null
          const { error: planError } = await supabase.from('planes_visitador_contratados').insert({
            empresa_id: pagoData.empresa_id,
            plan_visitador_id: 1,                 // catálogo sin FK; valor por defecto
            pais_id: planConfig.pais_id,          // bolsa POR PAÍS (la config es por país)
            cantidad_visitas_incluidas: incluidas,
            visitas_usadas: 0,
            precio_pagado: pagoData.monto,
            fecha_inicio: dia(hoy),
            fecha_fin: dia(fin),
            estado: 'activo',
          })

          if (planError) {
            toast.error('Error activando plan de visitas')
            console.error(planError)
            setProcesando(false)
            return
          }
        } else {
          toast.error('No se encontró la configuración del plan')
          setProcesando(false)
          return
        }
      }

      if (pagoData?.tipo === 'campana' && pagoData.referencia_id) {
        const { data: campana } = await supabase
          .from('solicitudes_campana')
          .select('*, plan:plan_publicidad_id(peso)')
          .eq('id', pagoData.referencia_id)
          .single()

        if (campana) {
          const pesoPlan = (campana.plan as any)?.peso || 1

          const { error: pubError } = await supabase.from('campanas_publicitarias').insert({
            titulo: campana.titulo,
            descripcion: campana.descripcion,
            tipo: campana.tipo,
            imagen_url: campana.imagen_url,
            link_url: campana.link_url,
            fecha_inicio: campana.fecha_inicio,
            fecha_fin: campana.fecha_fin,
            activa: true,
            pais_id: campana.pais_id,   // NOT NULL en campanas_publicitarias (mig 099); se propaga de la solicitud
            condicion_filtro: campana.condicion_filtro,
            genero_filtro: campana.genero_filtro,
            edad_min: campana.edad_min,
            edad_max: campana.edad_max,
            peso: pesoPlan,
            empresa_id: campana.empresa_id,          // dueño real: las métricas del proveedor dependen de esto
            solicitud_campana_id: pagoData.referencia_id,
          })

          // Solo marcar la solicitud como 'publicada' si el INSERT de la campaña fue exitoso.
          // Antes se marcaba antes de chequear el error -> solicitud "publicada" sin campaña.
          if (pubError) {
            toast.error('Error publicando campaña')
            console.error(pubError?.message ?? pubError?.code)
            setProcesando(false)
            return
          }

          const { error: updError } = await supabase
            .from('solicitudes_campana')
            .update({ estado: 'publicada' })
            .eq('id', pagoData.referencia_id)

          if (updError) {
            toast.error('Error publicando campaña')
            console.error(updError?.message ?? updError?.code)
            setProcesando(false)
            return
          }
        }
      }

      if ((pagoData?.tipo === 'plan_laboratorio' || pagoData?.tipo === 'plan_farmacia') && pagoData.referencia_id) {
        // Capacidad de módulo (lab/farmacia): leer duración del plan y otorgar la capacidad a la empresa.
        const { data: planConfig } = await supabase
          .from('planes_configuracion')
          .select('*, plan_base:plan_base_id(*)')
          .eq('id', pagoData.referencia_id)
          .single()

        if (!planConfig) {
          toast.error('No se encontró la configuración del plan')
          setProcesando(false)
          return
        }

        const atributos = (planConfig.plan_base as any)?.atributos || {}
        const duracionDias = atributos.duracion_dias || 30
        const fin = new Date()
        fin.setDate(fin.getDate() + duracionDias)
        const codigo = pagoData.tipo === 'plan_laboratorio' ? 'laboratorio' : 'farmacia'

        const { error: capError } = await supabase.rpc('otorgar_capacidad_empresa', {
          p_empresa_id: pagoData.empresa_id,
          p_codigo: codigo,
          p_hasta: fin.toISOString(),
        })

        if (capError) {
          toast.error('Error activando el plan (capacidad)')
          console.error(capError)
          setProcesando(false)
          return
        }
      }
    }

    const { error } = await supabase
      .from('pagos_proveedor')
      .update({
        estado,
        verificado_por: user?.id || null,
        fecha_verificacion: new Date().toISOString(),
      })
      .eq('id', id)

    if (error) {
      toast.error('Error actualizando pago')
      console.error(error)
    } else {
      toast.success(estado === 'verificado' ? 'Pago verificado y servicio activado' : 'Pago rechazado')

      // Notificar al proveedor (RPC gateado: deriva empresa + destinatarios + contenido del ref del pago; estado leído de la BD)
      try {
        await supabase.rpc('notificar_pago_resultado', { p_pago_id: id })
      } catch (e) {
        console.error('Error notificando pago al proveedor:', e)
      }

      setPagoActivo(null)
      fetchPagos()
    }
    setProcesando(false)
  }

  const estadoColor: Record<string, string> = {
    pendiente: 'bg-amber-100 text-amber-700',
    verificado: 'bg-emerald-100 text-emerald-700',
    rechazado: 'bg-red-100 text-red-700',
  }

  const filtrados = pagos.filter((p) =>
    p.empresa?.nombre_empresa?.toLowerCase().includes(filtro.toLowerCase()) ||
    p.tipo.toLowerCase().includes(filtro.toLowerCase())
  )

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
          <CreditCard className="h-6 w-6 text-emerald-500" />
          Pagos de Proveedores
        </h1>
        <p className="text-slate-500 mt-1">Verifica comprobantes de pago de planes y campañas</p>
      </div>

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Filter className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
          <Input
            placeholder="Buscar por empresa o tipo..."
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
          <option value="pendiente">Pendiente</option>
          <option value="verificado">Verificado</option>
          <option value="rechazado">Rechazado</option>
        </select>
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : filtrados.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-slate-500">
            <CreditCard className="h-12 w-12 mx-auto mb-3 text-slate-300" />
            <p>No hay pagos registrados</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {filtrados.map((p) => (
            <Card key={p.id}>
              <CardContent className="p-4 flex items-center justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <Badge className={estadoColor[p.estado] || estadoColor.pendiente}>{p.estado}</Badge>
                    <span className="text-sm font-medium capitalize">{p.tipo.replace('_', ' ')}</span>
                  </div>
                  <p className="text-sm text-slate-600">
                    {p.empresa?.nombre_empresa} • {p.empresa?.email_contacto}
                  </p>
                  <p className="text-xs text-slate-400 mt-1">
                    {p.moneda} {p.monto.toFixed(2)} • {p.metodo_pago || 'Sin método'} • {p.fecha_pago || 'Sin fecha'}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <Button size="sm" variant="outline" onClick={() => setPagoActivo(p)}>
                    <Eye className="h-3.5 w-3.5 mr-1" />
                    Ver
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={!!pagoActivo} onOpenChange={() => setPagoActivo(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Detalle del pago</DialogTitle>
          </DialogHeader>
          {pagoActivo && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div><span className="font-medium">Empresa:</span> {pagoActivo.empresa?.nombre_empresa}</div>
                <div><span className="font-medium">Tipo:</span> {pagoActivo.tipo}</div>
                <div><span className="font-medium">Monto:</span> {pagoActivo.moneda} {pagoActivo.monto.toFixed(2)}</div>
                <div><span className="font-medium">Método:</span> {pagoActivo.metodo_pago || '-'}</div>
                <div><span className="font-medium">Fecha pago:</span> {pagoActivo.fecha_pago || '-'}</div>
                <div><span className="font-medium">Estado:</span> {pagoActivo.estado}</div>
              </div>
              {pagoActivo.comprobante_url && (
                <div>
                  <p className="text-sm font-medium mb-1">Comprobante</p>
                  <button
                    type="button"
                    onClick={() => openSignedUrl('comprobantes', pagoActivo.comprobante_url)}
                    className="text-sm text-[#1E5C8E] hover:underline"
                  >
                    Ver comprobante
                  </button>
                </div>
              )}
              {pagoActivo.estado === 'pendiente' && (
                <div className="flex gap-3 pt-2">
                  <Button
                    variant="outline"
                    className="flex-1 text-red-600 hover:bg-red-50"
                    disabled={procesando}
                    onClick={() => verificar(pagoActivo.id, 'rechazado')}
                  >
                    <XCircle className="h-4 w-4 mr-1" />
                    Rechazar
                  </Button>
                  <Button
                    className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white"
                    disabled={procesando}
                    onClick={() => verificar(pagoActivo.id, 'verificado')}
                  >
                    <CheckCircle className="h-4 w-4 mr-1" />
                    Verificar
                  </Button>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
