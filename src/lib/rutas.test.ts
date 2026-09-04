import { describe, it, expect } from 'vitest'
import { rutaHomePorRol } from './rutas'

// Los 13 códigos de roles_catalogo, medidos contra la base 2026-09-04. La función es pura, así que
// esto cubre TODOS los roles — incluidos los que no tienen cuenta con contraseña conocida y por lo
// tanto no se pueden clickear en un navegador.
const PAIS = 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909'

describe('rutaHomePorRol — destino de cada rol del catálogo', () => {
  it.each([
    ['medico', '/medico'],
    ['super_admin', '/admin-ezpay'],
    ['secretaria', '/clinica/calendario'],
    ['asesor_comercial', '/comercial'],
    ['supervisor_comercial', '/comercial'],
    ['admin_clinica', '/dashboard'],
    ['asistente_medico', '/dashboard'],   // devuelto a su destino previo: tiene una cuenta real
    ['cliente', '/sin-panel'],
    ['enfermeria', '/sin-panel'],
    ['gerente', '/sin-panel'],
    ['soporte', '/sin-panel'],
    ['vendedor', '/sin-panel'],
  ])('%s -> %s', (rol, esperado) => {
    expect(rutaHomePorRol({ rol })).toBe(esperado)
  })

  it('admin_pais con país va a su panel; sin país (cuenta rota) NO cae en el panel clínico', () => {
    expect(rutaHomePorRol({ rol: 'admin_pais', pais_id: PAIS })).toBe(`/admin-ezpay/pais/${PAIS}`)
    expect(rutaHomePorRol({ rol: 'admin_pais', pais_id: null })).toBe('/sin-panel')
  })

  it('un rol que todavía no existe NO aterriza en una pantalla ajena', () => {
    for (const p of [{ rol: 'rol_del_futuro' }, { rol: '' }, { rol: null }, {}, null, undefined]) {
      expect(rutaHomePorRol(p as never)).toBe('/sin-panel')
    }
  })
})
