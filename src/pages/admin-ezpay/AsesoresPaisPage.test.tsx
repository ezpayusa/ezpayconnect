import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

// Cuatro cosas que esta pantalla tiene que hacer bien y que son fáciles de romper sin notarlo:
//  1. Un vacío EXPLICADO, no mudo: la lista de pendientes vacía se lee como error de carga si no
//     dice por qué está vacía. Las RPCs niegan devolviendo [] y no 42501, así que la pantalla no
//     puede distinguir "no hay nadie" de "no sos admin": el texto cubre el caso normal.
//  2. Las fichas INACTIVAS se listan. Filtrarlas las dejaría inalcanzables desde la única pantalla
//     que puede reactivarlas.
//  3. El 23505 lleva el contexto de ESTA pantalla (código repetido), no el genérico del mapa.
//  4. PA004 se ve PEGADO A LA FILA. Llega como toast desde el mapa y puede aparecer con un
//     candidato que SÍ está en el selector —la RPC de candidatos no anticipa la regla de dos
//     niveles—, así que un toast que se va dejaría al usuario sin saber qué pasó.
const rpcs: { nombre: string; args: Record<string, unknown> }[] = []
let errorGuardar: unknown = null
let errorAsignar: unknown = null
let errorApagar: unknown = null
let pendientes: unknown[] = []
let fichas: unknown[] = []

vi.mock('@/comercial/lib/api', () => ({
  perfilesSinFicha: async () => ({ data: pendientes, error: null }),
  listarFichasDePais: async () => ({ data: fichas, error: null }),
  supervisoresDelPais: async () => ({
    data: [{ id: 'sup-1', nombre_completo: 'Supervisor Uno' }], error: null,
  }),
  asesoresConNombre: async () => ({
    data: [
      { id: 'ase-1', codigo_asesor: 'GT-ASE-01', nombre_completo: 'Asesor Uno', activo: true, supervisor_id: null },
      { id: 'ase-off', codigo_asesor: 'GT-ASE-09', nombre_completo: 'Asesor Inactivo', activo: false, supervisor_id: null },
      { id: 'sup-1', codigo_asesor: 'GT-SUP-01', nombre_completo: 'Supervisor Uno', activo: true, supervisor_id: null },
    ],
    error: null,
  }),
  mapaAsesores: (f: { id: string }[] | null) => new Map((f ?? []).map(a => [a.id, a])),
  nombreAsesor: (id: string | null, m: Map<string, { nombre_completo: string | null }>) =>
    (id ? m.get(id)?.nombre_completo ?? 'asesor no visible' : 'sin asesor'),
  guardarAsesorPerfil: async (args: Record<string, unknown>) => {
    rpcs.push({ nombre: 'guardarAsesorPerfil', args }); return { data: null, error: errorGuardar }
  },
  asignarSupervisor: async (asesorId: string, supervisorId: string | null) => {
    rpcs.push({ nombre: 'asignarSupervisor', args: { asesorId, supervisorId } })
    return { data: null, error: errorAsignar }
  },
  apagarTarjetaDeAsesor: async (asesorId: string) => {
    rpcs.push({ nombre: 'apagarTarjetaDeAsesor', args: { asesorId } })
    return { data: null, error: errorApagar }
  },
}))
vi.mock('@/comercial/lib/reportarError', () => ({
  reportarError: (e: { code?: string }, o?: { setInline?: (v: unknown) => void }) => {
    // Doble mínimo del despacho real: inline va al setter, toast no.
    const inline = e?.code === '23505'
    if (inline) o?.setInline?.({ campo: 'nombre', mensaje: 'Ya existe un registro con esos datos.' })
    return { code: e?.code ?? null, mensaje: e?.code === 'PA004'
      ? 'PA004: el supervisor propuesto ya tiene supervisor (máximo dos niveles)'
      : 'error', destino: inline ? 'inline' : 'toast', reportar: false }
  },
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))

const { default: AsesoresPaisPage } = await import('./AsesoresPaisPage')

const pintar = () => render(
  <MemoryRouter initialEntries={['/admin-ezpay/pais/gt/asesores']}>
    <Routes><Route path="/admin-ezpay/pais/:paisId/asesores" element={<AsesoresPaisPage />} /></Routes>
  </MemoryRouter>,
)

const FICHA_ACTIVA = {
  id: 'ase-1', codigo_asesor: 'GT-ASE-01', pais_id: 'gt', supervisor_id: null,
  cargo: 'Ejecutivo', territorio: 'Zona 1', telefono: null, celular: null,
  fecha_ingreso: null, activo: true, tarjeta_publica: false,
}
const FICHA_INACTIVA = {
  id: 'ase-off', codigo_asesor: 'GT-ASE-09', pais_id: 'gt', supervisor_id: null,
  cargo: null, territorio: null, telefono: null, celular: null, fecha_ingreso: null, activo: false,
  tarjeta_publica: false,
}

beforeEach(() => {
  rpcs.length = 0; errorGuardar = null; errorAsignar = null; errorApagar = null
  pendientes = []; fichas = [FICHA_ACTIVA]
})

describe('AsesoresPaisPage — los vacíos se explican', () => {
  it('sin perfiles pendientes, dice POR QUÉ está vacío y de dónde salen las cuentas', async () => {
    pintar()
    await waitFor(() => {
      expect(screen.getByText(/No hay perfiles comerciales pendientes de ficha/)).toBeInTheDocument()
    })
    expect(screen.getByText(/Asignación de Roles/)).toBeInTheDocument()
  })
})

describe('AsesoresPaisPage — las fichas inactivas se ven', () => {
  it('lista la ficha inactiva y la marca como tal: si no, nadie podría reactivarla', async () => {
    fichas = [FICHA_ACTIVA, FICHA_INACTIVA]
    pintar()
    await waitFor(() => expect(screen.getByTestId('editar-ase-off')).toBeInTheDocument())
    expect(screen.getByText('inactiva')).toBeInTheDocument()
    expect(screen.getByText('activa')).toBeInTheDocument()
  })
})

describe('AsesoresPaisPage — alta de ficha', () => {
  it('el país viaja SIEMPRE el de la ruta, no un campo del formulario', async () => {
    pendientes = [{ id: 'p-nuevo', nombre_completo: 'Perfil Nuevo', rol: 'asesor_comercial' }]
    pintar()
    fireEvent.click(await screen.findByTestId('crear-ficha-p-nuevo'))
    fireEvent.change(document.getElementById('codigo_asesor')!, { target: { value: 'GT-ASE-77' } })
    fireEvent.click(screen.getByRole('button', { name: 'Guardar ficha nueva' }))
    await waitFor(() => expect(rpcs).toHaveLength(1))
    expect(rpcs[0].nombre).toBe('guardarAsesorPerfil')
    expect(rpcs[0].args).toMatchObject({ asesorId: 'p-nuevo', paisId: 'gt', codigoAsesor: 'GT-ASE-77' })
    // no hay control de país en la UI: nada puede mandar otro
    expect(document.getElementById('pais_id')).toBeNull()
  })

  it('el 23505 dice CÓDIGO REPETIDO, no el genérico del mapa', async () => {
    pendientes = [{ id: 'p-nuevo', nombre_completo: 'Perfil Nuevo', rol: 'asesor_comercial' }]
    errorGuardar = { code: '23505', message: 'duplicate key value violates unique constraint "asesores_perfil_pais_codigo_uniq"' }
    pintar()
    fireEvent.click(await screen.findByTestId('crear-ficha-p-nuevo'))
    fireEvent.change(document.getElementById('codigo_asesor')!, { target: { value: 'GT-ASE-01' } })
    fireEvent.click(screen.getByRole('button', { name: 'Guardar ficha nueva' }))
    await waitFor(() => {
      expect(screen.getByText('Ya hay otra ficha con ese código en este país. Elegí otro.')).toBeInTheDocument()
    })
    expect(screen.queryByText('Ya existe un registro con esos datos.')).not.toBeInTheDocument()
  })
})

describe('AsesoresPaisPage — etiquetas', () => {
  it('el botón que ABRE y el que GUARDA no se llaman igual', async () => {
    pendientes = [{ id: 'p-nuevo', nombre_completo: 'Perfil Nuevo', rol: 'asesor_comercial' }]
    pintar()
    fireEvent.click(await screen.findByTestId('crear-ficha-p-nuevo'))
    // con el formulario abierto, "Crear ficha" tiene que seguir siendo UNO solo
    expect(screen.getAllByRole('button', { name: 'Crear ficha' })).toHaveLength(1)
    expect(screen.getByRole('button', { name: 'Guardar ficha nueva' })).toBeInTheDocument()
  })
})

describe('AsesoresPaisPage — supervisor', () => {
  it('"— sin supervisor —" manda null: desasignar es válido', async () => {
    fichas = [{ ...FICHA_ACTIVA, supervisor_id: 'sup-1' }]
    pintar()
    const sel = await screen.findByTestId('supervisor-ase-1')
    fireEvent.change(sel, { target: { value: '' } })
    await waitFor(() => expect(rpcs).toHaveLength(1))
    expect(rpcs[0].nombre).toBe('asignarSupervisor')
    expect(rpcs[0].args).toEqual({ asesorId: 'ase-1', supervisorId: null })
  })

  it('PA004 se muestra PEGADO A LA FILA, aunque el mapa lo mande a toast', async () => {
    errorAsignar = { code: 'PA004', message: 'PA004: máximo dos niveles' }
    pintar()
    const sel = await screen.findByTestId('supervisor-ase-1')
    fireEvent.change(sel, { target: { value: 'sup-1' } })
    await waitFor(() => {
      expect(screen.getByText(/máximo dos niveles/)).toBeInTheDocument()
    })
  })

  it('un asesor no se ofrece como supervisor de sí mismo', async () => {
    fichas = [{ ...FICHA_ACTIVA, id: 'sup-1', codigo_asesor: 'GT-SUP-01' }]
    pintar()
    const sel = await screen.findByTestId('supervisor-sup-1') as HTMLSelectElement
    const valores = Array.from(sel.options).map(o => o.value)
    expect(valores).not.toContain('sup-1')
    expect(valores).toContain('')
  })
})

// ------------------------------------------------------------------ tarjeta pública (pieza 4b)
// El admin de país SOLO PUEDE APAGAR. Encender es del dueño de la cara y del teléfono, y la RPC ni
// siquiera acepta el caso. Lo que se mide acá es que la UI no sugiera lo contrario y que la
// confirmación diga las dos cosas: que el enlace muere ya, y que esto NO es permanente.
describe('tarjeta pública del asesor', () => {
  it('con la tarjeta APAGADA muestra el estado y NO ofrece despublicar', async () => {
    fichas = [{ ...FICHA_ACTIVA, tarjeta_publica: false }]
    pintar()
    await screen.findByTestId('tarjeta-estado-ase-1')
    expect(screen.getByTestId('tarjeta-estado-ase-1').textContent).toContain('tarjeta no publicada')
    expect(screen.queryByTestId('apagar-tarjeta-ase-1')).toBeNull()
  })

  it('NUNCA ofrece publicar: encender es del asesor, no del admin', async () => {
    for (const pub of [true, false]) {
      fichas = [{ ...FICHA_ACTIVA, tarjeta_publica: pub }]
      const { unmount } = pintar()
      await screen.findByTestId('tarjeta-estado-ase-1')
      expect(screen.queryByRole('button', { name: /^publicar/i })).toBeNull()
      unmount()
    }
  })

  it('con la tarjeta PUBLICADA ofrece despublicar, pero no apaga al primer clic', async () => {
    fichas = [{ ...FICHA_ACTIVA, tarjeta_publica: true }]
    pintar()
    fireEvent.click(await screen.findByTestId('apagar-tarjeta-ase-1'))

    // La confirmación dice LAS DOS cosas
    const caja = screen.getByTestId('confirmar-apagar-ase-1')
    expect(caja.textContent).toContain('deja de responder de')
    expect(caja.textContent).toContain('No es permanente')
    expect(caja.textContent).toContain('volver a publicarla')
    expect(rpcs.length).toBe(0)     // todavía no pasó nada
  })

  it('confirmar llama a la RPC con el id del asesor y nada más', async () => {
    fichas = [{ ...FICHA_ACTIVA, tarjeta_publica: true }]
    pintar()
    fireEvent.click(await screen.findByTestId('apagar-tarjeta-ase-1'))
    fireEvent.click(screen.getByTestId('confirmar-apagar-si-ase-1'))

    await waitFor(() => expect(rpcs.length).toBe(1))
    expect(rpcs[0].nombre).toBe('apagarTarjetaDeAsesor')
    // El país NO viaja: sale de la ficha dentro de la RPC. Mandarlo sería un parámetro de scope.
    expect(rpcs[0].args).toEqual({ asesorId: 'ase-1' })
  })

  it('cancelar no llama a nada y cierra la confirmación', async () => {
    fichas = [{ ...FICHA_ACTIVA, tarjeta_publica: true }]
    pintar()
    fireEvent.click(await screen.findByTestId('apagar-tarjeta-ase-1'))
    fireEvent.click(screen.getByRole('button', { name: /^cancelar$/i }))
    expect(rpcs.length).toBe(0)
    expect(screen.queryByTestId('confirmar-apagar-ase-1')).toBeNull()
  })

  it('el estado de la TARJETA es independiente del `activo` de la ficha', async () => {
    // Una ficha activa con la tarjeta apagada es el DEFAULT, no una anomalía: son dos flags
    // distintos y pintarlos como uno solo escondería el caso normal.
    fichas = [{ ...FICHA_ACTIVA, activo: true, tarjeta_publica: false }]
    pintar()
    await screen.findByTestId('tarjeta-estado-ase-1')
    expect(screen.getByText('activa')).toBeTruthy()
    expect(screen.getByTestId('tarjeta-estado-ase-1').textContent).toContain('no publicada')
  })
})

// ############################################################################################
// El error inline necesita DOS mitades, y se mantienen a mano en lugares distintos
// ############################################################################################
// Pintar un error inline pegado a su input exige: (a) el `errDe('<campo>')` en el JSX, que es lo
// único que dibuja, y (b) el campo en CAMPOS_DEL_FORM, que APAGA el fallback del pie para no
// duplicarlo. Con sólo (b) el mensaje no sale por ningún lado: se setea, corta el guardado y no se
// ve — así estuvieron PA033 y PA034 desde la mig 290 hasta el 8-sep, y ningún test lo notó porque
// todos los inline anteriores apuntaban a `codigo_asesor`, que sí tenía las dos mitades.
// Este test se cuenta contra el ARCHIVO, no contra una lista escrita acá: una lista de memoria
// tendría el mismo defecto que está vigilando.
describe('AsesoresPaisPage — el pie y los inputs cubren los mismos campos', () => {
  it('CAMPOS_DEL_FORM y los errDe(...) del JSX son EXACTAMENTE el mismo conjunto', async () => {
    // ruta desde la raiz del repo: en jsdom `import.meta.url` no es un file:// URL
    const fs = await import('node:fs')
    const src = fs.readFileSync('src/pages/admin-ezpay/AsesoresPaisPage.tsx', 'utf8')

    const decl = src.match(/const CAMPOS_DEL_FORM = \[([^\]]*)\]/)
    expect(decl, 'no se encontró la declaración de CAMPOS_DEL_FORM en el archivo').not.toBeNull()
    const declarados = [...(decl?.[1] ?? '').matchAll(/'([^']+)'/g)].map(m => m[1])
    expect(declarados.length, 'CAMPOS_DEL_FORM salió vacío: el regex dejó de calzar').toBeGreaterThan(0)

    // Una mención en un COMENTARIO no dibuja nada. Sin sacarlas, un `// falta errDe('x')` haría
    // pasar el test sobre un campo que sigue mudo.
    const codigo = src.split('\n').filter(l => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n')
    const pintados = [...codigo.matchAll(/errDe\('([^']+)'\)/g)].map(m => m[1])
    expect(pintados.length, 'no se encontró ninguna llamada a errDe(...) en el JSX').toBeGreaterThan(0)

    const mudos = declarados.filter(c => !pintados.includes(c))
    const dobles = pintados.filter(c => !declarados.includes(c))

    expect(mudos, 'MUDOS — están en CAMPOS_DEL_FORM (que apaga el fallback del pie) pero no tienen '
      + "errDe(...) en el JSX, así que su mensaje no se ve en NINGÚN lado. Poné {errDe('<campo>')} "
      + 'debajo de su input, o sacalos de la lista para que caigan al pie: ' + JSON.stringify(mudos))
      .toEqual([])
    expect(dobles, 'DUPLICADOS — tienen errDe(...) en el JSX pero no están en CAMPOS_DEL_FORM, así '
      + 'que su mensaje se pinta dos veces, pegado al input y otra vez al pie. Agregalos a '
      + 'CAMPOS_DEL_FORM: ' + JSON.stringify(dobles))
      .toEqual([])
  })
})
