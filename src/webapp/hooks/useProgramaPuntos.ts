import { useState, useCallback, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'

export interface Premio {
  id: number
  nombre: string
  descripcion: string | null
  costo_puntos: number
  tipo: string
  stock: number
  imagen_path: string | null
  ya_canjeado: boolean  // true si el paciente ya tiene un canje vigente (no rechazado) de este premio
}

export interface MiCanje {
  canje_id: number
  estado: 'pendiente' | 'aprobado' | 'rechazado' | 'entregado'
  costo_puntos: number
  solicitado_at: string
  resuelto_at: string | null
  premio_nombre: string
  premio_tipo: string
  nota_resolucion: string | null
}

/**
 * Programa de premios — lado PACIENTE (webapp). Consume:
 *  - saldo_puntos_paciente() → saldo
 *  - listar_premios_disponibles() → { saldo, premios[] } (filtrados por país del paciente)
 *  - mis_canjes() → solicitudes propias
 *  - solicitar_canje(_premio_id) → reserva (queda 'pendiente' de aprobación)
 */
export function useProgramaPuntos() {
  const [saldo, setSaldo] = useState(0)
  const [premios, setPremios] = useState<Premio[]>([])
  const [misCanjes, setMisCanjes] = useState<MiCanje[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const cargar = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [saldoRes, listaRes, canjesRes] = await Promise.all([
        supabase.rpc('saldo_puntos_paciente'),
        supabase.rpc('listar_premios_disponibles'),
        supabase.rpc('mis_canjes'),
      ])
      if (saldoRes.error) throw saldoRes.error
      if (listaRes.error) throw listaRes.error
      if (canjesRes.error) throw canjesRes.error
      setSaldo((saldoRes.data as any)?.saldo ?? 0)
      setPremios(((listaRes.data as any)?.premios ?? []) as Premio[])
      setMisCanjes((Array.isArray(canjesRes.data) ? canjesRes.data : []) as MiCanje[])
    } catch (err: any) {
      setError(err.message || 'Error cargando el programa de puntos')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { cargar() }, [cargar])

  const canjear = useCallback(async (premioId: number): Promise<boolean> => {
    const { error } = await supabase.rpc('solicitar_canje', { _premio_id: premioId })
    if (error) {
      const m = error.message || ''
      const msg = /saldo_insuficiente/.test(m) ? 'No tenés puntos suficientes para este premio.'
        : /premio_no_disponible/.test(m) ? 'El premio ya no está disponible (sin stock).'
        : /premio_otro_pais/.test(m) ? 'Ese premio no está disponible en tu país.'
        : 'No se pudo procesar el canje.'
      toast.error(msg)
      return false
    }
    toast.success('Solicitud enviada. Queda pendiente de aprobación.')
    await cargar()
    return true
  }, [cargar])

  return { saldo, premios, misCanjes, loading, error, recargar: cargar, canjear }
}
