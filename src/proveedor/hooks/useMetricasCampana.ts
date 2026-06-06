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
      // 1. Traer campañas publicadas de esta empresa
      const { data: solicitudes, error: solError } = await supabase
        .from('solicitudes_campana')
        .select('id, titulo, imagen_url, fecha_inicio, fecha_fin')
        .eq('empresa_id', empresa.id)
        .eq('estado', 'publicada')
        .order('fecha_inicio', { ascending: false })

      if (solError) throw solError
      if (!solicitudes || solicitudes.length === 0) {
        setMetricas([])
        setLoading(false)
        return
      }

      // 2. Buscar campanas_publicitarias que correspondan a estas solicitudes
      // Usamos título+descripción como clave de matching (no hay FK directa)
      const titulos = solicitudes.map((s: any) => s.titulo)
      const { data: campanasPublicadas, error: campError } = await supabase
        .from('campanas_publicitarias')
        .select('id, titulo')
        .in('titulo', titulos)
        .eq('activa', true)

      if (campError) throw campError

      const campanaMap: Record<string, number> = {}
      ;(campanasPublicadas || []).forEach((c: any) => {
        campanaMap[c.titulo] = c.id
      })

      // 3. Traer métricas de la vista
      const campanaIds = Object.values(campanaMap)
      if (campanaIds.length === 0) {
        setMetricas([])
        setLoading(false)
        return
      }

      const { data: resumen, error: metError } = await supabase
        .from('v_metricas_campana_resumen')
        .select('*')
        .in('campana_id', campanaIds)

      if (metError) throw metError

      const resumenMap: Record<number, any> = {}
      ;(resumen || []).forEach((r: any) => {
        resumenMap[r.campana_id] = r
      })

      // 4. Combinar todo
      const resultado: MetricaCampana[] = solicitudes.map((s: any) => {
        const campanaId = campanaMap[s.titulo]
        const r = resumenMap[campanaId] || {}
        const impresiones = r.impresiones || 0
        const clicks = r.clicks || 0
        return {
          campana_id: campanaId || 0,
          titulo: s.titulo,
          imagen_url: s.imagen_url,
          fecha_inicio: s.fecha_inicio,
          fecha_fin: s.fecha_fin,
          impresiones,
          clicks,
          usuarios_unicos: r.usuarios_unicos || 0,
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
