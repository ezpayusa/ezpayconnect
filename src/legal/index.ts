// Textos legales de GL-02 (D-8): el cuerpo vive en estos .md del repo y la base guarda un catálogo mínimo
// (public.textos_legales: codigo, version, aplica_a, exigible, md5). Cada .md tiene que ser byte a byte el que dio el md5
// sembrado por la mig 371 (UTF-8, LF, sin BOM); src/legal/index.test.ts lo verifica y .gitattributes fuerza eol=lf.
// Cambiar un texto = cambiar el .md, su md5 acá y en la base (migración que sube la versión, D-5).
import terminosMd from './terminos.md?raw'
import privacidadMd from './privacidad.md?raw'
import consentimientoSaludMd from './consentimiento-salud.md?raw'
import condicionesProfesionalesMd from './condiciones-profesionales.md?raw'

export type CodigoTextoLegal = 'terminos' | 'privacidad' | 'consentimiento_salud' | 'condiciones_profesionales'
export type AplicaA = 'todos' | 'paciente' | 'profesional'

export interface TextoLegal {
  codigo: CodigoTextoLegal
  /** Versión vigente, mismo formato que textos_legales.version (^[0-9]{1,3}\.[0-9]{1,3}$). */
  version: string
  /** md5 de los bytes UTF-8 del .md; igual a textos_legales.md5. */
  md5: string
  titulo: string
  ruta: string
  aplica_a: readonly AplicaA[]
  contenido: string
}

export const TEXTOS_LEGALES: readonly TextoLegal[] = [
  {
    codigo: 'terminos',
    version: '0.1',
    md5: '5eb1698ca0a0d9809c0b63482b41ff57',
    titulo: 'Términos y Condiciones de Uso',
    ruta: '/terminos',
    aplica_a: ['todos'],
    contenido: terminosMd,
  },
  {
    codigo: 'privacidad',
    version: '0.1',
    md5: 'd2a181910741a1994e9f2487907b7f9e',
    titulo: 'Aviso y Política de Privacidad',
    ruta: '/privacidad',
    aplica_a: ['todos'],
    contenido: privacidadMd,
  },
  {
    codigo: 'consentimiento_salud',
    version: '0.1',
    md5: '41d9e576b5e5157f030bbfc577f45e66',
    titulo: 'Consentimiento informado para el tratamiento de datos de salud',
    ruta: '/consentimiento-salud',
    aplica_a: ['paciente'],
    contenido: consentimientoSaludMd,
  },
  {
    codigo: 'condiciones_profesionales',
    version: '0.1',
    md5: 'c716f13e1fd19225dfac4b7ac248a456',
    titulo: 'Condiciones para profesionales de la salud y empresas',
    ruta: '/condiciones-profesionales',
    aplica_a: ['profesional'],
    contenido: condicionesProfesionalesMd,
  },
]

export function textoLegalPorCodigo(codigo: string): TextoLegal | undefined {
  return TEXTOS_LEGALES.find((t) => t.codigo === codigo)
}
