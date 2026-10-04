import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'
import { mensajeErrorCompraPlan } from '@/proveedor/lib/compraPlanVisitador'

export interface PagoProveedor {
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
}

export function usePagosProveedor() {
  const { empresa } = useProveedorAuth()
  const [pagos, setPagos] = useState<PagoProveedor[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchPagos = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('pagos_proveedor')
      .select('*')
      .eq('empresa_id', empresa.id)
      .order('created_at', { ascending: false })

    if (error) {
      toast.error('Error cargando pagos')
      console.error(error)
    } else {
      setPagos(data || [])
    }
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => {
    fetchPagos()
  }, [fetchPagos])

  // INSERT directo del pago: SOLO para los tipos que no son campaña (plan_laboratorio, plan_farmacia, ...). La campaña va
  // por solicitarPagoCampana (mig 359) y el plan de visitador por solicitarCompraPlanVisitador (mig 351).
  const crearPago = async (
    tipo: string,
    monto: number,
    moneda: string,
    referenciaId: string | null,
    comprobanteFile: File
  ): Promise<string | null> => {
    if (!empresa?.id) {
      toast.error('No hay empresa vinculada')
      return null
    }

    setSaving(true)

    // 1. Subir comprobante
    const fileExt = comprobanteFile.name.split('.').pop()
    const filePath = `${empresa.id}/${Date.now()}.${fileExt}`
    const { error: uploadError } = await supabase.storage
      .from('comprobantes')
      .upload(filePath, comprobanteFile, { upsert: true })

    if (uploadError) {
      toast.error('Error subiendo comprobante')
      console.error(uploadError)
      setSaving(false)
      return null
    }

    const { data: publicUrlData } = supabase.storage.from('comprobantes').getPublicUrl(filePath)
    const comprobante_url = publicUrlData.publicUrl

    // 2. Crear registro de pago
    const { data, error } = await supabase
      .from('pagos_proveedor')
      .insert({
        empresa_id: empresa.id,
        tipo,
        referencia_id: referenciaId,
        monto,
        moneda,
        metodo_pago: 'transferencia',
        comprobante_url,
        estado: 'pendiente',
        fecha_pago: new Date().toISOString().split('T')[0],
      })
      .select()
      .single()

    setSaving(false)

    if (error) {
      toast.error('Error registrando pago')
      console.error(error)
      return null
    }

    toast.success('Comprobante enviado. EzPayConnect lo va a revisar y le avisamos cuando esté acreditado.')
    fetchPagos()
    return data.id
  }

  // Compra de plan de visitador (mig 351): el monto, la moneda, las visitas y la duración los pone la RPC desde el
  // catálogo del país. El cliente solo sube el comprobante y manda la configuración elegida y el PATH del objeto.
  const solicitarCompraPlanVisitador = async (configuracionId: string, comprobanteFile: File): Promise<string | null> => {
    if (!empresa?.id) {
      toast.error('No hay empresa vinculada')
      return null
    }
    setSaving(true)
    const fileExt = comprobanteFile.name.split('.').pop()
    const filePath = `${empresa.id}/${Date.now()}.${fileExt}`
    const { error: uploadError } = await supabase.storage.from('comprobantes').upload(filePath, comprobanteFile)
    if (uploadError) {
      toast.error('Error subiendo comprobante')
      console.error(uploadError)
      setSaving(false)
      return null
    }
    const { data, error } = await supabase.rpc('solicitar_compra_plan_visitador', {
      p_configuracion_id: configuracionId,
      p_comprobante_path: filePath,
    })
    setSaving(false)
    if (error) {
      toast.error(mensajeErrorCompraPlan(error, 'solicitar'))
      console.error(error)
      return null
    }
    toast.success('Comprobante enviado. EzPayConnect lo va a revisar y le avisamos cuando esté acreditado.')
    fetchPagos()
    return data as string
  }

  // Pago de campaña (mig 359): el monto y la moneda los pone solicitar_pago_campana desde el plan del país; la RPC
  // también pasa la solicitud a 'enviada'. El cliente solo sube el comprobante y manda el PATH del objeto. No toastea los
  // errores de la RPC: los devuelve con su code (CA0xx) para que la página los traduzca.
  const solicitarPagoCampana = async (
    solicitudId: string,
    comprobanteFile: File
  ): Promise<{ pagoId: string | null; error: { code: string; message: string } | null }> => {
    if (!empresa?.id) return { pagoId: null, error: { code: 'sin_empresa', message: 'No hay empresa vinculada' } }
    setSaving(true)
    const fileExt = comprobanteFile.name.split('.').pop()
    const filePath = `${empresa.id}/${Date.now()}.${fileExt}`
    const { error: uploadError } = await supabase.storage.from('comprobantes').upload(filePath, comprobanteFile)
    if (uploadError) {
      console.error(uploadError)
      setSaving(false)
      return { pagoId: null, error: { code: 'upload', message: uploadError.message } }
    }
    const { data, error } = await supabase.rpc('solicitar_pago_campana', {
      p_solicitud_id: solicitudId,
      p_comprobante_path: filePath,
    })
    setSaving(false)
    if (error) {
      // TODO lote 2: si la RPC rechaza, el comprobante queda huérfano en Storage (no hay policy DELETE en comprobantes).
      console.error(error)
      return { pagoId: null, error: { code: error.code ?? '', message: error.message } }
    }
    fetchPagos()
    return { pagoId: data as string, error: null }
  }

  return {
    pagos,
    loading,
    saving,
    fetchPagos,
    crearPago,
    solicitarCompraPlanVisitador,
    solicitarPagoCampana,
  }
}
