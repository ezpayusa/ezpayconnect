import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

export interface PaisRegistro {
  id: string
  codigo: string
  nombre: string
  moneda: string
}

export function usePaisesRegistro() {
  const [paises, setPaises] = useState<PaisRegistro[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const fetchPaises = async () => {
      const { data, error } = await supabase
        .from('configuracion_pais')
        .select('id, codigo, nombre, moneda')
        .eq('activo', true)
        .order('nombre')

      if (!error) {
        setPaises(data || [])
      }
      setLoading(false)
    }
    fetchPaises()
  }, [])

  return { paises, loading }
}
