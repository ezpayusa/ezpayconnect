// Nombres de los médicos de las visitas del proveedor (mig 354).
//
// El proveedor ya no lee la tabla medicos ni perfiles: los nombres salen de la RPC nombres_medicos_visitas, que solo
// resuelve médicos que aparecen en visitas que el llamante puede ver (mismo criterio que la RLS de
// visitas_agendadas) y no devuelve email. Un id que la RPC no resuelve se muestra como "Sin nombre".
import { supabase } from '@/lib/supabase'

export interface NombreMedico {
  nombre_completo: string
  especialidad: string | null
}

export const SIN_NOMBRE = 'Sin nombre'

type FilaRpc = { medico_id: string; nombre_completo: string | null; especialidad: string | null }

/** Ids distintos y no vacíos, en el orden en que aparecen. */
export function idsUnicos(ids: Array<string | null | undefined>): string[] {
  return [...new Set(ids.filter((x): x is string => !!x))]
}

/** Filas de la RPC → mapa id → nombre/especialidad. Descarta filas sin id. */
export function mapaNombres(filas: FilaRpc[] | null | undefined): Record<string, NombreMedico> {
  const mapa: Record<string, NombreMedico> = {}
  for (const f of filas ?? []) {
    if (!f?.medico_id) continue
    mapa[f.medico_id] = { nombre_completo: (f.nombre_completo ?? '').trim(), especialidad: f.especialidad?.trim() || null }
  }
  return mapa
}

/** Nombre a mostrar: el resuelto, o "Sin nombre" si no hay id, no se resolvió o viene vacío. */
export function nombreMedico(mapa: Record<string, NombreMedico>, id: string | null | undefined): string {
  if (!id) return SIN_NOMBRE
  return mapa[id]?.nombre_completo || SIN_NOMBRE
}

/** Llama a nombres_medicos_visitas con los ids únicos. Sin ids no llama. El error se devuelve, no se traga. */
export async function resolverNombresMedicos(
  ids: Array<string | null | undefined>,
): Promise<{ mapa: Record<string, NombreMedico>; error: { code?: string; message?: string } | null }> {
  const unicos = idsUnicos(ids)
  if (unicos.length === 0) return { mapa: {}, error: null }
  const { data, error } = await supabase.rpc('nombres_medicos_visitas', { p_medico_ids: unicos })
  if (error) return { mapa: {}, error }
  return { mapa: mapaNombres(data as FilaRpc[]), error: null }
}
