import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { Receta, RecetaItem, Medicamento } from '@/types'

export function useRecetas() {
  const [recetas, setRecetas] = useState<Receta[]>([])
  const [loading, setLoading] = useState(true)

  const fetchRecetas = useCallback(async () => {
    setLoading(true)
    const { data } = await supabase
      .from('recetas')
      .select(`*, pacientes(nombre, apellido)`)
      .order('created_at', { ascending: false })
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
    if (!user) return { error: 'No autenticado' }
    const { data: recetaData, error } = await supabase.from('recetas').insert({
      ...receta,
      medico_id: user.id
    }).select().single()
    if (error || !recetaData) return { data: recetaData, error }

    if (items.length > 0) {
      const itemsConReceta = items.map(i => ({ ...i, receta_id: recetaData.id }))
      await supabase.from('receta_items').insert(itemsConReceta)
    }
    setRecetas(prev => [recetaData, ...prev])
    return { data: recetaData, error: null }
  }

  return { recetas, loading, fetchRecetas, createReceta }
}

export function useMedicamentos() {
  const [medicamentos, setMedicamentos] = useState<Medicamento[]>([])

  const fetchMedicamentos = useCallback(async (query?: string) => {
    let q = supabase.from('medicamentos').select('*').eq('activo', true)
    if (query) q = q.or(`nombre_generico.ilike.%${query}%,nombre_comercial.ilike.%${query}%`)
    const { data } = await q.limit(20)
    setMedicamentos(data || [])
  }, [])

  return { medicamentos, fetchMedicamentos }
}
