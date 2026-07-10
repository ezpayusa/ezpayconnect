import type { RecetaItem } from '@/types'

// Fuente unica de verdad del front sobre que categorias exigen acuse.
// Debe coincidir con el gate server-side de public.emitir_receta (mig 242),
// que lanza PR007 si falta el acuse. El servidor es la barrera real; esto es UX.
// categoria NULL = sin clasificar = NO regulado (fail-safe, decision A1).
export const CATEGORIAS_REGULADAS = ['psicotropico', 'estupefaciente', 'recetario_especial'] as const

export function esRegulado(categoria?: string | null): boolean {
  return !!categoria && (CATEGORIAS_REGULADAS as readonly string[]).includes(categoria)
}

export function etiquetaCategoria(categoria?: string | null): string {
  switch (categoria) {
    case 'psicotropico': return 'psicotrópico'
    case 'estupefaciente': return 'estupefaciente'
    case 'recetario_especial': return 'de recetario especial'
    default: return 'regulado'
  }
}

// Estado de UI de un item de receta. `categoria_regulatoria` NO es columna de
// receta_items: se lee del catalogo (useMedicamentos hace select('*')) solo para
// decidir si se pide el acuse. NO se manda al servidor — emitir_receta la lee del
// catalogo y la congela en receta_items.acuse_categoria (snapshot server-side).
export type ItemRecetaUI = Partial<RecetaItem> & { categoria_regulatoria?: string | null }
