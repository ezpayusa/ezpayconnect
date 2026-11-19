import { describe, it, expect } from 'vitest'
import { hayCambiosNota, type SoapForm } from './notaCambios'

const VACIO: SoapForm = { motivo_consulta: '', subjetivo: '', objetivo: '', analisis: '', plan: '', diagnostico: '' }
const base: SoapForm = { ...VACIO, motivo_consulta: 'Control', subjetivo: 'Dolor' }
const args = (soap: SoapForm, extra: Partial<Parameters<typeof hayCambiosNota>[0]> = {}) =>
  ({ soap, base, soloLectura: false, corrigiendo: false, motivoCorreccion: '', ...extra })

describe('hayCambiosNota (H3)', () => {
  it('igual a la base: sin cambios', () => {
    expect(hayCambiosNota(args({ ...base }))).toBe(false)
  })

  it('cualquier campo distinto: hay cambios', () => {
    expect(hayCambiosNota(args({ ...base, plan: 'Reposo' }))).toBe(true)
    expect(hayCambiosNota(args({ ...base, motivo_consulta: '' }))).toBe(true)
  })

  it('nota nueva: la base es el estado inicial con el motivo de la cita', () => {
    const inicial = { ...VACIO, motivo_consulta: 'Fiebre' }
    expect(hayCambiosNota(args({ ...inicial }, { base: inicial }))).toBe(false)
    expect(hayCambiosNota(args({ ...inicial, subjetivo: 'x' }, { base: inicial }))).toBe(true)
  })

  it('solo lectura: nunca hay cambios', () => {
    expect(hayCambiosNota(args({ ...base, plan: 'Reposo' }, { soloLectura: true }))).toBe(false)
  })

  it('cargando (sin base): sin cambios', () => {
    expect(hayCambiosNota(args({ ...base, plan: 'x' }, { base: null }))).toBe(false)
  })

  it('corrección: un motivo escrito cuenta aunque los campos no cambien; solo espacios no', () => {
    expect(hayCambiosNota(args({ ...base }, { corrigiendo: true, motivoCorreccion: 'Error de tipeo' }))).toBe(true)
    expect(hayCambiosNota(args({ ...base }, { corrigiendo: true, motivoCorreccion: '   ' }))).toBe(false)
    expect(hayCambiosNota(args({ ...base, plan: 'nuevo' }, { corrigiendo: true }))).toBe(true)
  })

  it('el motivo de corrección fuera del modo corrección no cuenta', () => {
    expect(hayCambiosNota(args({ ...base }, { motivoCorreccion: 'algo' }))).toBe(false)
  })
})
