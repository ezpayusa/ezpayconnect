import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'

// Tipos locales (sin precedente en repo). Catálogo = filas activas de consentimiento_permisos;
// estado vigente = salida de estado_consentimiento_paciente.
export interface PermisoCatalogo {
  codigo: string
  version: number
  etiqueta: string
  texto_legal: string
}
export interface ConsentimientoVigente {
  codigo: string
  concedido: boolean
  via: string
  permiso_version: number
  created_at: string
}

/**
 * Camino "app paciente" del consentimiento (Ola B, slice 1). Patrón useSignosVitalesCita:
 * estados locales + supabase.rpc/select + toast en error + recarga tras mutación.
 * Lectura del catálogo por SELECT directo (authenticated tiene SELECT); estado + escritura por RPC DEFINER.
 */
export function useConsentimientoPaciente(pacienteId: number | undefined) {
  const [catalogo, setCatalogo] = useState<PermisoCatalogo[]>([])
  const [estado, setEstado] = useState<ConsentimientoVigente[]>([])
  const [cargando, setCargando] = useState(true)

  const cargarCatalogo = useCallback(async () => {
    const { data, error } = await supabase
      .from('consentimiento_permisos')
      .select('codigo,version,etiqueta,texto_legal')
      .eq('activo', true)
      .order('codigo', { ascending: true })
      .order('version', { ascending: false })
    if (error) { toast.error(error.message); return }
    const rows = Array.isArray(data) ? (data as PermisoCatalogo[]) : []
    // Dedup: primera ocurrencia por codigo = mayor version activa (espejo del resolver server-side).
    const vistos = new Set<string>()
    const ultimas = rows.filter((r) => (vistos.has(r.codigo) ? false : (vistos.add(r.codigo), true)))
    ultimas.sort((a, b) => a.etiqueta.localeCompare(b.etiqueta))
    setCatalogo(ultimas)
  }, [])

  const cargarEstado = useCallback(async () => {
    if (!pacienteId) { setEstado([]); return }
    const { data, error } = await supabase.rpc('estado_consentimiento_paciente', { p_paciente_id: pacienteId })
    if (error) { toast.error(error.message); return }
    setEstado(Array.isArray(data) ? (data as ConsentimientoVigente[]) : [])
  }, [pacienteId])

  const recargar = useCallback(async () => {
    setCargando(true)
    await Promise.all([cargarCatalogo(), cargarEstado()])
    setCargando(false)
  }, [cargarCatalogo, cargarEstado])

  useEffect(() => { recargar() }, [recargar])

  const registrar = useCallback(async (pid: number, codigo: string, concedido: boolean): Promise<boolean> => {
    const { error } = await supabase.rpc('registrar_consentimiento', {
      p_paciente_id: pid,
      p_permiso_codigo: codigo,
      p_concedido: concedido,
      p_via: 'app',
      p_documento_id: null, // server resuelve version; app no pasa documento
    })
    if (error) { toast.error(error.message); return false }
    toast.success(concedido ? 'Autorización concedida' : 'Autorización revocada')
    await cargarEstado()
    return true
  }, [cargarEstado])

  return { catalogo, estado, cargando, registrar, recargar }
}
