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
