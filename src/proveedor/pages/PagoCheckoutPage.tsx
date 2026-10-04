import { useState, useEffect, useRef } from 'react'
import { useSearchParams, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { usePagosProveedor } from '@/proveedor/hooks/usePagosProveedor'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useCuentaBancariaCheckout } from '@/proveedor/hooks/useCuentaBancariaCheckout'
import { useConfigPlanVisitador } from '@/proveedor/hooks/useConfigPlanVisitador'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { ArrowLeft, Upload, CreditCard, MapPin, User, Hash, Loader2, Mail, FileText, AlertCircle } from 'lucide-react'

// Errores de cotizar_campana / solicitar_pago_campana (mig 359). Nunca se muestra el texto crudo de Postgres.
const MENSAJES_CAMPANA: Record<string, string> = {
  CA009: 'No tenés permiso para pagar esta campaña',
  CA010: 'El plan de esta campaña no tiene precio para tu país',
  CA011: 'Esta campaña ya no está en borrador',
  CA012: 'Esta campaña ya tiene un pago registrado',
  CA013: 'No se pudo validar el comprobante, volvé a subirlo',
  CA014: 'La duración de la campaña supera los días del plan',
  CA015: 'La fecha de fin es anterior a la de inicio',
}
const mensajeErrorCampana = (code: string | undefined, generico: string) => (code && MENSAJES_CAMPANA[code]) || generico

export default function PagoCheckoutPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const { crearPago, solicitarCompraPlanVisitador, solicitarPagoCampana, saving } = usePagosProveedor()
  const { empresa } = useProveedorAuth()
  const { cuenta, loading: loadingCuenta } = useCuentaBancariaCheckout(empresa?.pais_id)

  const tipo = searchParams.get('tipo') || ''
  const referenciaId = searchParams.get('referencia_id') || ''
  // Plan de visitador (mig 351): precio, moneda, visitas y duración salen de la configuración, NUNCA de la URL.
  const esPlanVisitador = tipo === 'plan_visitador'
  const { config: configPlan, loading: loadingPlan } = useConfigPlanVisitador(esPlanVisitador ? referenciaId || null : null)
  const planNoDisponible = esPlanVisitador && !loadingPlan && !configPlan?.comprable
  // Campaña (mig 359): monto y moneda salen de cotizar_campana (servidor), NUNCA de ?monto= ni de la cuenta bancaria.
  const esCampana = tipo === 'campana'
  const [cotizacion, setCotizacion] = useState<{ monto: number; moneda: string } | null>(null)
  const [cotizando, setCotizando] = useState(esCampana)
  const [errorCotizacion, setErrorCotizacion] = useState<string | null>(null)
  const enviandoRef = useRef(false)
  // ?monto= solo vale para los tipos que todavía no cotizan en el servidor (plan_laboratorio, plan_farmacia, ...).
  const monto = esPlanVisitador
    ? configPlan?.precio ?? 0
    : esCampana
      ? cotizacion?.monto ?? 0
      : parseFloat(searchParams.get('monto') || '0')
  const descripcion = esPlanVisitador ? configPlan?.nombre ?? '' : searchParams.get('descripcion') || ''
  const moneda = esPlanVisitador ? configPlan?.moneda ?? '' : esCampana ? cotizacion?.moneda ?? '' : cuenta?.moneda || 'GTQ'

  useEffect(() => {
    if (!esCampana) return
    if (!referenciaId) {
      setErrorCotizacion('No se encontró la campaña a pagar')
      setCotizando(false)
      return
    }
    let cancelado = false
    setCotizando(true)
    setErrorCotizacion(null)
    supabase.rpc('cotizar_campana', { p_solicitud_id: referenciaId }).then(({ data, error }) => {
      if (cancelado) return
      const fila = Array.isArray(data) ? data[0] : data
      if (error || !fila || !(Number(fila.monto) > 0) || !fila.moneda) {
        if (error) console.error(error)
        setCotizacion(null)
        setErrorCotizacion(mensajeErrorCampana(error?.code, 'No se pudo calcular el precio de la campaña'))
      } else {
        setCotizacion({ monto: Number(fila.monto), moneda: fila.moneda })
      }
      setCotizando(false)
    })
    return () => {
      cancelado = true
    }
  }, [esCampana, referenciaId])

  const [comprobanteFile, setComprobanteFile] = useState<File | null>(null)
  const [comprobantePreview, setComprobantePreview] = useState<string | null>(null)

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (file.size > 5 * 1024 * 1024) {
      toast.error('El archivo no puede superar 5MB')
      return
    }
    setComprobanteFile(file)
    setComprobantePreview(URL.createObjectURL(file))
  }

  const handleSubmit = async () => {
    if (!comprobanteFile) {
      toast.error('Debes subir el comprobante de pago')
      return
    }

    if (esPlanVisitador) {
      if (!configPlan?.comprable) return
      const pagoId = await solicitarCompraPlanVisitador(configPlan.id, comprobanteFile)
      if (pagoId) navigate('/proveedor/visitador/planes')
      return
    }

    if (esCampana) {
      // guard síncrono contra doble envío (además del botón deshabilitado): saving tarda un render en llegar
      if (saving || enviandoRef.current) return
      if (!referenciaId || !cotizacion) return
      enviandoRef.current = true
      try {
        // solicitar_pago_campana crea el pago con el precio del servidor Y pasa la solicitud a 'enviada'
        const { pagoId, error } = await solicitarPagoCampana(referenciaId, comprobanteFile)
        if (error || !pagoId) {
          toast.error(
            error?.code === 'upload'
              ? 'Error subiendo comprobante'
              : mensajeErrorCampana(error?.code, 'No se pudo registrar el pago. Intentá de nuevo.')
          )
          return
        }
        toast.success('Comprobante enviado. En espera de verificación.')
        // Avisar a los admins de EzPay (RPC gateado: gate dueño + estado='enviada', que ya dejó la RPC; deriva admins + monto del ref)
        await supabase.rpc('notificar_campana_enviada', { p_solicitud_id: referenciaId })
        navigate('/proveedor/publicidad/campanas')
      } finally {
        enviandoRef.current = false
      }
      return
    }

    const pagoId = await crearPago(tipo, monto, moneda, referenciaId || null, comprobanteFile)
    if (pagoId) {
      if (tipo === 'plan_visitador') {
        navigate('/proveedor/visitador/planes')
      } else {
        navigate('/proveedor/dashboard')
      }
    }
  }

  const volver = () => {
    if (tipo === 'plan_visitador') navigate('/proveedor/visitador/planes')
    else if (tipo === 'campana') navigate('/proveedor/publicidad/campanas')
    else navigate('/proveedor/dashboard')
  }

  const formatMonto = (val: number) => {
    try {
      return new Intl.NumberFormat('es-GT', { style: 'currency', currency: moneda }).format(val)
    } catch {
      return `${moneda} ${val.toLocaleString()}`
    }
  }

  const sinCuenta = !loadingCuenta && !cuenta

  return (
    <div className="space-y-6 max-w-2xl mx-auto">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={volver}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Confirmar pago</h1>
          <p className="text-sm text-muted-foreground">{descripcion}</p>
        </div>
      </div>

      {/* Resumen */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <CreditCard className="h-5 w-5 text-[#1E5C8E]" />
            Resumen de compra
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Concepto</span>
            <span className="font-medium">{descripcion}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Tipo</span>
            <span className="font-medium capitalize">{tipo.replace('_', ' ')}</span>
          </div>
          {esPlanVisitador && configPlan?.comprable && (
            <>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Visitas incluidas</span>
                <span className="font-medium">{configPlan.visitasIncluidas}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Vigencia</span>
                <span className="font-medium">{configPlan.duracionDias} días</span>
              </div>
            </>
          )}
          {(esPlanVisitador && loadingPlan) || (esCampana && cotizando) ? (
            <Skeleton className="h-8 w-full" />
          ) : planNoDisponible ? (
            <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-sm text-amber-800 flex items-start gap-2">
              <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" />
              <p>Este plan no está disponible para la compra. Volvé a la lista de planes y elegí otro.</p>
            </div>
          ) : esCampana && !cotizacion ? (
            <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-sm text-amber-800 flex items-start gap-2">
              <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" />
              <p>{errorCotizacion || 'No se pudo calcular el precio de la campaña'}</p>
            </div>
          ) : (
            <div className="border-t pt-3 flex justify-between items-center">
              <span className="font-medium">Total a pagar</span>
              <span className="text-2xl font-bold text-[#1E5C8E]">{formatMonto(monto)}</span>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Instrucciones de pago */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            <MapPin className="h-5 w-5 text-[#1E5C8E]" />
            Datos bancarios
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {loadingCuenta ? (
            <div className="space-y-3">
              <Skeleton className="h-4 w-3/4" />
              <Skeleton className="h-4 w-1/2" />
              <Skeleton className="h-4 w-2/3" />
            </div>
          ) : sinCuenta ? (
            <div className="bg-amber-50 border border-amber-200 rounded-lg p-4 text-sm text-amber-800 flex items-start gap-2">
              <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" />
              <div>
                <p className="font-medium">Pago por transferencia no disponible aún en tu país.</p>
                <p>Contacta al equipo de EzPayConnect para coordinar tu pago.</p>
              </div>
            </div>
          ) : (
            <>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                <div className="flex items-start gap-2">
                  <MapPin className="h-4 w-4 text-muted-foreground mt-0.5" />
                  <div>
                    <p className="text-muted-foreground">Banco</p>
                    <p className="font-medium">{cuenta!.banco}</p>
                  </div>
                </div>
                <div className="flex items-start gap-2">
                  <Hash className="h-4 w-4 text-muted-foreground mt-0.5" />
                  <div>
                    <p className="text-muted-foreground">Número de cuenta</p>
                    <p className="font-medium">{cuenta!.numero_cuenta}</p>
                  </div>
                </div>
                <div className="flex items-start gap-2">
                  <CreditCard className="h-4 w-4 text-muted-foreground mt-0.5" />
                  <div>
                    <p className="text-muted-foreground">Tipo de cuenta</p>
                    <p className="font-medium">{cuenta!.tipo_cuenta || '-'}</p>
                  </div>
                </div>
                <div className="flex items-start gap-2">
                  <User className="h-4 w-4 text-muted-foreground mt-0.5" />
                  <div>
                    <p className="text-muted-foreground">A nombre de</p>
                    <p className="font-medium">{cuenta!.titular}</p>
                  </div>
                </div>
                {cuenta!.nit && (
                  <div className="flex items-start gap-2">
                    <FileText className="h-4 w-4 text-muted-foreground mt-0.5" />
                    <div>
                      <p className="text-muted-foreground">NIT</p>
                      <p className="font-medium">{cuenta!.nit}</p>
                    </div>
                  </div>
                )}
                {cuenta!.moneda && (
                  <div className="flex items-start gap-2">
                    <CreditCard className="h-4 w-4 text-muted-foreground mt-0.5" />
                    <div>
                      <p className="text-muted-foreground">Moneda</p>
                      <p className="font-medium">{cuenta!.moneda}</p>
                    </div>
                  </div>
                )}
              </div>
              {cuenta!.email_pagos && (
                <div className="flex items-start gap-2 text-sm">
                  <Mail className="h-4 w-4 text-muted-foreground mt-0.5" />
                  <div>
                    <p className="text-muted-foreground">Email para comprobantes</p>
                    <p className="font-medium">{cuenta!.email_pagos}</p>
                  </div>
                </div>
              )}
              <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-sm text-amber-800">
                {cuenta!.instrucciones
                  ? cuenta!.instrucciones
                  : 'Una vez realizada la transferencia, sube el comprobante abajo. El admin lo verificará en un plazo de 24-48 horas hábiles.'}
              </div>
            </>
          )}
        </CardContent>
      </Card>

      {/* Subir comprobante */}
      {!sinCuenta && (
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <Upload className="h-5 w-5 text-[#1E5C8E]" />
              Subir comprobante
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center gap-4">
              <label className="flex items-center gap-2 px-4 py-2 border border-slate-200 rounded-lg cursor-pointer hover:bg-slate-50 transition-colors">
                <Upload className="h-4 w-4 text-slate-500" />
                <span className="text-sm text-slate-600">
                  {comprobanteFile ? comprobanteFile.name : 'Seleccionar archivo'}
                </span>
                <input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" className="hidden" onChange={handleFileChange} />
              </label>
            </div>
            {comprobantePreview && comprobanteFile?.type.startsWith('image/') && (
              <img src={comprobantePreview} alt="Preview" className="h-32 object-contain rounded-lg border" />
            )}
            <p className="text-xs text-slate-400">Máx 5MB. Formatos: JPG, PNG, WebP, PDF</p>

            <div className="flex gap-3 pt-2">
              <Button variant="outline" className="flex-1" onClick={volver}>
                Cancelar
              </Button>
              <Button
                className="flex-1 bg-[#1E5C8E] hover:bg-[#164a70]"
                disabled={
                  saving ||
                  !comprobanteFile ||
                  loadingCuenta ||
                  (esPlanVisitador && (loadingPlan || !configPlan?.comprable)) ||
                  (esCampana && (cotizando || !cotizacion))
                }
                onClick={handleSubmit}
              >
                {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Upload className="h-4 w-4 mr-2" />}
                Enviar comprobante
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
