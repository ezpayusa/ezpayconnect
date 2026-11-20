import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { RecetaPaciente, RecetaItemPaciente } from '@/webapp/types/webapp.types'
import { armarDespacho, cargarTokensDespacho, type FilaAvanzadaPublica } from '@/webapp/lib/despachoReceta'
import { nombresMedicosParaPaciente } from '@/webapp/lib/medicosPaciente'

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

      // 1. Obtener recetas del paciente + su fila avanzada (1:1 por receta_base_id; RLS recadv_select_paciente), SIN el
      //    token: desde la mig 396 el token de despacho sale de la RPC mis_despachos_receta (solo el dueño, solo
      //    vigentes; src/webapp/lib/despachoReceta.ts). Viaja solo en memoria: nunca a console, storage ni URL.
      const [{ data: recetasData, error: recetasErr }, { tokens }] = await Promise.all([
        supabase
          .from('recetas')
          .select('id, estado, instrucciones_generales, created_at, medico_id, receta_items(*), recetas_avanzadas(dispatch_token_expira_at, estado_dispensacion)')
          .eq('paciente_id', pacienteId)
          .order('created_at', { ascending: false }),
        cargarTokensDespacho(),
      ])

      if (recetasErr) throw recetasErr

      // 2. Nombres de los médicos, por fuentes que el paciente puede leer (no `perfiles`: ver medicosPaciente.ts)
      const medicosMap = await nombresMedicosParaPaciente((recetasData || []).map((r: any) => r.medico_id))

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

        // PostgREST devuelve la relación 1:1 como objeto; se acepta también arreglo por robustez. El token (si está
        // vigente) se toma del resultado de la RPC por receta_id.
        const avRaw = (r as { recetas_avanzadas?: FilaAvanzadaPublica | FilaAvanzadaPublica[] | null }).recetas_avanzadas
        const despacho = armarDespacho(r.id, avRaw, tokens)

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
