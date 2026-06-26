// Hook de la bandeja de recetas entrantes (Frente B). Envuelve los RPC SECURITY DEFINER;
// la UI NUNCA consulta tablas directamente (RLS cerrada para la farmacia) — la barrera
// real es el RPC. El dispatch_token del walk-in es transitorio: se pasa al RPC y nunca
// se persiste/loguea (lo maneja EscanearQRModal, no este hook ni estado global).
//
// Gate reveal-registrado (3 puertas, patrón de 2 pasos): listar/verificarToken/buscarPaciente devuelven CABECERA
// (sin med); el medicamento se obtiene SOLO en el paso 2 vía revelarItems(recetaBaseId, puerta), que registra el
// reveal server-side (actor=auth.uid; mig 154, bloqueante). UNA sola revelarItems genérica para las 3 puertas.
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
  farmacia_id?: number                 // revelar_items_receta devuelve farmacia_id (para mapear sucursal post-reveal)
}

// R3 (bandeja, patrón de 2 pasos): resumen de sucursal(es) en la cabecera (sin med).
export interface SucursalResumen {
  farmacia_id: number
  sucursal_nombre: string | null
  sucursal_direccion: string | null
}

export interface RecetaEntrante {
  receta_id: number
  created_at: string
  estado: string
  paciente_nombre: string
  medico_nombre: string | null
  tiene_token: boolean              // = existe recetas_avanzadas (para el FK); NO implica token vigente
  // R3: con flag bandeja=true el RPC NO trae items_pendientes; trae n_pendientes + sucursales (cabecera, sin med).
  // Con flag=false (transición) trae items_pendientes con med, pero el front NO los renderiza (med solo post-reveal).
  items_pendientes?: ItemEntrante[] | null
  n_pendientes?: number
  sucursales?: SucursalResumen[]
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

// F4 + R1 (búsqueda de mostrador sin-QR, patrón de 2 pasos) — cabecera del PASO 1 (sin clínico).
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

  // Bandeja PASO 1: cabeceras de recetas con ítems pendientes dirigidos a mi empresa.
  const listar = useCallback(async (): Promise<RecetaEntrante[]> => {
    setLoading(true)
    try {
      const { data, error } = await supabase.rpc('listar_recetas_entrantes')
      if (error) throw error
      const rows = (data as RecetaEntrante[]) ?? []
      // R3: normalizar n_pendientes (con flag off el RPC trae items_pendientes; el front NO los renderiza en la lista).
      return rows.map((r) => ({
        ...r,
        n_pendientes: typeof r.n_pendientes === 'number' ? r.n_pendientes : (r.items_pendientes?.length ?? 0),
      }))
    } finally {
      setLoading(false)
    }
  }, [])

  const detalle = useCallback(async (recetaId: number): Promise<DetalleEntrante> => {
    const { data, error } = await supabase.rpc('detalle_receta_entrante', { p_receta_id: recetaId })
    if (error) throw error
    return data as DetalleEntrante
  }, [])

  // Despacho DIRIGIDO (por receta_id; sin token). Requiere farmacéutico. Lo usan bandeja (R3) y búsqueda sin-QR (F4).
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

  // Sin-QR PASO 1 — búsqueda por identidad (3 campos, match exacto server-side; confina por empresa+sucursal). Con el
  // flag sinqr activo el RPC devuelve CABECERA (sin clínico). La UI NO filtra ni autocompleta.
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

  // PASO 2 GENÉRICO (3 puertas): revela los ítems pendientes con med de UNA receta y REGISTRA el reveal (mig 154,
  // bloqueante). `puerta` etiqueta el origen del reveal: 'bandeja' | 'walkin_qr' | 'sinqr'.
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

  return { loading, listar, detalle, despacharDirigido, verificarToken, despacharWalkin, buscarPaciente, revelarItems }
}
