import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface EventoHistorial {
  id: string
  tipo: 'consulta' | 'cita' | 'receta'
  fecha: string
  titulo: string
  descripcion: string
  estado?: string
  metadata: any
  color: string
  icono: string
}

export function useHistorialCompleto(pacienteId?: number) {
  const [eventos, setEventos] = useState<EventoHistorial[]>([])
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState<string>('todos')

  const cargarHistorial = useCallback(async () => {
    if (!pacienteId) {
      setEventos([])
      setLoading(false)
      return
    }

    setLoading(true)
    const eventosCombinados: EventoHistorial[] = []

    try {
      // 1. Cargar consultas médicas
      const { data: consultas, error: errConsultas } = await supabase
        .from('historial_medico')
        .select('*')
        .eq('paciente_id', pacienteId)
        .order('fecha', { ascending: false })

      if (!errConsultas && consultas) {
        consultas.forEach(c => {
          eventosCombinados.push({
            id: `consulta-${c.id}`,
            tipo: 'consulta',
            fecha: c.fecha,
            titulo: c.motivo_consulta || 'Consulta médica',
            descripcion: c.diagnostico || 'Sin diagnóstico registrado',
            estado: 'completada',
            metadata: {
              tratamiento: c.tratamiento,
              examenes: c.examenes_solicitados,
              notas: c.notas_medicas,
              medico_id: c.medico_id
            },
            color: '#1E5C8E',
            icono: 'stethoscope'
          })
        })
      }

      // 2. Cargar citas
      const { data: citas, error: errCitas } = await supabase
        .from('citas')
        .select('*')
        .eq('paciente_id', pacienteId)
        .order('fecha', { ascending: false })

      if (!errCitas && citas) {
        citas.forEach(c => {
          eventosCombinados.push({
            id: `cita-${c.id}`,
            tipo: 'cita',
            fecha: c.fecha,
            titulo: c.motivo || 'Cita médica',
            descripcion: `Hora: ${c.hora_inicio}${c.hora_fin ? ` - ${c.hora_fin}` : ''}`,
            estado: c.estado,
            metadata: {
              hora_inicio: c.hora_inicio,
              hora_fin: c.hora_fin,
              notas: c.notas
            },
            color: c.estado === 'cancelada' ? '#ef4444' : c.estado === 'completada' ? '#22c55e' : '#3A8ABF',
            icono: 'calendar'
          })
        })
      }

      // 3. Cargar recetas
      const { data: recetas, error: errRecetas } = await supabase
        .from('recetas')
        .select('*, receta_items(*)')
        .eq('paciente_id', pacienteId)
        .order('created_at', { ascending: false })

      if (!errRecetas && recetas) {
        for (const r of recetas) {
          const items = ((r as any).receta_items as any[]) || []

          const medicamentos = items?.map(i => i.nombre_medicamento).join(', ') || 'Sin medicamentos'

          eventosCombinados.push({
            id: `receta-${r.id}`,
            tipo: 'receta',
            fecha: r.created_at?.split('T')[0] || new Date().toISOString().split('T')[0],
            titulo: 'Receta médica',
            descripcion: medicamentos,
            estado: r.estado,
            metadata: {
              instrucciones: r.instrucciones_generales,
              items: items || [],
              receta_id: r.id
            },
            color: '#f59e0b',
            icono: 'filetext'
          })
        }
      }

      // Ordenar por fecha (más reciente primero)
      eventosCombinados.sort((a, b) => new Date(b.fecha).getTime() - new Date(a.fecha).getTime())

      setEventos(eventosCombinados)
    } catch (err: any) {
      console.error('Error cargando historial:', err?.message ?? err?.code)
    } finally {
      setLoading(false)
    }
  }, [pacienteId])

  useEffect(() => {
    cargarHistorial()
  }, [cargarHistorial])

  const eventosFiltrados = filtro === 'todos' 
    ? eventos 
    : eventos.filter(e => e.tipo === filtro)

  const stats = {
    total: eventos.length,
    consultas: eventos.filter(e => e.tipo === 'consulta').length,
    citas: eventos.filter(e => e.tipo === 'cita').length,
    recetas: eventos.filter(e => e.tipo === 'receta').length,
  }

  return {
    eventos,
    eventosFiltrados,
    loading,
    filtro,
    setFiltro,
    stats,
    recargar: cargarHistorial
  }
}
