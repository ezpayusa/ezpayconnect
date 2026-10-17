import { describe, it, expect, vi, beforeEach } from 'vitest'

// El PAYLOAD de las RPCs de agenda es contrato con la mig 280: `p_hora` viaja SIEMPRE, en null
// cuando no se envía. Si un día se omitiera, PostgREST resolvería igual por el DEFAULT — hasta que
// alguien agregue otra sobrecarga y la resolución se vuelva ambigua. Se fija acá.
const rpcs: { nombre: string; args: Record<string, unknown> }[] = []
const consultas: { tabla: string; ops: string[] }[] = []

function query(tabla: string) {
  const ops: string[] = []
  consultas.push({ tabla, ops })
  const q: Record<string, unknown> = {}
  for (const m of ['select', 'eq', 'gt', 'order']) {
    q[m] = (...a: unknown[]) => { ops.push(`${m}(${a.map(x => JSON.stringify(x)).join(',')})`); return q }
  }
  // termina la cadena: obtenerVisita la usa. Devuelve una promesa, no `q`.
  q.maybeSingle = async () => { ops.push('maybeSingle()'); return { data: null, error: null } }
  return q
}

// functions.invoke: cada test fija la respuesta de la edge en `invokeImpl`.
const invokes: { nombre: string; opciones: unknown }[] = []
const invokeDefault = async () => ({ data: null, error: null })
let invokeImpl: (nombre: string, opciones: unknown) => Promise<{ data: unknown; error: unknown }> = invokeDefault

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string, args: Record<string, unknown>) => { rpcs.push({ nombre, args }); return { data: null, error: null } },
    from: (tabla: string) => query(tabla),
    functions: {
      invoke: (nombre: string, opciones: unknown) => { invokes.push({ nombre, opciones }); return invokeImpl(nombre, opciones) },
    },
  },
}))

const api = await import('./api')

beforeEach(() => { rpcs.length = 0; consultas.length = 0; invokes.length = 0; invokeImpl = invokeDefault })

describe('payload de las 3 RPCs de agenda (mig 280)', () => {
  it('planificarVisita manda p_hora aunque no se pase: null explícito, no ausente', async () => {
    await api.planificarVisita('pros-1', '2026-09-10')
    expect(rpcs[0].nombre).toBe('planificar_visita')
    expect(rpcs[0].args).toEqual({ p_prospecto_id: 'pros-1', p_fecha: '2026-09-10', p_hora: null })
    expect('p_hora' in rpcs[0].args).toBe(true)
  })

  it('planificarVisita con hora la manda tal cual', async () => {
    await api.planificarVisita('pros-1', '2026-09-10', '10:30')
    expect(rpcs[0].args).toEqual({ p_prospecto_id: 'pros-1', p_fecha: '2026-09-10', p_hora: '10:30' })
  })

  it('reprogramarVisita: mismo criterio con p_hora', async () => {
    await api.reprogramarVisita('vis-1', '2026-09-11')
    expect(rpcs[0].nombre).toBe('reprogramar_visita_comercial')
    expect(rpcs[0].args).toEqual({ p_visita_id: 'vis-1', p_fecha: '2026-09-11', p_hora: null })
    await api.reprogramarVisita('vis-1', '2026-09-11', '08:15')
    expect(rpcs[1].args.p_hora).toBe('08:15')
  })

  it('cancelarVisita manda el motivo', async () => {
    await api.cancelarVisita('vis-1', 'El cliente pidió moverla')
    expect(rpcs[0].nombre).toBe('cancelar_visita_comercial')
    expect(rpcs[0].args).toEqual({ p_visita_id: 'vis-1', p_motivo: 'El cliente pidió moverla' })
  })
})

describe('visitasProximas — filtra estado y fecha, y NO filtra por asesor', () => {
  it('pide estado planificada y fecha ESTRICTAMENTE mayor a `desde`', async () => {
    await api.visitasProximas('2026-09-05')
    const ops = consultas[0].ops.join(' ')
    expect(consultas[0].tabla).toBe('visitas_comerciales')
    expect(ops).toContain('eq("estado","planificada")')
    expect(ops).toContain('gt("fecha_planificada","2026-09-05")')
    // gt y no gte: las de hoy ya salen en "Visitas de hoy"; duplicarlas seria mentir el conteo
    expect(ops).not.toContain('gte(')
  })

  it('ordena por fecha asc y hora asc con los NULL al final', async () => {
    await api.visitasProximas('2026-09-05')
    const ops = consultas[0].ops.join(' ')
    expect(ops).toContain('order("fecha_planificada",{"ascending":true})')
    expect(ops).toContain('order("hora_planificada",{"ascending":true,"nullsFirst":false})')
  })

  it('NO agrega ningún filtro de ownership: el conjunto lo arma la policy', async () => {
    await api.visitasProximas('2026-09-05')
    // Se miran SOLO las operaciones de filtro. Leer la columna asesor_id está bien —la lista la
    // muestra y el supervisor agrupa por ella—; lo prohibido es FILTRAR por ella en el cliente,
    // que sería una segunda definición de "de quién es la cartera".
    const filtros = consultas[0].ops.filter(o => /^(eq|gt|gte|lt|lte|in|is)\(/.test(o)).join(' ')
    expect(filtros).not.toContain('asesor_id')
    expect(filtros).not.toContain('pais_id')
    expect(filtros).toContain('estado')
  })

  it('visitasDelProspecto filtra por la clave del join y ordena descendente', async () => {
    await api.visitasDelProspecto('pros-1')
    const ops = consultas[0].ops.join(' ')
    expect(ops).toContain('eq("prospecto_id","pros-1")')
    expect(ops).toContain('order("fecha_planificada",{"ascending":false})')
    // el único filtro es la clave del join; nada de ownership
    const filtros = consultas[0].ops.filter(o => /^(eq|gt|gte|lt|lte|in|is)\(/.test(o))
    expect(filtros).toEqual(['eq("prospecto_id","pros-1")'])
  })
})

describe('las columnas de coordenada NO vuelven al select', () => {
  it('el select de visitas no pide checkin_lat/lng ni checkout_lat/lng (mig 277)', async () => {
    await api.visitasProximas('2026-09-05')
    const sel = consultas[0].ops.find(o => o.startsWith('select(')) ?? ''
    for (const c of ['checkin_lat', 'checkin_lng', 'checkout_lat', 'checkout_lng']) {
      expect(sel, `el select pide ${c}`).not.toContain(c)
    }
    // y sí trae lo que la agenda necesita
    for (const c of ['hora_planificada', 'planificada_por', 'cancelacion_motivo']) {
      expect(sel).toContain(c)
    }
    expect(sel).not.toContain('*')
  })
})

// Las coordenadas del PROSPECTO son otra cosa que las del check-in: son la dirección del negocio y
// `authenticated` sí puede leerlas. Pero sólo la ficha de UNA visita las necesita —y sólo para saber
// si son null, porque la distancia la calcula la RPC—, así que las listas no las bajan. La asimetría
// se fija acá porque es exactamente lo que un refactor "unificá los dos selects" rompería.
const selectDe = () => consultas[0].ops.find(o => o.startsWith('select(')) ?? ''

describe('el embed geo del prospecto viaja SOLO en la ficha de la visita', () => {
  for (const [nombre, correr] of [
    ['visitasDelDia (Equipo, Equipo del asesor y Hoy)', () => api.visitasDelDia('2026-09-05')],
    ['visitasProximas (Próximas)', () => api.visitasProximas('2026-09-05')],
    ['visitasDelProspecto (lista de la ficha del prospecto)', () => api.visitasDelProspecto('pros-1')],
  ] as [string, () => Promise<unknown>][]) {
    it(`${nombre} NO pide lat ni lng del prospecto`, async () => {
      await correr()
      const sel = selectDe()
      expect(sel).toContain('prospecto:prospectos')
      expect(sel).toContain('(nombre)')
      expect(sel, 'el embed trae lat').not.toContain('lat')
      expect(sel, 'el embed trae lng').not.toContain('lng')
    })
  }

  it('obtenerVisita SI las pide: es la pantalla del check-in', async () => {
    await api.obtenerVisita('vis-1')
    const sel = selectDe()
    expect(sel).toContain('(nombre,lat,lng)')
  })

  it('y aun con geo, obtenerVisita sigue sin pedir las coordenadas del CHECK-IN (mig 277)', async () => {
    await api.obtenerVisita('vis-1')
    const sel = selectDe()
    for (const c of ['checkin_lat', 'checkin_lng', 'checkout_lat', 'checkout_lng']) {
      expect(sel, `el select pide ${c}`).not.toContain(c)
    }
  })
})

// ############################################################################################
// CENSO: ninguna consulta de este modulo vuelve a nombrar `perfiles` (mig 283)
// ############################################################################################
// `perfiles` tiene UNA sola policy de SELECT util (`auth.uid() = id`), asi que todo embed a ella
// devolvia NULL para cualquier asesor que no fuera uno mismo — y el supervisor veia "sin asesor"
// en su propia cartera. El nombre ahora sale de comercial_asesores_visibles().
//
// Es CENSO y no cuatro casos: manana alguien agrega una consulta con un embed a perfiles y un test
// por funcion no se entera. La segunda mitad —que la lista cubra TODOS los .from() del archivo— es
// lo que impide que el censo se quede corto en silencio.
const LECTURAS: [string, () => Promise<unknown>][] = [
  ['listarProspectos', () => api.listarProspectos()],
  ['listarProspectosDePais', () => api.listarProspectosDePais('gt')],
  ['obtenerProspecto', () => api.obtenerProspecto('pros-1')],
  ['listarContactos', () => api.listarContactos('pros-1')],
  ['listarTipos', () => api.listarTipos()],
  ['listarEstados', () => api.listarEstados()],
  ['listarAsesores', () => api.listarAsesores()],
  ['jornadaDeHoy', () => api.jornadaDeHoy('ase-1')],
  ['jornadasDelDia', () => api.jornadasDelDia('2026-09-06')],
  ['asesoresVisibles', () => api.asesoresVisibles()],
  ['visitasDelDia', () => api.visitasDelDia('2026-09-06')],
  ['obtenerVisita', () => api.obtenerVisita('vis-1')],
  ['reporteDeVisita', () => api.reporteDeVisita('vis-1')],
  ['adjuntosDeVisita', () => api.adjuntosDeVisita('vis-1')],
  ['listarResultados', () => api.listarResultados()],
  ['visitasProximas', () => api.visitasProximas('2026-09-06')],
  ['visitasDelProspecto', () => api.visitasDelProspecto('pros-1')],
  ['listarFichasDePais', () => api.listarFichasDePais('gt')],
]

describe('ninguna consulta del modulo comercial nombra `perfiles`', () => {
  for (const [nombre, correr] of LECTURAS) {
    it(nombre + ' no embebe perfiles', async () => {
      await correr()
      const sel = consultas[0].ops.find(o => o.startsWith('select(')) ?? ''
      expect(sel, nombre + ' sigue embebiendo perfiles').not.toContain('perfiles')
      expect(sel).not.toContain('nombre_completo')
    })
  }

  it('el censo cubre TODAS las consultas del archivo, no una lista escrita de memoria', async () => {
    // Sin esto el censo se queda corto solo: se agrega una funcion nueva con un embed y ningun
    // test la ejercita. Se cuenta contra el fuente.
    // ruta desde la raiz del repo: en jsdom `import.meta.url` no es un file:// URL
    const fs = await import('node:fs')
    const src = fs.readFileSync('src/comercial/lib/api.ts', 'utf8')
    const froms = (src.match(/supabase\.from\(/g) ?? []).length
    expect(LECTURAS.length).toBe(froms)
    // y de paso: el fuente no tiene ni un embed a perfiles fuera de los comentarios
    const codigo = src.split('\n').filter(l => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n')
    expect(codigo).not.toContain('perfiles!')
  })
})

// ############################################################################################
// Los tres select('*') que quedaban, ahora explicitos
// ############################################################################################
describe('sin select(*): se piden SOLO las columnas que la pantalla pinta', () => {
  it('listarContactos pide id,nombre,puesto,email y nada mas', async () => {
    await api.listarContactos('pros-1')
    const sel = consultas[0].ops.find(o => o.startsWith('select(')) ?? ''
    expect(sel).toContain('id,nombre,puesto,email')
    // telefono, celular y notas existen en la tabla y la ficha NO los muestra
    for (const c of ['telefono', 'celular', 'notas', '*']) expect(sel).not.toContain(c)
  })

  it('reporteDeVisita pide id,resultado,resumen,compromisos', async () => {
    await api.reporteDeVisita('vis-1')
    const sel = consultas[0].ops.find(o => o.startsWith('select(')) ?? ''
    expect(sel).toContain('id,resultado,resumen,compromisos')
    expect(sel).not.toContain('*')
  })

  it('adjuntosDeVisita pide id,storage_path', async () => {
    await api.adjuntosDeVisita('vis-1')
    const sel = consultas[0].ops.find(o => o.startsWith('select(')) ?? ''
    expect(sel).toContain('id,storage_path')
    expect(sel).not.toContain('*')
  })
})

// ############################################################################################
// nombreAsesor: las TRES situaciones no se confunden nunca mas
// ############################################################################################
// Antes las tres caian en "sin asesor", y por eso un bug de RLS se leyo durante semanas como un
// dato faltante. Este test existe para que esa fusion no vuelva.
describe('nombreAsesor — sin asesor, no visible y el nombre son tres cosas distintas', () => {
  const mapa = api.mapaAsesores([
    { id: 'ase-1', codigo_asesor: 'QA-ASE-01', nombre_completo: 'Asesor Comercial 1 QA', activo: true, supervisor_id: 'sup-1' },
    { id: 'ase-3', codigo_asesor: 'QA-ASE-03', nombre_completo: null, activo: true, supervisor_id: null },
  ])

  it('id en el mapa da el nombre real', () => {
    expect(api.nombreAsesor('ase-1', mapa)).toBe('Asesor Comercial 1 QA')
  })

  it('asesor_id NULL da "sin asesor", y SOLO en ese caso', () => {
    expect(api.nombreAsesor(null, mapa)).toBe('sin asesor')
    expect(api.nombreAsesor(undefined, mapa)).toBe('sin asesor')
    expect(api.nombreAsesor('', mapa)).toBe('sin asesor')
  })

  it('id fuera del alcance y sin codigo conocido da "asesor no visible", NUNCA "sin asesor"', () => {
    expect(api.nombreAsesor('ase-fuera', mapa)).toBe('asesor no visible')
    expect(api.nombreAsesor('ase-fuera', mapa)).not.toBe('sin asesor')
  })

  it('id fuera del alcance pero con codigo conocido da el codigo', () => {
    expect(api.nombreAsesor('ase-fuera', mapa, 'QA-ASE-09')).toBe('QA-ASE-09')
  })

  it('en el mapa pero con nombre_completo NULL cae al codigo de la ficha', () => {
    expect(api.nombreAsesor('ase-3', mapa)).toBe('QA-ASE-03')
  })

  it('mapaAsesores tolera null y undefined', () => {
    expect(api.mapaAsesores(null).size).toBe(0)
    expect(api.mapaAsesores(undefined).size).toBe(0)
    expect(api.nombreAsesor('ase-1', api.mapaAsesores(null))).toBe('asesor no visible')
  })
})

describe('asesoresConNombre llama a la RPC de la mig 283', () => {
  it('usa comercial_asesores_visibles', async () => {
    await api.asesoresConNombre()
    expect(rpcs[0].nombre).toBe('comercial_asesores_visibles')
  })
})


// ############################################################################################
// jornadaDeHoy: "la mía" no es "las del equipo"
// ############################################################################################
// El `.eq('asesor_id', ...)` de jornadaDeHoy NO es un gate de ownership —de esos el módulo no
// tiene— sino la diferencia entre dos preguntas. Sin él, para el ASESOR la consulta andaba de
// casualidad (la RLS le muestra una sola jornada, así que maybeSingle recibía una fila), pero al
// SUPERVISOR la policy le muestra las de TODO su equipo y con dos jornadas abiertas revienta.
describe('jornadaDeHoy filtra por asesor: el supervisor ve varias y quiere UNA', () => {
  it('pide fecha Y asesor_id, y cierra con maybeSingle', async () => {
    await api.jornadaDeHoy('ase-1')
    const ops = consultas[0].ops.join(' ')
    expect(consultas[0].tabla).toBe('jornadas_comerciales')
    expect(ops).toContain('eq("asesor_id","ase-1")')
    expect(ops).toMatch(/eq\("fecha","\d{4}-\d{2}-\d{2}"\)/)
    expect(ops).toContain('maybeSingle()')
  })

  it('sin asesorId NO consulta: no vuelve al bug mientras el perfil carga', async () => {
    const r = await api.jornadaDeHoy(null)
    expect(consultas).toHaveLength(0)
    expect(r).toEqual({ data: null, error: null })
    await api.jornadaDeHoy(undefined)
    await api.jornadaDeHoy('')
    expect(consultas).toHaveLength(0)
  })

  it('el filtro deja UNA jornada donde la consulta sin filtrar traía dos', () => {
    // Reproduce lo que la RLS le entrega a un supervisor con dos asesores con jornada abierta:
    // sin el .eq, maybeSingle recibe 2 filas y falla. Con el filtro, queda exactamente una.
    const loQueVeElSupervisor = [
      { id: 'j1', asesor_id: 'ase-1', fecha: '2026-09-06' },
      { id: 'j2', asesor_id: 'ase-2', fecha: '2026-09-06' },
    ]
    const mias = loQueVeElSupervisor.filter(j => j.asesor_id === 'ase-1')
    expect(loQueVeElSupervisor).toHaveLength(2)
    expect(mias).toHaveLength(1)
    expect(mias[0].id).toBe('j1')
  })

  it('jornadasDelDia (las del equipo) sigue SIN filtro de asesor', async () => {
    await api.jornadasDelDia('2026-09-06')
    const ops = consultas[0].ops.join(' ')
    expect(ops).toContain('eq("fecha","2026-09-06")')
    expect(ops).not.toContain('maybeSingle')
    // Se miran SOLO las ops de FILTRO: `asesor_id` está en el select y debe estarlo —las pantallas
    // agrupan por esa columna—; lo que no debe haber es un .eq sobre ella.
    const filtros = consultas[0].ops.filter(o => /^(eq|gt|gte|lt|lte|in|is)\(/.test(o)).join(' ')
    expect(filtros).not.toContain('asesor_id')
    expect(filtros).toBe('eq("fecha","2026-09-06")')
  })
})

// ############################################################################################
// CENSO DE SIMETRÍA: lo que el formulario ENVÍA y lo que el select PRECARGA son el mismo conjunto
// ############################################################################################
// `guardar_asesor_perfil` hace UPSERT, y su `ON CONFLICT DO UPDATE` pisa las nueve columnas con lo
// que venga en los parámetros. Así que TODO campo que el formulario mande pero el select no
// precargue se guarda VACÍO al editar: el usuario abre una ficha, cambia el teléfono, guarda, y
// pierde en silencio lo que no estaba en pantalla. Pasó con `bio`.
//
// Es el molde del censo invertido de la mig 281 traído al front: no verifica un campo puntual sino
// la IGUALDAD de los dos conjuntos, así que agregar un campo al formulario sin agregarlo al select
// —o al revés— se pone rojo solo, sin que nadie tenga que acordarse de este test.
//
// Los dos conjuntos salen de EJERCITAR las funciones, no de leer el fuente: se compara lo que de
// verdad viaja.
//
// TRES CATEGORÍAS, y cada una protege de algo distinto. Una columna que no caiga en ninguna de las
// tres pone el censo en rojo, que es exactamente el punto: agregar algo al select sin decidir qué
// es tiene que doler.
//
//   1. IDENTIDAD — `IDENT_PARAM` / `IDENT_COL`. No son campos del formulario: el `id` identifica la
//      fila, el país es fijo de la ruta, y el supervisor se cambia con `asignar_supervisor`. Fuera
//      de los dos lados.
//
//   2. FORMULARIO — todo lo demás. SIMETRÍA ESTRICTA: lo que `guardarAsesorPerfil` envía tiene que
//      ser exactamente lo que `listarFichasDePais` precarga. Ésta es la categoría que protege del
//      bug de `bio` —un campo que el formulario manda pero el select no precarga se guarda VACÍO al
//      editar, y el usuario pierde en silencio lo que no estaba en pantalla—.
//
//   3. SOLO LECTURA — `SOLO_LECTURA`. Columnas que el select TRAE para mostrar y que el formulario
//      NUNCA escribe, porque las escribe otra cosa. `tarjeta_publica` la escriben
//      `tarjeta_set_consentimiento` (el asesor) y `tarjeta_apagar_de_asesor` (el admin de país), y
//      el UPSERT de la ficha ni la lista.
//
// LA LISTA DE SOLO LECTURA NO ES UNA VÁLVULA DE ESCAPE, y por eso está verificada EN LAS DOS
// DIRECCIONES (ver el describe de más abajo):
//   * una columna declarada que NO esté en el select es una declaración muerta, y una declaración
//     muerta absorbería en silencio a una columna futura que se llame igual;
//   * una columna declarada que el formulario SÍ envíe sería el bug de `bio` con permiso escrito
//     — declararla read-only es justo lo que lo escondería.
// Aflojar el censo agregando acá lo que moleste es la única forma de romperlo, y esos dos tests son
// los que lo impiden.
//
// FUERA DE LAS TRES A PROPÓSITO: `foto_path` y `foto_publica_path`. No son parámetros de la RPC y
// el select tampoco las trae, así que no están en ningún lado y no hace falta declararlas. NO
// agregarlas "por simetría" — rompería el censo sin que haya nada roto.
const IDENT_PARAM = new Set(['p_asesor_id', 'p_pais_id'])
const IDENT_COL = new Set(['id', 'pais_id', 'supervisor_id'])
const SOLO_LECTURA = new Set(['tarjeta_publica'])

/**
 * Los conjuntos, EJERCITANDO las dos funciones: se compara lo que de verdad viaja, no lo que dice
 * el fuente. Vive a nivel de módulo porque lo usan los dos describes de abajo y tienen que medir
 * exactamente lo mismo.
 */
const conjuntos = async () => {
  await api.guardarAsesorPerfil({ asesorId: 'a', codigoAsesor: 'c', paisId: 'p' })
  await api.listarFichasDePais('p')
  const envia = Object.keys(rpcs[0].args)
    .filter(k => !IDENT_PARAM.has(k)).map(k => k.replace(/^p_/, '')).sort()
  const sel = consultas[0].ops.find(o => o.startsWith('select(')) ?? ''
  const cols = (sel.match(/"([^"]+)"/)?.[1] ?? '').split(',')
  // `trae` es lo que queda tras sacar las DOS categorías declaradas. Lo que sobre tiene que ser
  // exactamente el formulario.
  const trae = cols.filter(c => !IDENT_COL.has(c) && !SOLO_LECTURA.has(c)).sort()
  return { envia, trae, cols }
}

describe('ficha de asesor: el formulario y el select cubren las MISMAS columnas', () => {
  it('el conjunto que envía guardarAsesorPerfil es exactamente el que trae listarFichasDePais', async () => {
    const { envia, trae } = await conjuntos()
    expect(envia).toEqual(trae)
  })

  it('ningún campo del formulario se pierde al editar (envía pero no precarga)', async () => {
    const { envia, trae } = await conjuntos()
    const perdidos = envia.filter(c => !trae.includes(c))
    expect(perdidos, 'se guardarían vacíos al editar: ' + perdidos.join(', ')).toEqual([])
  })

  it('el select no arrastra columnas que el formulario no maneja', async () => {
    const { envia, trae } = await conjuntos()
    const sobran = trae.filter(c => !envia.includes(c))
    expect(sobran, 'columnas de más en el select: ' + sobran.join(', ')).toEqual([])
  })

  it('las dos de foto quedan fuera de los dos lados: no son parámetros de la RPC', async () => {
    const { envia, trae } = await conjuntos()
    for (const c of ['foto_path', 'foto_publica_path']) {
      expect(envia).not.toContain(c)
      expect(trae).not.toContain(c)
    }
  })
})

// La lista de SOLO LECTURA es la única forma de sacarle una columna al censo, así que ella misma
// tiene que estar censada. Sin estos dos tests, `SOLO_LECTURA` sería una válvula de escape: bastaría
// meter ahí lo que moleste para que el bug de `bio` volviera con permiso escrito.
describe('la lista de SOLO LECTURA no es una válvula de escape', () => {
  it('cada columna declarada de solo lectura ESTÁ de verdad en el select', async () => {
    const { cols } = await conjuntos()
    const muertas = [...SOLO_LECTURA].filter(c => !cols.includes(c))
    expect(
      muertas,
      'declaradas de solo lectura pero ausentes del select: ' + muertas.join(', ')
      + ' — una declaración muerta absorbe en silencio a una columna futura con ese nombre',
    ).toEqual([])
  })

  it('NINGUNA columna de solo lectura es enviada por el formulario', async () => {
    const { cols } = await conjuntos()
    await api.guardarAsesorPerfil({ asesorId: 'a', codigoAsesor: 'c', paisId: 'p' })
    const enviadas = Object.keys(rpcs[rpcs.length - 1].args).map(k => k.replace(/^p_/, ''))
    const mentira = [...SOLO_LECTURA].filter(c => enviadas.includes(c))
    expect(
      mentira,
      'declaradas de solo lectura pero el formulario SÍ las envía: ' + mentira.join(', ')
      + ' — eso es el bug de bio con permiso escrito',
    ).toEqual([])
    expect(cols.length).toBeGreaterThan(0)   // que el select se haya ejercitado de verdad
  })

  it('una columna NUEVA en el select, sin declarar, pone el censo en rojo', async () => {
    // Contraprueba del censo: se simula la columna sin declarar y se comprueba que la comparación
    // falla. Sin esto, "los conjuntos son iguales" no distingue un censo que mide de uno que no.
    const { envia, trae } = await conjuntos()
    const conIntrusa = [...trae, 'columna_nueva_sin_declarar'].sort()
    expect(conIntrusa).not.toEqual(envia)
  })
})

// --- Ubicación del prospecto (punto 1) -----------------------------------------------------------

describe('coordenadasValidas — solo dos números finitos en rango, y nunca el (0,0)', () => {
  it.each([
    [14.6, -90.5],
    [90, 180],
    [-90, -180],
  ])('acepta (%s, %s)', (lat, lng) => {
    expect(api.coordenadasValidas(lat, lng)).toBe(true)
  })

  it.each([
    [0, 0],
    [91, 0],
    [0, 181],
    [NaN, 1],
    [Infinity, 1],
    ['14.6', '-90.5'],
    [null, null],
    [14.6, null],
  ])('rechaza (%s, %s)', (lat, lng) => {
    expect(api.coordenadasValidas(lat, lng)).toBe(false)
  })
})

describe('crearProspecto — dirección y coordenada viajan a la RPC, o no viaja nada', () => {
  const base = { nombre: 'Farmacia X', tipo: 'farmacia', asesorId: 'ase-1' }

  it('con lat y lng válidas manda las mismas y la dirección con trim', async () => {
    await api.crearProspecto({ ...base, direccion: '  6a Av 12-45  ', lat: 14.6, lng: -90.5 })
    expect(rpcs[0].nombre).toBe('crear_prospecto')
    expect(rpcs[0].args.p_lat).toBe(14.6)
    expect(rpcs[0].args.p_lng).toBe(-90.5)
    expect(rpcs[0].args.p_direccion).toBe('6a Av 12-45')
  })

  it('sin coordenadas manda p_lat y p_lng en null explícito', async () => {
    await api.crearProspecto(base)
    expect(rpcs[0].args).toHaveProperty('p_lat', null)
    expect(rpcs[0].args).toHaveProperty('p_lng', null)
  })

  it('una dirección de solo espacios viaja como null', async () => {
    await api.crearProspecto({ ...base, direccion: '   ' })
    expect(rpcs[0].args.p_direccion).toBeNull()
  })

  it('con una sola coordenada rechaza y NO llama a la RPC', async () => {
    await expect(api.crearProspecto({ ...base, lat: 14.6 })).rejects.toThrow('coordenadas_invalidas')
    await expect(api.crearProspecto({ ...base, lng: -90.5 })).rejects.toThrow('coordenadas_invalidas')
    expect(rpcs).toHaveLength(0)
  })

  it('con (0, 0) rechaza y NO llama a la RPC', async () => {
    await expect(api.crearProspecto({ ...base, lat: 0, lng: 0 })).rejects.toThrow('coordenadas_invalidas')
    expect(rpcs).toHaveLength(0)
  })
})

describe('geocodificarDireccion — best-effort y sin la dirección en los logs', () => {
  const DIRECCION = 'Calle Secreta 42, Zona 10'

  // Ningún argumento de ningún console.error puede contener la dirección.
  const sinDireccionEnLogs = (spy: ReturnType<typeof vi.spyOn>) => {
    for (const llamada of spy.mock.calls) {
      for (const arg of llamada) {
        const texto = typeof arg === 'string' ? arg : JSON.stringify(arg) ?? String(arg)
        expect(texto).not.toContain(DIRECCION)
      }
    }
  }

  it('vacía o de solo espacios devuelve null sin llamar a la edge', async () => {
    expect(await api.geocodificarDireccion('')).toBeNull()
    expect(await api.geocodificarDireccion('   ')).toBeNull()
    expect(invokes).toHaveLength(0)
  })

  it('mapea { lat, lng, display_name } a { lat, lng, displayName }', async () => {
    invokeImpl = async () => ({ data: { lat: 14.6, lng: -90.5, display_name: 'Zona 10, Guatemala' }, error: null })
    expect(await api.geocodificarDireccion(`  ${DIRECCION}  `))
      .toEqual({ lat: 14.6, lng: -90.5, displayName: 'Zona 10, Guatemala' })
    expect(invokes[0]).toEqual({ nombre: 'geocodificar', opciones: { body: { direccion: DIRECCION } } })
  })

  it('sin display_name devuelve displayName vacío', async () => {
    invokeImpl = async () => ({ data: { lat: 14.6, lng: -90.5 }, error: null })
    expect(await api.geocodificarDireccion(DIRECCION)).toEqual({ lat: 14.6, lng: -90.5, displayName: '' })
  })

  it('la edge responde 200 con { error } → null', async () => {
    invokeImpl = async () => ({ data: { error: 'No se encontraron resultados' }, error: null })
    expect(await api.geocodificarDireccion(DIRECCION)).toBeNull()
  })

  it('lat como string → null', async () => {
    invokeImpl = async () => ({ data: { lat: '14.6', lng: -90.5, display_name: 'x' }, error: null })
    expect(await api.geocodificarDireccion(DIRECCION)).toBeNull()
  })

  it('el invoke devuelve error → null, y el log no lleva la dirección', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      invokeImpl = async () => ({ data: null, error: { message: 'FunctionsHttpError', code: '401' } })
      expect(await api.geocodificarDireccion(DIRECCION)).toBeNull()
      expect(spy).toHaveBeenCalled()
      sinDireccionEnLogs(spy)
    } finally {
      spy.mockRestore()
    }
  })

  it('el invoke lanza → null, y el log no lleva la dirección', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      invokeImpl = async () => { throw new Error('network down') }
      expect(await api.geocodificarDireccion(DIRECCION)).toBeNull()
      expect(spy).toHaveBeenCalled()
      sinDireccionEnLogs(spy)
    } finally {
      spy.mockRestore()
    }
  })
})

describe('actualizarProspecto — la RPC reescribe los 8 campos: no se puede omitir ninguno', () => {
  it('manda EXACTAMENTE las 8 claves', async () => {
    await api.actualizarProspecto({
      id: 'pros-1', nombre: 'Farmacia X', tipo: 'farmacia', direccion: null,
      lat: null, lng: null, notas: null, empresaProveedoraId: null,
    })
    expect(rpcs[0].nombre).toBe('actualizar_prospecto')
    expect(Object.keys(rpcs[0].args).sort()).toEqual([
      'p_direccion', 'p_empresa_proveedora_id', 'p_lat', 'p_lng',
      'p_nombre', 'p_notas', 'p_prospecto_id', 'p_tipo',
    ])
  })

  it('cada clave lleva SU valor: con 8 valores distintos, un cruce (p. ej. lat <-> lng) se nota', async () => {
    await api.actualizarProspecto({
      id: 'pros-9', nombre: 'N', tipo: 'T', direccion: 'D',
      lat: 14.1, lng: -90.2, notas: 'NO', empresaProveedoraId: 'emp-3',
    })
    expect(rpcs[0].nombre).toBe('actualizar_prospecto')
    const a = rpcs[0].args
    expect(a.p_prospecto_id).toBe('pros-9')
    expect(a.p_nombre).toBe('N')
    expect(a.p_tipo).toBe('T')
    expect(a.p_direccion).toBe('D')
    expect(a.p_lat).toBe(14.1)
    expect(a.p_lng).toBe(-90.2)
    expect(a.p_notas).toBe('NO')
    expect(a.p_empresa_proveedora_id).toBe('emp-3')
  })
})
