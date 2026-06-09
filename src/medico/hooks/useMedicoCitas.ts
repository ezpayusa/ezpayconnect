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
    tipo: 'confirmada' | 'cancelada' | 'recordatorio'
  ) => {
    const pacienteAuthId = (cita.paciente as any)?.auth_user_id
    if (!pacienteAuthId) {
      console.warn('Paciente sin auth_user_id, no se puede notificar')
      return
    }

    const nombrePaciente = cita.paciente
      ? `${cita.paciente.nombre} ${cita.paciente.apellido}`
      : 'Paciente'

    const fechaStr = new Date(cita.fecha).toLocaleDateString('es-GT', {
      weekday: 'long', month: 'long', day: 'numeric',
    })

    let titulo = ''
    let mensaje = ''
    let url = '/paciente/citas'

    if (tipo === 'confirmada') {
      titulo = 'Cita confirmada'
      mensaje = `Tu cita para el ${fechaStr} a las ${cita.hora_inicio?.slice(0, 5)} ha sido confirmada por el médico.`
    } else if (tipo === 'cancelada') {
      titulo = 'Cita cancelada'
      mensaje = `Tu cita para el ${fechaStr} a las ${cita.hora_inicio?.slice(0, 5)} ha sido cancelada. Por favor agenda una nueva cita.`
    } else {
      titulo = 'Recordatorio de cita'
      mensaje = `Recordatorio: tienes una cita el ${fechaStr} a las ${cita.hora_inicio?.slice(0, 5)}.`
    }

    // Notificación in-app
    try {
      await supabase.functions.invoke('enviar-notificacion', {
        body: {
          usuario_id: pacienteAuthId,
          tipo: tipo === 'confirmada' ? 'cita_confirmada' : tipo === 'cancelada' ? 'cita_cancelada' : 'recordatorio_cita',
          titulo,
          mensaje,
          accion_url: url,
          metadata: { cita_id: cita.id, paciente_id: cita.paciente_id },
        },
      })
    } catch (e) {
      console.error('Error notificación in-app:', e)
    }

    // Push notification
    try {
      await supabase.functions.invoke('enviar-push', {
        body: {
          usuario_ids: [pacienteAuthId],
          titulo,
          mensaje,
          url,
          tag: `cita-${cita.id}`,
        },
      })
    } catch (e) {
      console.error('Error push notification:', e)
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

    // Enviar notificación al paciente si es confirmada o cancelada
    if (nuevoEstado === 'confirmada') {
      await enviarNotificacionPaciente(cita, 'confirmada')
    } else if (nuevoEstado === 'cancelada') {
      await enviarNotificacionPaciente(cita, 'cancelada')
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
