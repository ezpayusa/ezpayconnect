import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { Receta, RecetaItem, Medicamento } from '@/types'

export function useRecetas() {
  const [recetas, setRecetas] = useState<Receta[]>([])
  const [loading, setLoading] = useState(true)

  const fetchRecetas = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('recetas')
      .select(`*, pacientes(nombre, apellido)`)
      .order('created_at', { ascending: false })
    if (error) console.error('Error fetching recetas:', error)
    const mapped = (data || []).map((r: any) => ({
      ...r,
      paciente_nombre: r.pacientes?.nombre + ' ' + r.pacientes?.apellido
    }))
    setRecetas(mapped)
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
    const { data: recetaData, error } = await supabase.from('recetas').insert({
      paciente_id: receta.paciente_id,
      instrucciones_generales: receta.instrucciones_generales || null,
      medico_id: user.id
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
        cantidad: i.cantidad || 1
      }))
      const { error: itemsError } = await supabase.from('receta_items').insert(itemsConReceta)
      if (itemsError) {
        await supabase.from('recetas').delete().eq('id', recetaData.id)
        return { data: null, error: `Error al guardar medicamentos: ${itemsError.message}` }
      }
    }
    const { data: pacienteData } = await supabase.from('pacientes').select('nombre, apellido').eq('id', receta.paciente_id).single()
    const recetaConNombre = {
      ...recetaData,
      paciente_nombre: pacienteData ? `${pacienteData.nombre} ${pacienteData.apellido}` : `Paciente #${receta.paciente_id}`
    }
    setRecetas(prev => [recetaConNombre, ...prev])
    return { data: recetaConNombre, error: null }
  }

  return { recetas, loading, fetchRecetas, createReceta }
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
