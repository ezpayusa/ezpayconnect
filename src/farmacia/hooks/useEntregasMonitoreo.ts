import { useCallback, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { openSignedUrl } from '@/lib/signedUrl'
import type { EstadoEntrega } from '@/repartidor/types'

const BUCKET = 'entregas-evidencia'

export interface EvidenciaMonitoreo {
  tipo: 'foto' | 'firma'
  path: string
  subido_at: string | null
}

/** Una entrega como la devuelve listar_entregas_monitoreo (gate entregas_ver, confinado por entrega_visible). */
export interface EntregaMonitoreo {
  id: number
  estado: EstadoEntrega
  farmacia_id: number
  sucursal_nombre: string | null
  delivery_id: string | null
  delivery_nombre: string | null
  monto: number | null
  cobrado: boolean
  cobrado_at: string | null
  cobrado_por: string | null
  metodo_cobro: string | null
  intentos: number
  motivo_fallo: string | null
  reabierta_at: string | null
  asignado_at: string | null
  entregado_at: string | null
  created_at: string
  paciente_nombre: string | null
  direccion_entrega: string | null
  telefono_contacto: string | null
  evidencia_path: string | null
  lat: number | null
  lng: number | null
  evidencias: EvidenciaMonitoreo[]
  disc_monto: boolean
  disc_cobrada_fallida: boolean
}

export interface StatsSucursal {
  farmacia_id: number
  sucursal_nombre: string | null
  total: number
  pendiente: number
  asignada: number
  en_camino: number
  entregada: number
  fallida: number
  pct_exito: number | null
  monto_cobrado: number
  reintentos: number
  disc_monto: number
  disc_cobrada_fallida: number
}

export interface FaltanteReconciliacion {
  receta_base_id: number
  farmacia_id: number
  sucursal_nombre: string | null
  fallo_log: boolean
}

export interface FiltrosMonitoreo {
  estado?: EstadoEntrega | null
  sucursalId?: number | null
  deliveryId?: string | null
  desde?: string | null
  hasta?: string | null
}

export function useEntregasMonitoreo() {
  const [entregas, setEntregas] = useState<EntregaMonitoreo[]>([])
  const [stats, setStats] = useState<StatsSucursal[]>([])
  const [faltantes, setFaltantes] = useState<FaltanteReconciliacion[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const cargarLista = useCallback(async (f: FiltrosMonitoreo = {}) => {
    setLoading(true)
    setError(null)
    const { data, error: e } = await supabase.rpc('listar_entregas_monitoreo', {
      p_estado: f.estado ?? null,
      p_sucursal_id: f.sucursalId ?? null,
      p_delivery_id: f.deliveryId ?? null,
      p_desde: f.desde ?? null,
      p_hasta: f.hasta ?? null,
    })
    if (e) setError(e.message)
    else setEntregas((data ?? []) as EntregaMonitoreo[])
    setLoading(false)
  }, [])

  const cargarStats = useCallback(async (desde: string | null, hasta: string | null, sucursalId: number | null) => {
    const { data, error: e } = await supabase.rpc('stats_entregas_sucursal', {
      p_desde: desde, p_hasta: hasta, p_sucursal_id: sucursalId,
    })
    if (!e) setStats((data ?? []) as StatsSucursal[])
    return e?.message ?? null
  }, [])

  const cargarReconciliacion = useCallback(async (sucursalId: number | null) => {
    const { data, error: e } = await supabase.rpc('reconciliar_entregas_faltantes', { p_sucursal_id: sucursalId })
    if (!e) setFaltantes((data ?? []) as FaltanteReconciliacion[])
    return e?.message ?? null
  }, [])

  /** Geocodifica una dirección (texto→coords) vía edge. Best-effort: null si falla (no bloquea). */
  const geocodificar = useCallback(async (direccion: string): Promise<{ lat: number; lng: number } | null> => {
    try {
      const { data, error: e } = await supabase.functions.invoke('geocodificar', { body: { direccion } })
      if (e || !data || data.error) return null
      return { lat: data.lat, lng: data.lng }
    } catch {
      return null
    }
  }, [])

  /** Gestor corrige la dirección/coords de una entrega (gate entregas_gestionar server-side). */
  const guardarDireccion = useCallback(async (entregaId: number, direccion: string, lat: number | null, lng: number | null) => {
    const { error: e } = await supabase.rpc('actualizar_direccion_entrega', {
      p_entrega_id: entregaId, p_direccion: direccion, p_lat: lat, p_lng: lng,
    })
    if (e) throw new Error(e.message)
  }, [])

  /** Abre una evidencia (foto/firma) por signed URL 120 s — NUNCA getPublicUrl. */
  const verEvidencia = useCallback(async (path: string) => {
    await openSignedUrl(BUCKET, path)
  }, [])

  return {
    entregas, stats, faltantes, loading, error,
    cargarLista, cargarStats, cargarReconciliacion,
    geocodificar, guardarDireccion, verEvidencia,
  }
}
