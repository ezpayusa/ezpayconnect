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
  peso: number
  created_at: string
  updated_at: string
}

export interface PlanPublicidadConfig {
  id: number
  pais_id: string
  plan_publicidad_id: number
  precio_local: number
  moneda_local: string
  activo: boolean
}

export interface PlanPublicidadConPrecio extends PlanPublicidad {
  precio_local: number
  moneda_local: string
}

export function usePlanesPublicidad(paisId?: string) {
  const [planes, setPlanes] = useState<PlanPublicidadConPrecio[]>([])
  const [loading, setLoading] = useState(false)

  const fetchPlanes = useCallback(async () => {
    setLoading(true)

    // 1. Obtener planes base
    const { data: planesBase, error: baseError } = await supabase
      .from('planes_publicidad')
      .select('*')
      .eq('activo', true)
      .order('orden', { ascending: true })

    if (baseError) {
      toast.error('Error cargando planes de publicidad')
      console.error(baseError)
      setLoading(false)
      return
    }

    if (!planesBase || planesBase.length === 0) {
      setPlanes([])
      setLoading(false)
      return
    }

    // 2. Si hay país, obtener configuración de precios
    let configs: PlanPublicidadConfig[] = []
    if (paisId) {
      const { data: configData } = await supabase
        .from('planes_publicidad_config')
        .select('*')
        .eq('pais_id', paisId)
        .eq('activo', true)
      configs = (configData || []) as PlanPublicidadConfig[]
    }

    // 3. Combinar: usar precio local si existe, sino precio base
    const combinados: PlanPublicidadConPrecio[] = (planesBase || []).map((p: any) => {
      const config = configs.find((c) => c.plan_publicidad_id === p.id)
      return {
        ...p,
        precio_local: config?.precio_local ?? p.precio,
        moneda_local: config?.moneda_local ?? p.moneda,
      }
    })

    setPlanes(combinados)
    setLoading(false)
  }, [paisId])

  useEffect(() => {
    fetchPlanes()
  }, [fetchPlanes])

  return { planes, loading, fetchPlanes }
}
