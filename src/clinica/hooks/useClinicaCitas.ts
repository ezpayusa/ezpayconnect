import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import type { CitaConPaciente, FiltroCitaEstado } from '@/medico/types/medico.types'

export interface ClinicaOption {
  id: string
  nombre: string
}

export function useClinicaCitas() {
  const [citas, setCitas] = useState<CitaConPaciente[]>([])
  const [loading, setLoading] = useState(true)
  const [filtroEstado, setFiltroEstado] = useState<FiltroCitaEstado>('todos')
  const [medicosClinica, setMedicosClinica] = useState<{ id: string; nombre_completo: string; especialidad: string | null }[]>([])
  const [clinicas, setClinicas] = useState<ClinicaOption[]>([])
  const [clinicaId, setClinicaId] = useState<string | null>(null)
  const [clinicaNombre, setClinicaNombre] = useState<string | null>(null)

  const fetchClinicaYCitas = useCallback(async () => {
    setLoading(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setCitas([])
        setLoading(false)
        return
      }

      // 1. Obtener TODAS las clínicas del usuario via RPC
      const { data: clinicasRel, error: clinicasError } = await supabase
        .rpc('obtener_clinica_usuario', { p_user_id: user.id })

      if (clinicasError) {
        console.error('Error cargando clínicas:', clinicasError)
        toast.error('Error cargando clínicas')
        setLoading(false)
        return
      }

      const clinicasList: ClinicaOption[] = (clinicasRel || []).map((c: any) => ({
        id: c.clinica_id,
        nombre: c.clinica_nombre || 'Clínica sin nombre',
      }))

      setClinicas(clinicasList)

      if (clinicasList.length === 0) {
        console.warn('[useClinicaCitas] Usuario sin clínica asociada')
        setCitas([])
        setLoading(false)
        return
      }

      // Si hay una sola clínica, usarla. Si hay múltiples y no hay seleccionada, usar la primera
      const currentClinicaId = clinicaId || clinicasList[0].id
      const currentClinicaNombre = clinicasList.find(c => c.id === currentClinicaId)?.nombre || clinicasList[0].nombre

      if (!clinicaId) {
        setClinicaId(currentClinicaId)
      }
      setClinicaNombre(currentClinicaNombre)

      // 2. Cargar médicos de la clínica seleccionada
      const { data: relMedicos } = await supabase
        .rpc('obtener_medicos_clinica', { p_clinica_id: currentClinicaId })

      const medicoIds = relMedicos?.map((r: any) => r.medico_id) || []

      // Cargar datos de todos los médicos disponibles para asignar
      const { data: todosMedicos } = await supabase
        .rpc('listar_medicos_por_pais')

      const todosMedicosList = (todosMedicos || []) as any[]
      const medicosFiltrados = todosMedicosList
        .filter((m: any) => medicoIds.includes(m.id))
        .map((m: any) => ({
          id: m.id,
          nombre_completo: m.nombre_completo,
          especialidad: m.especialidad || null,
        }))
      setMedicosClinica(medicosFiltrados)

      // 3. Cargar citas de la clínica via RPC (bypass RLS)
      const { data: citasData, error: citasError } = await supabase
        .rpc('obtener_citas_clinica', { p_clinica_id: currentClinicaId })

      if (citasError) {
        console.error('Error cargando citas:', citasError)
        toast.error('Error cargando citas')
        setCitas([])
        setLoading(false)
        return
      }

      let citasList = (citasData || []) as any[]

      if (filtroEstado !== 'todos') {
        citasList = citasList.filter((c: any) => c.estado === filtroEstado)
      }

      // 4. Mapear al formato del frontend
      const citasConPaciente: CitaConPaciente[] = citasList.map((cita: any) => ({
        id: cita.id,
        medico_id: cita.medico_id,
        paciente_id: cita.paciente_id,
        clinica_id: cita.clinica_id,
        fecha: cita.fecha,
        hora_inicio: cita.hora_inicio,
        hora_fin: cita.hora_fin,
        motivo: cita.motivo,
        estado: cita.estado,
        notas: cita.notas,
        created_at: cita.created_at,
        paciente: cita.paciente_id ? {
          id: cita.paciente_id,
          nombre: cita.paciente_nombre || '',
          apellido: cita.paciente_apellido || '',
          telefono: cita.paciente_telefono || null,
          email: cita.paciente_email || null,
          auth_user_id: cita.paciente_auth_user_id,
        } : undefined,
      }))

      setCitas(citasConPaciente)
    } catch (err) {
      console.error('Error:', err)
      setCitas([])
    } finally {
      setLoading(false)
    }
  }, [filtroEstado, clinicaId])

  useEffect(() => {
    fetchClinicaYCitas()
  }, [fetchClinicaYCitas])

  const cambiarClinica = useCallback((nuevaClinicaId: string) => {
    setClinicaId(nuevaClinicaId)
    const nombre = clinicas.find(c => c.id === nuevaClinicaId)?.nombre || null
    setClinicaNombre(nombre)
  }, [clinicas])

  const updateCitaEstado = async (cita: CitaConPaciente, nuevoEstado: CitaConPaciente['estado'], mensaje?: string) => {
    const { error } = await supabase
      .rpc('actualizar_estado_cita', {
        p_cita_id: cita.id,
        p_estado: nuevoEstado,
      })

    if (error) {
      toast.error('Error: ' + error.message)
      return false
    }

    setCitas(prev => prev.map(c => c.id === cita.id ? { ...c, estado: nuevoEstado } : c))
    if (mensaje) toast.success(mensaje)
    return true
  }

  const asignarMedico = async (cita: CitaConPaciente, medicoId: string) => {
    const { error } = await supabase
      .rpc('asignar_medico_cita', {
        p_cita_id: cita.id,
        p_medico_id: medicoId,
      })

    if (error) {
      toast.error('Error asignando médico: ' + error.message)
      return false
    }

    // Obtener nombre del médico asignado
    const medico = medicosClinica.find(m => m.id === medicoId)
    const medicoNombre = medico?.nombre_completo || 'asignado'

    setCitas(prev => prev.map(c => c.id === cita.id ? { ...c, medico_id: medicoId, estado: 'agendada' } : c))
    toast.success('Médico asignado correctamente')

    // Notificar al paciente
    const pacienteAuthId = (cita.paciente as any)?.auth_user_id
    if (pacienteAuthId) {
      try {
        await enviarNotificacionPaciente(pacienteAuthId, cita, 'cita_asignada', medicoNombre)
      } catch (err) {
        console.error('[useClinicaCitas] Error notificando paciente:', err)
      }
    } else {
      console.warn('[useClinicaCitas] Paciente sin auth_user_id, no se puede notificar. paciente_id:', cita.paciente_id)
    }

    return true
  }

  const enviarNotificacionPaciente = async (
    pacienteAuthId: string,
    cita: CitaConPaciente,
    tipo: 'cita_asignada' | 'cita_confirmada' | 'cita_cancelada',
    medicoNombre?: string
  ) => {
    const fechaStr = new Date(cita.fecha).toLocaleDateString('es-GT', {
      weekday: 'long', month: 'long', day: 'numeric',
    })

    let titulo: string
    let mensaje: string

    switch (tipo) {
      case 'cita_confirmada':
        titulo = 'Tu cita ha sido confirmada'
        mensaje = `Tu cita para el ${fechaStr} a las ${cita.hora_inicio?.slice(0, 5)} ha sido confirmada.`
        break
      case 'cita_cancelada':
        titulo = 'Tu cita ha sido cancelada'
        mensaje = `Tu cita para el ${fechaStr} a las ${cita.hora_inicio?.slice(0, 5)} ha sido cancelada.`
        break
      default:
        titulo = 'Médico asignado a tu cita'
        mensaje = `Tu cita para el ${fechaStr} a las ${cita.hora_inicio?.slice(0, 5)} ha sido asignada al Dr. ${medicoNombre || 'tu médico'}.`
    }

    const url = '/paciente/citas'

    console.log('[useClinicaCitas] Enviando notificación a:', pacienteAuthId)

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
      console.log('[useClinicaCitas] Notificación campanita creada')
    } catch (e) {
      console.error('Error notificación campanita:', e)
    }

    // Notificación in-app (tabla general 'notificaciones', otros paneles)
    try {
      await supabase.functions.invoke('enviar-notificacion', {
        body: {
          usuario_id: pacienteAuthId,
          tipo,
          titulo,
          mensaje,
          accion_url: url,
          metadata: { cita_id: cita.id, paciente_id: cita.paciente_id },
        },
      })
      console.log('[useClinicaCitas] Notificación in-app enviada')
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
      console.log('[useClinicaCitas] Push notification enviada')
    } catch (e) {
      console.error('Error push notification:', e)
    }
  }

  const confirmarCita = async (cita: CitaConPaciente) => {
    const result = await updateCitaEstado(cita, 'confirmada', 'Cita confirmada correctamente')
    if (result) {
      const pacienteAuthId = (cita.paciente as any)?.auth_user_id
      if (pacienteAuthId) {
        try {
          await enviarNotificacionPaciente(pacienteAuthId, cita, 'cita_confirmada')
        } catch (err) {
          console.error('[useClinicaCitas] Error notificando paciente:', err)
        }
      } else {
        console.warn('[useClinicaCitas] Paciente sin auth_user_id, no se puede notificar confirmación. paciente_id:', cita.paciente_id)
      }
    }
    return result
  }

  const rechazarCita = async (cita: CitaConPaciente) => {
    const result = await updateCitaEstado(cita, 'cancelada', 'Cita cancelada correctamente')
    if (result) {
      const pacienteAuthId = (cita.paciente as any)?.auth_user_id
      if (pacienteAuthId) {
        try {
          await enviarNotificacionPaciente(pacienteAuthId, cita, 'cita_cancelada')
        } catch (err) {
          console.error('[useClinicaCitas] Error notificando paciente:', err)
        }
      }
    }
    return result
  }

  return {
    citas,
    loading,
    filtroEstado,
    setFiltroEstado,
    medicosClinica,
    clinicas,
    clinicaId,
    clinicaNombre,
    cambiarClinica,
    fetchCitas: fetchClinicaYCitas,
    confirmarCita,
    rechazarCita,
    asignarMedico,
  }
}
