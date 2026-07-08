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
        console.error('Error cargando clínicas:', clinicasError?.message ?? clinicasError?.code)
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
        console.error('Error cargando citas:', citasError?.message ?? citasError?.code)
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
      console.error('Error:', err?.message ?? err?.code)
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
        console.error('[useClinicaCitas] Error notificando paciente:', err?.message ?? err?.code)
      }
    } else {
      console.warn('[useClinicaCitas] Paciente sin auth_user_id, no se puede notificar. paciente_id:', cita.paciente_id)
    }

    return true
  }

  const enviarNotificacionPaciente = async (
    _pacienteAuthId: string,
    cita: CitaConPaciente,
    tipo: 'cita_asignada' | 'cita_confirmada' | 'cita_cancelada',
    _medicoNombre?: string
  ) => {
    // Camino ÚNICO server-side gateado: notificar_cita_paciente verifica la relación clínica→cita
    // (clinicas_del_usuario), compone el contenido server-side (incluye nombre del médico para 'asignada')
    // y crea AMBAS notificaciones in-app (campanita + general) + web-push. Reemplaza notificar_paciente
    // + enviar-notificacion + enviar-push (cierra los dos huecos de confused-deputy para el evento cita).
    const evento = tipo === 'cita_asignada' ? 'asignada' : tipo === 'cita_confirmada' ? 'confirmada' : 'cancelada'
    try {
      await supabase.rpc('notificar_cita_paciente', { p_cita_id: cita.id, p_evento: evento })
    } catch (e) {
      console.error('Error notificar_cita_paciente:', e?.message ?? e?.code)
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
          console.error('[useClinicaCitas] Error notificando paciente:', err?.message ?? err?.code)
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
          console.error('[useClinicaCitas] Error notificando paciente:', err?.message ?? err?.code)
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
