import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from './usePaisFiltro'
import type { Receta, RecetaItem, Medicamento } from '@/types'
import { cargarAlertasAlergia } from '@/lib/alertasAlergiaReceta'

/** Respuesta de public.emitir_receta (mig 395). */
interface EmitirRecetaRespuesta {
  receta_id: number
  numero_correlativo: number
  numero_formateado: string
  folio: string
}

/** Resultado de useRecetas().createReceta. `code` solo viene en los errores de negocio (PRxxx). */
export interface ResultadoCrearReceta {
  data?: Receta | null
  error: string | null
  folio?: string | null
  code?: string
}

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

    const createReceta = async (receta: Partial<Receta>, items: Partial<RecetaItem>[]): Promise<ResultadoCrearReceta> => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesion para crear recetas' }
    if (!receta.paciente_id) return { error: 'Debes seleccionar un paciente' }
    for (const item of items) {
      if (!item.dosis || !item.frecuencia) {
        return { error: 'Todos los medicamentos deben tener dosis y frecuencia' }
      }
    }
    // La emision pasa SOLO por emitir_receta (mig 328: authenticated ya no puede
    // insertar directo en recetas ni en receta_items). Si la RPC falla, el error
    // se muestra y NO hay camino alternativo.
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
        // H20 (mig 395): obligatorio (5-500) si el ítem coincide con una alergia; si falta, PR011.
        alergia_confirmacion_motivo: i.alergia_confirmacion_motivo?.trim() || null,
      })),
      // H2 (mig 395): la receta emitida desde la consulta queda vinculada a su cita. El servidor valida
      // que la cita sea del paciente y del médico (PR012); fuera de una consulta va NULL.
      p_cita_id: receta.cita_id ?? null,
    })

    if (rpcError) {
      const esErrorDeNegocio = typeof rpcError.code === 'string' && rpcError.code.startsWith('PR')
      if (esErrorDeNegocio) {
        // El código viaja para que el caller distinga casos (p. ej. PR011 marca el ítem en RecetaModal).
        return { data: null, error: rpcError.message, code: rpcError.code }
      }
      console.error('emitir_receta:', rpcError.code, rpcError.message)
      return { data: null, error: 'No se pudo emitir la receta. Intenta de nuevo.' }
    }

    // Desde la mig 395 la RPC devuelve {receta_id, numero_correlativo, numero_formateado, folio}
    // (numero_formateado = folio, se conserva por compatibilidad) y guarda el folio en recetas.folio.
    const respuesta = res as EmitirRecetaRespuesta | null
    const recetaId = respuesta?.receta_id
    if (!recetaId) {
      console.error('emitir_receta: respuesta sin receta_id', res)
      return { data: null, error: 'No se pudo emitir la receta. Intenta de nuevo.' }
    }
    const folio = respuesta?.folio ?? respuesta?.numero_formateado ?? null

    // Los callers esperan la FILA (RecetaModal usa result.data.id).
    const { data: recetaData, error: selError } = await supabase
      .from('recetas').select('*').eq('id', recetaId).single()
    if (selError || !recetaData) {
      console.error('emitir_receta: receta creada pero no legible', selError?.message)
      return { data: null, error: 'No se pudo emitir la receta. Intenta de nuevo.' }
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
    return { data: recetaConNombre, folio, error: null }
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
      return { receta: null, items: [], paciente: null, cedula_medico: null, alertas_alergia: [] }
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

// H12: cédula del médico de la receta, para reconstruir el folio de las recetas sin folio guardado.
// medicos tiene GRANT SELECT por columna (mig 375): hay que listar la columna. Si no se puede
// leer, queda null y el folio usa 'SINCED'.
let cedula_medico: string | null = null
if (receta.medico_id) {
  const { data: medicoRow } = await supabase
    .from('medicos').select('cedula_profesional').eq('id', receta.medico_id).maybeSingle()
  cedula_medico = (medicoRow?.cedula_profesional as string | null | undefined) ?? null
}

// H23: alertas de alergia confirmadas al emitir. Solo las lee el médico autor (policy); para
// cualquier otro queda [] y no se muestra nada.
const alertas_alergia = await cargarAlertasAlergia(id, itemsConFarmacia)

return { 
  receta, 
  items: itemsConFarmacia,
  paciente: receta.pacientes || null,
  cedula_medico,
  alertas_alergia,
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
      // H22: genérico O comercial (el placeholder del modal ya lo prometía); misma tabla, sin RPC.
      const filtro = filtroBusquedaMedicamento(searchTerm)
      if (filtro) q = q.or(filtro)
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

/**
 * H22: filtro PostgREST `or` para buscar un medicamento por nombre genérico o comercial.
 * Se quitan los caracteres que la sintaxis de `or` usa como separadores o agrupadores (`,` `(` `)`)
 * y las comillas/barras invertidas, para que el texto del médico no rompa ni amplíe el filtro.
 * Devuelve null si no queda nada que buscar.
 */
export function filtroBusquedaMedicamento(texto: string): string | null {
  const limpio = texto.replace(/[,()"\\]/g, ' ').replace(/\s+/g, ' ').trim()
  if (!limpio) return null
  const patron = `%${limpio}%`
  return `nombre_generico.ilike.${patron},nombre_comercial.ilike.${patron}`
}
