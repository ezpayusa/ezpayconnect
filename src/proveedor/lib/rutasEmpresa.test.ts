import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import { rutaHomeEmpresa, rutaLoginEmpresa } from './rutasEmpresa'

describe('rutaHomeEmpresa: tabla tipo × rol', () => {
  it.each([
    // farmacia
    ['farmacia', 'visitador_medico', '/visitador'],
    ['farmacia', 'delivery', '/repartidor'],
    ['farmacia', 'admin', '/farmacia/dashboard'],
    ['farmacia', 'cajero', '/farmacia/dashboard'],
    // laboratorio clínico
    ['laboratorio_clinico', 'visitador_medico', '/visitador'],
    ['laboratorio_clinico', 'delivery', '/laboratorio/dashboard'],
    ['laboratorio_clinico', 'admin', '/laboratorio/dashboard'],
    ['laboratorio_clinico', 'cajero', '/laboratorio/dashboard'],
    // laboratorio farmacéutico
    ['laboratorio_farmaceutico', 'visitador_medico', '/visitador'],
    ['laboratorio_farmaceutico', 'delivery', '/proveedor/dashboard'],
    ['laboratorio_farmaceutico', 'admin', '/proveedor/dashboard'],
    ['laboratorio_farmaceutico', 'cajero', '/proveedor/dashboard'],
    // empresa afín
    ['empresa_afin', 'visitador_medico', '/visitador'],
    ['empresa_afin', 'delivery', '/proveedor/dashboard'],
    ['empresa_afin', 'admin', '/proveedor/dashboard'],
    ['empresa_afin', 'cajero', '/proveedor/dashboard'],
    // tipo ausente o desconocido
    [null, 'admin', '/proveedor/dashboard'],
    [undefined, 'admin', '/proveedor/dashboard'],
    ['otro', 'admin', '/proveedor/dashboard'],
    [null, null, '/proveedor/dashboard'],
    [undefined, undefined, '/proveedor/dashboard'],
  ])('%s × %s → %s', (tipo, rol, destino) => {
    expect(rutaHomeEmpresa(tipo, rol)).toBe(destino)
  })

  it('el visitador va a /visitador aunque el tipo sea farmacia (se evalúa antes que el tipo)', () => {
    expect(rutaHomeEmpresa('farmacia', 'visitador_medico')).toBe('/visitador')
  })

  it('un delivery de una empresa que NO es farmacia va al panel de proveedor, no a /repartidor', () => {
    expect(rutaHomeEmpresa('laboratorio_clinico', 'delivery')).not.toBe('/repartidor')
    expect(rutaHomeEmpresa('laboratorio_farmaceutico', 'delivery')).toBe('/proveedor/dashboard')
    expect(rutaHomeEmpresa('empresa_afin', 'delivery')).toBe('/proveedor/dashboard')
    expect(rutaHomeEmpresa(null, 'delivery')).toBe('/proveedor/dashboard')
  })
})

describe('rutaLoginEmpresa', () => {
  it.each([
    ['farmacia', '/farmacia/login'],
    ['laboratorio_clinico', '/laboratorio/login'],
    ['laboratorio_farmaceutico', '/proveedor/login'],
    ['empresa_afin', '/proveedor/login'],
    [null, '/proveedor/login'],
    ['otro', '/proveedor/login'],
  ])('%s → %s', (tipo, login) => {
    expect(rutaLoginEmpresa(tipo)).toBe(login)
  })
})

// Censo: los tres logins de empresa delegan el destino en rutaHomeEmpresa. Un navigate a un panel
// escrito a mano en un login es exactamente lo que dejaba a una cuenta en el panel equivocado según por
// dónde entrara.
describe('censo: los logins de empresa usan rutaHomeEmpresa', () => {
  const LOGINS = [
    'src/proveedor/pages/ProveedorLogin.tsx',
    'src/farmacia/pages/FarmaciaLogin.tsx',
    'src/laboratorio/pages/LabLogin.tsx',
  ]
  const DESTINOS_A_MANO = [
    "navigate('/repartidor'",
    "navigate('/visitador'",
    "navigate('/farmacia/dashboard'",
    "navigate('/laboratorio/dashboard'",
    "navigate('/proveedor/dashboard'",
  ]

  it.each(LOGINS)('%s delega en rutaHomeEmpresa y no decide destinos a mano', (archivo) => {
    const src = fs.readFileSync(archivo, 'utf8')
    expect(src, `${archivo} no llama a rutaHomeEmpresa(`).toContain('rutaHomeEmpresa(')
    for (const d of DESTINOS_A_MANO) {
      expect(src.includes(d), `${archivo} decide un destino a mano: ${d}`).toBe(false)
    }
  })

  it.each(LOGINS)('%s lee rol_en_empresa en el select de cuentas_proveedor', (archivo) => {
    const src = fs.readFileSync(archivo, 'utf8')
    const m = src.match(/\.from\('cuentas_proveedor'\)\s*\.select\('([^']*)'\)/)
    expect(m, `${archivo}: no encontré .from('cuentas_proveedor').select('…')`).not.toBeNull()
    expect(m![1], `${archivo}: el select no trae rol_en_empresa`).toContain('rol_en_empresa')
  })
})

// Si un guard cambia lo que exige, el destino que da rutaHomeEmpresa puede dejar de ser alcanzable
// (o el guard rebota a la cuenta a otro panel). Este test avisa para revisar los dos juntos.
describe('coherencia con los guards de los PWA', () => {
  it("RepartidorPrivateRoute sigue exigiendo rol 'delivery' Y empresa tipo 'farmacia'", () => {
    const src = fs.readFileSync('src/repartidor/components/RepartidorPrivateRoute.tsx', 'utf8')
    expect(src, 'RepartidorPrivateRoute cambió su condición: revisar rutaHomeEmpresa').toContain(
      "if (cuenta.rol_en_empresa !== 'delivery' || empresa?.tipo !== 'farmacia') {",
    )
  })

  it("VisitadorPrivateRoute sigue exigiendo solo rol 'visitador_medico'", () => {
    const src = fs.readFileSync('src/visitador/components/VisitadorPrivateRoute.tsx', 'utf8')
    expect(src, 'VisitadorPrivateRoute cambió su condición: revisar rutaHomeEmpresa').toContain(
      "if (cuenta.rol_en_empresa !== 'visitador_medico') {",
    )
  })
})
