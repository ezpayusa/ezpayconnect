import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

// Columnas del calendario: médicos de la clínica, en tiempo real desde listar_medicos_clinica (RPC DEFINER).
export interface MedicoColumna {
  medico_id: string
  nombre_completo: string
  es_principal: boolean
}

export interface CitaCalendario {
  cita_id: number
  medico_id: string | null
  paciente_id: number
  paciente_nombre: string
  paciente_apellido: string
  paciente_telefono: string | null
  foto_path: string | null
  fecha: string
  hora_inicio: string
  hora_fin: string | null
  estado: string
  motivo: string | null
  notas: string | null
}

export interface VisitaCalendario {
  visita_id: string
  medico_id: string
  medico_nombre: string
  empresa_id: string | null
  empresa_nombre: string | null
  fecha_visita: string
  hora_inicio: string
  hora_fin: string | null
  estado: string
  confirmado_presente_clinica_at: string | null
  confirmado_presente_clinica_por: string | null
}

export interface PacienteBusqueda {
  paciente_id: number
  nombre: string
  apellido: string
  telefono: string | null
  fecha_nacimiento: string | null
  foto_path: string | null
}

export interface NuevoPacienteDatos {
  nombre: string
  apellido: string
  telefono?: string | null
  fecha_nacimiento?: string | null
  genero?: string | null
  email?: string | null
  pais_id?: string | null
}

export interface NuevaCitaDatos {
  paciente_id: number
  medico_id: string
  fecha: string
  hora_inicio: string
  hora_fin?: string | null
  motivo?: string | null
  pais_id?: string | null
}

export type ModoCalendario = 'citas' | 'visitas'

// yyyy-mm-dd en hora LOCAL (no UTC → evita corrimiento de día en TZ negativas).
export function fechaLocalISO(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${dd}`
}

/**
 * Datos del calendario de clínica. Toda la lectura pasa por RPCs DEFINER (mig 232):
 * las columnas de médicos y las citas/visitas se leen server-side (la RLS actual no
 * alcanza para todos los roles del calendario). `fecha` es el día visible (Date local).
 */
export function useCalendarioClinica(clinicaId: string | null | undefined, fecha: Date, modo: ModoCalendario) {
  const [medicos, setMedicos] = useState<MedicoColumna[]>([])
  const [citas, setCitas] = useState<CitaCalendario[]>([])
  const [visitas, setVisitas] = useState<VisitaCalendario[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const diaISO = fechaLocalISO(fecha)

  const cargarMedicos = useCallback(async () => {
    if (!clinicaId) return
    const { data, error } = await supabase.rpc('listar_medicos_clinica', { p_clinica_id: clinicaId })
    if (error) { setError(error.message); return }
    setMedicos((data as MedicoColumna[]) || [])
  }, [clinicaId])

  const cargarEventos = useCallback(async () => {
    if (!clinicaId) return
    setLoading(true)
    setError(null)
    try {
      if (modo === 'citas') {
        const { data, error } = await supabase.rpc('listar_citas_clinica', {
          p_clinica_id: clinicaId, p_desde: diaISO, p_hasta: diaISO,
        })
        if (error) throw error
        setCitas((data as CitaCalendario[]) || [])
      } else {
        const { data, error } = await supabase.rpc('listar_visitas_clinica', {
          p_clinica_id: clinicaId, p_desde: diaISO, p_hasta: diaISO,
        })
        if (error) throw error
        setVisitas((data as VisitaCalendario[]) || [])
      }
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [clinicaId, diaISO, modo])

  useEffect(() => { cargarMedicos() }, [cargarMedicos])
  useEffect(() => { cargarEventos() }, [cargarEventos])

  // Toggle de presencia del visitador (registro paralelo; no toca estado ni checkin/checkout).
  const marcarPresente = useCallback(async (visitaId: string, presente: boolean) => {
    const { data, error } = await supabase.rpc('marcar_visitador_presente', {
      p_visita_id: visitaId, p_presente: presente,
    })
    if (error) return { error }
    // Refrescar la fila en el estado local con lo que devolvió la RPC ({presente, at, por}).
    const res = data as { presente: boolean; at: string | null; por: string | null }
    setVisitas((prev) => prev.map((v) => v.visita_id === visitaId
      ? { ...v, confirmado_presente_clinica_at: res.at, confirmado_presente_clinica_por: res.por }
      : v))
    return { data: res }
  }, [])

  // Búsqueda de pacientes de la clínica (para adjuntar a una cita nueva). RPC DEFINER (mig 233).
  const buscarPacientes = useCallback(async (texto: string): Promise<PacienteBusqueda[]> => {
    if (!clinicaId) return []
    const { data, error } = await supabase.rpc('buscar_pacientes_clinica', { p_clinica_id: clinicaId, p_texto: texto })
    if (error) { console.error('[calendario] buscar_pacientes_clinica:', error); return [] }
    return (data as PacienteBusqueda[]) || []
  }, [clinicaId])

  // Alta de paciente por staff (registro completo, sin auth_user_id). RPC DEFINER (mig 233).
  const crearPaciente = useCallback(async (datos: NuevoPacienteDatos): Promise<{ id?: number; error?: any }> => {
    if (!clinicaId) return { error: { message: 'Sin clínica activa' } }
    const { data, error } = await supabase.rpc('crear_paciente_clinica', {
      p_clinica_id: clinicaId,
      p_nombre: datos.nombre,
      p_apellido: datos.apellido,
      p_telefono: datos.telefono || null,
      p_fecha_nacimiento: datos.fecha_nacimiento || null,
      p_genero: datos.genero || null,
      p_email: datos.email || null,
      p_pais_id: datos.pais_id || null,
    })
    if (error) return { error }
    return { id: data as number }
  }, [clinicaId])

  // Creación de cita por staff (rama c de crear_cita, mig 231). Refresca la vista al terminar.
  const crearCita = useCallback(async (datos: NuevaCitaDatos): Promise<{ id?: number; error?: any }> => {
    if (!clinicaId) return { error: { message: 'Sin clínica activa' } }
    const { data, error } = await supabase.rpc('crear_cita', {
      p_paciente_id: datos.paciente_id,
      p_medico_id: datos.medico_id,
      p_clinica_id: clinicaId,
      p_fecha: datos.fecha,
      p_hora_inicio: datos.hora_inicio,
      p_hora_fin: datos.hora_fin || null,
      p_motivo: datos.motivo || null,
      p_estado: 'agendada',
      p_pais_id: datos.pais_id || null,
    })
    if (error) return { error }
    await cargarEventos()
    return { id: data as number }
  }, [clinicaId, cargarEventos])

  return { medicos, citas, visitas, loading, error, marcarPresente, buscarPacientes, crearPaciente, crearCita, recargar: cargarEventos, recargarMedicos: cargarMedicos }
}
