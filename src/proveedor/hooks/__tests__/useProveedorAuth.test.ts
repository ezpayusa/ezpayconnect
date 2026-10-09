import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'

// supabase simulado: auth, rpc y la cadena from().select().eq().maybeSingle() de cuentas_proveedor.
const signUp = vi.fn()
const signInWithPassword = vi.fn()
const signOut = vi.fn(async () => ({ error: null }))
const updateUser = vi.fn(async (..._a: unknown[]) => ({ error: null }))
const rpc = vi.fn()
// Respuestas de cuentas_proveedor en orden, separadas por columnas: 'id, activo' (login) y '*, empresa:empresa_id(*)' (fetchCuenta).
let colaLogin: unknown[] = []
let colaFetch: unknown[] = []
const select = vi.fn((cols: string) => ({
  eq: () => ({
    maybeSingle: async () => {
      const cola = cols === 'id, activo' ? colaLogin : colaFetch
      return { data: cola.length ? cola.shift() : null, error: null }
    },
  }),
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      signUp: (...a: unknown[]) => signUp(...a),
      signInWithPassword: (...a: unknown[]) => signInWithPassword(...a),
      signOut: () => signOut(),
      updateUser: (...a: unknown[]) => updateUser(...a),
      getSession: async () => ({ data: { session: null } }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
    },
    rpc: (...a: unknown[]) => rpc(...a),
    from: () => ({ select: (cols: string) => select(cols) }),
  },
}))

const aceptarInvitacionPendiente = vi.fn(async () => false)
vi.mock('@/lib/invitacionProveedor', () => ({
  aceptarInvitacionPendiente: () => aceptarInvitacionPendiente(),
}))

const { useProveedorAuth } = await import('../useProveedorAuth')
const { MENSAJE_IDENTIDAD_PREVIA } = await import('@/proveedor/lib/registroDiferido')

const UID = 'uid-nuevo'
const EMPRESA_ID = '11111111-2222-4333-8444-555555555555'
const YA_REGISTRADO = 'Este correo ya está registrado. Usa otro email o inicia sesión.'
const NO_PROVEEDOR = 'Esta cuenta no es de un proveedor. Usa el portal que corresponde a tu cuenta.'

async function hook() {
  const r = renderHook(() => useProveedorAuth())
  await act(async () => {}) // deja terminar el init (getSession) dentro de act
  return r
}

beforeEach(() => {
  vi.clearAllMocks()
  colaLogin = []
  colaFetch = []
  aceptarInvitacionPendiente.mockResolvedValue(false)
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('register (alta diferida)', () => {
  const empresa = {
    nombre_empresa: 'Farmacia X',
    tipo: 'farmacia' as const,
    ruc_nit: '',
    pais_id: 'pais-gt',
    ciudad: 'Guatemala',
    direccion: '',
    email_contacto: 'c@x.com',
    telefono: '',
  }

  async function registrar(e: Record<string, unknown> = empresa) {
    const { result } = await hook()
    let r: Record<string, unknown> = {}
    await act(async () => {
      r = await result.current.register('rep@x.com', 'secreta123', 'Rep Uno', e)
    })
    return r
  }

  it('(a) signUp lleva registro_empresa en la metadata (sin tipo suelto) y no llama a registrar_proveedor', async () => {
    signUp.mockResolvedValue({ data: { user: { id: UID, identities: [{}] }, session: null }, error: null })
    await registrar()
    expect(signUp).toHaveBeenCalledTimes(1)
    const arg = signUp.mock.calls[0][0]
    expect(arg.email).toBe('rep@x.com')
    expect(arg.options.data).toEqual({
      registro_empresa: {
        nombre_empresa: 'Farmacia X',
        tipo: 'farmacia',
        ruc_nit: null,
        pais_id: 'pais-gt',
        ciudad: 'Guatemala',
        direccion: null,
        email_contacto: 'c@x.com',
        telefono: null,
        nombre_completo: 'Rep Uno',
      },
    })
    expect(Object.keys(arg.options.data)).toEqual(['registro_empresa'])
    expect(rpc).not.toHaveBeenCalled()
  })

  it.each([
    ['farmacia', 'https://med.ezpayconnect.com/farmacia/login'],
    ['laboratorio_clinico', 'https://med.ezpayconnect.com/laboratorio/login'],
    ['empresa_afin', 'https://med.ezpayconnect.com/proveedor/login'],
  ])('(b) %s → emailRedirectTo al login de su portal', async (tipo, url) => {
    signUp.mockResolvedValue({ data: { user: { id: UID, identities: [{}] }, session: null }, error: null })
    await registrar({ ...empresa, tipo })
    expect(signUp.mock.calls[0][0].options.emailRedirectTo).toBe(url)
    expect(signUp.mock.calls[0][0].options.data.registro_empresa.tipo).toBe(tipo)
  })

  it('(c) sin email_contacto ni tipo → usa el email del alta y farmacia', async () => {
    signUp.mockResolvedValue({ data: { user: { id: UID, identities: [{}] }, session: null }, error: null })
    await registrar({ nombre_empresa: 'Y', pais_id: 'pais-gt' })
    const reg = signUp.mock.calls[0][0].options.data.registro_empresa
    expect(reg.email_contacto).toBe('rep@x.com')
    expect(reg.tipo).toBe('farmacia')
    expect(signUp.mock.calls[0][0].options.emailRedirectTo).toBe('https://med.ezpayconnect.com/farmacia/login')
  })

  it('(d) correo ya registrado: error del signUp o usuario sin identidades → mismo mensaje, sin userId', async () => {
    signUp.mockResolvedValue({ data: { user: null, session: null }, error: { message: 'User already registered', status: 422 } })
    const r1 = await registrar()
    expect((r1.error as { message: string }).message).toBe(YA_REGISTRADO)
    expect('userId' in r1).toBe(false)

    signUp.mockResolvedValue({ data: { user: { id: UID, identities: [] }, session: null }, error: null })
    const r2 = await registrar()
    expect((r2.error as { message: string }).message).toBe(YA_REGISTRADO)
    expect('userId' in r2).toBe(false)
    expect(rpc).not.toHaveBeenCalled()
  })

  it('(e) sin sesión (Confirm email ON) → pendienteConfirmacion true con userId; sin rpc ni signOut', async () => {
    signUp.mockResolvedValue({ data: { user: { id: UID, identities: [{}] }, session: null }, error: null })
    const r = await registrar()
    expect(r.error).toBeNull()
    expect(r.userId).toBe(UID)
    expect(r.pendienteConfirmacion).toBe(true)
    expect(rpc).not.toHaveBeenCalled()
    expect(signOut).not.toHaveBeenCalled()
  })

  it('(f) con sesión: completar OK → pendienteConfirmacion false; completar en error → signOut, mensaje de la whitelist, sin userId', async () => {
    signUp.mockResolvedValue({ data: { user: { id: UID, identities: [{}] }, session: { access_token: 't' } }, error: null })
    rpc.mockResolvedValue({ data: EMPRESA_ID, error: null })
    const ok = await registrar()
    expect(rpc).toHaveBeenCalledWith('completar_registro_proveedor')
    expect(ok.error).toBeNull()
    expect(ok.userId).toBe(UID)
    expect(ok.pendienteConfirmacion).toBe(false)
    expect(signOut).not.toHaveBeenCalled()

    rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'La cuenta ya tiene una identidad en la plataforma' } })
    const falla = await registrar()
    expect((falla.error as { message: string }).message).toBe(MENSAJE_IDENTIDAD_PREVIA)
    expect('userId' in falla).toBe(false)
    expect(signOut).toHaveBeenCalledTimes(1)
  })
})

describe('login (invitación y alta diferida antes del rechazo)', () => {
  async function entrar() {
    const r = await hook()
    let res: Record<string, unknown> = {}
    await act(async () => {
      res = await r.result.current.login('rep@x.com', 'secreta123')
    })
    return { res, result: r.result }
  }

  beforeEach(() => {
    signInWithPassword.mockResolvedValue({ data: { user: { id: UID } }, error: null })
  })

  it('(g) error de credenciales → lo devuelve tal cual, sin consultar cuentas', async () => {
    const error = { message: 'Invalid login credentials' }
    signInWithPassword.mockResolvedValue({ data: { user: null }, error })
    const { res } = await entrar()
    expect(res.error).toBe(error)
    expect(select).not.toHaveBeenCalled()
    expect(aceptarInvitacionPendiente).not.toHaveBeenCalled()
  })

  it('(h) cuenta activa → entra sin invitación ni completar', async () => {
    colaLogin = [{ id: UID, activo: true }]
    const { res } = await entrar()
    expect(res.error).toBeNull()
    expect(aceptarInvitacionPendiente).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
    expect(signOut).not.toHaveBeenCalled()
  })

  it('(i) sin cuenta + invitación aceptada → re-consulta y entra, sin completar', async () => {
    colaLogin = [null, { id: UID, activo: true }]
    aceptarInvitacionPendiente.mockResolvedValue(true)
    const { res } = await entrar()
    expect(res.error).toBeNull()
    expect(aceptarInvitacionPendiente).toHaveBeenCalledTimes(1)
    expect(rpc).not.toHaveBeenCalled()
    expect(signOut).not.toHaveBeenCalled()
  })

  it('(j) sin cuenta ni invitación + alta diferida OK → re-consulta, actualiza cuenta/empresa del hook y entra', async () => {
    colaLogin = [null, { id: UID, activo: true }]
    rpc.mockResolvedValue({ data: EMPRESA_ID, error: null })
    colaFetch = [{ id: UID, activo: true, rol: 'admin', empresa: { id: EMPRESA_ID, nombre_empresa: 'Farmacia X' } }]
    const { res, result } = await entrar()
    expect(res.error).toBeNull()
    expect(aceptarInvitacionPendiente).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('completar_registro_proveedor')
    expect(updateUser).toHaveBeenCalledWith({ data: { registro_empresa: null } })
    expect(select).toHaveBeenCalledWith('*, empresa:empresa_id(*)')
    expect(result.current.empresa?.id).toBe(EMPRESA_ID)
    expect(result.current.cuenta?.id).toBe(UID)
    expect(signOut).not.toHaveBeenCalled()
  })

  it('(k) sin cuenta y sin registro pendiente (RP003) → signOut y "no es de un proveedor"', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: 'RP003', message: 'No hay un registro de empresa pendiente. Escríbenos a soporte.' } })
    const { res } = await entrar()
    expect((res.error as { message: string }).message).toBe(NO_PROVEEDOR)
    expect(signOut).toHaveBeenCalledTimes(1)
  })

  it('(l) alta diferida con otro error (RP004 / 42501 / 23505) → signOut y mensaje de la whitelist', async () => {
    const rp004 = 'Los datos de registro de tu empresa no son válidos. Escríbenos a soporte para completarlo.'
    rpc.mockResolvedValue({ data: null, error: { code: 'RP004', message: rp004 } })
    expect(((await entrar()).res.error as { message: string }).message).toBe(rp004)

    rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'La cuenta ya tiene una identidad en la plataforma' } })
    expect(((await entrar()).res.error as { message: string }).message).toBe(MENSAJE_IDENTIDAD_PREVIA)

    rpc.mockResolvedValue({ data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint' } })
    const msg = ((await entrar()).res.error as { message: string }).message
    expect(msg).not.toContain('duplicate key')
    expect(signOut).toHaveBeenCalledTimes(3)
  })

  it('(m) cuenta desactivada → signOut y mensaje de desactivada (sin invitación ni completar)', async () => {
    colaLogin = [{ id: UID, activo: false }]
    const { res } = await entrar()
    expect((res.error as { message: string }).message).toBe('Tu cuenta fue desactivada. Contacta al administrador de tu empresa.')
    expect(signOut).toHaveBeenCalledTimes(1)
    expect(aceptarInvitacionPendiente).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
  })
})
