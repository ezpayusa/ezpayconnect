import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useClinicaAuth } from './useClinicaAuth'

export interface CitaAdmision {
  id: number
  paciente_id: number
  paciente_nombre: string | null
  paciente_apellido: string | null
  medico_id: string | null
  medico_nombre: string | null
  hora_inicio: string | null
  estado: string
}

// Fecha local YYYY-MM-DD (obtener_citas_clinica devuelve `fecha` como date 'YYYY-MM-DD').
function hoyISO(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

/**
 * Cola de citas de HOY de la clínica del usuario, para el panel de Admisión.
 * obtener_citas_clinica (gate por pertenencia, mig 159) → filtra fecha===hoy en cliente →
 * resuelve nombres de médicos con obtener_medicos_por_ids (sin N+1). Ordena por hora_inicio.
 */
export function useAdmisionCitas() {
  const { clinica } = useClinicaAuth()
  const [citas, setCitas] = useState<CitaAdmision[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [tomasPorCita, setTomasPorCita] = useState<Record<number, number>>({})

  // Conteo de tomas por cita (✓ en la cola). UNA sola llamada para todas las citas de hoy (sin N+1).
  // Degrada: si la RPC falla, NO rompe la cola — queda sin ✓ (es indicador, no bloqueante).
  const cargarConteos = useCallback(async (ids: number[]) => {
    if (!ids.length) { setTomasPorCita({}); return }
    const { data, error: errConteo } = await supabase.rpc('contar_tomas_citas', { p_cita_ids: ids })
    if (errConteo) {
      console.warn('[useAdmisionCitas] conteo de tomas falló (degradado, sin ✓):', errConteo.message)
      return
    }
    setTomasPorCita(Object.fromEntries((data || []).map((r: any) => [r.cita_id, r.n])))
  }, [])

  const cargar = useCallback(async () => {
    if (!clinica) return
    setLoading(true)
    setError(null)
    try {
      const { data, error: errCitas } = await supabase.rpc('obtener_citas_clinica', { p_clinica_id: clinica.id })
      if (errCitas) throw errCitas

      const hoy = hoyISO()
      const delDia = (data || []).filter((c: any) => c.fecha === hoy)

      // Resolver nombres de médicos asignados (una sola llamada, no por cita).
      const medicoIds = [...new Set(delDia.map((c: any) => c.medico_id).filter(Boolean))] as string[]
      let nombres: Record<string, string> = {}
      if (medicoIds.length) {
        const { data: meds } = await supabase.rpc('obtener_medicos_por_ids', { p_medico_ids: medicoIds })
        nombres = Object.fromEntries((meds || []).map((m: any) => [m.id, m.nombre_completo]))
      }

      const mapped: CitaAdmision[] = delDia
        .map((c: any) => ({
          id: c.id,
          paciente_id: c.paciente_id,
          paciente_nombre: c.paciente_nombre,
          paciente_apellido: c.paciente_apellido,
          medico_id: c.medico_id,
          medico_nombre: c.medico_id ? (nombres[c.medico_id] || null) : null,
          hora_inicio: c.hora_inicio,
          estado: c.estado,
        }))
        .sort((a: CitaAdmision, b: CitaAdmision) => (a.hora_inicio || '').localeCompare(b.hora_inicio || ''))

      setCitas(mapped)
      await cargarConteos(mapped.map((c) => c.id))
    } catch (e: any) {
      setError(e.message || 'Error cargando citas')
      setCitas([])
    } finally {
      setLoading(false)
    }
  }, [clinica, cargarConteos])

  useEffect(() => { cargar() }, [cargar])

  // Refresca SOLO los conteos de las citas ya cargadas (post-captura), sin recargar la cola entera.
  const recargarConteos = useCallback(() => cargarConteos(citas.map((c) => c.id)), [citas, cargarConteos])

  return { citas, loading, error, recargar: cargar, tomasPorCita, recargarConteos }
}
