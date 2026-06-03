import { useMemo } from 'react'
import { useWebAppCitas } from './useWebAppCitas'
import { useWebAppRecetas } from './useWebAppRecetas'
import { useWebAppExamenes } from './useWebAppExamenes'
import type { HistorialItem } from '@/webapp/types/webapp.types'

export function useWebAppHistorial(pacienteId: number | undefined) {
  const { citas, loading: loadingCitas, error: errorCitas } = useWebAppCitas(pacienteId)
  const { recetas, loading: loadingRecetas, error: errorRecetas } = useWebAppRecetas(pacienteId)
  const { examenes, loading: loadingExamenes, error: errorExamenes } = useWebAppExamenes(pacienteId)

  const items = useMemo<HistorialItem[]>(() => {
    const historial: HistorialItem[] = []

    // Citas → historial
    citas.forEach((c) => {
      historial.push({
        id: c.id,
        tipo: 'cita',
        fecha: c.fecha,
        titulo: c.motivo || 'Consulta médica',
        descripcion: `Estado: ${c.estado}${c.hora_inicio ? ` · ${c.hora_inicio.slice(0, 5)}` : ''}`,
        medico_nombre: c.medico_nombre,
        detalles: { estado: c.estado, notas: c.notas },
      })
    })

    // Recetas → historial
    recetas.forEach((r) => {
      const medicamentos = r.items.map((i) => i.nombre_medicamento).join(', ')
      historial.push({
        id: r.id + 10000, // offset para evitar colisión de IDs
        tipo: 'receta',
        fecha: r.created_at.slice(0, 10),
        titulo: `Receta #${r.id}`,
        descripcion: medicamentos || 'Receta médica',
        medico_nombre: r.medico_nombre,
        detalles: { estado: r.estado, items: r.items, codigo_qr: r.codigo_qr },
      })
    })

    // Exámenes → historial
    examenes.forEach((e) => {
      historial.push({
        id: e.id + 20000,
        tipo: 'examen',
        fecha: e.fecha,
        titulo: e.tipo,
        descripcion: e.descripcion || e.resultados || `Estado: ${e.estado}`,
        medico_nombre: e.medico_nombre,
        detalles: { estado: e.estado, archivo_url: e.archivo_url, resultados: e.resultados },
      })
    })

    // Ordenar por fecha descendente (más reciente primero)
    return historial.sort((a, b) => new Date(b.fecha).getTime() - new Date(a.fecha).getTime())
  }, [citas, recetas, examenes])

  const loading = loadingCitas || loadingRecetas || loadingExamenes
  const error = errorCitas || errorRecetas || errorExamenes

  return { items, loading, error }
}
