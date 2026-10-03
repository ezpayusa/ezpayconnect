import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'

/** Fila de tablero_repartidores (mig 353): carga por repartidor activo, sin datos de pacientes. */
export interface RepartidorTablero {
  repartidor_id: string
  nombre: string
  sucursal_id: number | null
  sucursal_nombre: string | null
  asignadas: number
  en_camino: number
  entregadas_hoy: number // hoy en UTC (el CURRENT_DATE del servidor)
  fallidas_hoy: number
  estado_calc: 'libre' | 'en_ruta'
}

/** Fila de listar_repartidores_asignables: los que asignar_entrega aceptaría (misma sucursal), menos cargado primero. */
export interface RepartidorAsignable {
  repartidor_id: string
  nombre: string
  asignadas: number
  en_camino: number
  estado_calc: 'libre' | 'en_ruta'
}

/** Error de RPC tal cual (code + details) para mapearlo con mensajeErrorEntrega. */
export type ErrorGestion = { code?: string; message?: string; details?: string } | null

const REFRESCO_TABLERO_MS = 30_000

/** Tablero del gerente con refresco periódico (cada 30 s mientras el componente está montado). */
export function useTableroRepartidores(farmaciaId: number | null, activo = true) {
  const [repartidores, setRepartidores] = useState<RepartidorTablero[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ErrorGestion>(null)
  const [actualizado, setActualizado] = useState<Date | null>(null)

  const cargar = useCallback(async () => {
    setLoading(true)
    const { data, error: e } = await supabase.rpc('tablero_repartidores', { p_farmacia_id: farmaciaId })
    if (e) setError(e)
    else {
      setError(null)
      setRepartidores((data ?? []) as RepartidorTablero[])
      setActualizado(new Date())
    }
    setLoading(false)
  }, [farmaciaId])

  useEffect(() => {
    if (!activo) return
    void cargar()
    const t = window.setInterval(() => { void cargar() }, REFRESCO_TABLERO_MS)
    return () => window.clearInterval(t)
  }, [cargar, activo])

  return { repartidores, loading, error, actualizado, recargar: cargar }
}

/** Asignar en tanda y reasignar. El servidor valida todo (gate, estado, sucursal); acá solo se invoca. */
export function useAsignacionEntregas() {
  const listarAsignables = useCallback(async (entregaId: number) => {
    const { data, error } = await supabase.rpc('listar_repartidores_asignables', { p_entrega_id: entregaId })
    return { data: (data ?? []) as RepartidorAsignable[], error: error as ErrorGestion }
  }, [])

  const asignarLote = useCallback(async (entregaIds: number[], deliveryId: string) => {
    const { error } = await supabase.rpc('asignar_entregas_lote', { p_entrega_ids: entregaIds, p_delivery_id: deliveryId })
    return { error: error as ErrorGestion }
  }, [])

  const reasignar = useCallback(async (entregaId: number, deliveryId: string) => {
    const { error } = await supabase.rpc('reasignar_entrega', { p_entrega_id: entregaId, p_delivery_id: deliveryId })
    return { error: error as ErrorGestion }
  }, [])

  return { listarAsignables, asignarLote, reasignar }
}
