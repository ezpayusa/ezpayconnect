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

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: async (nombre: string, args: Record<string, unknown>) => { rpcs.push({ nombre, args }); return { data: null, error: null } },
    from: (tabla: string) => query(tabla),
  },
}))

const api = await import('./api')

beforeEach(() => { rpcs.length = 0; consultas.length = 0 })

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
