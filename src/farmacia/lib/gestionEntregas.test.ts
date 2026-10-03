import { describe, it, expect } from 'vitest'
import {
  mensajeErrorEntrega, entregaQueFallo, puedeAsignar, puedeReasignar, sucursalUnica,
  MENSAJES_ENTREGAS, MENSAJE_GENERICO_ENTREGAS,
} from './gestionEntregas'

const pg = (code: string, details: string | null = null) => ({ code, message: 'texto de la base', details })

describe('mensajeErrorEntrega (errcodes de la mig 353)', () => {
  it.each(['42501', 'DE001', 'DE002', 'DE003', 'DE004', 'DE005', 'DE006', 'DE007', 'DE008', 'DE009'])('%s tiene mensaje propio en espanol', (code) => {
    const m = mensajeErrorEntrega(pg(code))
    expect(m).toBe(MENSAJES_ENTREGAS[code])
    expect(m).not.toMatch(/texto de la base/)
  })
  it('en la tanda antepone el folio de la entrega que fallo (DETAIL)', () => {
    expect(mensajeErrorEntrega(pg('DE002', '149'))).toBe(`GT-149: ${MENSAJES_ENTREGAS.DE002}`)
    expect(mensajeErrorEntrega(pg('DE004', ' 151 '))).toBe(`GT-151: ${MENSAJES_ENTREGAS.DE004}`)
  })
  it('un DE desconocido muestra el codigo, no el generico', () => {
    expect(mensajeErrorEntrega(pg('DE099'))).toBe('No se pudo completar la operación (DE099).')
  })
  it('sin codigo (red) o codigo ajeno -> generico, sin folio', () => {
    expect(mensajeErrorEntrega(null)).toBe(MENSAJE_GENERICO_ENTREGAS)
    expect(mensajeErrorEntrega({ message: 'Failed to fetch' })).toBe(MENSAJE_GENERICO_ENTREGAS)
    expect(mensajeErrorEntrega(pg('P0001', '149'))).toBe(MENSAJE_GENERICO_ENTREGAS)
  })
  it('entregaQueFallo solo acepta un id numerico', () => {
    expect(entregaQueFallo(pg('DE001', '153'))).toBe(153)
    expect(entregaQueFallo(pg('DE001', 'entrega 153'))).toBeNull()
    expect(entregaQueFallo(pg('DE001', ''))).toBeNull()
    expect(entregaQueFallo(null)).toBeNull()
  })
})

describe('reglas de asignacion (espejo de asignar_entrega / reasignar_entrega)', () => {
  const e = (estado: Parameters<typeof puedeAsignar>[0]['estado'], cobrado = false, farmacia_id = 1) => ({ estado, cobrado, farmacia_id })
  it('se asigna solo desde pendiente', () => {
    expect(puedeAsignar(e('pendiente'))).toBe(true)
    for (const s of ['asignada', 'en_camino', 'entregada', 'fallida'] as const) expect(puedeAsignar(e(s))).toBe(false)
  })
  it('se reasigna desde asignada, en_camino o fallida, si no esta cobrada', () => {
    for (const s of ['asignada', 'en_camino', 'fallida'] as const) {
      expect(puedeReasignar(e(s))).toBe(true)
      expect(puedeReasignar(e(s, true))).toBe(false)
    }
    expect(puedeReasignar(e('pendiente'))).toBe(false)
    expect(puedeReasignar(e('entregada'))).toBe(false)
  })
  it('una tanda es de una sola sucursal', () => {
    expect(sucursalUnica([])).toBeNull()
    expect(sucursalUnica([{ farmacia_id: 3 }, { farmacia_id: 3 }])).toBe(3)
    expect(sucursalUnica([{ farmacia_id: 3 }, { farmacia_id: 5 }])).toBeNull()
  })
})
