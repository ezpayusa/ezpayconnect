import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { RecetaPaciente, RecetaItemPaciente, DespachoReceta } from '@/webapp/types/webapp.types'

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

      // 1. Obtener recetas del paciente + su fila avanzada (1:1 por receta_base_id; RLS recadv_select_paciente).
      //    El token de despacho viaja solo en memoria: nunca a console, storage ni URL.
      const { data: recetasData, error: recetasErr } = await supabase
        .from('recetas')
        .select('id, estado, instrucciones_generales, created_at, medico_id, receta_items(*), recetas_avanzadas(dispatch_token, dispatch_token_expira_at, estado_dispensacion)')
        .eq('paciente_id', pacienteId)
        .order('created_at', { ascending: false })

      if (recetasErr) throw recetasErr

      // 2. Obtener nombres de médicos por separado
      const medicoIds = [...new Set((recetasData || []).map((r: any) => r.medico_id).filter(Boolean))]
      let medicosMap: Record<string, string> = {}

      if (medicoIds.length > 0) {
        const { data: perfilesData } = await supabase
          .from('perfiles')
          .select('id, nombre_completo')
          .in('id', medicoIds)

        medicosMap = (perfilesData || []).reduce((acc: Record<string, string>, p: any) => {
          acc[p.id] = p.nombre_completo
          return acc
        }, {})
      }

      const recetasConItems: RecetaPaciente[] = []

      for (const r of recetasData || []) {
        const itemsData = (r as any).receta_items || []

        const items: RecetaItemPaciente[] = (itemsData || []).map((i: any) => ({
          id: i.id,
          nombre_medicamento: i.nombre_medicamento,
          dosis: i.dosis,
          frecuencia: i.frecuencia,
          duracion: i.duracion,
          instrucciones: i.instrucciones,
          cantidad: i.cantidad,
          // F2: campos para el control de modalidad por grupo (farmacia)
          farmacia_id: i.farmacia_id ?? null,
          modalidad: i.modalidad ?? null,
          dispensado: i.dispensado ?? null,
        }))

        // PostgREST devuelve la relación 1:1 como objeto; se acepta también arreglo por robustez.
        type FilaAvanzada = { dispatch_token: string | null; dispatch_token_expira_at: string | null; estado_dispensacion: DespachoReceta['estado_dispensacion'] }
        const avRaw = (r as { recetas_avanzadas?: FilaAvanzada | FilaAvanzada[] | null }).recetas_avanzadas
        const av = Array.isArray(avRaw) ? avRaw[0] : avRaw
        const despacho: DespachoReceta | null = av?.dispatch_token
          ? {
              token: av.dispatch_token,
              expira_at: av.dispatch_token_expira_at ?? null,
              estado_dispensacion: av.estado_dispensacion,
            }
          : null

        recetasConItems.push({
          id: r.id,
          medico_nombre: medicosMap[r.medico_id] || 'Médico asignado',
          estado: r.estado,
          instrucciones_generales: r.instrucciones_generales,
          items,
          despacho,
          created_at: r.created_at,
        })
      }

      // F2: nombre de la sucursal por farmacia_id (solo las farmacias a las que la receta del propio paciente
      // está ruteada → no expone nada que el paciente no debiera ver). Si RLS lo bloquea, queda fallback "Sucursal {id}".
      const farmaciaIds = [...new Set(
        recetasConItems.flatMap(r => r.items.map(it => it.farmacia_id)).filter((f): f is number => f != null),
      )]
      if (farmaciaIds.length > 0) {
        const { data: farmData } = await supabase
          .from('farmacias')
          .select('id, nombre')
          .in('id', farmaciaIds)
        const nombreMap: Record<number, string> = (farmData || []).reduce((acc: Record<number, string>, f: any) => {
          acc[f.id] = f.nombre
          return acc
        }, {})
        for (const r of recetasConItems) {
          for (const it of r.items) {
            if (it.farmacia_id != null) it.farmacia_nombre = nombreMap[it.farmacia_id] ?? `Sucursal ${it.farmacia_id}`
          }
        }
      }

      setRecetas(recetasConItems)
    } catch (err: any) {
      console.error('Error cargando recetas:', err?.message ?? err?.code)
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
