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
    const pacienteAuthId = (cita.paciente as any)?.auth_user_id

    const fechaStr = new Date(cita.fecha).toLocaleDateString('es-GT', {
      weekday: 'long', month: 'long', day: 'numeric',
    })
    const horaStr = cita.hora_inicio?.slice(0, 5)

    let titulo = ''
    let mensaje = ''
    const url = '/paciente/citas'
    // tipo para la tabla general 'notificaciones' (otros paneles)
    let tipoGeneral = 'recordatorio_cita'

    if (tipo === 'confirmada') {
      titulo = 'Cita confirmada'
      mensaje = `Tu cita para el ${fechaStr} a las ${horaStr} ha sido confirmada por el médico.`
      tipoGeneral = 'cita_confirmada'
    } else if (tipo === 'cancelada') {
      titulo = 'Cita cancelada'
      mensaje = `Tu cita para el ${fechaStr} a las ${horaStr} ha sido cancelada. Por favor agenda una nueva cita.`
      tipoGeneral = 'cita_cancelada'
    } else if (tipo === 'en_curso') {
      titulo = 'Tu consulta ha comenzado'
      mensaje = `El médico te ha llamado a consulta para tu cita del ${fechaStr} a las ${horaStr}.`
      tipoGeneral = 'cita_en_curso'
    } else if (tipo === 'completada') {
      titulo = 'Consulta completada'
      mensaje = `Tu consulta del ${fechaStr} a las ${horaStr} ha finalizado. Revisa tus recetas y órdenes de examen si aplica.`
      tipoGeneral = 'cita_completada'
    } else {
      titulo = 'Recordatorio de cita'
      mensaje = `Recordatorio: tienes una cita el ${fechaStr} a las ${horaStr}.`
      tipoGeneral = 'recordatorio_cita'
    }

    // Campanita del webapp del paciente (tabla notificaciones_pacientes).
    // Vía RPC SECURITY DEFINER porque el RLS solo permite al propio paciente.
    // El hook useWebAppNotificaciones tiene realtime, así que aparece al instante.
    try {
      await supabase.rpc('notificar_paciente', {
        p_paciente_id: cita.paciente_id,
        p_tipo: 'cita',
        p_titulo: titulo,
        p_mensaje: mensaje,
        p_accion_url: url,
      })
    } catch (e) {
      console.error('Error notificación campanita:', e)
    }

    if (!pacienteAuthId) {
      console.warn('Paciente sin auth_user_id, no se envían in-app/push')
      return
    }

    // Notificación in-app (tabla general 'notificaciones')
    try {
      await supabase.functions.invoke('enviar-notificacion', {
        body: {
          usuario_id: pacienteAuthId,
          tipo: tipoGeneral,
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
