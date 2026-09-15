import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'

// Lo que se mide acá es lo que el visor PROMETE y que un test de "renderiza sin romper" no vería:
//   1. el token de la URL firmada NUNCA llega al DOM — se muestra un blob: local;
//   2. el blob se revoca al cerrar y al cambiar de archivo (si no, cada RX abierto queda en memoria);
//   3. un archivo que no carga dice POR QUÉ y nunca deja la pantalla en blanco;
//   4. "sin acceso" no ofrece reintentar (reintentar no va a cambiar la RLS); "red" sí.
// La cadena firma → fetch → blob es la REAL de signedUrl.ts; sólo se simulan supabase y la red.

const SECRETO = 'TOKEN-SECRETO-NO-DEBE-VERSE'
let firmaFalla = false

vi.mock('@/lib/supabase', () => ({
  supabase: {
    storage: {
      from: () => ({
        createSignedUrl: async (path: string) => firmaFalla
          ? { data: null, error: { message: 'Object not found' } }
          : { data: { signedUrl: `https://storage.example/${path}?token=${SECRETO}` }, error: null },
      }),
    },
  },
}))

const { default: VisorArchivos } = await import('./VisorArchivos')

let fetchMock: ReturnType<typeof vi.fn>
let creados: string[]
let revocados: string[]

beforeEach(() => {
  firmaFalla = false
  creados = []
  revocados = []
  fetchMock = vi.fn(async () => new Response(new Blob(['img'], { type: 'image/png' }), { status: 200 }))
  vi.stubGlobal('fetch', fetchMock)
  // jsdom no implementa object URLs.
  URL.createObjectURL = vi.fn(() => { const u = `blob:local/${creados.length + 1}`; creados.push(u); return u })
  URL.revokeObjectURL = vi.fn((u: string) => { revocados.push(u) })
})
afterEach(() => vi.unstubAllGlobals())

const A = { bucket: 'resultados-examenes', path: 'lab/1-111.png' }
const B = { bucket: 'resultados-examenes', path: 'lab/2-222.png' }

describe('VisorArchivos', () => {
  it('muestra la imagen desde un blob: local y el token de la firma no aparece en el DOM', async () => {
    render(<VisorArchivos archivos={[A]} indice={0} onIndice={() => {}} onCerrar={() => {}} />)
    const img = await screen.findByRole('img', { name: '1-111.png' })
    expect(img.getAttribute('src')).toBe('blob:local/1')
    expect(document.body.innerHTML).not.toContain(SECRETO)
    expect(document.body.innerHTML).not.toContain('storage.example')
  })

  it('al cerrar, revoca el blob', async () => {
    const onCerrar = vi.fn()
    const { unmount } = render(<VisorArchivos archivos={[A]} indice={0} onIndice={() => {}} onCerrar={onCerrar} />)
    await screen.findByRole('img')
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar visor' }))
    expect(onCerrar).toHaveBeenCalled()
    unmount() // useVisor desmonta el visor al cerrar
    expect(revocados).toContain('blob:local/1')
  })

  it('navega entre adjuntos y revoca el blob del anterior al cambiar', async () => {
    let indice = 0
    const { rerender } = render(
      <VisorArchivos archivos={[A, B]} indice={indice} onIndice={(i) => { indice = i }} onCerrar={() => {}} />,
    )
    await screen.findByRole('img', { name: '1-111.png' })
    expect(screen.getByText('1 / 2')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Archivo siguiente' }))
    expect(indice).toBe(1)
    rerender(<VisorArchivos archivos={[A, B]} indice={indice} onIndice={(i) => { indice = i }} onCerrar={() => {}} />)
    await screen.findByRole('img', { name: '2-222.png' })
    expect(screen.getByText('2 / 2')).toBeInTheDocument()
    expect(revocados).toContain('blob:local/1')
  })

  it('sin acceso: explica y NO ofrece reintentar', async () => {
    firmaFalla = true
    render(<VisorArchivos archivos={[A]} indice={0} onIndice={() => {}} onCerrar={() => {}} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('No tienes acceso a este archivo o ya no está disponible.')
    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('corte de red: explica y reintentar vuelve a pedir el archivo', async () => {
    fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'))
    render(<VisorArchivos archivos={[A]} indice={0} onIndice={() => {}} onCerrar={() => {}} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Revisa tu conexión')
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    await screen.findByRole('img', { name: '1-111.png' })
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('los controles de zoom cambian la escala y el de rotar gira 90°', async () => {
    render(<VisorArchivos archivos={[A]} indice={0} onIndice={() => {}} onCerrar={() => {}} />)
    const img = await screen.findByRole('img')
    fireEvent.click(screen.getByRole('button', { name: 'Acercar' }))
    fireEvent.click(screen.getByRole('button', { name: 'Rotar' }))
    await waitFor(() => expect(img.style.transform).toContain('scale(1.25)'))
    expect(img.style.transform).toContain('rotate(90deg)')
  })
})
