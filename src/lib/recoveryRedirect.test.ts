import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import { destinoRecovery } from './recoveryRedirect'

describe('destinoRecovery', () => {
  it('la raíz con type=recovery va a /set-password con el hash intacto', () => {
    expect(destinoRecovery('/', '', '#access_token=x&type=recovery'))
      .toBe('/set-password#access_token=x&type=recovery')
  })

  it('cualquier otra ruta conserva el search y el hash', () => {
    expect(destinoRecovery('/admin-ezpay', '?a=1', '#access_token=x&refresh_token=y&type=recovery'))
      .toBe('/set-password?a=1#access_token=x&refresh_token=y&type=recovery')
  })

  it('ya en /set-password no reescribe (sin loop)', () => {
    expect(destinoRecovery('/set-password', '?next=%2Fdashboard', '#access_token=x&type=recovery')).toBeNull()
  })

  it('otro type no reescribe', () => {
    expect(destinoRecovery('/', '', '#access_token=x&type=signup')).toBeNull()
  })

  it('sin hash no reescribe', () => {
    expect(destinoRecovery('/', '', '')).toBeNull()
  })

  it('el valor de type se compara exacto', () => {
    expect(destinoRecovery('/', '', '#type=recoveryX')).toBeNull()
  })
})

describe('censo: orden del import en main.tsx', () => {
  it("la primera sentencia import de main.tsx es import './lib/recoveryRedirect'", () => {
    const src = fs.readFileSync('src/main.tsx', 'utf8')
    const primera = src.split(/\r?\n/).map(l => l.trim()).find(l => /^import\b/.test(l))
    if (primera?.replace(/;$/, '') !== "import './lib/recoveryRedirect'") {
      throw new Error(
        `src/main.tsx: la primera sentencia import tiene que ser "import './lib/recoveryRedirect'" ` +
        `(reescribe el link de recovery antes de que se cree el cliente de Supabase); es: ${primera ?? '(ninguna)'}`,
      )
    }
  })
})
