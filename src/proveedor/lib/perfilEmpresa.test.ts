import { describe, it, expect } from 'vitest'
import { camposPerfilCambiados, CAMPOS_PERFIL, type FormPerfil } from './perfilEmpresa'
import type { EmpresaProveedora } from '@/proveedor/types/proveedor.types'

// Empresa "llena" de referencia (solo los campos que importan al diff).
const empresaLlena = {
  nombre_empresa: 'QA Farmacia',
  ruc_nit: '900123',
  ciudad: 'Ciudad',
  direccion: 'Calle 1',
  email_contacto: 'oscarabadgutierreztomas@gmail.com',
  telefono: '3852992463',
  tipo: 'farmacia',
} as unknown as EmpresaProveedora

// Form seedeado desde la empresa (como queda tras el fix #1 al entrar en edición).
const formDesde = (e: typeof empresaLlena): FormPerfil => ({
  nombre_empresa: e.nombre_empresa ?? '',
  ruc_nit: e.ruc_nit ?? '',
  ciudad: e.ciudad ?? '',
  direccion: e.direccion ?? '',
  email_contacto: e.email_contacto ?? '',
  telefono: e.telefono ?? '',
})

describe('camposPerfilCambiados', () => {
  it('(a) solo el teléfono cambió → el diff trae solo telefono', () => {
    const form = { ...formDesde(empresaLlena), telefono: '3535-3535' }
    const diff = camposPerfilCambiados(empresaLlena, form)
    expect(diff).toEqual({ telefono: '3535-3535' })
  })

  it('(b) form vacío con empresa llena → NO manda "" sobre valores existentes', () => {
    const formVacio: FormPerfil = {
      nombre_empresa: '',
      ruc_nit: '',
      ciudad: '',
      direccion: '',
      email_contacto: '',
      telefono: '',
    }
    const diff = camposPerfilCambiados(empresaLlena, formVacio)
    // El bug original: acá se blanqueaban 5 columnas. Ahora el diff es vacío.
    expect(diff).toEqual({})
  })

  it('(c) sin cambios → diff vacío', () => {
    const diff = camposPerfilCambiados(empresaLlena, formDesde(empresaLlena))
    expect(diff).toEqual({})
  })

  it('(d) tipo nunca aparece en el diff (columna privilegiada, fuera de la whitelist)', () => {
    // Aunque alguien meta `tipo` en el form, no se propaga.
    const form = { ...formDesde(empresaLlena), tipo: 'laboratorio_clinico' } as unknown as FormPerfil
    const diff = camposPerfilCambiados(
      { ...empresaLlena, tipo: 'farmacia' } as EmpresaProveedora,
      form,
    )
    expect(diff).not.toHaveProperty('tipo')
    expect(CAMPOS_PERFIL).not.toContain('tipo' as never)
    // y sin otros cambios, queda vacío
    expect(diff).toEqual({})
  })

  it('llenar un campo que estaba vacío/null SÍ se manda', () => {
    const empresaSinTel = { ...empresaLlena, telefono: null } as unknown as EmpresaProveedora
    const form = { ...formDesde(empresaLlena), telefono: '111-222' }
    const diff = camposPerfilCambiados(empresaSinTel, form)
    expect(diff).toEqual({ telefono: '111-222' })
  })

  it('empresa null/undefined + form vacío → diff vacío (nada que blanquear)', () => {
    const formVacio: FormPerfil = {
      nombre_empresa: '',
      ruc_nit: '',
      ciudad: '',
      direccion: '',
      email_contacto: '',
      telefono: '',
    }
    expect(camposPerfilCambiados(null, formVacio)).toEqual({})
    expect(camposPerfilCambiados(undefined, formVacio)).toEqual({})
  })

  it('cambio real de varios campos → los trae todos (menos los vacíos sobre existentes)', () => {
    const form: FormPerfil = {
      ...formDesde(empresaLlena),
      nombre_empresa: 'QA Farmacia Central',
      email_contacto: 'nuevo@qa.com',
      ciudad: '', // vaciado → NO se propaga
    }
    const diff = camposPerfilCambiados(empresaLlena, form)
    expect(diff).toEqual({
      nombre_empresa: 'QA Farmacia Central',
      email_contacto: 'nuevo@qa.com',
    })
  })
})
