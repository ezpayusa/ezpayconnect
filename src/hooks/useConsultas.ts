import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { ExpedienteNota, SignosVitales } from '@/types'

interface CrearConsultaData {
  cita_id?: number | null
  paciente_id: number
  motivo_consulta?: string
  subjetivo?: string
  objetivo?: string
  analisis?: string
  plan?: string
  diagnostico?: string
  presion_arterial?: string
  frecuencia_cardiaca?: number
  frecuencia_respiratoria?: number
  temperatura?: number
  peso_kg?: number
  talla_cm?: number
  imc?: number
  saturacion_o2?: number
  glucosa?: number
}

export function useConsultas() {
  const [consultas, setConsultas] = useState<ExpedienteNota[]>([])
  const [signosVitales, setSignosVitales] = useState<SignosVitales[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchConsultasPorPaciente = useCallback(async (pacienteId: number) => {
    setLoading(true)
    const { data, error } = await supabase
      .from('expediente_notas')
      .select('*')
      .eq('paciente_id', pacienteId)
      .order('created_at', { ascending: false })

    if (error) {
      console.error('Error cargando consultas:', error)
      setConsultas([])
    } else {
      setConsultas(data || [])
    }
    setLoading(false)
  }, [])

  const fetchConsultaPorCita = useCallback(async (citaId: number) => {
    setLoading(true)
    const { data, error } = await supabase
      .from('expediente_notas')
      .select('*')
      .eq('cita_id', citaId)
      .maybeSingle()

    if (error) {
      console.error('Error cargando consulta:', error)
      setLoading(false)
      return null
    }
    setLoading(false)
    return data as ExpedienteNota | null
  }, [])

  const crearOActualizarConsulta = useCallback(async (data: CrearConsultaData, consultaId?: number) => {
    setSaving(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      setSaving(false)
      return { error: 'Usuario no autenticado' }
    }

    const payload = {
      ...data,
      medico_id: user.id,
    }

    if (consultaId) {
      const { error } = await supabase
        .from('expediente_notas')
        .update(payload)
        .eq('id', consultaId)
      setSaving(false)
      return { error: error?.message || null }
    } else {
      const { data: result, error } = await supabase
        .from('expediente_notas')
        .insert(payload)
        .select()
        .single()
      setSaving(false)
      return { data: result as ExpedienteNota | null, error: error?.message || null }
    }
  }, [])

  const fetchSignosVitalesPorPaciente = useCallback(async (pacienteId: number) => {
    setLoading(true)
    const { data, error } = await supabase
      .from('signos_vitales')
      .select('*')
      .eq('paciente_id', pacienteId)
      .order('fecha_toma', { ascending: false })
      .limit(50)

    if (error) {
      console.error('Error cargando signos vitales:', error)
      setSignosVitales([])
    } else {
      setSignosVitales(data || [])
    }
    setLoading(false)
  }, [])

  const guardarSignosVitales = useCallback(async (sv: Omit<SignosVitales, 'id' | 'created_at'>) => {
    const { data, error } = await supabase
      .from('signos_vitales')
      .insert(sv)
      .select()
      .single()

    return { data: data as SignosVitales | null, error: error?.message || null }
  }, [])

  return {
    consultas,
    signosVitales,
    loading,
    saving,
    fetchConsultasPorPaciente,
    fetchConsultaPorCita,
    crearOActualizarConsulta,
    fetchSignosVitalesPorPaciente,
    guardarSignosVitales,
  }
}
