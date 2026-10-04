import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// Checkout de campaña (mig 359): lo que se muestra como "Total a pagar" sale SOLO de cotizar_campana. El ?monto= de la
// URL (que un proveedor puede editar a mano) y la moneda de la cuenta bancaria no cuentan. Si no hay cotización, no se
// muestra ningún monto.

let cotizacion: { data: unknown; error: unknown } = { data: [{ monto: 3500, moneda: 'GTQ' }], error: null }
const rpcs: { nombre: string; args: unknown }[] = []

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string, args: unknown) => {
      rpcs.push({ nombre, args })
      if (nombre === 'cotizar_campana') return cotizacion
      return { data: null, error: null }
    },
  },
}))
vi.mock('@/proveedor/hooks/usePagosProveedor', () => ({
  usePagosProveedor: () => ({
    crearPago: vi.fn(),
    solicitarCompraPlanVisitador: vi.fn(),
    solicitarPagoCampana: vi.fn(),
    saving: false,
  }),
}))
vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({
  useProveedorAuth: () => ({ empresa: { id: 'emp-1', pais_id: 'pais-gt' } }),
}))
// la cuenta en otra moneda: si el total la usara, el test lo nota
vi.mock('@/proveedor/hooks/useCuentaBancariaCheckout', () => ({
  useCuentaBancariaCheckout: () => ({
    cuenta: { banco: 'Banco QA', numero_cuenta: '123', tipo_cuenta: 'monetaria', titular: 'EzPay', moneda: 'USD' },
    loading: false,
  }),
}))
vi.mock('@/proveedor/hooks/useConfigPlanVisitador', () => ({
  useConfigPlanVisitador: () => ({ config: null, loading: false }),
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

const { default: PagoCheckoutPage } = await import('./PagoCheckoutPage')

// Intl separa símbolo y monto con un espacio duro (U+00A0); testing-library normaliza el texto del DOM a espacio común.
const fmt = (monto: number, moneda: string) =>
  new Intl.NumberFormat('es-GT', { style: 'currency', currency: moneda }).format(monto).replace(/\s/g, ' ')
const pintar = (url: string) =>
  render(
    <MemoryRouter initialEntries={[url]}>
      <PagoCheckoutPage />
    </MemoryRouter>
  )

beforeEach(() => {
  cotizacion = { data: [{ monto: 3500, moneda: 'GTQ' }], error: null }
  rpcs.length = 0
})

describe('PagoCheckoutPage — campaña', () => {
  it('muestra el monto de cotizar_campana e ignora ?monto= de la URL', async () => {
    pintar('/proveedor/checkout?tipo=campana&referencia_id=sol-1&monto=1&descripcion=Banner%20Profesional')
    expect(await screen.findByText(fmt(3500, 'GTQ'))).toBeInTheDocument()
    expect(screen.queryByText(fmt(1, 'GTQ'))).not.toBeInTheDocument()
    expect(screen.queryByText(fmt(1, 'USD'))).not.toBeInTheDocument()
    expect(rpcs).toContainEqual({ nombre: 'cotizar_campana', args: { p_solicitud_id: 'sol-1' } })
  })

  it('si cotizar_campana falla no muestra ningún monto (ni el de la URL)', async () => {
    cotizacion = { data: null, error: { code: 'CA010', message: 'sin precio' } }
    pintar('/proveedor/checkout?tipo=campana&referencia_id=sol-1&monto=1&descripcion=Banner%20Profesional')
    expect(await screen.findByText('El plan de esta campaña no tiene precio para tu país')).toBeInTheDocument()
    await waitFor(() => expect(screen.queryByText('Total a pagar')).not.toBeInTheDocument())
    expect(screen.queryByText(fmt(1, 'GTQ'))).not.toBeInTheDocument()
    expect(screen.queryByText(fmt(1, 'USD'))).not.toBeInTheDocument()
  })
})
