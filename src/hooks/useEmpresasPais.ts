import { useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { falla, type Resultado } from '@/visitador/hooks/useEnrolamiento'

// Bandeja de empresas por país (mig 386): listar_empresas_pais + resolver_empresa. Mismo contrato que
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

  return useMemo(() => ({ listar, aprobar, rechazar }), [listar, aprobar, rechazar])
}
