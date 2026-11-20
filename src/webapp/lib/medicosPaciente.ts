import { supabase } from '@/lib/supabase'

// Nombres de los médicos que el PACIENTE puede ver, por id. El paciente no lee `perfiles` ajenos
// (solo aplican "Ver propio perfil" y la de admin), así que esa lectura le devolvía 0 filas y la
// receta caía en el placeholder «Médico asignado». Fuentes que el paciente ya puede leer:
//   1. la RPC obtener_medicos_por_ids (DEFINER, mig 357): el médico de una cita que el paciente ve;
//   2. la tabla medicos, policy "Paciente ve medicos de su pais" (SELECT por columna desde la 375:
//      hay que listar las columnas, nunca select('*')).
// La 2 solo se consulta para los ids que la 1 no resolvió. Un error de cualquiera de las dos deja
// esos ids sin nombre (el llamador pone el placeholder); no rompe la pantalla.
type Cliente = Pick<typeof supabase, 'rpc' | 'from'>

export async function nombresMedicosParaPaciente(
  ids: string[],
  cliente: Cliente = supabase
): Promise<Record<string, string>> {
  const nombres: Record<string, string> = {}
  const unicos = [...new Set(ids.filter(Boolean))]
  if (unicos.length === 0) return nombres

  const { data: rpc } = await cliente.rpc('obtener_medicos_por_ids', { p_medico_ids: unicos })
  for (const m of (rpc ?? []) as { id: string; nombre_completo: string | null }[]) {
    if (m.id && m.nombre_completo?.trim()) nombres[m.id] = m.nombre_completo
  }

  const faltan = unicos.filter((id) => !nombres[id])
  if (faltan.length > 0) {
    const { data: meds } = await cliente.from('medicos').select('id, nombre_completo').in('id', faltan)
    for (const m of (meds ?? []) as { id: string; nombre_completo: string | null }[]) {
      if (m.id && m.nombre_completo?.trim()) nombres[m.id] = m.nombre_completo
    }
  }
  return nombres
}
