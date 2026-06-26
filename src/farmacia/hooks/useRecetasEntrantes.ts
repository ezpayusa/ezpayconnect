// Hook de la bandeja de recetas entrantes (Frente B). Envuelve los RPC SECURITY DEFINER;
// la UI NUNCA consulta tablas directamente (RLS cerrada para la farmacia) — la barrera
// real es el RPC. El dispatch_token del walk-in es transitorio: se pasa al RPC y nunca
// se persiste/loguea (lo maneja EscanearQRModal, no este hook ni estado global).
import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface ItemEntrante {
  item_id: number
  nombre_medicamento: string
  dosis: string
  frecuencia: string
  cantidad: number
  instrucciones?: string
  dispensado?: boolean
  sucursal_nombre?: string | null      // 3.4: a qué sucursal está ruteado el ítem (informativo, admin-central)
  sucursal_direccion?: string | null
}

export interface RecetaEntrante {
  receta_id: number
  created_at: string
  estado: string
  paciente_nombre: string
  medico_nombre: string | null
  tiene_token: boolean              // = existe recetas_avanzadas (para el FK); NO implica token vigente
  items_pendientes: ItemEntrante[] | null
}

export interface DetalleEntrante {
  receta_id: number
  created_at: string
  estado: string
  paciente_nombre: string
  medico_nombre: string | null
  tiene_token: boolean
  items: ItemEntrante[]
}

// F4 + R1 (búsqueda de mostrador sin-QR, patrón de 2 pasos).
// PASO 1 (buscar_recetas_pendientes_paciente con flag sinqr activo): devuelve CABECERA, SIN datos clínicos.
// PASO 2 (revelar_items_receta, puerta 'sinqr'): devuelve los ítems con med y REGISTRA el reveal (mig 154).
// `instrucciones` llega del RPC del paso 2 pero NO se renderiza en mostrador.
export interface ItemEncontrado {
  item_id: number
  nombre_medicamento: string
  dosis: string
  frecuencia: string
  cantidad: number
  instrucciones?: string
  farmacia_id: number
}

// PASO 1 — cabecera por receta (sin clínico)
export interface RecetaCabecera {
  receta_base_id: number
  n_items_pendientes: number
}

export interface PacienteCabecera {
  paciente_ref: string        // opaco (md5+salt por-llamada); solo handle interno, NUNCA en URL/logs
  paciente_nombre: string
  recetas: RecetaCabecera[]
}

export function useRecetasEntrantes() {
  const [loading, setLoading] = useState(false)

  // Bandeja: recetas con ítems pendientes dirigidos a mi empresa.
  const listar = useCallback(async (): Promise<RecetaEntrante[]> => {
    setLoading(true)
    try {
      const { data, error } = await supabase.rpc('listar_recetas_entrantes')
      if (error) throw error
      return (data as RecetaEntrante[]) ?? []
    } finally {
      setLoading(false)
    }
  }, [])

  const detalle = useCallback(async (recetaId: number): Promise<DetalleEntrante> => {
    const { data, error } = await supabase.rpc('detalle_receta_entrante', { p_receta_id: recetaId })
    if (error) throw error
    return data as DetalleEntrante
  }, [])

  // Despacho DIRIGIDO (por receta_id; sin token). Requiere farmacéutico.
  const despacharDirigido = useCallback(
    async (recetaId: number, itemIds: number[], farmaceutico: string): Promise<{ despachados: number }> => {
      const { data, error } = await supabase.rpc('registrar_dispensacion_dirigida', {
        p_receta_id: recetaId,
        p_item_ids: itemIds,
        p_farmaceutico: farmaceutico,
      })
      if (error) throw error
      return data as { despachados: number }
    },
    [],
  )

  // Walk-in: el token es secreto del paciente. Solo se pasa al RPC; nunca se guarda.
  const verificarToken = useCallback(async (token: string): Promise<DetalleEntrante & { dispatch_token?: string }> => {
    const { data, error } = await supabase.rpc('verificar_receta_despacho', { p_token: token })
    if (error) throw error
    return data
  }, [])

  const despacharWalkin = useCallback(
    async (token: string, itemIds: number[], farmaceutico: string): Promise<{ despachados: number }> => {
      const { data, error } = await supabase.rpc('registrar_dispensacion', {
        p_token: token,
        p_item_ids: itemIds,
        p_farmaceutico: farmaceutico,
      })
      if (error) throw error
      return data as { despachados: number }
    },
    [],
  )

  // PASO 1 — búsqueda por identidad (3 campos, match exacto server-side; confina por empresa+sucursal). Con el flag
  // sinqr activo el RPC devuelve CABECERA (sin clínico). La UI NO filtra ni autocompleta.
  const buscarPaciente = useCallback(
    async (nombre: string, apellido: string, fechaNac: string): Promise<PacienteCabecera[]> => {
      const { data, error } = await supabase.rpc('buscar_recetas_pendientes_paciente', {
        p_nombre: nombre,
        p_apellido: apellido,
        p_fecha_nac: fechaNac,
      })
      if (error) throw new Error(error.message)
      return (data as PacienteCabecera[]) ?? []
    },
    [],
  )

  // PASO 2 — revelar los ítems con med de UNA receta (puerta 'sinqr'). El RPC registra el reveal (mig 154, bloqueante).
  const revelarItems = useCallback(
    async (recetaBaseId: number): Promise<ItemEncontrado[]> => {
      const { data, error } = await supabase.rpc('revelar_items_receta', {
        p_receta_base_id: recetaBaseId,
        p_puerta: 'sinqr',
      })
      if (error) throw new Error(error.message)
      return (data as ItemEncontrado[]) ?? []
    },
    [],
  )

  return { loading, listar, detalle, despacharDirigido, verificarToken, despacharWalkin, buscarPaciente, revelarItems }
}
