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
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchPaises = async () => {
      try {
        setLoading(true)
        setError(null)
        const { data, error } = await supabase
          .from('configuracion_pais')
          .select('id, codigo, nombre, moneda')
          .eq('activo', true)
          .order('nombre')

        if (error) {
          console.error('[usePaisesRegistro] Error cargando países:', error)
          setError(error.message)
          setPaises([])
        } else {
          setPaises(data || [])
        }
      } catch (err: any) {
        console.error('[usePaisesRegistro] Error inesperado:', err)
        setError(err.message || 'Error desconocido')
        setPaises([])
      } finally {
        setLoading(false)
      }
    }
    fetchPaises()
  }, [])

  return { paises, loading, error }
}
