import { useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { mapearErrorRpc, type ErrorRpcMapeado } from '@/lib/erroresRpc'
import {
  parsearPrioridad,
  parsearRespuestaSolicitud,
  paramsSolicitudAlta,
  type DatosSolicitudAlta,
  type EstadoEnrolamiento,
  type PrioridadAgendar,
  type RespuestaSolicitud,
  type SolicitudAlta,
} from '@/visitador/lib/enrolamiento'

// Las 5 RPCs del enrolamiento que usa la PWA del visitador. Cada una devuelve { ok, data } o { ok:false, error }
// con el error ya mapeado por código (mapearErrorRpc: los PV traen su mensaje para el usuario). No hace toasts:
// la pantalla decide dónde va el mensaje (toast o inline).
// Las dos ramas declaran las dos propiedades: el proyecto no tiene strictNullChecks y sin eso el union no se estrecha.
export type Resultado<T> =
  | { ok: true; data: T; error?: undefined }
  | { ok: false; data?: undefined; error: ErrorRpcMapeado }

const falla = (error: unknown): { ok: false; data?: undefined; error: ErrorRpcMapeado } => ({ ok: false, error: mapearErrorRpc(error) })
// Una respuesta con forma inesperada es bug nuestro (o de la base): genérico y reportable.
const respuestaInvalida = () => falla(null)

export function useEnrolamiento() {
  const enrolarMedico = useCallback(async (medicoId: string): Promise<Resultado<EstadoEnrolamiento>> => {
    const { data, error } = await supabase.rpc('enrolar_medico', { p_medico_id: medicoId })
    if (error) return falla(error)
    const fila = Array.isArray(data) ? data[0] : data
    const estado = fila?.estado
    if (estado !== 'enrolado' && estado !== 'ya_enrolado_por_ti') return respuestaInvalida()
    return { ok: true, data: estado }
  }, [])

  const solicitarAlta = useCallback(async (datos: DatosSolicitudAlta): Promise<Resultado<RespuestaSolicitud>> => {
    const { data, error } = await supabase.rpc('solicitar_alta_medico', paramsSolicitudAlta(datos))
    if (error) return falla(error)
    const r = parsearRespuestaSolicitud(data)
    return r ? { ok: true, data: r } : respuestaInvalida()
  }, [])

  const cancelarSolicitud = useCallback(async (solicitudId: string): Promise<Resultado<true>> => {
    const { error } = await supabase.rpc('cancelar_solicitud_alta', { p_solicitud_id: solicitudId })
    if (error) return falla(error)
    return { ok: true, data: true }
  }, [])

  const listarSolicitudes = useCallback(async (): Promise<Resultado<SolicitudAlta[]>> => {
    const { data, error } = await supabase.rpc('listar_solicitudes_alta', { p_estado: null })
    if (error) return falla(error)
    const filas = (Array.isArray(data) ? data : []) as Record<string, unknown>[]
    return {
      ok: true,
      data: filas.map((f) => ({
        id: String(f.id),
        nombre_completo: String(f.nombre_completo ?? ''),
        email: String(f.email ?? ''),
        especialidad_nombre: (f.especialidad_nombre as string | null) ?? null,
        estado: String(f.estado ?? ''),
        motivo_rechazo: (f.motivo_rechazo as string | null) ?? null,
        created_at: String(f.created_at ?? ''),
      })),
    }
  }, [])

  const prioridadParaAgendar = useCallback(async (medicoId: string): Promise<Resultado<PrioridadAgendar | null>> => {
    const { data, error } = await supabase.rpc('prioridad_para_agendar', { p_medico_id: medicoId })
    if (error) return falla(error)
    return { ok: true, data: parsearPrioridad(data) }
  }, [])

  return useMemo(
    () => ({ enrolarMedico, solicitarAlta, cancelarSolicitud, listarSolicitudes, prioridadParaAgendar }),
    [enrolarMedico, solicitarAlta, cancelarSolicitud, listarSolicitudes, prioridadParaAgendar],
  )
}
