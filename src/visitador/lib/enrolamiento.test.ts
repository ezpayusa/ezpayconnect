import { describe, it, expect } from 'vitest'
import {
  parsearPrioridad, textoPrioridad, fechaBloqueadaPorPrioridad, semanasHasta, formatearFechaIso,
  validarSolicitudAlta, paramsSolicitudAlta, type DatosSolicitudAlta,
} from './enrolamiento'

describe('prioridad_para_agendar — parseo y textos', () => {
  it('parsea los 3 estados', () => {
    expect(parsearPrioridad({ estado: 'propia', fecha_minima: null, visitas_completadas: 2, visitas_limite: 8 }))
      .toEqual({ estado: 'propia', fecha_minima: null, visitas_completadas: 2, visitas_limite: 8 })
    expect(parsearPrioridad({ estado: 'otro_laboratorio', fecha_minima: '2026-10-30', visitas_completadas: null, visitas_limite: null })?.fecha_minima)
      .toBe('2026-10-30')
    expect(parsearPrioridad({ estado: 'libre', fecha_minima: null, visitas_completadas: null, visitas_limite: null })?.estado).toBe('libre')
  })

  it('forma desconocida u otro_laboratorio sin fecha -> null (no se inventa nada)', () => {
    for (const raw of [null, 'x', {}, { estado: 'raro' }, { estado: 'otro_laboratorio', fecha_minima: null }, { estado: 'otro_laboratorio', fecha_minima: '30/10/2026' }]) {
      expect(parsearPrioridad(raw)).toBeNull()
    }
  })

  it('no conserva campos extra que la RPC no promete (p. ej. un id de laboratorio)', () => {
    const p = parsearPrioridad({ estado: 'otro_laboratorio', fecha_minima: '2026-10-30', lab_prioritario_id: 'x' })
    expect(Object.keys(p!).sort()).toEqual(['estado', 'fecha_minima', 'visitas_completadas', 'visitas_limite'])
  })

  it('textos de los 3 estados', () => {
    expect(textoPrioridad({ estado: 'propia', fecha_minima: null, visitas_completadas: 3, visitas_limite: 8 }))
      .toBe('Tienes prioridad con este médico (3 de 8 visitas)')
    expect(textoPrioridad({ estado: 'propia', fecha_minima: null, visitas_completadas: null, visitas_limite: null }))
      .toBe('Tienes prioridad con este médico')
    expect(textoPrioridad({ estado: 'otro_laboratorio', fecha_minima: '2026-10-30', visitas_completadas: null, visitas_limite: null }))
      .toBe('Este médico tiene prioridad de otro laboratorio. Puedes agendar desde 30/10/2026')
    expect(textoPrioridad({ estado: 'libre', fecha_minima: null, visitas_completadas: null, visitas_limite: null })).toBeNull()
  })

  it('formatearFechaIso no corre el día por zona horaria', () => {
    expect(formatearFechaIso('2026-01-01')).toBe('01/01/2026')
  })

  it('bloqueo de fechas: solo con otro_laboratorio y estrictamente antes de fecha_minima', () => {
    const otro = { estado: 'otro_laboratorio' as const, fecha_minima: '2026-10-30', visitas_completadas: null, visitas_limite: null }
    expect(fechaBloqueadaPorPrioridad('2026-10-29', otro)).toBe(true)
    expect(fechaBloqueadaPorPrioridad('2026-10-30', otro)).toBe(false)
    expect(fechaBloqueadaPorPrioridad('2026-11-02', otro)).toBe(false)
    expect(fechaBloqueadaPorPrioridad('2026-10-01', { ...otro, estado: 'propia', fecha_minima: null })).toBe(false)
    expect(fechaBloqueadaPorPrioridad('2026-10-01', null)).toBe(false)
  })

  it('semanasHasta: semanas de lunes a domingo, nunca negativo', () => {
    const mie21 = new Date(2026, 9, 21, 10)
    expect(semanasHasta('2026-10-25', mie21)).toBe(0) // domingo de la misma semana
    expect(semanasHasta('2026-10-26', mie21)).toBe(1) // lunes siguiente
    expect(semanasHasta('2026-11-08', mie21)).toBe(2)
    expect(semanasHasta('2026-10-01', mie21)).toBe(0)
    expect(semanasHasta('2026-11-02', new Date(2026, 9, 25, 23))).toBe(2) // desde un domingo
  })
})

const ok: DatosSolicitudAlta = {
  nombre: 'Dra. Ana Pérez', email: 'ana@clinica.com', telefono: '', especialidad_id: '', numero_colegiado: '',
  nombre_clinica: '', autorizado: true,
}

describe('validarSolicitudAlta — los límites de solicitar_alta_medico', () => {
  it('un formulario mínimo válido no tiene errores', () => {
    expect(validarSolicitudAlta(ok)).toEqual({})
  })

  it('la casilla de autorización es obligatoria', () => {
    expect(validarSolicitudAlta({ ...ok, autorizado: false }).autorizado).toBeTruthy()
  })

  it('nombre: 3 a 150 caracteres, recortado', () => {
    expect(validarSolicitudAlta({ ...ok, nombre: '  ab  ' }).nombre).toBeTruthy()
    expect(validarSolicitudAlta({ ...ok, nombre: 'abc' }).nombre).toBeUndefined()
    expect(validarSolicitudAlta({ ...ok, nombre: 'a'.repeat(151) }).nombre).toBeTruthy()
  })

  it('correo: obligatorio, con forma x@y.z y hasta 254', () => {
    for (const email of ['', 'ana', 'ana@clinica', 'a na@x.co', `${'a'.repeat(250)}@x.co`]) {
      expect(validarSolicitudAlta({ ...ok, email }).email, email).toBeTruthy()
    }
    expect(validarSolicitudAlta({ ...ok, email: ' ANA@Clinica.com ' }).email).toBeUndefined()
  })

  it('teléfono opcional: si viene, 7 a 15 dígitos y hasta 30 caracteres', () => {
    expect(validarSolicitudAlta({ ...ok, telefono: '' }).telefono).toBeUndefined()
    expect(validarSolicitudAlta({ ...ok, telefono: '+502 5555-1234' }).telefono).toBeUndefined()
    expect(validarSolicitudAlta({ ...ok, telefono: '123456' }).telefono).toBeTruthy()
    expect(validarSolicitudAlta({ ...ok, telefono: '1234567890123456' }).telefono).toBeTruthy()
    expect(validarSolicitudAlta({ ...ok, telefono: '1234567 ' + '-'.repeat(25) }).telefono).toBeTruthy()
  })

  it('colegiado hasta 30 y clínica hasta 150', () => {
    expect(validarSolicitudAlta({ ...ok, numero_colegiado: 'x'.repeat(31) }).numero_colegiado).toBeTruthy()
    expect(validarSolicitudAlta({ ...ok, nombre_clinica: 'x'.repeat(151) }).nombre_clinica).toBeTruthy()
  })

  it('los opcionales vacíos viajan como null', () => {
    expect(paramsSolicitudAlta(ok)).toMatchObject({ p_telefono: null, p_especialidad_id: null, p_numero_colegiado: null, p_nombre_clinica: null })
  })
})
