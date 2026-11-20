import { supabase } from '@/lib/supabase'

// H23 (versión médico): «Prescrito pese a alergia» en el detalle y en el PDF de la receta.
//
// receta_alertas_alergia la escribe emitir_receta (mig 395) cuando el médico confirma un medicamento
// que coincide con una alergia del paciente. Su única policy de lectura es medico_id = auth.uid() (o
// super_admin): el médico autor la ve; el paciente y cualquier otro rol leen 0 filas, sin error. Por
// eso esta lectura NUNCA rompe la pantalla: ante 0 filas o un error devuelve [] y no se muestra nada.

export interface AlertaAlergiaReceta {
  medicamento: string | null
  termino: string
  motivo: string
}

type FilaAlerta = { receta_item_id: number | null; termino_alergia: string | null; motivo: string | null }
type ItemNombre = { id?: number | null; nombre_medicamento?: string | null }

export function armarAlertasAlergia(filas: FilaAlerta[], items: ItemNombre[]): AlertaAlergiaReceta[] {
  const nombrePorItem = new Map(items.filter(i => i.id != null).map(i => [i.id as number, i.nombre_medicamento ?? null]))
  return filas
    .filter(f => f.termino_alergia)
    .map(f => ({
      medicamento: f.receta_item_id != null ? nombrePorItem.get(f.receta_item_id) ?? null : null,
      termino: f.termino_alergia as string,
      motivo: (f.motivo ?? '').trim(),
    }))
}

export async function cargarAlertasAlergia(recetaId: number, items: ItemNombre[]): Promise<AlertaAlergiaReceta[]> {
  try {
    const { data, error } = await supabase
      .from('receta_alertas_alergia')
      .select('receta_item_id, termino_alergia, motivo')
      .eq('receta_id', recetaId)
    if (error || !data) return []
    return armarAlertasAlergia(data as FilaAlerta[], items)
  } catch {
    return []
  }
}

/** Una línea por alerta, para el detalle y el PDF. */
export function textoAlertaAlergia(a: AlertaAlergiaReceta): string {
  const base = a.medicamento
    ? `${a.medicamento}: coincide con la alergia «${a.termino}».`
    : `Coincide con la alergia «${a.termino}».`
  return a.motivo ? `${base} Motivo: ${a.motivo}` : base
}
