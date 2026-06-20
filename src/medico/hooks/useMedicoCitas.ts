import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import type { CitaConPaciente, FiltroCitaEstado } from '@/medico/types/medico.types'

export function useMedicoCitas() {
  const [citas, setCitas] = useState<CitaConPaciente[]>([])
  const [loading, setLoading] = useState(true)
  const [filtroEstado, setFiltroEstado] = useState<FiltroCitaEstado>('todos')

  const fetchCitas = useCallback(async () => {
    setLoading(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setCitas([])
        setLoading(false)
        return
      }

      // 1. Cargar citas SIN join (evita bug de schema cache)
      let query = supabase
        .from('citas')
        .select('*')
        .eq('medico_id', user.id)
        .order('fecha', { ascending: true })
        .order('hora_inicio', { ascending: true })

      if (filtroEstado !== 'todos') {
        query = query.eq('estado', filtroEstado)
      }

      const { data: citasData, error: citasError } = await query

      if (citasError) {
        console.error('Error cargando citas:', citasError)
        toast.error('Error cargando citas')
        setCitas([])
        setLoading(false)
        return
      }

      if (!citasData || citasData.length === 0) {
        setCitas([])
        setLoading(false)
        return
      }

      // 2. Cargar pacientes por separado
      const pacienteIds = [...new Set(citasData.map(c => c.paciente_id).filter(Boolean))]
      let pacientesMap = new Map()

      if (pacienteIds.length > 0) {
        const { data: pacientesData } = await supabase
          .from('pacientes')
          .select('id, nombre, apellido, telefono, email, auth_user_id')
          .in('id', pacienteIds)

        pacientesMap = new Map((pacientesData || []).map(p => [p.id, p]))
      }

      // 3. Combinar datos
      const citasConPaciente: CitaConPaciente[] = citasData.map((cita: any) => {
        const p = pacientesMap.get(cita.paciente_id)
        return {
          ...cita,
          paciente: p ? {
            id: p.id,
            nombre: p.nombre,
            apellido: p.apellido,
            telefono: p.telefono,
            email: p.email,
            auth_user_id: p.auth_user_id,
          } : undefined,
        }
      })

      setCitas(citasConPaciente)
    } catch (err) {
      console.error('Error:', err)
      setCitas([])
    } finally {
      setLoading(false)
    }
  }, [filtroEstado])

  useEffect(() => {
    fetchCitas()
  }, [fetchCitas])

  const enviarNotificacionPaciente = async (
    cita: CitaConPaciente,
    tipo: 'confirmada' | 'cancelada' | 'en_curso' | 'completada' | 'recordatorio'
  ) => {
    // Camino ÚNICO server-side gateado: notificar_cita_paciente verifica la relación médico/clínica→cita,
    // compone el contenido server-side, crea AMBAS notificaciones in-app (campanita + general) y dispara
    // el web-push (pg_net→edge). Reemplaza notificar_paciente + enviar-notificacion + enviar-push
    // (cierra los dos huecos de confused-deputy para el evento cita). Contenido/target ya NO los pasa el cliente.
    try {
      await supabase.rpc('notificar_cita_paciente', { p_cita_id: cita.id, p_evento: tipo })
    } catch (e) {
      console.error('Error notificar_cita_paciente:', e)
    }
  }

  const updateCitaEstado = async (cita: CitaConPaciente, nuevoEstado: CitaConPaciente['estado'], mensaje?: string) => {
    const { error } = await supabase
      .from('citas')
      .update({ estado: nuevoEstado })
      .eq('id', cita.id)

    if (error) {
      toast.error('Error: ' + error.message)
      return false
    }

    setCitas(prev => prev.map(c => c.id === cita.id ? { ...c, estado: nuevoEstado } : c))

    if (mensaje) toast.success(mensaje)

    // Enviar notificación al paciente según el nuevo estado
    if (nuevoEstado === 'confirmada') {
      await enviarNotificacionPaciente(cita, 'confirmada')
    } else if (nuevoEstado === 'cancelada') {
      await enviarNotificacionPaciente(cita, 'cancelada')
    } else if (nuevoEstado === 'en_curso') {
      await enviarNotificacionPaciente(cita, 'en_curso')
    } else if (nuevoEstado === 'completada') {
      await enviarNotificacionPaciente(cita, 'completada')
    }

    return true
  }

  const confirmarCita = async (cita: CitaConPaciente) => {
    return updateCitaEstado(cita, 'confirmada', 'Cita confirmada correctamente')
  }

  const rechazarCita = async (cita: CitaConPaciente) => {
    return updateCitaEstado(cita, 'cancelada', 'Cita cancelada correctamente')
  }

  const marcarEnSala = async (cita: CitaConPaciente) => {
    return updateCitaEstado(cita, 'en_curso', 'Paciente en sala de consulta')
  }

  const completarCita = async (cita: CitaConPaciente) => {
    return updateCitaEstado(cita, 'completada', 'Cita completada')
  }

  return {
    citas,
    loading,
    filtroEstado,
    setFiltroEstado,
    fetchCitas,
    confirmarCita,
    rechazarCita,
    marcarEnSala,
    completarCita,
  }
}
