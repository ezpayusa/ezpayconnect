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

// R2 (walk-in QR, patrón de 2 pasos): cabecera de verificar_receta_despacho con el flag walkin_qr activo.
// SIN array de items ni datos clínicos — el med se obtiene en el paso 2 vía revelarItems (que registra el reveal).
export interface CabeceraWalkin {
  receta_id: number
  dispatch_token?: string
  estado_dispensacion?: string
  paciente_nombre: string
  n_pendientes: number
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

  // Walk-in PASO 1: el token es secreto del paciente. Solo se pasa al RPC; nunca se guarda.
  // Con flag walkin_qr=true el RPC devuelve CABECERA (sin med). En la transición (flag=false) el RPC trae items[]:
  // en ese caso derivamos n_pendientes acá y NO exponemos los items (el med solo se ve en el paso 2 vía revelarItems).
  const verificarToken = useCallback(async (token: string): Promise<CabeceraWalkin> => {
    const { data, error } = await supabase.rpc('verificar_receta_despacho', { p_token: token })
    if (error) throw error
    const d = data as any
    const n_pendientes = typeof d?.n_pendientes === 'number'
      ? d.n_pendientes
      : ((d?.items as ItemEntrante[] | undefined)?.filter((i) => !i.dispensado).length ?? 0)
    return {
      receta_id: d.receta_id,
      dispatch_token: d.dispatch_token,
      estado_dispensacion: d.estado_dispensacion,
      paciente_nombre: d.paciente_nombre,
      n_pendientes,
    }
  }, [])

  // Walk-in / sin-QR PASO 2: revela los ítems pendientes con med de una receta y REGISTRA el reveal (mig 154,
  // bloqueante). Reusa el RPC compartido; `puerta` etiqueta el origen ('walkin_qr' acá; 'sinqr' en F4).
  const revelarItems = useCallback(
    async (recetaBaseId: number, puerta: string): Promise<ItemEntrante[]> => {
      const { data, error } = await supabase.rpc('revelar_items_receta', {
        p_receta_base_id: recetaBaseId,
        p_puerta: puerta,
      })
      if (error) throw error
      return (data as ItemEntrante[]) ?? []
    },
    [],
  )

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

  return { loading, listar, detalle, despacharDirigido, verificarToken, revelarItems, despacharWalkin }
}
