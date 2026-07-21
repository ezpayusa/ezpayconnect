import { supabase } from '@/lib/supabase'

let sesionId = ''
try {
  sesionId = crypto.randomUUID()
} catch {
  sesionId = Math.random().toString(36).substring(2) + Date.now().toString(36)
}

export async function registrarMetricaCampana(
  campanaId: number,
  opciones: {
    clickeado?: boolean
    contexto?: string
    tipoPerfil?: 'paciente' | 'medico' | 'admin' | 'visitador' | 'clinica'
    pacienteId?: number
    paisId?: string
  } = {}
) {
  try {
    const { data: { user } } = await supabase.auth.getUser()
    const perfilId = user?.id || null

    await supabase.rpc('registrar_campana_metrica', {
      p_campana_id: campanaId,
      p_perfil_id: perfilId,
      p_paciente_id: opciones.pacienteId || null,
      p_tipo_perfil: opciones.tipoPerfil || 'desconocido',
      p_sesion_id: sesionId,
      p_clickeado: opciones.clickeado || false,
      p_contexto: opciones.contexto || null,
      p_pais_id: opciones.paisId || null,
    })
  } catch (err) {
    console.error('Error registrando métrica:', err)
  }
}

export function expandirCampanasPorPeso<T extends { peso?: number }>(
  campanas: T[]
): T[] {
  const resultado: T[] = []
  campanas.forEach((c) => {
    const repeticiones = Math.max(1, c.peso || 1)
    for (let i = 0; i < repeticiones; i++) {
      resultado.push(c)
    }
  })
  // Mezclar aleatoriamente para que no siempre aparezca primero la de mayor peso
  return resultado.sort(() => Math.random() - 0.5)
}

const MAX_IMPRESIONES_POR_DIA = 20

export async function filtrarCampanasPorFrequencyCap<T extends { id: number }>(
  campanas: T[]
): Promise<T[]> {
  try {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return campanas

    // RPC SECURITY DEFINER: impresiones (24h) del propio usuario por campaña. El .from directo antes
    // caía en la RLS super_admin-only → [] → el cap nunca se aplicaba.
    const { data } = await supabase.rpc('mis_impresiones_campana_recientes')

    const conteo: Record<number, number> = {}
    ;(data || []).forEach((row: any) => {
      conteo[row.campana_id] = Number(row.impresiones) || 0
    })

    return campanas.filter((c) => (conteo[c.id] || 0) < MAX_IMPRESIONES_POR_DIA)
  } catch (err) {
    console.error('Error en frequency capping:', err)
    return campanas
  }
}
