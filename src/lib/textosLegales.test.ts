import { describe, it, expect, vi, beforeEach } from 'vitest'
import { TEXTOS_LEGALES } from '@/legal/catalogo'

// Las respuestas simuladas copian la forma de las RPCs vivas (migs 371/372):
//   textos_legales_pendientes() → filas {codigo, version}
//   aceptar_textos_legales(p_textos, p_via, p_user_agent) → {aceptados, ya_aceptados, pendientes}

type Resp = { data: unknown; error: unknown }
let respuesta: Resp = { data: [], error: null }
let lanzar: unknown = null
const llamadas: { fn: string; args: unknown }[] = []
let sesion: { user: { id: string } } | null = null
let lanzarSesion: unknown = null
const getSession = vi.fn(async () => {
  if (lanzarSesion) throw lanzarSesion
  return { data: { session: sesion }, error: null }
})

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: { getSession: () => getSession() },
    rpc: async (fn: string, args?: unknown) => {
      llamadas.push({ fn, args })
      if (lanzar) throw lanzar
      return respuesta
    },
  },
}))

const {
  obtenerPendientes,
  aceptarTextos,
  aceptarEnRegistro,
  mensajeErrorTextosLegales,
  MENSAJE_SIN_PERMISO,
  MENSAJE_GENERICO,
} = await import('./textosLegales')

const terminos = TEXTOS_LEGALES.find((t) => t.codigo === 'terminos')!
const consentimiento = TEXTOS_LEGALES.find((t) => t.codigo === 'consentimiento_salud')!

beforeEach(() => {
  respuesta = { data: [], error: null }
  lanzar = null
  llamadas.length = 0
  sesion = null
  lanzarSesion = null
  getSession.mockClear()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('obtenerPendientes', () => {
  it('0 filas → ok con []', async () => {
    expect(await obtenerPendientes()).toEqual({ ok: true, pendientes: [] })
    expect(llamadas).toEqual([{ fn: 'textos_legales_pendientes', args: undefined }])
  })

  it('2 filas conocidas → ok con los TextoLegal completos del catálogo', async () => {
    respuesta = {
      data: [
        { codigo: 'consentimiento_salud', version: '0.1' },
        { codigo: 'terminos', version: '0.1' },
      ],
      error: null,
    }
    const r = await obtenerPendientes()
    expect(r).toEqual({ ok: true, pendientes: [consentimiento, terminos] })
    if (r.ok) expect(r.pendientes[1]).toBe(terminos)
  })

  it('un código que el front no conoce → ok:false (falla cerrado, sin lista parcial)', async () => {
    respuesta = { data: [{ codigo: 'terminos', version: '0.1' }, { codigo: 'cookies', version: '0.1' }], error: null }
    const r = await obtenerPendientes()
    expect(r.ok).toBe(false)
  })

  it('versión de la base distinta a la del catálogo → ok:false', async () => {
    respuesta = { data: [{ codigo: 'terminos', version: '0.2' }], error: null }
    expect((await obtenerPendientes()).ok).toBe(false)
  })

  it('error de la RPC → ok:false con el error', async () => {
    const error = { code: 'LG001', message: 'Necesitas iniciar sesión.' }
    respuesta = { data: null, error }
    expect(await obtenerPendientes()).toEqual({ ok: false, error })
  })

  it('si el cliente lanza (red) → ok:false y no lanza', async () => {
    lanzar = new TypeError('Failed to fetch')
    await expect(obtenerPendientes()).resolves.toMatchObject({ ok: false })
  })
})

describe('aceptarTextos', () => {
  it('pasa p_textos, p_via y p_user_agent', async () => {
    const data = { aceptados: 1, ya_aceptados: 0, pendientes: [] }
    respuesta = { data, error: null }
    const r = await aceptarTextos([{ codigo: 'terminos', version: '0.1' }], 'registro')
    expect(r).toEqual({ ok: true, data })
    expect(llamadas).toEqual([
      {
        fn: 'aceptar_textos_legales',
        args: { p_textos: [{ codigo: 'terminos', version: '0.1' }], p_via: 'registro', p_user_agent: navigator.userAgent },
      },
    ])
  })

  it('error de la RPC → ok:false y no lanza', async () => {
    const error = { code: 'LG006', message: 'Este texto no corresponde a tu cuenta.' }
    respuesta = { data: null, error }
    await expect(aceptarTextos([{ codigo: 'consentimiento_salud', version: '0.1' }], 'login')).resolves.toEqual({
      ok: false,
      error,
    })
  })

  it('si el cliente lanza → ok:false y no lanza', async () => {
    lanzar = new TypeError('Failed to fetch')
    await expect(aceptarTextos([{ codigo: 'terminos', version: '0.1' }], 'app')).resolves.toMatchObject({ ok: false })
  })
})

describe('aceptarEnRegistro', () => {
  const TEXTOS = [
    { codigo: 'terminos' as const, version: '0.1' },
    { codigo: 'privacidad' as const, version: '0.1' },
  ]
  const llamoRpc = () => llamadas.some((l) => l.fn === 'aceptar_textos_legales')

  it.each([null, undefined, ''])('uidEsperado %j → omitido, sin getSession ni RPC', async (uid) => {
    sesion = { user: { id: 'u1' } }
    expect(await aceptarEnRegistro(TEXTOS, uid)).toBe('omitido')
    expect(getSession).not.toHaveBeenCalled()
    expect(llamadas).toEqual([])
  })

  it('textos vacíos → omitido, sin RPC', async () => {
    sesion = { user: { id: 'u1' } }
    expect(await aceptarEnRegistro([], 'u1')).toBe('omitido')
    expect(llamoRpc()).toBe(false)
  })

  it('sin sesión → omitido, sin RPC', async () => {
    expect(await aceptarEnRegistro(TEXTOS, 'u1')).toBe('omitido')
    expect(getSession).toHaveBeenCalledTimes(1)
    expect(llamoRpc()).toBe(false)
  })

  it('sesión de OTRO uid → omitido, sin RPC', async () => {
    sesion = { user: { id: 'otro' } }
    expect(await aceptarEnRegistro(TEXTOS, 'u1')).toBe('omitido')
    expect(llamoRpc()).toBe(false)
  })

  it('sesión del uid esperado + RPC ok → grabado, con vía registro y los textos exactos', async () => {
    sesion = { user: { id: 'u1' } }
    respuesta = { data: { aceptados: 2, ya_aceptados: 0, pendientes: [] }, error: null }
    expect(await aceptarEnRegistro(TEXTOS, 'u1')).toBe('grabado')
    expect(llamadas).toEqual([
      {
        fn: 'aceptar_textos_legales',
        args: { p_textos: TEXTOS, p_via: 'registro', p_user_agent: navigator.userAgent },
      },
    ])
  })

  it('error de la RPC → fallo; log con mensaje fijo y solo el código', async () => {
    sesion = { user: { id: 'u1' } }
    respuesta = { data: null, error: { code: 'LG006', message: 'Este texto no corresponde a tu cuenta.' } }
    expect(await aceptarEnRegistro(TEXTOS, 'u1')).toBe('fallo')
    expect(console.error).toHaveBeenCalledWith('GL-02 aceptación en registro falló:', 'LG006')
  })

  it('getSession lanza → fallo, sin RPC y sin lanzar', async () => {
    lanzarSesion = new TypeError('Failed to fetch')
    await expect(aceptarEnRegistro(TEXTOS, 'u1')).resolves.toBe('fallo')
    expect(llamoRpc()).toBe(false)
    expect(console.error).toHaveBeenCalledWith('GL-02 aceptación en registro falló:', null)
  })

  it('la RPC lanza → fallo, sin lanzar', async () => {
    sesion = { user: { id: 'u1' } }
    lanzar = new TypeError('Failed to fetch')
    await expect(aceptarEnRegistro(TEXTOS, 'u1')).resolves.toBe('fallo')
  })
})

describe('mensajeErrorTextosLegales', () => {
  it.each(['LG001', 'LG002', 'LG003', 'LG004', 'LG005', 'LG006'])('%s devuelve el message de la base', (code) => {
    expect(mensajeErrorTextosLegales({ code, message: `mensaje de ${code}` })).toBe(`mensaje de ${code}`)
  })

  it('42501 → sin permiso (no el texto de Postgres)', () => {
    expect(mensajeErrorTextosLegales({ code: '42501', message: 'permission denied for function x' })).toBe(MENSAJE_SIN_PERMISO)
  })

  it.each(['LG007', 'PA001'])('código desconocido %s → genérico', (code) => {
    expect(mensajeErrorTextosLegales({ code, message: 'texto interno' })).toBe(MENSAJE_GENERICO)
  })

  it('sin código, null o undefined → genérico', () => {
    expect(mensajeErrorTextosLegales({ message: 'Failed to fetch' })).toBe(MENSAJE_GENERICO)
    expect(mensajeErrorTextosLegales(null)).toBe(MENSAJE_GENERICO)
    expect(mensajeErrorTextosLegales(undefined)).toBe(MENSAJE_GENERICO)
  })
})
