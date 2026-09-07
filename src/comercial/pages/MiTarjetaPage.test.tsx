import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// Lo que se mide acá es lo que hace distinta a esta pantalla del resto del módulo: que el texto del
// consentimiento esté ANTES de encender —es parte del consentimiento, no decoración—, que sin ficha
// no se ofrezca ningún control roto, y que despublicar se describa como "el enlace deja de
// responder" y no como "se esconde un botón".

type Ficha = {
  id: string; codigo_asesor: string; tarjeta_token: string; tarjeta_publica: boolean
  tarjeta_consentimiento_at: string | null; tarjeta_token_rotado_at: string | null
  foto_publica_path: string | null; activo: boolean
}

const FICHA_BASE: Ficha = {
  id: 'ase-1', codigo_asesor: 'QA-ASE-01', tarjeta_token: 'tok-abc',
  tarjeta_publica: false, tarjeta_consentimiento_at: null, tarjeta_token_rotado_at: null,
  foto_publica_path: null, activo: true,
}

let ficha: Ficha | null = FICHA_BASE
let rpcError: unknown = null
const rpcs: { nombre: string; args: unknown }[] = []
let firmaOk = true

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string, args: unknown) => {
      rpcs.push({ nombre, args })
      return { data: null, error: rpcError }
    },
    from: () => {
      const q: Record<string, unknown> = {}
      for (const m of ['select', 'eq']) q[m] = () => q
      q.maybeSingle = async () => ({ data: ficha, error: null })
      return q
    },
    storage: {
      from: () => ({
        createSignedUrl: async () => firmaOk
          ? { data: { signedUrl: 'https://firmada.example/foto.png' }, error: null }
          : { data: null, error: { message: 'nope' } },
        remove: async () => ({ error: null }),
      }),
    },
  },
}))
vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({ perfil: { id: 'ase-1', nombre_completo: 'Ana Pérez', rol: 'asesor_comercial' } }),
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))

const { default: MiTarjetaPage } = await import('./MiTarjetaPage')

const pintar = () => render(<MemoryRouter><MiTarjetaPage /></MemoryRouter>)

beforeEach(() => {
  ficha = { ...FICHA_BASE }
  rpcError = null
  rpcs.length = 0
  firmaOk = true
})

describe('sin ficha de asesor', () => {
  it('lo dice con calma y NO ofrece ningún control', async () => {
    ficha = null
    pintar()
    await screen.findByText(/Todavía no tenés ficha de asesor/i)

    // Ni interruptor, ni foto, ni rotar: un botón que siempre falla es peor que no tenerlo.
    expect(screen.queryByRole('button', { name: /publicar mi tarjeta/i })).toBeNull()
    expect(screen.queryByRole('button', { name: /subir foto/i })).toBeNull()
    expect(screen.queryByRole('button', { name: /generar enlace nuevo/i })).toBeNull()
    // y explica quién puede resolverlo
    expect(screen.getByText(/administrador de tu país/i)).toBeTruthy()
  })
})

describe('tarjeta NO publicada', () => {
  it('el estado es visible y no se muestra ningún enlace', async () => {
    pintar()
    await screen.findByText('No publicada')
    expect(screen.getByText(/El enlace no le responde a nadie/i)).toBeTruthy()
    // el token NO se pinta si no está publicada
    expect(screen.queryByText(/tok-abc/)).toBeNull()
    expect(screen.queryByRole('button', { name: /copiar enlace/i })).toBeNull()
  })

  it('EL TEXTO DEL CONSENTIMIENTO está presente ANTES de encender', async () => {
    pintar()
    await screen.findByRole('button', { name: /publicar mi tarjeta/i })

    // Las tres cosas que hay que saber para consentir: quién puede verla, que no hace falta sesión,
    // y qué datos quedan expuestos.
    expect(screen.getByText(/cualquier persona que tenga el enlace/i)).toBeTruthy()
    expect(screen.getByText(/sin iniciar sesión/i)).toBeTruthy()
    expect(screen.getByText(/tu nombre, tu cargo, tu territorio, tus/i)).toBeTruthy()
    expect(screen.getByText(/no controlás a quién se lo pasan/i)).toBeTruthy()

    // Y que revocar MATA el enlace, no que esconde un botón.
    expect(screen.getByText(/el enlace deja de responder de inmediato/i)).toBeTruthy()
    expect(screen.getByText(/no se\s+esconde un botón/i)).toBeTruthy()
  })

  it('publicar llama a la RPC con true y no manda id de asesor', async () => {
    pintar()
    const b = await screen.findByRole('button', { name: /publicar mi tarjeta/i })
    fireEvent.click(b)
    await waitFor(() => expect(rpcs.length).toBe(1))
    expect(rpcs[0].nombre).toBe('tarjeta_set_consentimiento')
    expect(rpcs[0].args).toEqual({ p_activo: true })
    // el sujeto es auth.uid(): que la pantalla mande un id sería otra definición de "quién soy"
    expect(JSON.stringify(rpcs[0].args)).not.toContain('ase-1')
  })
})

describe('tarjeta publicada', () => {
  beforeEach(() => {
    ficha = { ...FICHA_BASE, tarjeta_publica: true, tarjeta_consentimiento_at: '2026-09-07T10:00:00Z' }
  })

  it('muestra el enlace completo, el botón de copiar y el de abrirla', async () => {
    pintar()
    await screen.findByText('Publicada')
    expect(screen.getByText(/\/t\/tok-abc$/)).toBeTruthy()
    expect(screen.getByRole('button', { name: /copiar enlace/i })).toBeTruthy()
    const abrir = screen.getByRole('link', { name: /ver mi tarjeta/i }) as HTMLAnchorElement
    expect(abrir.href).toContain('/t/tok-abc')
    expect(abrir.rel).toContain('noopener')
  })

  it('el botón pasa a DESpublicar', async () => {
    pintar()
    const b = await screen.findByRole('button', { name: /despublicar mi tarjeta/i })
    fireEvent.click(b)
    await waitFor(() => expect(rpcs.length).toBe(1))
    expect(rpcs[0].args).toEqual({ p_activo: false })
  })

  it('SIN foto: dice que se muestran las iniciales, y ofrece subir y no quitar', async () => {
    pintar()
    await screen.findByText('Publicada')
    expect(screen.getByText(/tu tarjeta muestra un círculo con tus iniciales/i)).toBeTruthy()
    expect(screen.getByRole('button', { name: /subir foto/i })).toBeTruthy()
    expect(screen.queryByRole('button', { name: /quitar foto/i })).toBeNull()
    // el avatar de vista previa es el placeholder con las iniciales de "Ana Pérez"
    expect(screen.getByText('AP')).toBeTruthy()
  })

  it('CON foto: pinta la vista previa firmada, ofrece cambiarla y quitarla', async () => {
    ficha = { ...ficha!, foto_publica_path: 'ase-1/abc.png' }
    pintar()
    const img = await screen.findByAltText(/tu foto de la tarjeta/i) as HTMLImageElement
    expect(img.src).toBe('https://firmada.example/foto.png')
    expect(screen.getByRole('button', { name: /cambiar foto/i })).toBeTruthy()
    expect(screen.getByRole('button', { name: /quitar foto/i })).toBeTruthy()
    // y avisa qué implica quitarla
    expect(screen.getByText(/deja de mostrarla y la imagen deja de servirse/i)).toBeTruthy()
  })

  it('si la URL firmada falla, cae al placeholder y NO rompe la pantalla', async () => {
    // La foto pública se sigue sirviendo por la edge: acá sólo se pierde la vista previa.
    ficha = { ...ficha!, foto_publica_path: 'ase-1/abc.png' }
    firmaOk = false
    pintar()
    await screen.findByText('Publicada')
    await waitFor(() => expect(screen.getByText('AP')).toBeTruthy())
    expect(screen.queryByAltText(/tu foto de la tarjeta/i)).toBeNull()
  })

  it('quitar la foto manda NULL', async () => {
    ficha = { ...ficha!, foto_publica_path: 'ase-1/abc.png' }
    pintar()
    const b = await screen.findByRole('button', { name: /quitar foto/i })
    fireEvent.click(b)
    await waitFor(() => expect(rpcs.length).toBe(1))
    expect(rpcs[0].nombre).toBe('guardar_foto_publica_asesor')
    expect(rpcs[0].args).toEqual({ p_path: null })
  })
})

describe('rotar el enlace', () => {
  beforeEach(() => { ficha = { ...FICHA_BASE, tarjeta_publica: true } })

  it('NO rota al primer clic: primero dice qué rompe', async () => {
    pintar()
    fireEvent.click(await screen.findByRole('button', { name: /generar enlace nuevo/i }))

    expect(screen.getByText(/deja de funcionar para siempre/i)).toBeTruthy()
    expect(screen.getByText(/incluidos todos\s+los que ya compartiste/i)).toBeTruthy()
    expect(screen.getByText(/no se puede deshacer/i)).toBeTruthy()
    expect(rpcs.length).toBe(0)     // todavía no pasó nada
  })

  it('confirmar rota y RECARGA la ficha (la RPC devuelve void, no el token nuevo)', async () => {
    pintar()
    fireEvent.click(await screen.findByRole('button', { name: /generar enlace nuevo/i }))
    fireEvent.click(screen.getByRole('button', { name: /sí, generar uno nuevo/i }))

    await waitFor(() => expect(rpcs.length).toBe(1))
    expect(rpcs[0].nombre).toBe('tarjeta_rotar_token')
    // y el panel de confirmación se cierra
    await waitFor(() => expect(screen.queryByText(/sí, generar uno nuevo/i)).toBeNull())
  })

  it('cancelar no llama a nada', async () => {
    pintar()
    fireEvent.click(await screen.findByRole('button', { name: /generar enlace nuevo/i }))
    fireEvent.click(screen.getByRole('button', { name: /^cancelar$/i }))
    expect(rpcs.length).toBe(0)
    expect(screen.queryByText(/deja de funcionar para siempre/i)).toBeNull()
  })
})
