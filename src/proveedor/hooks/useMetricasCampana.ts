import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'

export interface MetricaCampana {
  campana_id: number
  titulo: string
  imagen_url: string | null
  fecha_inicio: string
  fecha_fin: string
  impresiones: number
  clicks: number
  usuarios_unicos: number
  ctr: number
}

export function useMetricasCampana() {
  const { empresa } = useProveedorAuth()
  const [metricas, setMetricas] = useState<MetricaCampana[]>([])
  const [loading, setLoading] = useState(false)

  const fetchMetricas = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)

    try {
      // RPC SECURITY DEFINER: agrega campana_metricas (RLS super_admin-only) scoped a mi_empresa_proveedor()
      // vía el link real campanas_publicitarias.empresa_id. Reemplaza el match-por-titulo + la vista rota.
      const { data, error } = await supabase.rpc('metricas_campana_proveedor')
      if (error) throw error

      const resultado: MetricaCampana[] = (data || []).map((r: any) => {
        const impresiones = Number(r.impresiones) || 0
        const clicks = Number(r.clicks) || 0
        return {
          campana_id: r.campana_id,
          titulo: r.titulo,
          imagen_url: r.imagen_url,
          fecha_inicio: r.fecha_inicio,
          fecha_fin: r.fecha_fin,
          impresiones,
          clicks,
          usuarios_unicos: Number(r.usuarios_unicos) || 0,
          ctr: impresiones > 0 ? (clicks / impresiones) * 100 : 0,
        }
      })

      setMetricas(resultado)
    } catch (err: any) {
      toast.error('Error cargando métricas')
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [empresa?.id])

  useEffect(() => {
    fetchMetricas()
  }, [fetchMetricas])

  return { metricas, loading, fetchMetricas }
}
