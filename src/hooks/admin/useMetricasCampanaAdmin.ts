import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface MetricasCampanaPais {
  pais_id: string
  pais_nombre: string
  pais_codigo: string
  campanas_activas: number
  total_campanas: number
  impresiones_totales: number
  clicks_totales: number
  usuarios_unicos: number
  ctr_porcentaje: number
}

export interface MetricasCampanaDetalle {
  campana_id: number
  titulo: string
  tipo: string
  activa: boolean
  fecha_fin: string
  impresiones: number
  clicks: number
  usuarios_unicos: number
  ctr: number
}

export function useMetricasCampanaAdmin() {
  const [metricasPais, setMetricasPais] = useState<MetricasCampanaPais[]>([])
  const [metricasDetalle, setMetricasDetalle] = useState<MetricasCampanaDetalle[]>([])
  const [loading, setLoading] = useState(false)

  const fetchMetricasPais = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('v_metricas_campana_pais')
      .select('*')
      .order('pais_nombre')

    if (error) {
      console.error('Error cargando métricas por país:', error)
    } else {
      setMetricasPais(data || [])
    }
    setLoading(false)
  }, [])

  const fetchMetricasPorPais = useCallback(async (paisId: string) => {
    setLoading(true)

    // 1. Obtener campañas del país
    const { data: campanas, error: campError } = await supabase
      .from('campanas_publicitarias')
      .select('id, titulo, tipo, activa, fecha_fin')
      .eq('pais_id', paisId)
      .order('created_at', { ascending: false })

    if (campError) {
      console.error('Error cargando campañas:', campError)
      setLoading(false)
      return
    }

    if (!campanas || campanas.length === 0) {
      setMetricasDetalle([])
      setLoading(false)
      return
    }

    // 2. Obtener métricas por campaña vía RPC país (SECURITY DEFINER; gate super_admin / admin_pais-de-este-país).
    const { data: metricas, error: metError } = await supabase.rpc('metricas_campana_pais', { p_pais_id: paisId })

    if (metError) {
      console.error('Error cargando métricas:', metError)
      setLoading(false)
      return
    }

    // 3. Agrupar métricas por campaña (la RPC ya devuelve agregado por campaña)
    const statsMap: Record<number, { impresiones: number; clicks: number; usuarios_unicos: number }> = {}
    ;(metricas || []).forEach((m: any) => {
      statsMap[m.campana_id] = {
        impresiones: Number(m.impresiones) || 0,
        clicks: Number(m.clicks) || 0,
        usuarios_unicos: Number(m.usuarios_unicos) || 0,
      }
    })

    // 4. Combinar
    const detalle: MetricasCampanaDetalle[] = campanas.map((c: any) => {
      const s = statsMap[c.id] || { impresiones: 0, clicks: 0, usuarios_unicos: 0 }
      const ctr = s.impresiones > 0 ? Math.round((s.clicks / s.impresiones) * 100 * 100) / 100 : 0
      return {
        campana_id: c.id,
        titulo: c.titulo,
        tipo: c.tipo,
        activa: c.activa,
        fecha_fin: c.fecha_fin,
        impresiones: s.impresiones,
        clicks: s.clicks,
        usuarios_unicos: s.usuarios_unicos,
        ctr,
      }
    })

    setMetricasDetalle(detalle)
    setLoading(false)
  }, [])

  return {
    metricasPais,
    metricasDetalle,
    loading,
    fetchMetricasPais,
    fetchMetricasPorPais,
  }
}
