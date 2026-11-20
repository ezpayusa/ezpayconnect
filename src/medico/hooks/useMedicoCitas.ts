import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { cambiarEstadoCita } from '@/lib/estadoCita'
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
        console.error('Error cargando citas:', citasError?.message ?? citasError?.code)
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
      console.error('Error:', err?.message ?? err?.code)
      setCitas([])
    } finally {
      setLoading(false)
    }
  }, [filtroEstado])

  useEffect(() => {
    fetchCitas()
  }, [fetchCitas])

  // H5/H6: el UPDATE y el aviso al paciente van por cambiarEstadoCita (src/lib/estadoCita.ts), el mismo
  // camino que usa la consulta; 0 filas (mig 391) es un error, no un éxito.
  const updateCitaEstado = async (cita: CitaConPaciente, nuevoEstado: CitaConPaciente['estado'], mensaje?: string) => {
    const r = await cambiarEstadoCita(cita.id, nuevoEstado)
    if (!r.ok) {
      toast.error(r.mensaje)
      return false
    }

    setCitas(prev => prev.map(c => c.id === cita.id ? { ...c, estado: nuevoEstado } : c))

    if (mensaje) toast.success(mensaje)
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

  // El expediente antes que el estado. Esta pantalla escribe la tabla `citas` directo, igual que
  // ConsultaPage, así que la barrera real no está acá: es el trigger trg_exigir_nota_al_completar
  // (mig 291), que devuelve PE001 con este mismo texto. Este chequeo es cortesía — le ahorra al
  // médico un error que viene de la base — y por eso no importa que sea evitable.
  const completarCita = async (cita: CitaConPaciente) => {
    const { count, error } = await supabase
      .from('expediente_notas')
      .select('id', { count: 'exact', head: true })
      .eq('cita_id', cita.id)

    if (error) {
      toast.error('No se pudo verificar la nota de la consulta: ' + error.message)
      return false
    }
    if (!count) {
      toast.error('Debe guardar la nota de la consulta antes de finalizar')
      return false
    }
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
