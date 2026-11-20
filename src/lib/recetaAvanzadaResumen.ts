import { folioReceta, type RecetaParaFolio } from '@/lib/folioReceta'

// H24: las tarjetas de «Recetas Avanzadas» del expediente mostraban la firma cruda (FIRMADO-…Z).
// Ahora muestran el folio oficial de la receta base (folioReceta, H12) y sus medicamentos.

export interface ItemResumen {
  receta_id: number
  nombre_medicamento: string | null
  dosis?: string | null
}

export interface ResumenRecetaAvanzada {
  folio: string
  medicamentos: string[]
}

/**
 * Arma el resumen de la tarjeta. Si la receta base no se pudo leer (RLS u otro error), el folio cae a
 * «Receta #<id>» y la lista de medicamentos queda vacía: nunca se muestra la firma.
 */
export function resumenRecetaAvanzada(
  recetaBaseId: number,
  base: RecetaParaFolio | undefined,
  items: ItemResumen[],
  cedula?: string | null,
): ResumenRecetaAvanzada {
  const folio = base ? folioReceta(base, cedula) : `Receta #${recetaBaseId}`
  const medicamentos = items
    .filter(i => i.receta_id === recetaBaseId && i.nombre_medicamento)
    .map(i => (i.dosis ? `${i.nombre_medicamento} — ${i.dosis}` : (i.nombre_medicamento as string)))
  return { folio, medicamentos }
}
