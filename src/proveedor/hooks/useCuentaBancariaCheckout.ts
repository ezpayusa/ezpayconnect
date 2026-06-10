import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

export interface CuentaCheckout {
  banco: string
  numero_cuenta: string
  tipo_cuenta: string | null
  titular: string
  nit: string | null
  moneda: string | null
  instrucciones: string | null
  email_pagos: string | null
}

// Devuelve la cuenta bancaria configurada para el país del cliente.
// Si el país no tiene cuenta -> null (la transferencia no está disponible ahí).
export function useCuentaBancariaCheckout(paisId?: string | null) {
  const [cuenta, setCuenta] = useState<CuentaCheckout | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancel = false
    const load = async () => {
      setLoading(true)
      try {
        if (!paisId) {
          if (!cancel) setCuenta(null)
          return
        }
        const { data } = await supabase
          .from('cuentas_bancarias_pais')
          .select('banco, numero_cuenta, tipo_cuenta, titular, nit, moneda, instrucciones, email_pagos')
          .eq('pais_id', paisId)
          .eq('activo', true)
          .order('created_at')
          .limit(1)
          .maybeSingle()
        if (!cancel) setCuenta((data as CuentaCheckout) || null)
      } catch (e) {
        console.error('Error cargando cuenta bancaria del país:', e)
        if (!cancel) setCuenta(null)
      } finally {
        if (!cancel) setLoading(false)
      }
    }
    load()
    return () => {
      cancel = true
    }
  }, [paisId])

  return { cuenta, loading }
}
