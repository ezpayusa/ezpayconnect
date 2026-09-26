import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { ExpedienteNota } from '@/types'

interface CrearConsultaData {
  cita_id?: number | null
  paciente_id: number
  motivo_consulta?: string
  subjetivo?: string
  objetivo?: string
  analisis?: string
  plan?: string
  diagnostico?: string
}

export interface SoapNota {
  motivo_consulta: string | null
  subjetivo: string | null
  objetivo: string | null
  analisis: string | null
  plan: string | null
  diagnostico: string | null
}

/** Los rechazos NTnnn (mig 334) y el 42501 traen el mensaje para el usuario: se muestran tal cual. */
export function mensajeErrorNota(error: { code?: string | null; message: string }, prefijo = 'Error: '): string {
  return error.code?.startsWith('NT') || error.code === '42501' ? error.message : prefijo + error.message
}

export function useConsultas() {
  const [consultas, setConsultas] = useState<ExpedienteNota[]>([])
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
      console.error('Error cargando consultas:', error?.message ?? error?.code)
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
      console.error('Error cargando consulta:', error?.message ?? error?.code)
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

    // errorCode: la pantalla necesita distinguir NT006 (la nota se cerró mientras estaba abierta).
    if (consultaId) {
      const { error } = await supabase
        .from('expediente_notas')
        .update(payload)
        .eq('id', consultaId)
      setSaving(false)
      return { error: error?.message || null, errorCode: error?.code ?? null }
    } else {
      const { data: result, error } = await supabase
        .from('expediente_notas')
        .insert(payload)
        .select()
        .single()
      setSaving(false)
      return { data: result as ExpedienteNota | null, error: error?.message || null, errorCode: error?.code ?? null }
    }
  }, [])

  // Mig 334 (P4): una nota cerrada solo cambia por esta RPC, con motivo. Se mandan SIEMPRE los 6
  // campos: son la versión nueva completa (la RPC compara contra la vigente, NT005 si no cambia nada).
  const corregirNota = useCallback(async (notaId: number, soap: SoapNota, motivo: string) => {
    setSaving(true)
    const { data, error } = await supabase.rpc('corregir_nota_consulta', {
      p_nota_id: notaId,
      p_motivo: motivo,
      p_motivo_consulta: soap.motivo_consulta,
      p_subjetivo: soap.subjetivo,
      p_objetivo: soap.objetivo,
      p_analisis: soap.analisis,
      p_plan: soap.plan,
      p_diagnostico: soap.diagnostico,
    })
    setSaving(false)
    return {
      data: data as { nota_id: number; revision: number; corregida_at: string } | null,
      error: error ? mensajeErrorNota(error) : null,
    }
  }, [])

  return {
    consultas,
    loading,
    saving,
    fetchConsultasPorPaciente,
    fetchConsultaPorCita,
    crearOActualizarConsulta,
    corregirNota,
  }
}
