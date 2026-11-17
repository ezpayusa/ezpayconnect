import { useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { falla, type Resultado } from '@/visitador/hooks/useEnrolamiento'

// Bandeja de empresas por país (migs 386-387): listar_empresas_pais, resolver_empresa y obtener_empresa_pais. Mismo contrato que
// useSolicitudesAlta: { ok, data } o { ok:false, error } con el error ya mapeado por código (EP001-EP005). Sin toasts.
// La barrera es la RPC (super_admin, o admin_pais de ESE país); el front no decide quién ve qué.

export type EstadoEmpresa = 'pendiente' | 'activa' | 'suspendida' | 'rechazada'

/** Una fila de listar_empresas_pais: solo lo que devuelve la RPC (D8: email y teléfono; D5: tiene_plan_activo). */
export interface EmpresaPais {
  id: string
  nombre_empresa: string
  tipo: string
  estado: EstadoEmpresa
  pais_id: string
  email_contacto: string | null
  telefono: string | null
  created_at: string
  motivo_rechazo: string | null
  revisado_at: string | null
  tiene_plan_activo: boolean
}

/** La fila de obtener_empresa_pais (mig 387): datos del modal "Ver detalle" y los 4 conteos. */
export interface EmpresaDetalle {
  id: string
  nombre_empresa: string
  tipo: string
  estado: EstadoEmpresa
  pais_id: string
  ruc_nit: string | null
  ciudad: string | null
  direccion: string | null
  email_contacto: string | null
  telefono: string | null
  logo_url: string | null
  created_at: string
  cuentas_count: number
  productos_count: number
  campanas_count: number
  pagos_count: number
}

export interface ResolucionEmpresa {
  empresa_id: string
  estado: EstadoEmpresa
  /** false = la empresa quedó resuelta pero el aviso in-app/push falló (la RPC no revierte por eso). */
  notificado: boolean
}

export function useEmpresasPais() {
  const listar = useCallback(async (paisId: string, estado: EstadoEmpresa | null): Promise<Resultado<EmpresaPais[]>> => {
    const { data, error } = await supabase.rpc('listar_empresas_pais', { p_pais_id: paisId, p_estado: estado })
    if (error) return falla(error)
    if (!Array.isArray(data)) return falla(null) // forma inesperada: genérico y reportable
    return { ok: true, data: data as EmpresaPais[] }
  }, [])

  const obtenerEmpresaPais = useCallback(async (empresaId: string): Promise<Resultado<EmpresaDetalle>> => {
    const { data, error } = await supabase.rpc('obtener_empresa_pais', { p_empresa_id: empresaId })
    if (error) return falla(error)
    // RETURNS TABLE: una fila. Inexistente o sin autoridad ya viene como EP002; sin fila = forma inesperada.
    if (!Array.isArray(data) || data.length !== 1) return falla(null)
    const fila = data[0] as EmpresaDetalle
    return {
      ok: true,
      data: {
        ...fila,
        cuentas_count: Number(fila.cuentas_count),
        productos_count: Number(fila.productos_count),
        campanas_count: Number(fila.campanas_count),
        pagos_count: Number(fila.pagos_count),
      },
    }
  }, [])

  const aprobar = useCallback(async (empresaId: string): Promise<Resultado<ResolucionEmpresa>> => {
    const { data, error } = await supabase.rpc('resolver_empresa', { p_empresa_id: empresaId, p_accion: 'aprobar' })
    if (error) return falla(error)
    return { ok: true, data: data as ResolucionEmpresa }
  }, [])

  const rechazar = useCallback(async (empresaId: string, motivo: string): Promise<Resultado<ResolucionEmpresa>> => {
    const { data, error } = await supabase.rpc('resolver_empresa', {
      p_empresa_id: empresaId,
      p_accion: 'rechazar',
      p_motivo: motivo,
    })
    if (error) return falla(error)
    return { ok: true, data: data as ResolucionEmpresa }
  }, [])

  return useMemo(
    () => ({ listar, obtenerEmpresaPais, aprobar, rechazar }),
    [listar, obtenerEmpresaPais, aprobar, rechazar],
  )
}
