import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'

export interface ProveedorStats {
  productosActivos: number
  productosTotal: number
  visitasPropuestas: number
  visitasConfirmadas: number
  visitasCompletadas: number
  visitasTotal: number
  campanasEnviadas: number
  campanasAprobadas: number
  campanasTotal: number
  pagosPendientes: number
  pagosVerificados: number
  pagosTotal: number
  visitasHoy: number
  visitasSemana: number
}

export function useProveedorStats() {
  const { empresa } = useProveedorAuth()
  const [stats, setStats] = useState<ProveedorStats | null>(null)
  const [loading, setLoading] = useState(false)

  const fetchStats = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)

    try {
      const hoy = new Date().toISOString().split('T')[0]
      const inicioSemana = new Date()
      inicioSemana.setDate(inicioSemana.getDate() - inicioSemana.getDay())
      const inicioSemanaStr = inicioSemana.toISOString().split('T')[0]

      // Productos
      const { data: productosData, error: productosError } = await supabase
        .from('productos_empresa')
        .select('estado', { count: 'exact', head: false })
        .eq('empresa_id', empresa.id)

      if (productosError) throw productosError
      const productosTotal = productosData?.length || 0
      const productosActivos = productosData?.filter((p: any) => p.estado === 'activo').length || 0

      // Visitas
      const { data: visitasData, error: visitasError } = await supabase
        .from('visitas_agendadas')
        .select('estado, fecha_visita', { count: 'exact', head: false })
        .eq('empresa_id', empresa.id)

      if (visitasError) throw visitasError
      const visitasTotal = visitasData?.length || 0
      const visitasPropuestas = visitasData?.filter((v: any) => v.estado === 'propuesta').length || 0
      const visitasConfirmadas = visitasData?.filter((v: any) => v.estado === 'confirmada').length || 0
      const visitasCompletadas = visitasData?.filter((v: any) => v.estado === 'completada').length || 0
      const visitasHoy = visitasData?.filter((v: any) => v.fecha_visita === hoy).length || 0
      const visitasSemana = visitasData?.filter((v: any) => v.fecha_visita >= inicioSemanaStr && v.fecha_visita <= hoy).length || 0

      // Campañas
      const { data: campanasData, error: campanasError } = await supabase
        .from('solicitudes_campana')
        .select('estado', { count: 'exact', head: false })
        .eq('empresa_id', empresa.id)

      if (campanasError) throw campanasError
      const campanasTotal = campanasData?.length || 0
      const campanasEnviadas = campanasData?.filter((c: any) => c.estado === 'enviada').length || 0
      const campanasAprobadas = campanasData?.filter((c: any) => c.estado === 'aprobada' || c.estado === 'publicada').length || 0

      // Pagos
      const { data: pagosData, error: pagosError } = await supabase
        .from('pagos_proveedor')
        .select('estado', { count: 'exact', head: false })
        .eq('empresa_id', empresa.id)

      if (pagosError) throw pagosError
      const pagosTotal = pagosData?.length || 0
      const pagosPendientes = pagosData?.filter((p: any) => p.estado === 'pendiente').length || 0
      const pagosVerificados = pagosData?.filter((p: any) => p.estado === 'verificado').length || 0

      setStats({
        productosActivos,
        productosTotal,
        visitasPropuestas,
        visitasConfirmadas,
        visitasCompletadas,
        visitasTotal,
        campanasEnviadas,
        campanasAprobadas,
        campanasTotal,
        pagosPendientes,
        pagosVerificados,
        pagosTotal,
        visitasHoy,
        visitasSemana,
      })
    } catch (err: any) {
      toast.error('Error cargando estadísticas')
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [empresa?.id])

  useEffect(() => {
    fetchStats()
  }, [fetchStats])

  return { stats, loading, fetchStats }
}
