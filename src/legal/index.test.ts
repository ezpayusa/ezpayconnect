import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { TEXTOS_LEGALES } from './index'

// El md5 declarado de cada texto es el que sembró la mig 371 en public.textos_legales. Si un .md cambia un solo byte
// (incluido un CRLF de un checkout de Windows), este test falla.
describe('src/legal: catálogo de textos legales', () => {
  it.each(TEXTOS_LEGALES.map((t) => [t.codigo, t] as const))('%s: md5 del contenido = md5 declarado', (_codigo, t) => {
    const md5 = createHash('md5').update(Buffer.from(t.contenido, 'utf8')).digest('hex')
    expect(md5).toBe(t.md5)
  })

  it('declara exactamente los 4 códigos de la base, sin duplicados', () => {
    const codigos = TEXTOS_LEGALES.map((t) => t.codigo)
    expect(new Set(codigos).size).toBe(codigos.length)
    expect([...codigos].sort()).toEqual(['condiciones_profesionales', 'consentimiento_salud', 'privacidad', 'terminos'])
  })

  it('la versión tiene el formato de textos_legales.version', () => {
    for (const t of TEXTOS_LEGALES) expect(t.version).toMatch(/^[0-9]{1,3}\.[0-9]{1,3}$/)
  })

  it('las rutas son únicas y empiezan con /', () => {
    const rutas = TEXTOS_LEGALES.map((t) => t.ruta)
    expect(new Set(rutas).size).toBe(rutas.length)
    for (const r of rutas) expect(r.startsWith('/')).toBe(true)
  })

  it('aplica_a está dentro de {todos, paciente, profesional}', () => {
    const permitidos = new Set(['todos', 'paciente', 'profesional'])
    for (const t of TEXTOS_LEGALES) {
      expect(t.aplica_a.length).toBeGreaterThan(0)
      for (const a of t.aplica_a) expect(permitidos.has(a)).toBe(true)
    }
  })
})
