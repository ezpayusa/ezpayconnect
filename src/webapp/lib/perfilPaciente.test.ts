import { describe, it, expect } from 'vitest'
import {
  camposPacienteCambiados,
  validarPaciente,
  snapshotPaciente,
  formVacioPaciente,
  type FormPaciente,
} from './perfilPaciente'
import type { PacientePerfil } from '@/webapp/types/webapp.types'

const perfilBase: PacientePerfil = {
  id: 23,
  nombre: 'Ana',
  apellido: 'Pérez',
  email: 'ana@ej.com',
  telefono: '555-1000',
  fecha_nacimiento: '1990-01-01',
  genero: 'femenino',
  direccion: 'Calle 1',
  alergias: 'penicilina',
  notas: 'nota',
  emergencia_nombre: 'Luis',
  emergencia_telefono: '555-2000',
  foto_url: null,
  activo: true,
  created_at: '2026-01-01T00:00:00Z',
}

const formDe = (p: PacientePerfil): FormPaciente => snapshotPaciente(p)

describe('camposPacienteCambiados', () => {
  it('sin cambios → {}', () => {
    expect(camposPacienteCambiados(perfilBase, formDe(perfilBase))).toEqual({})
  })

  it('cambia teléfono → solo { telefono }', () => {
    const form = { ...formDe(perfilBase), telefono: '555-9999' }
    expect(camposPacienteCambiados(perfilBase, form)).toEqual({ telefono: '555-9999' })
  })

  it('vaciar alergias (tenía valor) → { alergias: null }', () => {
    const form = { ...formDe(perfilBase), alergias: '' }
    expect(camposPacienteCambiados(perfilBase, form)).toEqual({ alergias: null })
  })

  it('llenar un opcional que estaba vacío → { campo: valor }', () => {
    const perfil = { ...perfilBase, direccion: null }
    const form = { ...formDe(perfil), direccion: 'Nueva 2' }
    expect(camposPacienteCambiados(perfil, form)).toEqual({ direccion: 'Nueva 2' })
  })

  it('campo fuera de whitelist en el form → ignorado (email y columnas privilegiadas)', () => {
    const form = {
      ...formDe(perfilBase),
      // claves que NO están en la whitelist: no deben aparecer en el diff
      email: 'hack@x.y',
      medico_id: '00000000-0000-0000-0000-000000000000',
      pais_id: 'otro',
      activo: 'false',
    } as unknown as FormPaciente
    const cambios = camposPacienteCambiados(perfilBase, form)
    expect(cambios).toEqual({})
    expect(cambios).not.toHaveProperty('email')
    expect(cambios).not.toHaveProperty('medico_id')
    expect(cambios).not.toHaveProperty('pais_id')
    expect(cambios).not.toHaveProperty('activo')
  })

  it('obligatorio (nombre) vaciado → NO se emite null en el diff', () => {
    const form = { ...formDe(perfilBase), nombre: '' }
    const cambios = camposPacienteCambiados(perfilBase, form)
    expect(cambios).not.toHaveProperty('nombre')
    expect(cambios).toEqual({})
  })

  it('nombre cambiado a un valor → { nombre: valor }', () => {
    const form = { ...formDe(perfilBase), nombre: 'Anabel' }
    expect(camposPacienteCambiados(perfilBase, form)).toEqual({ nombre: 'Anabel' })
  })
})

describe('validarPaciente', () => {
  it('form válido → null', () => {
    expect(validarPaciente(formDe(perfilBase))).toBeNull()
  })

  it('nombre vacío → mensaje', () => {
    expect(validarPaciente({ ...formDe(perfilBase), nombre: '   ' })).toBe('El nombre es obligatorio')
  })

  it('apellido vacío → mensaje', () => {
    expect(validarPaciente({ ...formDe(perfilBase), apellido: '' })).toBe('El apellido es obligatorio')
  })
})

describe('regresión: bug viejo (form vacío por no hidratar)', () => {
  it('un form SIN hidratar (todo vacío) es rechazado por la validación → el guardado no se ejecuta', () => {
    // El bug original: el form nacía en '' y un guardado pisaba todo. Ahora, aun si el form llegara
    // vacío, validarPaciente corta antes de tocar la base (nombre obligatorio). En el componente,
    // además, "Editar" está deshabilitado mientras perfil sea null y el useEffect hidrata el form.
    expect(validarPaciente(formVacioPaciente)).toBe('El nombre es obligatorio')
  })
})
