import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import { ROLES_QUE_EXIGEN_PAIS, rolExigePais } from './rolesPais'

// Ruta desde la raíz del repo (vitest corre con cwd = raíz; mismo patrón que api.test.ts).
const EDGE = 'supabase/functions/crear-empleado/index.ts'

/** Extrae la lista `const ROLES_QUE_EXIGEN_PAIS = [...]` del fuente de la edge, o null si no la encuentra. */
function rolesDeLaEdge(src: string): string[] | null {
  const m = src.match(/const\s+ROLES_QUE_EXIGEN_PAIS\s*=\s*\[([^\]]*)\]/)
  if (!m) return null
  return Array.from(m[1].matchAll(/['"]([^'"]+)['"]/g), x => x[1])
}

describe('rolExigePais', () => {
  it.each(['admin_pais', 'asesor_comercial', 'supervisor_comercial'])('%s exige país', (rol) => {
    expect(rolExigePais(rol)).toBe(true)
  })

  it.each(['medico', 'super_admin', 'soporte', '', null, undefined])('%s no exige país', (rol) => {
    expect(rolExigePais(rol)).toBe(false)
  })
})

describe('sincronía con la edge crear-empleado', () => {
  it('ROLES_QUE_EXIGEN_PAIS del front es la misma lista que la de la edge', () => {
    const src = fs.readFileSync(EDGE, 'utf8')
    const edge = rolesDeLaEdge(src)
    // Nunca pasar en vacío: si la edge cambió la forma de declararla, el test lo dice.
    if (edge === null) {
      throw new Error(`no encontré la declaración "const ROLES_QUE_EXIGEN_PAIS = [...]" en ${EDGE}`)
    }
    expect(edge.length, 'la lista de la edge vino vacía').toBeGreaterThan(0)
    expect([...edge].sort()).toEqual([...ROLES_QUE_EXIGEN_PAIS].sort())
  })
})
