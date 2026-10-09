// Catálogo de los textos legales de GL-02, SIN el contenido: código, versión, md5, título, ruta y a quién aplica.
// Lo importan el guard, /aceptar-textos, la casilla de las altas y src/lib/textosLegales.ts, que van en el chunk de
// entrada o cerca: por eso acá no se importa ningún .md (src/legal/index.test.ts lo verifica). El cuerpo de cada texto
// vive en src/legal/index.ts, que solo carga la página pública del texto (lazy).
// Cambiar un texto = cambiar el .md, su md5 acá y en la base (migración que sube la versión, D-5).

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
}

export const TEXTOS_LEGALES: readonly TextoLegal[] = [
  {
    codigo: 'terminos',
    version: '0.1',
    md5: '5eb1698ca0a0d9809c0b63482b41ff57',
    titulo: 'Términos y Condiciones de Uso',
    ruta: '/terminos',
    aplica_a: ['todos'],
  },
  {
    codigo: 'privacidad',
    version: '0.1',
    md5: 'd2a181910741a1994e9f2487907b7f9e',
    titulo: 'Aviso y Política de Privacidad',
    ruta: '/privacidad',
    aplica_a: ['todos'],
  },
  {
    codigo: 'consentimiento_salud',
    version: '0.1',
    md5: '41d9e576b5e5157f030bbfc577f45e66',
    titulo: 'Consentimiento informado para el tratamiento de datos de salud',
    ruta: '/consentimiento-salud',
    aplica_a: ['paciente'],
  },
  {
    codigo: 'condiciones_profesionales',
    version: '0.1',
    md5: 'c716f13e1fd19225dfac4b7ac248a456',
    titulo: 'Condiciones para profesionales de la salud y empresas',
    ruta: '/condiciones-profesionales',
    aplica_a: ['profesional'],
  },
]
