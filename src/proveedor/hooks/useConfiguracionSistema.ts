import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface ConfiguracionSistema {
  banco: string
  cuenta_bancaria: string
  tipo_cuenta: string
  titular_cuenta: string
  email_pagos: string
}

export function useConfiguracionSistema() {
  const [config, setConfig] = useState<ConfiguracionSistema | null>(null)
  const [loading, setLoading] = useState(false)

  const fetchConfig = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('configuracion_sistema')
      .select('clave, valor')
      .in('clave', ['banco', 'cuenta_bancaria', 'tipo_cuenta', 'titular_cuenta', 'email_pagos'])

    if (error) {
      console.error('Error cargando configuración:', error)
    } else {
      const map: Record<string, string> = {}
      ;(data || []).forEach((row: any) => {
        map[row.clave] = row.valor
      })
      setConfig({
        banco: map['banco'] || 'Banco Industrial',
        cuenta_bancaria: map['cuenta_bancaria'] || '-',
        tipo_cuenta: map['tipo_cuenta'] || '-',
        titular_cuenta: map['titular_cuenta'] || '-',
        email_pagos: map['email_pagos'] || '-',
      })
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchConfig()
  }, [fetchConfig])

  return { config, loading, fetchConfig }
}
