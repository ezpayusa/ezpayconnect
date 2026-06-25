import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { openSignedUrl } from '@/lib/signedUrl'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import type {
  EntregaRepartidor,
  EntregaDetalle,
  EstadoEntrega,
  FiltrosCola,
  MetodoCobro,
  MotivoFallo,
} from '@/repartidor/types'

const BUCKET = 'entregas-evidencia'
const CACHE_KEY = 'repartidor.cola.cache.v1' // cache de la ÚLTIMA cola leída (offline read; sin cola de escritura)

/** Lanza si no hay red: toda ESCRITURA exige online (sin cola offline en v1 → evita inconsistencia de cobro). */
function requireOnline(): void {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    throw new Error('Sin conexión. Reintentá cuando vuelva la red.')
  }
}

function leerCache(): EntregaRepartidor[] | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY)
    return raw ? (JSON.parse(raw) as EntregaRepartidor[]) : null
  } catch {
    return null
  }
}

function guardarCache(data: EntregaRepartidor[]): void {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(data))
  } catch {
    /* cache best-effort: si falla (cuota/privado), la app sigue online */
  }
}

export function useEntregasRepartidor() {
  const { cuenta } = useProveedorAuth()
  const empresaId = cuenta?.empresa_id ?? null

  const [entregas, setEntregas] = useState<EntregaRepartidor[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [offline, setOffline] = useState(false)
  const [lastUpdated, setLastUpdated] = useState<string | null>(null) // "Última actualización HH:MM" (mockup cola)

  /** Cola de SUS entregas vía RPC (confinado server-side a delivery_id=auth.uid()). */
  const recargar = useCallback(async (filtros?: FiltrosCola) => {
    setLoading(true)
    setError(null)
    const { data, error: rpcError } = await supabase.rpc('listar_entregas_delivery', {
      p_estado: filtros?.estado ?? null,
      p_desde: filtros?.desde ?? null,
      p_hasta: filtros?.hasta ?? null,
    })
    if (rpcError) {
      // Posible offline o error de red → caer al último cache (solo si no hay filtros).
      const cache = !filtros ? leerCache() : null
      if (cache) {
        setEntregas(cache)
        setOffline(true)
        setError(null)
      } else {
        setError(rpcError.message)
      }
      setLoading(false)
      return
    }
    const lista = (data ?? []) as EntregaRepartidor[]
    setEntregas(lista)
    setOffline(false)
    setLastUpdated(new Date().toLocaleTimeString('es-GT', { hour: '2-digit', minute: '2-digit' }))
    if (!filtros) guardarCache(lista)
    setLoading(false)
  }, [])

  useEffect(() => {
    void recargar()
  }, [recargar])

  /** Transición de estado (asignada→en_camino→entregada/fallida). El RPC re-valida y confina. */
  const actualizarEstado = useCallback(
    async (entregaId: number, nuevoEstado: EstadoEntrega, motivo?: MotivoFallo): Promise<EntregaRepartidor> => {
      requireOnline()
      const { data, error: rpcError } = await supabase.rpc('actualizar_estado_entrega', {
        p_entrega_id: entregaId,
        p_nuevo_estado: nuevoEstado,
        p_motivo_fallo: motivo ?? null,
      })
      if (rpcError) throw new Error(rpcError.message)
      const actualizada = data as EntregaRepartidor
      setEntregas((prev) => prev.map((e) => (e.entrega_id === entregaId ? actualizada : e)))
      return actualizada
    },
    [],
  )

  /** Cobro COD. El monto NO se envía (server lo re-deriva); el front solo elige el método. */
  const cobrar = useCallback(
    async (entregaId: number, metodo: MetodoCobro): Promise<EntregaRepartidor> => {
      requireOnline()
      const { data, error: rpcError } = await supabase.rpc('registrar_cobro_entrega', {
        p_entrega_id: entregaId,
        p_metodo_cobro: metodo,
      })
      if (rpcError) throw new Error(rpcError.message)
      const actualizada = data as EntregaRepartidor
      setEntregas((prev) => prev.map((e) => (e.entrega_id === entregaId ? actualizada : e)))
      return actualizada
    },
    [],
  )

  /**
   * Sube la evidencia (foto o firma) al bucket PRIVADO con path {empresa_id}/{entrega_id}/...
   * y la asocia vía RPC. NUNCA getPublicUrl.
   */
  const subirEvidencia = useCallback(
    async (entregaId: number, blob: Blob, kind: 'foto' | 'firma'): Promise<EntregaRepartidor> => {
      requireOnline()
      // empresaId viene de la cuenta autenticada (cuentas_proveedor de auth.uid(), leída por RLS) → fuente CONFIABLE,
      // no algo que el cliente pueda alterar para escribir fuera de su scope. Si aun así el 1er segmento no coincide
      // con mi_empresa_proveedor(), la storage INSERT policy (D) RECHAZA el upload → lo surfaceamos como error claro.
      if (!empresaId) throw new Error('Sin empresa vinculada.')
      const ext = blob.type === 'image/png' ? 'png' : 'jpg'
      const path = `${empresaId}/${entregaId}/${kind}_${Date.now()}.${ext}`
      const { error: upError } = await supabase.storage.from(BUCKET).upload(path, blob, {
        contentType: blob.type || 'image/jpeg',
        upsert: false,
      })
      if (upError) {
        const msg = /row-level security|not authorized|violates/i.test(upError.message)
          ? 'No tenés permiso para adjuntar evidencia a esta entrega (fuera de tu sucursal o no asignada).'
          : upError.message
        throw new Error(msg)
      }
      const { data, error: rpcError } = await supabase.rpc('registrar_evidencia_entrega', {
        p_entrega_id: entregaId,
        p_path: path,
        p_tipo: kind, // F1.5: tipo explícito → registra una fila por tipo en entrega_evidencias
      })
      if (rpcError) throw new Error(rpcError.message)
      const actualizada = data as EntregaRepartidor
      setEntregas((prev) => prev.map((e) => (e.entrega_id === entregaId ? actualizada : e)))
      return actualizada
    },
    [empresaId],
  )

  /** Detalle ampliado (F1.5): ítems despachados + cobrado_at + evidencias por tipo. Confinado server-side. */
  const obtenerDetalle = useCallback(async (entregaId: number): Promise<EntregaDetalle> => {
    requireOnline()
    const { data, error: rpcError } = await supabase.rpc('detalle_entrega_delivery', { p_entrega_id: entregaId })
    if (rpcError) throw new Error(rpcError.message)
    return data as EntregaDetalle
  }, [])

  /** Abre la evidencia con signed URL (TTL 120 s, helper vivo). Confinada por la policy SELECT del bucket. */
  const verEvidencia = useCallback(async (path: string | null): Promise<void> => {
    await openSignedUrl(BUCKET, path)
  }, [])

  return {
    entregas,
    loading,
    error,
    offline,
    lastUpdated,
    recargar,
    actualizarEstado,
    cobrar,
    subirEvidencia,
    obtenerDetalle,
    verEvidencia,
  }
}
