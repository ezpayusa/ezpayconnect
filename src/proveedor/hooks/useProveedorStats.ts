import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'
import { hoyISO, fechaLocalISO } from '@/lib/fecha'

export interface ProveedorStats {
  productosActivos: number
  productosTotal: number
  visitasPropuestas: number
  visitasPendientes: number
  visitasConfirmadas: number
  visitasCanceladas: number
  // estados del CHECK de visitas_agendadas sin badge propio (aprobada, rechazada, completada, no_asistio)
  visitasOtras: number
  visitasTotal: number
  campanasEnviadas: number
  campanasActivas: number
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
      // fecha_visita es DATE: hoy y el domingo de la semana como strings de día LOCAL
      const hoy = hoyISO()
      const ahora = new Date()
      const inicioSemanaStr = fechaLocalISO(new Date(ahora.getFullYear(), ahora.getMonth(), ahora.getDate() - ahora.getDay()))

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
      const visitasPendientes = visitasData?.filter((v: any) => v.estado === 'pendiente').length || 0
      const visitasConfirmadas = visitasData?.filter((v: any) => v.estado === 'confirmada').length || 0
      const visitasCanceladas = visitasData?.filter((v: any) => v.estado === 'cancelada').length || 0
      // Total = suma de los badges: lo que no es propuesta/pendiente/confirmada/cancelada va a "Otras"
      const visitasOtras = visitasTotal - visitasPropuestas - visitasPendientes - visitasConfirmadas - visitasCanceladas
      const visitasHoy = visitasData?.filter((v: any) => v.fecha_visita === hoy).length || 0
      const visitasSemana = visitasData?.filter((v: any) => v.fecha_visita >= inicioSemanaStr && v.fecha_visita <= hoy).length || 0

      // Campañas: el proveedor no lee campanas_publicitarias por empresa_id (RLS: solo admin y viewer por país),
      // así que "activas" = solicitudes publicadas de la empresa vigentes hoy (día local).
      const { data: campanasData, error: campanasError } = await supabase
        .from('solicitudes_campana')
        .select('estado, fecha_inicio, fecha_fin', { count: 'exact', head: false })
        .eq('empresa_id', empresa.id)

      if (campanasError) throw campanasError
      const campanasTotal = campanasData?.length || 0
      const campanasEnviadas = campanasData?.filter((c: any) => c.estado === 'enviada').length || 0
      const campanasActivas = campanasData?.filter((c: any) =>
        c.estado === 'publicada' && c.fecha_inicio && c.fecha_fin && c.fecha_inicio <= hoy && hoy <= c.fecha_fin
      ).length || 0

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
        visitasPendientes,
        visitasConfirmadas,
        visitasCanceladas,
        visitasOtras,
        visitasTotal,
        campanasEnviadas,
        campanasActivas,
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
