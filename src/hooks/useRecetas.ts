import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from './usePaisFiltro'
import type { Receta, RecetaItem, Medicamento } from '@/types'

export function useRecetas(opts?: { autoFetch?: boolean }) {
  const autoFetch = opts?.autoFetch ?? true
  const [recetas, setRecetas] = useState<Receta[]>([])
  const [loading, setLoading] = useState(true)
  const { paisId } = usePaisFiltro()

  const fetchRecetas = useCallback(async () => {
    setLoading(true)
    
    let recetasQuery = supabase
      .from('recetas')
      .select(`*, pacientes(nombre, apellido), receta_items(farmacia_id)`)
      .order('created_at', { ascending: false })
      .limit(500)
    if (paisId) recetasQuery = recetasQuery.eq('pais_id', paisId)
    const { data: recetasData, error: recetasError } = await recetasQuery
    
    if (recetasError) {
      console.error('Error fetching recetas:', recetasError?.message ?? recetasError?.code)
      setRecetas([])
      setLoading(false)
      return
    }

    const recetasConFarmacia = (recetasData || []).map((r: any) => ({
      ...r,
      paciente_nombre: r.pacientes?.nombre + ' ' + r.pacientes?.apellido,
      tiene_farmacia_asignada: Array.isArray(r.receta_items) && r.receta_items.some((it: any) => it.farmacia_id != null),
    }))

    setRecetas(recetasConFarmacia)
    setLoading(false)
  }, [paisId])

  useEffect(() => { if (autoFetch) fetchRecetas() }, [fetchRecetas, autoFetch])

    const createReceta = async (receta: Partial<Receta>, items: Partial<RecetaItem>[]) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesion para crear recetas' }
    if (!receta.paciente_id) return { error: 'Debes seleccionar un paciente' }
    for (const item of items) {
      if (!item.dosis || !item.frecuencia) {
        return { error: 'Todos los medicamentos deben tener dosis y frecuencia' }
      }
    }
    // ─────────────────────────────────────────────────────────────
    // CUTOVER O1. El flag vive en private.emision_flags y se lee por RPC
    // (private.* no es alcanzable desde PostgREST). Fail-safe: si la lectura
    // falla, `usarRPC` queda false y se emite por el camino directo de siempre.
    // Apagar el flag = un UPDATE de una linea. Sin build, sin deploy.
    // ─────────────────────────────────────────────────────────────
    let usarRPC = false
    try {
      const { data: flag } = await supabase.rpc('emision_flag', { p_clave: 'emitir_receta_rpc' })
      usarRPC = flag === true
    } catch {
      usarRPC = false
    }

    let recetaData: Receta | null = null

    if (usarRPC) {
      // Los errores PRxxx son RAISE deliberados de emitir_receta, con mensaje
      // redactado para el medico. Cualquier otro codigo es un error de Postgres:
      // su texto expone internals del esquema y no le sirve a nadie.
      const { data: res, error: rpcError } = await supabase.rpc('emitir_receta', {
        p_paciente_id: receta.paciente_id,
        p_instrucciones_generales: receta.instrucciones_generales ?? null,
        p_items: items.map(i => ({
          medicamento_id: i.medicamento_id ?? null,
          nombre_medicamento: i.nombre_medicamento,
          dosis: i.dosis,
          frecuencia: i.frecuencia,
          duracion: i.duracion ?? null,
          instrucciones: i.instrucciones ?? null,
          cantidad: i.cantidad ?? 1,
          farmacia_id: i.farmacia_id ?? null,
          precio_unitario: i.precio_unitario ?? null,
          stock_actual: i.stock_actual ?? null,
          acuse_iniciales: i.acuse_iniciales ?? null,
        })),
      })

      if (rpcError) {
        const esErrorDeNegocio = typeof rpcError.code === 'string' && rpcError.code.startsWith('PR')
        if (esErrorDeNegocio) {
          return { data: null, error: rpcError.message }
        }
        console.error('emitir_receta:', rpcError.code, rpcError.message)
        return { data: null, error: 'No se pudo emitir la receta. Intenta de nuevo.' }
      }

      const recetaId = (res as { receta_id?: number } | null)?.receta_id
      if (!recetaId) {
        console.error('emitir_receta: respuesta sin receta_id', res)
        return { data: null, error: 'No se pudo emitir la receta. Intenta de nuevo.' }
      }

      // La RPC devuelve {receta_id, numero_correlativo, numero_formateado}.
      // Los callers esperan la FILA (RecetaModal:294 usa result.data.id).
      const { data: fila, error: selError } = await supabase
        .from('recetas').select('*').eq('id', recetaId).single()
      if (selError || !fila) {
        console.error('emitir_receta: receta creada pero no legible', selError?.message)
        return { data: null, error: 'No se pudo emitir la receta. Intenta de nuevo.' }
      }
      recetaData = fila

    } else {
      // ── Camino directo (pre-cutover). Sin correlativo, sin dispatch_token:
      //    la receta NO nace despachable. Se conserva como backout del flag.
      const { data: filaDirecta, error } = await supabase.from('recetas').insert({
        paciente_id: receta.paciente_id,
        instrucciones_generales: receta.instrucciones_generales || null,
        medico_id: user.id,
        estado: 'activa',
        pais_id: paisId,
      }).select().single()
      if (error || !filaDirecta) {
        return { data: null, error: `Error al crear receta: ${error?.message || 'Error desconocido'}` }
      }
      recetaData = filaDirecta

      if (items.length > 0) {
        const itemsConReceta = items.map(i => ({
          receta_id: filaDirecta.id,
          medicamento_id: i.medicamento_id || null,
          nombre_medicamento: i.nombre_medicamento,
          dosis: i.dosis,
          frecuencia: i.frecuencia,
          duracion: i.duracion || null,
          instrucciones: i.instrucciones || null,
          cantidad: i.cantidad || 1,
          farmacia_id: i.farmacia_id || null,
          acuse_iniciales: i.acuse_iniciales ?? null,
          precio_unitario: i.precio_unitario || null,
          stock_actual: i.stock_actual || null,
        }))
        const { error: itemsError } = await supabase.from('receta_items').insert(itemsConReceta)
        if (itemsError) {
          await supabase.from('recetas').delete().eq('id', filaDirecta.id)
          return { data: null, error: `Error al guardar medicamentos: ${itemsError.message}` }
        }
      }
    }
    // Notificar al paciente (RPC gateado: deriva recipient + contenido genérico del ref ya insertado; in-app + push). Best-effort.
    try {
      await supabase.rpc('notificar_receta', { p_receta_id: recetaData.id })
    } catch (e) {
      console.error('Error notificando receta al paciente:', e?.message ?? e?.code)
    }

    const { data: pacienteData } = await supabase.from('pacientes').select('nombre, apellido').eq('id', receta.paciente_id).single()
    const recetaConNombre = {
      ...recetaData,
      paciente_nombre: pacienteData ? `${pacienteData.nombre} ${pacienteData.apellido}` : `Paciente #${receta.paciente_id}`
    }
    setRecetas(prev => [recetaConNombre, ...prev])
    return { data: recetaConNombre, error: null }
  }

  // ✅ Obtener receta completa con items y paciente
  const getRecetaCompleta = async (id: number) => {
    const { data: receta, error: recetaError } = await supabase
      .from('recetas')
      .select(`*, pacientes(*)`)
      .eq('id', id)
      .maybeSingle()

    if (recetaError || !receta) {
      console.error('Error fetching receta:', recetaError?.message ?? recetaError?.code)
      return { receta: null, items: [], paciente: null }
    }

   const { data: items, error: itemsError } = await supabase
  .from('receta_items')
  .select('*')
  .eq('receta_id', id)

if (itemsError) {
  console.error('Error fetching receta items:', itemsError?.message ?? itemsError?.code)
}

// Traer nombres de farmacias si hay farmacia_id
let itemsConFarmacia = items || []
if (itemsConFarmacia.length > 0) {
  const farmaciaIds = itemsConFarmacia
    .filter((i: any) => i.farmacia_id)
    .map((i: any) => i.farmacia_id)
  
  if (farmaciaIds.length > 0) {
    const { data: farmaciasData } = await supabase
      .from('farmacias')
      .select('id, nombre, direccion, telefono')
      .in('id', farmaciaIds)
    
    const farmaciasMap = (farmaciasData || []).reduce((acc: any, f: any) => {
      acc[f.id] = f
      return acc
    }, {} as Record<number, any>)
    
    itemsConFarmacia = itemsConFarmacia.map((item: any) => ({
      ...item,
      farmacia: item.farmacia_id ? farmaciasMap[item.farmacia_id] : null
    }))
  }
}

  // Fallback: si items no tienen precio_unitario, buscar en farmacia_medicamentos
  const itemsSinPrecio = itemsConFarmacia.filter((i: any) => i.farmacia_id && !i.precio_unitario)
  if (itemsSinPrecio.length > 0) {
    const farmaciaIdsUnicos = [...new Set(itemsSinPrecio.map((i: any) => i.farmacia_id))]
    const nombresMedicamentos = [...new Set(itemsSinPrecio.map((i: any) => i.nombre_medicamento))]
    
    const { data: inventarioData } = await supabase
      .from('farmacia_medicamentos')
      .select('farmacia_id, nombre_medicamento, precio_unitario, stock_actual')
      .in('farmacia_id', farmaciaIdsUnicos)
      .in('nombre_medicamento', nombresMedicamentos)
    
    const inventarioMap = (inventarioData || []).reduce((acc: any, inv: any) => {
      const key = `${inv.farmacia_id}_${inv.nombre_medicamento}`
      acc[key] = inv
      return acc
    }, {} as Record<string, any>)
    
    itemsConFarmacia = itemsConFarmacia.map((item: any) => {
      if (item.precio_unitario || !item.farmacia_id) return item
      const key = `${item.farmacia_id}_${item.nombre_medicamento}`
      const inv = inventarioMap[key]
      if (inv) {
        return { ...item, precio_unitario: inv.precio_unitario, stock_actual: inv.stock_actual }
      }
      return item
    })
  }

return { 
  receta, 
  items: itemsConFarmacia,
  paciente: receta.pacientes || null
}
 } // ✅ Cambiar estado de receta
  const updateReceta = async (id: number, updates: Partial<Receta>) => {
    const { data, error } = await supabase.from('recetas').update(updates).eq('id', id).select().single()
    if (!error && data) {
      setRecetas(prev => prev.map(r => r.id === id ? { ...r, ...data } : r))
    }
    return { data, error }
  }

  return { recetas, loading, fetchRecetas, createReceta, getRecetaCompleta, updateReceta }
}

export function useMedicamentos() {
  const [medicamentos, setMedicamentos] = useState<Medicamento[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchMedicamentos = useCallback(async (query?: string) => {
    setLoading(true)
    setError(null)
    try {
      const searchTerm = query?.trim() || ''
      let q = supabase.from('medicamentos').select('*').eq('activo', true)
      if (searchTerm.length > 0) {
        q = q.ilike('nombre_generico', `%${searchTerm}%`)
      }
      const { data, error: err } = await q.order('nombre_generico').limit(20)
      if (err) {
        setError(`Error: ${err.message}`)
        setMedicamentos([])
      } else {
        setMedicamentos(data || [])
      }
    } catch (e: any) {
      setError(`Error: ${e?.message || 'No se pudieron cargar'}`)
      setMedicamentos([])
    }
    setLoading(false)
  }, [])

  return { medicamentos, loading, error, fetchMedicamentos }
}
