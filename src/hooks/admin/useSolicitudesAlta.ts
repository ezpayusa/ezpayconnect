import { useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { mapearErrorRpc } from '@/lib/erroresRpc'
import { parsearSolicitudesAdmin, type SolicitudAltaAdmin } from '@/lib/solicitudesAltaAdmin'
import type { Resultado } from '@/visitador/hooks/useEnrolamiento'

// Las 4 RPCs de la bandeja de solicitudes de alta (377/378). Mismo contrato que useEnrolamiento: { ok, data } o
// { ok:false, error } con el error ya mapeado por código (PV022-PV025 traen el mensaje del servidor). Sin toasts.
const falla = (error: unknown): { ok: false; data?: undefined; error: ReturnType<typeof mapearErrorRpc> } =>
  ({ ok: false, error: mapearErrorRpc(error) })

export function useSolicitudesAlta() {
  const listar = useCallback(async (estado: string | null): Promise<Resultado<SolicitudAltaAdmin[]>> => {
    const { data, error } = await supabase.rpc('listar_solicitudes_alta', { p_estado: estado })
    if (error) return falla(error)
    return { ok: true, data: parsearSolicitudesAdmin(data) }
  }, [])

  const aprobar = useCallback(async (solicitudId: string): Promise<Resultado<true>> => {
    const { error } = await supabase.rpc('aprobar_solicitud_alta', { p_solicitud_id: solicitudId })
    if (error) return falla(error)
    return { ok: true, data: true }
  }, [])

  const rechazar = useCallback(async (solicitudId: string, motivo: string): Promise<Resultado<true>> => {
    const { error } = await supabase.rpc('rechazar_solicitud_alta', { p_solicitud_id: solicitudId, p_motivo: motivo })
    if (error) return falla(error)
    return { ok: true, data: true }
  }, [])

  const reenviar = useCallback(async (solicitudId: string): Promise<Resultado<true>> => {
    const { error } = await supabase.rpc('reenviar_solicitud_alta', { p_solicitud_id: solicitudId })
    if (error) return falla(error)
    return { ok: true, data: true }
  }, [])

  return useMemo(() => ({ listar, aprobar, rechazar, reenviar }), [listar, aprobar, rechazar, reenviar])
}
