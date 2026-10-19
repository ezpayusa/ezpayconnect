// Textos legales de GL-02 (D-8): el cuerpo vive en estos .md del repo y la base guarda un catálogo mínimo
// (public.textos_legales: codigo, version, aplica_a, exigible, md5). Cada .md tiene que ser byte a byte el que dio el md5
// sembrado por la mig 371 (UTF-8, LF, sin BOM); src/legal/index.test.ts lo verifica y .gitattributes fuerza eol=lf.
// El catálogo sin contenido vive en ./catalogo (lo usa el chunk de entrada); este módulo le suma el cuerpo de cada texto
// y solo lo importa la página pública del texto.
import terminosMd from './terminos.md?raw'
import privacidadMd from './privacidad.md?raw'
import consentimientoSaludMd from './consentimiento-salud.md?raw'
import condicionesProfesionalesMd from './condiciones-profesionales.md?raw'
import { TEXTOS_LEGALES, type CodigoTextoLegal, type TextoLegal } from './catalogo'

export * from './catalogo'

export interface TextoLegalConContenido extends TextoLegal {
  contenido: string
}

const CONTENIDO: Record<CodigoTextoLegal, string> = {
  terminos: terminosMd,
  privacidad: privacidadMd,
  consentimiento_salud: consentimientoSaludMd,
  condiciones_profesionales: condicionesProfesionalesMd,
}

export function textoLegalPorCodigo(codigo: string): TextoLegalConContenido | undefined {
  const texto = TEXTOS_LEGALES.find((t) => t.codigo === codigo)
  return texto ? { ...texto, contenido: CONTENIDO[texto.codigo] } : undefined
}
