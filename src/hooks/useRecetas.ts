import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from './usePaisFiltro'
import type { Receta, RecetaItem, Medicamento } from '@/types'

export function useRecetas() {
  const [recetas, setRecetas] = useState<Receta[]>([])
  const [loading, setLoading] = useState(true)
  const { paisId } = usePaisFiltro()

  const fetchRecetas = useCallback(async () => {
    setLoading(true)
    
    let recetasQuery = supabase
      .from('recetas')
      .select(`*, pacientes(nombre, apellido)`)
      .order('created_at', { ascending: false })
    if (paisId) recetasQuery = recetasQuery.eq('pais_id', paisId)
    const { data: recetasData, error: recetasError } = await recetasQuery
    
    if (recetasError) {
      console.error('Error fetching recetas:', recetasError)
      setRecetas([])
      setLoading(false)
      return
    }

    // Para cada receta, verificar si tiene al menos un item con farmacia_id
    const recetasConFarmacia = await Promise.all(
      (recetasData || []).map(async (r: any) => {
        const { data: itemsData } = await supabase
          .from('receta_items')
          .select('farmacia_id')
          .eq('receta_id', r.id)
          .not('farmacia_id', 'is', null)
          .limit(1)
        
        return {
          ...r,
          paciente_nombre: r.pacientes?.nombre + ' ' + r.pacientes?.apellido,
          tiene_farmacia_asignada: (itemsData && itemsData.length > 0) || false
        }
      })
    )

    setRecetas(recetasConFarmacia)
    setLoading(false)
  }, [])

  useEffect(() => { fetchRecetas() }, [fetchRecetas])

    const createReceta = async (receta: Partial<Receta>, items: Partial<RecetaItem>[]) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesion para crear recetas' }
    if (!receta.paciente_id) return { error: 'Debes seleccionar un paciente' }
    for (const item of items) {
      if (!item.dosis || !item.frecuencia) {
        return { error: 'Todos los medicamentos deben tener dosis y frecuencia' }
      }
    }
    // Generar código QR único para dispensación
    const codigoQR = `EZP-${Date.now()}-${Math.random().toString(36).substring(2, 8).toUpperCase()}`

    const { data: recetaData, error } = await supabase.from('recetas').insert({
      paciente_id: receta.paciente_id,
      instrucciones_generales: receta.instrucciones_generales || null,
      medico_id: user.id,
      estado: 'activa',
      codigo_qr: codigoQR,
      pais_id: paisId,
    }).select().single()
    if (error || !recetaData) {
      return { data: null, error: `Error al crear receta: ${error?.message || 'Error desconocido'}` }
    }
    if (items.length > 0) {
      const itemsConReceta = items.map(i => ({
        receta_id: recetaData.id,
        medicamento_id: i.medicamento_id || null,
        nombre_medicamento: i.nombre_medicamento,
        dosis: i.dosis,
        frecuencia: i.frecuencia,
        duracion: i.duracion || null,
        instrucciones: i.instrucciones || null,
        cantidad: i.cantidad || 1,
        farmacia_id: i.farmacia_id || null,
        precio_unitario: i.precio_unitario || null,
        stock_actual: i.stock_actual || null
      }))
      const { error: itemsError } = await supabase.from('receta_items').insert(itemsConReceta)
      if (itemsError) {
        await supabase.from('recetas').delete().eq('id', recetaData.id)
        return { data: null, error: `Error al guardar medicamentos: ${itemsError.message}` }
      }
    }
    // Notificar al paciente (campanita del webapp)
    try {
      await supabase.rpc('notificar_paciente', {
        p_paciente_id: receta.paciente_id,
        p_tipo: 'receta',
        p_titulo: 'Nueva receta',
        p_mensaje: 'Tu médico te emitió una nueva receta. Revísala en la app.',
        p_accion_url: '/paciente/recetas',
      })
    } catch (e) {
      console.error('Error notificando receta al paciente:', e)
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
      console.error('Error fetching receta:', recetaError)
      return { receta: null, items: [], paciente: null }
    }

   const { data: items, error: itemsError } = await supabase
  .from('receta_items')
  .select('*')
  .eq('receta_id', id)

if (itemsError) {
  console.error('Error fetching receta items:', itemsError)
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
