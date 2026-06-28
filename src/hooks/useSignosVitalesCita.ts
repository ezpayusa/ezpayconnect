import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import type { VitalesValues } from '@/clinica/components/FormularioVitales'

export interface SignoVitalToma {
  id: number
  fecha_toma: string
  capturado_por: string | null
  capturado_por_nombre: string | null
  estado: 'declarado' | 'capturado' | 'validado' | 'corregido'
  presion_arterial: string | null
  frecuencia_cardiaca: number | null
  frecuencia_respiratoria: number | null
  temperatura: number | null
  peso_kg: number | null
  talla_cm: number | null
  imc: number | null
  saturacion_o2: number | null
  glucosa: number | null
  notas: string | null
  medico_id: string | null
  validado_por: string | null
  validado_at: string | null
}

// Mismo mapeo string→número/null que ClinicaAdmisionPage (helper num).
const num = (v: string) => (v.trim() === '' ? null : Number(v))

/**
 * Serie de signos vitales de una cita (fuente única = signos_vitales, append-only).
 * Todo por RPC DEFINER — NUNCA .from('signos_vitales') (la RLS deniega lectura/escritura directa).
 */
export function useSignosVitalesCita(citaId: number) {
  const [serie, setSerie] = useState<SignoVitalToma[]>([])
  const [cargando, setCargando] = useState(true)

  const cargarSerie = useCallback(async () => {
    if (!citaId) { setSerie([]); setCargando(false); return }
    setCargando(true)
    const { data, error } = await supabase.rpc('listar_signos_vitales_cita', { p_cita_id: citaId })
    if (error) toast.error(error.message)
    setSerie(Array.isArray(data) ? data : [])
    setCargando(false)
  }, [citaId])

  useEffect(() => { cargarSerie() }, [cargarSerie])

  const validarToma = useCallback(async (signoId: number): Promise<boolean> => {
    const { error } = await supabase.rpc('validar_signo_vital', { p_signo_id: signoId })
    if (error) { toast.error(error.message); return false }
    toast.success('Toma validada')
    await cargarSerie()
    return true
  }, [cargarSerie])

  const agregarToma = useCallback(
    async (values: VitalesValues, pacienteId: number, medicoId: string): Promise<boolean> => {
      const { error } = await supabase.rpc('capturar_signo_vital', {
        p_paciente_id: pacienteId,
        p_cita_id: citaId,
        p_medico_id: medicoId,
        p_presion_arterial: values.presion_arterial.trim() || null,
        p_frecuencia_cardiaca: num(values.frecuencia_cardiaca),
        p_frecuencia_respiratoria: num(values.frecuencia_respiratoria),
        p_temperatura: num(values.temperatura),
        p_peso_kg: num(values.peso_kg),
        p_talla_cm: num(values.talla_cm),
        p_saturacion_o2: num(values.saturacion_o2),
        p_glucosa: num(values.glucosa),
        p_notas: values.notas.trim() || null,
      })
      if (error) { toast.error(error.message); return false }
      toast.success('Toma registrada')
      await cargarSerie()
      return true
    },
    [citaId, cargarSerie],
  )

  return { serie, cargando, cargarSerie, validarToma, agregarToma }
}
