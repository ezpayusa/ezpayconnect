import type { RecetaItem } from '@/types'

// UX del front: que categorias muestran el recuadro de acuse en la receta.
// La barrera REAL es server-side: public.emitir_receta (mig 249) lee
// medicamentos_categorias.requiere_acuse y lanza PR007. Esto solo decide si
// se PIDE el acuse en pantalla; si el front se equivoca, el server rechaza igual.
// categoria NULL = sin clasificar = NO regulado (fail-safe, decision A1).
//
// 'recetario_especial' YA NO es una categoria (mig 248): paso a ser la columna
// requiere_recetario_especial. Las categorias que exigen acuse hoy son
// psicotropico y estupefaciente. Si el abogado agrega una categoria con
// requiere_acuse=true, hay que sumarla aca O—mejor—leer la tabla (pendiente).
export const CATEGORIAS_REGULADAS = ['psicotropico', 'estupefaciente'] as const

export function esRegulado(categoria?: string | null): boolean {
  return !!categoria && (CATEGORIAS_REGULADAS as readonly string[]).includes(categoria)
}

export function etiquetaCategoria(categoria?: string | null): string {
  switch (categoria) {
    case 'psicotropico': return 'psicotrópico'
    case 'estupefaciente': return 'estupefaciente'
    default: return 'regulado'
  }
}

// Estado de UI de un item de receta. `categoria_regulatoria` NO es columna de
// receta_items: se lee del catalogo (useMedicamentos hace select('*')) solo para
// decidir si se pide el acuse. NO se manda al servidor — emitir_receta la lee del
// catalogo y la congela en receta_items.acuse_categoria (snapshot server-side).
export type ItemRecetaUI = Partial<RecetaItem> & { categoria_regulatoria?: string | null }
