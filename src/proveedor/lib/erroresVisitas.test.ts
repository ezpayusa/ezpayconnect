import { describe, it, expect } from 'vitest'
import { mensajeErrorVisita, TEXTO_TURNO_TOMADO, type AccionVisita } from './erroresVisitas'

const pg = (code: string, message = '') => ({ code, message, details: null, hint: null })
const ACCIONES: AccionVisita[] = ['agendar', 'cancelar', 'administrar', 'checkin', 'checkout']

describe('mensajeErrorVisita — por código, nunca por texto', () => {
  it('PV002 al agendar muestra el mensaje del servidor con la fecha', () => {
    const msg = 'Esta fecha está reservada para el laboratorio con prioridad hasta el 2026-10-25. Puedes agendar a partir de esa fecha.'
    expect(mensajeErrorVisita(pg('PV002', msg), 'agendar')).toBe(msg)
  })

  it('PV002 y PV003 al modificar (administrar) muestran el mensaje del servidor', () => {
    expect(mensajeErrorVisita(pg('PV002', 'Reservada hasta el 2026-10-25.'), 'administrar')).toBe('Reservada hasta el 2026-10-25.')
    expect(mensajeErrorVisita(pg('PV003', 'La hora debe tener formato HH:MM.'), 'administrar')).toBe('La hora debe tener formato HH:MM.')
  })

  it('PV001 (bolsa agotada) muestra el mensaje del servidor', () => {
    expect(mensajeErrorVisita(pg('PV001', 'Bolsa de visitas agotada para el país (20 de 20 usadas)'), 'agendar'))
      .toBe('Bolsa de visitas agotada para el país (20 de 20 usadas)')
  })

  it('23505 al agendar = turno tomado', () => {
    expect(mensajeErrorVisita(pg('23505', 'duplicate key value violates unique constraint "x"'), 'agendar')).toBe(TEXTO_TURNO_TOMADO)
  })

  it('42501 -> texto de permiso del mapa', () => {
    expect(mensajeErrorVisita(pg('42501', 'no_autorizado'), 'cancelar')).toBe('No tienes permiso para esta acción.')
  })

  it.each(ACCIONES)('P0001 en %s -> texto fijo de la acción, sin leer el mensaje', (accion) => {
    const a = mensajeErrorVisita(pg('P0001', 'No autorizado para lo que sea'), accion)
    const b = mensajeErrorVisita(pg('P0001', 'otro texto cualquiera'), accion)
    expect(a).toBe(b)
    expect(a).not.toContain('No autorizado')
    expect(a.trim()).not.toBe('')
  })

  it('los textos muertos SIN_PLAN / LIMITE_MENSUAL ya no tienen trato especial', () => {
    expect(mensajeErrorVisita(pg('P0001', 'SIN_PLAN'), 'agendar')).toBe(mensajeErrorVisita(pg('P0001', 'x'), 'agendar'))
  })

  it('fallo de red (sin código) -> genérico', () => {
    expect(mensajeErrorVisita(new Error('Failed to fetch'), 'checkin')).toBe('No se pudo completar la operación. Intenta de nuevo.')
  })
})
