import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { hoyISO, fechaLocalISO, combinar } from '@/lib/fecha'
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

      // Fechas DATE en hora local (el día UTC hacía que en GT, después de las 18:00, "hoy" fuera mañana).
      const ahora = new Date()
      const hoy = hoyISO()
      const inicioMes = fechaLocalISO(new Date(ahora.getFullYear(), ahora.getMonth(), 1))
      // fin de una cita = fecha + hora_fin (o hora_inicio si no hay); inicio = fecha + hora_inicio
      const finDe = (c: { fecha: string; hora_inicio: string | null; hora_fin?: string | null }) =>
        combinar(c.fecha, c.hora_fin || c.hora_inicio).getTime()
      const inicioDe = (c: { fecha: string; hora_inicio: string | null }) => combinar(c.fecha, c.hora_inicio).getTime()

      // Citas de hoy
      const { count: citasHoyCount } = await supabase
        .from('citas')
        .select('*', { count: 'exact', head: true })
        .eq('medico_id', user.id)
        .eq('fecha', hoy)

      // Pendientes de confirmar (solicitada + agendada) que todavía no terminaron: una vieja sin cerrar no cuenta.
      const { data: pendientesData } = await supabase
        .from('citas')
        .select('fecha, hora_inicio, hora_fin')
        .eq('medico_id', user.id)
        .in('estado', ['solicitada', 'agendada'])
        .gte('fecha', hoy)
      const pendientesCount = (pendientesData || []).filter((c) => finDe(c) >= ahora.getTime()).length

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

      // Próxima cita confirmada o agendada: la primera que todavía no empezó (las de hoy ya pasadas no cuentan).
      // Sin join para evitar schema cache bug.
      const { data: candidatas } = await supabase
        .from('citas')
        .select('*')
        .eq('medico_id', user.id)
        .in('estado', ['confirmada', 'agendada'])
        .gte('fecha', hoy)
        .order('fecha', { ascending: true })
        .order('hora_inicio', { ascending: true })
        .limit(50)
      const proximaData = (candidatas || []).find((c) => inicioDe(c) >= ahora.getTime()) ?? null

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
