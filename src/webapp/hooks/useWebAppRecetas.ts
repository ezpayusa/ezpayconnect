import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { RecetaPaciente, RecetaItemPaciente } from '@/webapp/types/webapp.types'

export function useWebAppRecetas(pacienteId: number | undefined) {
  const [recetas, setRecetas] = useState<RecetaPaciente[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchRecetas = useCallback(async () => {
    if (!pacienteId) {
      setRecetas([])
      setLoading(false)
      return
    }

    try {
      setLoading(true)
      setError(null)

      // Obtener recetas del paciente
      const { data: recetasData, error: recetasErr } = await supabase
        .from('recetas')
        .select(`
          id,
          estado,
          instrucciones_generales,
          codigo_qr,
          created_at,
          perfiles!recetas_medico_id_fkey(nombre_completo)
        `)
        .eq('paciente_id', pacienteId)
        .order('created_at', { ascending: false })

      if (recetasErr) throw recetasErr

      const recetasConItems: RecetaPaciente[] = []

      for (const r of recetasData || []) {
        // Obtener items de cada receta
        const { data: itemsData } = await supabase
          .from('receta_items')
          .select('*')
          .eq('receta_id', r.id)

        const items: RecetaItemPaciente[] = (itemsData || []).map((i: any) => ({
          id: i.id,
          nombre_medicamento: i.nombre_medicamento,
          dosis: i.dosis,
          frecuencia: i.frecuencia,
          duracion: i.duracion,
          instrucciones: i.instrucciones,
          cantidad: i.cantidad,
        }))

        recetasConItems.push({
          id: r.id,
          medico_nombre: r.perfiles?.nombre_completo || 'Médico asignado',
          estado: r.estado,
          instrucciones_generales: r.instrucciones_generales,
          items,
          codigo_qr: r.codigo_qr,
          created_at: r.created_at,
        })
      }

      setRecetas(recetasConItems)
    } catch (err: any) {
      console.error('Error cargando recetas:', err)
      setError(err.message || 'Error al cargar recetas')
    } finally {
      setLoading(false)
    }
  }, [pacienteId])

  useEffect(() => {
    fetchRecetas()
  }, [fetchRecetas])

  const activas = recetas.filter((r) => r.estado === 'activa')

  return { recetas, activas, loading, error, refetch: fetchRecetas }
}
