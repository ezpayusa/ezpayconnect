import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, within, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// Landing /planes-visitador: el catálogo sale SOLO de catalogo_planes_visitador_publico (mig 362, funciona sin sesión).
// El selector tiene solo los países que devuelve la RPC, y el país de la sesión (un uuid de configuracion_pais) se
// resuelve a su código: comparar el uuid contra el código dejaba todos los planes en "No disponible".

const CATALOGO = [
  { pais_codigo: 'GT', pais_nombre: 'Guatemala', config_id: 'cfg-gt-1', plan_nombre: 'Plan Bronce', plan_descripcion: 'Básico', precio: 250, moneda: 'GTQ', visitas: 20, duracion_dias: 30 },
  { pais_codigo: 'GT', pais_nombre: 'Guatemala', config_id: 'cfg-gt-2', plan_nombre: 'Plan Plata', plan_descripcion: 'Intermedio', precio: 450, moneda: 'GTQ', visitas: 50, duracion_dias: 30 },
  { pais_codigo: 'HN', pais_nombre: 'Honduras', config_id: 'cfg-hn-1', plan_nombre: 'Plan Hondureño', plan_descripcion: null, precio: 900, moneda: 'HNL', visitas: 40, duracion_dias: 60 },
]

let catalogo: { data: unknown; error: unknown } = { data: CATALOGO, error: null }
let proveedor: { user: unknown; cuenta: unknown; empresa: unknown } = { user: null, cuenta: null, empresa: null }
const codigosPorId: Record<string, string> = { 'uuid-hn': 'HN', 'uuid-gt': 'GT' }
const rpcs: string[] = []

// Cadena de PostgREST tolerante: la versión vieja leía planes_base/planes_configuracion/configuracion_pais por acá.
const cadena = (tabla: string) => {
  const filtros: Record<string, unknown> = {}
  const q: any = {}
  for (const m of ['select', 'in', 'order', 'limit', 'neq', 'is', 'or', 'gte', 'lte']) q[m] = () => q
  q.eq = (col: string, val: unknown) => {
    filtros[col] = val
    return q
  }
  q.maybeSingle = async () =>
    tabla === 'configuracion_pais' && filtros.id === 'uuid-error'
      ? { data: null, error: { code: 'PGRST301', message: 'JWT expired' } }
      : tabla === 'configuracion_pais' && typeof filtros.id === 'string' && codigosPorId[filtros.id]
        ? { data: { codigo: codigosPorId[filtros.id] }, error: null }
        : { data: null, error: null }
  q.single = q.maybeSingle
  q.then = (ok: any, ko: any) => Promise.resolve({ data: [], error: null }).then(ok, ko)
  return q
}

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string) => {
      rpcs.push(nombre)
      if (nombre === 'catalogo_planes_visitador_publico') return catalogo
      return { data: null, error: null }
    },
    from: (tabla: string) => cadena(tabla),
  },
}))
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: proveedor.user, perfil: null, loading: false }) }))
vi.mock('@/hooks/usePaisFiltro', () => ({ usePaisFiltro: () => ({ paisId: undefined, tienePais: false, esAdmin: false }) }))
vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({ useProveedorAuth: () => ({ ...proveedor, loading: false }) }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

const { default: PlanesVisitadorPage } = await import('./PlanesVisitadorPage')

const pintar = () =>
  render(
    <MemoryRouter>
      <PlanesVisitadorPage />
    </MemoryRouter>
  )
const botonesPais = () => within(screen.getByRole('group', { name: 'País' })).getAllByRole('button')

beforeEach(() => {
  catalogo = { data: CATALOGO, error: null }
  proveedor = { user: null, cuenta: null, empresa: null }
  rpcs.length = 0
})

describe('PlanesVisitadorPage (landing pública)', () => {
  it('sin sesión: muestra los planes de la RPC y el selector solo tiene sus países', async () => {
    pintar()
    expect(await screen.findByText('Plan Bronce')).toBeInTheDocument()
    expect(rpcs).toContain('catalogo_planes_visitador_publico')
    const paises = botonesPais().map((b) => b.textContent ?? '')
    expect(paises).toHaveLength(2)
    expect(paises[0]).toContain('Guatemala')
    expect(paises[1]).toContain('Honduras')
    // primer país del catálogo
    expect(screen.getByRole('button', { name: /Guatemala/, pressed: true })).toBeInTheDocument()
    expect(screen.getByText('Plan Plata')).toBeInTheDocument()
    expect(screen.queryByText('Plan Hondureño')).not.toBeInTheDocument()
    expect(screen.getByText('Q250.00')).toBeInTheDocument()
    expect(screen.getByText('20 visitas para todo su equipo')).toBeInTheDocument()
    expect(screen.queryByText(/No disponible/)).not.toBeInTheDocument()
    expect(screen.queryByText('Recomendado')).not.toBeInTheDocument()
    // GL-40: solo lo que existe. El check-out guarda notas (sin evidencia) y el admin ve el reporte, no la ruta de cada visitador.
    expect(screen.getAllByText('Check-in con foto y check-out con notas').length).toBeGreaterThan(0)
    expect(screen.queryByText(/con evidencia/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Usted ve la ruta del día/)).not.toBeInTheDocument()

    // sin sesión de proveedor: sin fila "Usuario" y con el aviso de ingreso
    fireEvent.click(screen.getAllByRole('button', { name: /Elegir plan/ })[0])
    expect(await screen.findByText(/Para comprar, ingrese con la cuenta de su empresa proveedora/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Ingresar' })).toHaveAttribute('href', '/proveedor/login')
    expect(screen.queryByText('Usuario:')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Continuar: pago por transferencia/ })).not.toBeInTheDocument()
  })

  it('con sesión cuyo país es un uuid: el país inicial se selecciona por su código y los planes están disponibles', async () => {
    proveedor = {
      user: { email: 'proveedor@qa.test' },
      cuenta: { id: 'c1', pais_id: null },
      empresa: { id: 'e1', pais_id: 'uuid-hn' },
    }
    pintar()
    expect(await screen.findByText('Plan Hondureño')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Honduras/, pressed: true })).toBeInTheDocument()
    expect(screen.queryByText('Plan Bronce')).not.toBeInTheDocument()
    expect(screen.queryByText(/No disponible/)).not.toBeInTheDocument()
    expect(screen.getByText('40 visitas para todo su equipo')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /Elegir plan/ }))
    expect(await screen.findByRole('button', { name: /Continuar: pago por transferencia/ })).toBeInTheDocument()
    expect(screen.getByText('Usuario:')).toBeInTheDocument()
    expect(screen.getByText(/la vigencia se extiende 60 días/)).toBeInTheDocument()
  })

  it('cuenta en HN y empresa en GT: el país inicial es el de la empresa (GT)', async () => {
    proveedor = {
      user: { email: 'proveedor@qa.test' },
      cuenta: { id: 'c1', pais_id: 'uuid-hn' },
      empresa: { id: 'e1', pais_id: 'uuid-gt' },
    }
    pintar()
    expect(await screen.findByText('Plan Bronce')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Guatemala/, pressed: true })).toBeInTheDocument()
    expect(screen.queryByText('Plan Hondureño')).not.toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: /Elegir plan/ }).length).toBeGreaterThan(0)
  })

  it('empresa en GT que elige HN: sin botón de compra y con el aviso del país de la empresa', async () => {
    proveedor = {
      user: { email: 'proveedor@qa.test' },
      cuenta: { id: 'c1', pais_id: null },
      empresa: { id: 'e1', pais_id: 'uuid-gt' },
    }
    pintar()
    expect(await screen.findByText('Plan Bronce')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Honduras/ }))
    expect(await screen.findByText('Plan Hondureño')).toBeInTheDocument()
    expect(screen.getByText('Su empresa puede comprar planes solo en Guatemala.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Elegir plan/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Continuar: pago por transferencia/ })).not.toBeInTheDocument()
  })

  it('si no se puede resolver el país: console.error con mensaje fijo y el primer país del catálogo', async () => {
    const espia = vi.spyOn(console, 'error').mockImplementation(() => {})
    proveedor = {
      user: { email: 'proveedor@qa.test' },
      cuenta: { id: 'c1', pais_id: null },
      empresa: { id: 'e1', pais_id: 'uuid-error' },
    }
    pintar()
    expect(await screen.findByText('Plan Bronce')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Guatemala/, pressed: true })).toBeInTheDocument()
    expect(espia).toHaveBeenCalledWith('[planes-visitador] no se pudo resolver el país:', 'PGRST301')
    espia.mockRestore()
  })

  it('error de la RPC: mensaje fijo, nunca el texto de Postgres', async () => {
    catalogo = { data: null, error: { code: '42501', message: 'permission denied for function catalogo_planes_visitador_publico' } }
    pintar()
    expect(await screen.findByText('No pudimos cargar los planes. Intente de nuevo en unos minutos.')).toBeInTheDocument()
    expect(screen.queryByText(/permission denied/)).not.toBeInTheDocument()
  })

  it('catálogo vacío: aviso sin invitar a escribir a un canal que no existe (GL-40)', async () => {
    catalogo = { data: [], error: null }
    pintar()
    expect(await screen.findByText('Por ahora no hay planes de visitas a la venta en este país.')).toBeInTheDocument()
    expect(screen.queryByText(/Escriba al equipo/)).not.toBeInTheDocument()
  })
})
