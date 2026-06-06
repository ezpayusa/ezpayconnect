import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'

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

    toast.success('Comprobante enviado. En espera de verificación.')
    fetchPagos()
    return data.id
  }

  return {
    pagos,
    loading,
    saving,
    fetchPagos,
    crearPago,
  }
}
