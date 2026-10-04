import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { openSignedUrl } from '@/lib/signedUrl'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { CreditCard, CheckCircle, XCircle, Loader2, Filter, Eye } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { mensajeErrorCompraPlan } from '@/proveedor/lib/compraPlanVisitador'

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
  // Plan de visitador (mig 351): snapshot del catálogo al comprar y bolsa a la que sumó la aprobación.
  plan_visitas?: number | null
  plan_duracion_dias?: number | null
  pvc_id?: string | null
  empresa: { nombre_empresa: string; email_contacto: string } | null
}

// Un pendiente de plan de visitador sin snapshot nació antes de la compra por RPC: la RPC lo rechaza (CP013).
const esPlanVisitadorLegacy = (p: PagoConEmpresa) =>
  p.tipo === 'plan_visitador' && (p.plan_visitas == null || p.plan_duracion_dias == null)

// Errores de aprobar_solicitud_campana (mig 358). Nunca se muestra el texto crudo de Postgres.
const MENSAJES_APROBAR_CAMPANA: Record<string, string> = {
  CA001: 'Solo el superadministrador puede aprobar campañas',
  CA002: 'La solicitud no existe',
  CA003: 'La solicitud no está en estado enviada',
  CA004: 'La campaña no tiene pago registrado',
  CA005: 'La campaña tiene más de un pago; revisá antes de aprobar',
  CA006: 'El pago de esta campaña fue rechazado',
  CA007: 'La campaña no tiene plan asignado',
  CA008: 'La empresa no opera en el país de la campaña',
}
const mensajeErrorAprobarCampana = (code: string | undefined) =>
  (code && MENSAJES_APROBAR_CAMPANA[code]) || 'No se pudo aprobar la campaña. Intentá de nuevo.'

// Avisos al proveedor después de aprobar: primero el pago, después la campaña. Ninguno de los dos es idempotente (cada
// llamada inserta otra notificación), por eso se llaman UNA vez, solo tras el éxito de la aprobación. Un fallo no
// deshace la aprobación, pero queda en la consola (mensaje fijo + code, sin datos personales).
const notificarAprobacionCampana = async (pagoId: string | null | undefined, solicitudId: string) => {
  if (pagoId) {
    try {
      const { error } = await supabase.rpc('notificar_pago_resultado', { p_pago_id: pagoId })
      if (error) console.error('notificar_pago_resultado falló:', error.code)
    } catch (e) {
      console.error('notificar_pago_resultado falló:', (e as { code?: string })?.code ?? 'sin code')
    }
  }
  try {
    const { error } = await supabase.rpc('notificar_campana_resultado', { p_solicitud_id: solicitudId })
    if (error) console.error('notificar_campana_resultado falló:', error.code)
  } catch (e) {
    console.error('notificar_campana_resultado falló:', (e as { code?: string })?.code ?? 'sin code')
  }
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

  // Plan de visitador (mig 351): UNA RPC atómica e idempotente crea o suma la bolsa, activa la capacidad,
  // marca el pago y notifica al proveedor. No hay camino viejo (INSERT directo de la bolsa).
  const aprobarPlanVisitador = async (pago: PagoConEmpresa) => {
    setProcesando(true)
    const { data, error } = await supabase.rpc('aprobar_pago_plan_visitador', { p_pago_id: pago.id })
    setProcesando(false)
    if (error) {
      toast.error(mensajeErrorCompraPlan(error, 'aprobar'))
      console.error(error)
      return
    }
    const r = (data || {}) as { accion?: string; cantidad_visitas_incluidas?: number; fecha_fin?: string; idempotente?: boolean }
    toast.success(
      r.idempotente
        ? 'Este pago ya estaba aprobado.'
        : `Plan ${r.accion === 'sumada' ? 'sumado a la bolsa vigente' : 'creado'}: ${r.cantidad_visitas_incluidas} visitas, vigente hasta ${r.fecha_fin}`
    )
    setPagoActivo(null)
    fetchPagos()
  }

  // Campaña (mig 358): aprobar_solicitud_campana es el ÚNICO camino de publicación. Verifica el pago pendiente, publica y
  // marca la solicitud en una sola transacción, y es idempotente. Nada de INSERT directo en campanas_publicitarias.
  const aprobandoCampanaRef = useRef(false)
  const aprobarCampana = async (pago: { id: string; referencia_id: string | null }) => {
    // guard síncrono contra doble click (procesando tarda un render en deshabilitar el botón)
    if (aprobandoCampanaRef.current) return
    if (!pago.referencia_id) {
      toast.error('El pago no tiene una campaña asociada')
      return
    }
    aprobandoCampanaRef.current = true
    setProcesando(true)
    try {
      const { error } = await supabase.rpc('aprobar_solicitud_campana', { p_solicitud_id: pago.referencia_id })
      if (error) {
        console.error('aprobar_solicitud_campana falló:', error.code)
        toast.error(mensajeErrorAprobarCampana(error.code))
        return
      }
      toast.success('Pago verificado y campaña publicada')
      await notificarAprobacionCampana(pago.id, pago.referencia_id)
      setPagoActivo(null)
      fetchPagos()
    } finally {
      aprobandoCampanaRef.current = false
      setProcesando(false)
    }
  }

  const verificar = async (id: string, estado: 'verificado' | 'rechazado') => {
    setProcesando(true)
    const { data: { user } } = await supabase.auth.getUser()

    if (estado === 'verificado') {
      // Obtener datos del pago para procesar según tipo
      const { data: pagoData } = await supabase.from('pagos_proveedor').select('*').eq('id', id).single()

      if (pagoData?.tipo === 'plan_visitador') {
        // Se aprueba solo por aprobarPlanVisitador (RPC); un legacy se resuelve a mano.
        toast.error('Los planes de visitador se aprueban con su propio botón.')
        setProcesando(false)
        return
      }

      if (pagoData?.tipo === 'campana') {
        // Mig 358: verificar un pago de campaña ES aprobar la campaña, y eso se hace solo por aprobar_solicitud_campana
        // (verifica el pago, publica y marca la solicitud en una transacción). El UPDATE genérico de abajo no corre.
        setProcesando(false)
        await aprobarCampana({ id: pagoData.id, referencia_id: pagoData.referencia_id })
        return
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
              {pagoActivo.tipo === 'plan_visitador' && !esPlanVisitadorLegacy(pagoActivo) && (
                <div className="text-sm text-slate-600">
                  <span className="font-medium">Plan:</span> {pagoActivo.plan_visitas} visitas · {pagoActivo.plan_duracion_dias} días
                </div>
              )}
              {pagoActivo.estado === 'pendiente' && esPlanVisitadorLegacy(pagoActivo) && (
                <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-sm text-amber-800">
                  Pago legacy: resolver manualmente.
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
                  {!esPlanVisitadorLegacy(pagoActivo) && (
                    <Button
                      className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white"
                      disabled={procesando}
                      onClick={() =>
                        pagoActivo.tipo === 'plan_visitador' ? aprobarPlanVisitador(pagoActivo) : verificar(pagoActivo.id, 'verificado')
                      }
                    >
                      <CheckCircle className="h-4 w-4 mr-1" />
                      Verificar
                    </Button>
                  )}
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
