import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'

export interface PlanPublicidad {
  id: number
  nombre: string
  descripcion: string | null
  dias: number
  precio: number
  moneda: string
  activo: boolean
  orden: number
  created_at: string
  updated_at: string
}

export function usePlanesPublicidad() {
  const [planes, setPlanes] = useState<PlanPublicidad[]>([])
  const [loading, setLoading] = useState(false)

  const fetchPlanes = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('planes_publicidad')
      .select('*')
      .eq('activo', true)
      .order('orden', { ascending: true })

    if (error) {
      toast.error('Error cargando planes de publicidad')
      console.error(error)
    } else {
      setPlanes(data || [])
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchPlanes()
  }, [fetchPlanes])

  return { planes, loading, fetchPlanes }
}
