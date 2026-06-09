import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { MedicoStats, CitaConPaciente } from '@/medico/types/medico.types'

export function useMedicoStats() {
  const [stats, setStats] = useState<MedicoStats>({
    citasHoy: 0,
    pendientesCount: 0,
    pacientesMes: 0,
    recetasMes: 0,
    proximaCita: null,
  })
  const [loading, setLoading] = useState(true)

  const fetchStats = useCallback(async () => {
    setLoading(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }

      const hoy = new Date().toISOString().split('T')[0]
      const inicioMes = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]

      // Citas de hoy
      const { count: citasHoyCount } = await supabase
        .from('citas')
        .select('*', { count: 'exact', head: true })
        .eq('medico_id', user.id)
        .eq('fecha', hoy)

      // Pendientes de confirmar (solicitada + agendada)
      const { count: pendientesCount } = await supabase
        .from('citas')
        .select('*', { count: 'exact', head: true })
        .eq('medico_id', user.id)
        .in('estado', ['solicitada', 'agendada'])

      // Pacientes únicos atendidos este mes (completadas)
      const { data: pacientesMesData } = await supabase
        .from('citas')
        .select('paciente_id')
        .eq('medico_id', user.id)
        .eq('estado', 'completada')
        .gte('fecha', inicioMes)

      const pacientesUnicos = new Set(pacientesMesData?.map(c => c.paciente_id) || []).size

      // Recetas emitidas este mes
      const { count: recetasCount } = await supabase
        .from('recetas')
        .select('*', { count: 'exact', head: true })
        .eq('medico_id', user.id)
        .gte('created_at', inicioMes)

      // Próxima cita confirmada o agendada (sin join para evitar schema cache bug)
      const { data: proximaData } = await supabase
        .from('citas')
        .select('*')
        .eq('medico_id', user.id)
        .in('estado', ['confirmada', 'agendada'])
        .gte('fecha', hoy)
        .order('fecha', { ascending: true })
        .order('hora_inicio', { ascending: true })
        .limit(1)
        .maybeSingle()

      let proximaCita: CitaConPaciente | null = null
      if (proximaData) {
        // Cargar paciente por separado
        const { data: pacienteData } = await supabase
          .from('pacientes')
          .select('id, nombre, apellido, telefono, email')
          .eq('id', proximaData.paciente_id)
          .maybeSingle()

        proximaCita = {
          ...proximaData,
          paciente: pacienteData ? {
            id: pacienteData.id,
            nombre: pacienteData.nombre,
            apellido: pacienteData.apellido,
            telefono: pacienteData.telefono,
            email: pacienteData.email,
          } : undefined,
        } as CitaConPaciente
      }

      setStats({
        citasHoy: citasHoyCount || 0,
        pendientesCount: pendientesCount || 0,
        pacientesMes: pacientesUnicos,
        recetasMes: recetasCount || 0,
        proximaCita,
      })
    } catch (err) {
      console.error('Error cargando stats:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchStats()
  }, [fetchStats])

  return { stats, loading, recargar: fetchStats }
}
