import { describe, it, expect, vi, beforeEach } from 'vitest'

type Resp = { data: unknown; error: unknown }
let respuestaRpc: Resp = { data: null, error: null }
let lanzarRpc: unknown = null
let respuestaUpdate: { error: unknown } = { error: null }
const rpc = vi.fn(async (..._a: unknown[]) => {
  if (lanzarRpc) throw lanzarRpc
  return respuestaRpc
})
const updateUser = vi.fn(async (..._a: unknown[]) => respuestaUpdate)

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpc(...a),
    auth: { updateUser: (...a: unknown[]) => updateUser(...a) },
  },
}))

const {
  loginDePortal,
  completarRegistroPendiente,
  mensajeErrorRegistroEmpresa,
  MENSAJE_IDENTIDAD_PREVIA,
  MENSAJE_PAIS_NO_VALIDO,
  MENSAJE_GENERICO_REGISTRO,
} = await import('../registroDiferido')

const EMPRESA = '11111111-2222-4333-8444-555555555555'
let consoleError: ReturnType<typeof vi.spyOn>

beforeEach(() => {
  respuestaRpc = { data: null, error: null }
  lanzarRpc = null
  respuestaUpdate = { error: null }
  rpc.mockClear()
  updateUser.mockClear()
  consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('loginDePortal', () => {
  it('farmacia, laboratorio_clinico y el resto van a su login', () => {
    expect(loginDePortal('farmacia')).toBe('/farmacia/login')
    expect(loginDePortal('laboratorio_clinico')).toBe('/laboratorio/login')
    expect(loginDePortal('laboratorio_farmaceutico')).toBe('/proveedor/login')
    expect(loginDePortal('empresa_afin')).toBe('/proveedor/login')
  })
})

describe('completarRegistroPendiente', () => {
  it('éxito → ok con empresaId; rpc sin argumentos y limpieza de registro_empresa', async () => {
    respuestaRpc = { data: EMPRESA, error: null }
    expect(await completarRegistroPendiente()).toEqual({ ok: true, empresaId: EMPRESA })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc.mock.calls[0]).toEqual(['completar_registro_proveedor'])
    expect(updateUser).toHaveBeenCalledWith({ data: { registro_empresa: null } })
    expect(consoleError).not.toHaveBeenCalled()
  })

  it('éxito con la limpieza en error → sigue ok; log con mensaje fijo y solo el code', async () => {
    respuestaRpc = { data: EMPRESA, error: null }
    respuestaUpdate = { error: { code: 'over_request_rate_limit', message: 'texto interno con ana@example.com' } }
    expect(await completarRegistroPendiente()).toEqual({ ok: true, empresaId: EMPRESA })
    expect(consoleError).toHaveBeenCalledTimes(1)
    expect(consoleError).toHaveBeenCalledWith('[registroDiferido] no se pudo limpiar registro_empresa', 'over_request_rate_limit')
  })

  it('error RP002 → ok:false con el code; sin limpieza; log sin message', async () => {
    const error = { code: 'RP002', message: 'Confirma tu correo antes de completar el registro.' }
    respuestaRpc = { data: null, error }
    expect(await completarRegistroPendiente()).toEqual({ ok: false, error })
    expect(updateUser).not.toHaveBeenCalled()
    expect(consoleError).toHaveBeenCalledWith('[registroDiferido] completar_registro_proveedor falló', 'RP002')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('Confirma tu correo')
  })

  it('la rpc lanza → ok:false con code null, sin lanzar', async () => {
    lanzarRpc = new TypeError('Failed to fetch')
    await expect(completarRegistroPendiente()).resolves.toEqual({ ok: false, error: { code: null, message: null } })
    expect(updateUser).not.toHaveBeenCalled()
  })
})

describe('mensajeErrorRegistroEmpresa', () => {
  it('whitelist: RP001-RP004 con el message de la base; 42501 y 22023 con texto propio; el resto genérico sin filtrar el message crudo', () => {
    for (const code of ['RP001', 'RP002', 'RP003', 'RP004']) {
      expect(mensajeErrorRegistroEmpresa({ code, message: `mensaje de ${code}` })).toBe(`mensaje de ${code}`)
    }
    expect(mensajeErrorRegistroEmpresa({ code: '42501', message: 'La cuenta ya tiene una identidad en la plataforma' })).toBe(MENSAJE_IDENTIDAD_PREVIA)
    expect(mensajeErrorRegistroEmpresa({ code: '22023', message: 'País no válido para el registro' })).toBe(MENSAJE_PAIS_NO_VALIDO)
    const crudo = 'duplicate key value violates unique constraint "empresas_proveedoras_pkey"'
    expect(mensajeErrorRegistroEmpresa({ code: 'XX999', message: crudo })).toBe(MENSAJE_GENERICO_REGISTRO)
    expect(mensajeErrorRegistroEmpresa({ code: '23505', message: crudo })).toBe(MENSAJE_GENERICO_REGISTRO)
    expect(mensajeErrorRegistroEmpresa({ code: null, message: crudo })).toBe(MENSAJE_GENERICO_REGISTRO)
    expect(mensajeErrorRegistroEmpresa(null)).toBe(MENSAJE_GENERICO_REGISTRO)
    expect(mensajeErrorRegistroEmpresa({ code: 'RP003', message: null })).toBe(MENSAJE_GENERICO_REGISTRO)
  })
})
