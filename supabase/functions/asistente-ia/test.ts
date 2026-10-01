// Test del borde de asistente-ia. deno test --allow-net --allow-env --no-check test.ts
// Sin red: las piezas puras se prueban directo y `handle` corre contra un fetch stubeado que hace de
// auth, PostgREST y OpenAI. Lo que se mide: (a) el modo resumen_visita se decide antes del soap y no
// rompe el contrato actual; (b) sin_visita no llama a OpenAI ni audita; (c) la salida del modelo se
// valida con forma exacta y una inválida da 502 auditada; (d) consulta_id se valida con el cliente del
// usuario antes de OpenAI; (e) la auditoría del resumen toma la nota de la RPC, nunca del body.
import { assertEquals, assertStringIncludes, assert } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  handle, decidirModo, idPositivo, parsearConsultaId, mapearErrorRpc, buildPromptResumen,
  validarResumen, parsearResumen, SYSTEM_PROMPT_RESUMEN,
} from './index.ts'

// Forma real de contexto_ia_ultima_visita (339), recortada.
const CTX = {
  sin_visita: false,
  cita_id: 970, fecha: '2026-09-30', hora_inicio: '10:00:00', medico_nombre: 'Dra. QA',
  nota_id: 2214,
  motivo_consulta: 'Cefalea', subjetivo: 'Dolor frontal 3 dias', objetivo: null, analisis: '',
  diagnostico: 'Cefalea tensional', plan: 'cambio a prueba 2', nota: null, corregida: true,
  signos_vitales: [
    { fecha_toma: '2026-09-30T10:05:00+00:00', estado: 'validado', presion_arterial: '120/80',
      frecuencia_cardiaca: 72, frecuencia_respiratoria: null, temperatura: 36.6, peso_kg: null,
      talla_cm: null, imc: null, saturacion_o2: 98, glucosa: null },
  ],
  unidades_signos_vitales: { presion_arterial: 'mmHg', frecuencia_cardiaca: 'lpm', temperatura: '°C', saturacion_o2: '%' },
  paciente: { edad: 40, genero: 'F', tipo_sangre: null, alergias: 'Penicilina', medicacion_en_uso: '',
    antecedentes_personales: null, antecedentes_familiares: 'HTA' },
}

const RESUMEN_OK = {
  resumen: 'Visita por cefalea; nota corregida.',
  hallazgos_clave: ['Cefalea tensional'],
  signos_vitales_relevantes: ['PA 120/80 mmHg (2026-09-30)'],
  pendientes_seguimiento: [],
  datos_faltantes: ['Objetivo'],
}

// ------------------------------------------------------------------------------------ puras

Deno.test('decidirModo: solo resumen_visita exacto entra al modo nuevo', () => {
  assertEquals(decidirModo({ modo: 'resumen_visita', paciente_id: 23 }), 'resumen_visita')
  assertEquals(decidirModo({ paciente_id: 23, soap: {} }), 'asistente')
  assertEquals(decidirModo({ modo: 'RESUMEN_VISITA' }), 'asistente')
  assertEquals(decidirModo({ modo: 'otro' }), 'asistente')
  assertEquals(decidirModo(null), 'asistente')
  assertEquals(decidirModo([{ modo: 'resumen_visita' }]), 'asistente')
})

Deno.test('idPositivo / parsearConsultaId', () => {
  assertEquals(idPositivo(23), 23)
  assertEquals(idPositivo('23'), 23)
  for (const malo of [0, -1, 1.5, '', ' ', 'abc', null, undefined, {}, [], Number.MAX_SAFE_INTEGER + 1, '1e400']) {
    assertEquals(idPositivo(malo), null, `idPositivo(${JSON.stringify(malo)})`)
  }
  assertEquals(parsearConsultaId(undefined), { presente: false })
  assertEquals(parsearConsultaId(null), { presente: false })
  assertEquals(parsearConsultaId(2214), { presente: true, id: 2214 })
  assertEquals(parsearConsultaId('x'), { presente: true, id: null })
  assertEquals(parsearConsultaId(0), { presente: true, id: null })
})

Deno.test('mapearErrorRpc: motivos del gate, 42501 y desconocido', () => {
  assertEquals(mapearErrorRpc({ message: 'no_auth', code: 'P0001' }), { status: 401, error: 'no_auth' })
  assertEquals(mapearErrorRpc({ message: 'no_pertenencia', code: 'P0001' }), { status: 403, error: 'no_pertenencia' })
  assertEquals(mapearErrorRpc({ message: 'consentimiento_revocado', code: 'P0001' }), { status: 403, error: 'consentimiento_revocado' })
  assertEquals(mapearErrorRpc({ message: 'permission denied for function contexto_ia_ultima_visita', code: '42501' }),
    { status: 403, error: 'sin_permiso' })
  assertEquals(mapearErrorRpc({ message: 'paciente_no_encontrado', code: 'P0001' }), { status: 404, error: 'paciente_no_encontrado' })
  assertEquals(mapearErrorRpc({ message: 'algo raro', code: 'XX000' }), null)
  assertEquals(mapearErrorRpc(null), null)
})

Deno.test('buildPromptResumen: campos, vacíos como No registrado, corregida, sin nombre del médico', () => {
  const p = buildPromptResumen(CTX)
  assertStringIncludes(p, 'VISITA: 2026-09-30 10:00')
  assertStringIncludes(p, 'NOTA CORREGIDA DESPUES DE CERRADA: Si')
  assertStringIncludes(p, '- Plan: cambio a prueba 2')
  assertStringIncludes(p, '- Objetivo: No registrado')       // null
  assertStringIncludes(p, '- Analisis: No registrado')       // ''
  assertStringIncludes(p, '- Medicacion en uso (declarada en ficha): No registrado')
  assertStringIncludes(p, '- Alergias: Penicilina')
  assertStringIncludes(p, '- 2026-09-30 10:05 (validado): PA 120/80 mmHg, FC 72 lpm, Temp 36.6 °C, SpO2 98 %')
  assert(!p.includes('Dra. QA'), 'el nombre del médico no sale al prompt')
  assert(!p.includes('2214') && !p.includes('970'), 'ids internos no salen al prompt')
  assertStringIncludes(buildPromptResumen({ ...CTX, corregida: false, signos_vitales: [] }), 'NOTA CORREGIDA DESPUES DE CERRADA: No')
  assertStringIncludes(buildPromptResumen({ ...CTX, signos_vitales: [] }), 'SIGNOS VITALES DE ESA VISITA (hora de toma en UTC; validados primero, luego mas reciente primero):\nNo registrado')
  // Robusto ante contexto vacío (no tira)
  assertStringIncludes(buildPromptResumen(null), '- Edad: No registrado')
})

Deno.test('SYSTEM_PROMPT_RESUMEN declara las 5 claves exactas', () => {
  for (const k of Object.keys(RESUMEN_OK)) assertStringIncludes(SYSTEM_PROMPT_RESUMEN, `"${k}"`)
})

Deno.test('validarResumen: forma exacta', () => {
  assertEquals(validarResumen(RESUMEN_OK), RESUMEN_OK)
  assertEquals(validarResumen({ ...RESUMEN_OK, extra: 'x' }), null)                 // clave de más
  const { datos_faltantes: _, ...sinUna } = RESUMEN_OK
  assertEquals(validarResumen(sinUna), null)                                         // clave de menos
  assertEquals(validarResumen({ ...RESUMEN_OK, resumen: '' }), null)
  assertEquals(validarResumen({ ...RESUMEN_OK, resumen: 3 }), null)
  assertEquals(validarResumen({ ...RESUMEN_OK, hallazgos_clave: 'x' }), null)
  assertEquals(validarResumen({ ...RESUMEN_OK, hallazgos_clave: ['a', 2] }), null)
  assertEquals(validarResumen({ ...RESUMEN_OK, pendientes_seguimiento: null }), null)
  assertEquals(validarResumen([RESUMEN_OK]), null)
  assertEquals(validarResumen(null), null)
  assertEquals(parsearResumen(JSON.stringify(RESUMEN_OK)), RESUMEN_OK)
  assertEquals(parsearResumen('no es json'), null)
  assertEquals(parsearResumen('```json\n' + JSON.stringify(RESUMEN_OK) + '\n```'), null) // sin rescate por regex
})

// ------------------------------------------------------------------------------------ handle

type Llamada = { url: string; method: string; body: any }

// fetch falso: getUser, RPCs, select a expediente_notas, OpenAI y el POST de auditoría.
function stub(opts: {
  rpc?: { status: number; body: unknown }
  notas?: unknown[]
  openai?: string
}) {
  const llamadas: Llamada[] = []
  const original = globalThis.fetch
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    const method = init?.method ?? (input instanceof Request ? input.method : 'GET')
    let body: any = init?.body ?? null
    try { body = typeof body === 'string' ? JSON.parse(body) : body } catch { /* texto */ }
    llamadas.push({ url, method, body })
    const j = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } })
    if (url.includes('/auth/v1/user')) return j({ id: 'medico-real-uuid', aud: 'authenticated', role: 'authenticated' })
    if (url.includes('/rest/v1/rpc/')) return j(opts.rpc?.body ?? {}, opts.rpc?.status ?? 200)
    if (url.includes('/rest/v1/expediente_notas')) return j(opts.notas ?? [])
    if (url.includes('/rest/v1/auditoria_ia')) return new Response(null, { status: 201 })
    if (url.includes('api.openai.com')) return j({ choices: [{ message: { content: opts.openai ?? '' } }] })
    return j({ error: 'url no esperada ' + url }, 599)
  }) as typeof fetch
  return { llamadas, restaurar: () => { globalThis.fetch = original } }
}

function env() {
  Deno.env.set('OPENAI_API_KEY', 'sk-test')
  Deno.env.set('SB_URL', 'http://sb.test')
  Deno.env.set('SB_ANON_KEY', 'anon-test')
  Deno.env.set('SB_SERVICE_ROLE_KEY', 'service-test')
}

const req = (body: unknown) => new Request('http://edge.test/asistente-ia', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer jwt-del-caller', 'Content-Type': 'application/json', 'Origin': 'https://med.ezpayconnect.com' },
  body: JSON.stringify(body),
})

const a = (ll: Llamada[], frag: string) => ll.filter((l) => l.url.includes(frag))

async function correr(body: unknown, opts: Parameters<typeof stub>[0]) {
  env()
  const s = stub(opts)
  try {
    const r = await handle(req(body))
    return { status: r.status, json: await r.json(), llamadas: s.llamadas }
  } finally {
    s.restaurar()
  }
}

Deno.test('resumen: OK → 200 con metadatos de la RPC; auditoría con nota_id de la RPC y la clave del caller en la RPC', async () => {
  const { status, json, llamadas } = await correr(
    { modo: 'resumen_visita', paciente_id: 23, consulta_id: 99999, medico_id: 'falso', soap: { x: 1 } },
    { rpc: { status: 200, body: CTX }, openai: JSON.stringify(RESUMEN_OK) },
  )
  assertEquals(status, 200)
  assertEquals(json, { sin_visita: false, cita_id: 970, fecha: '2026-09-30', hora_inicio: '10:00:00',
    medico_nombre: 'Dra. QA', corregida: true, resumen: RESUMEN_OK })
  const rpc = a(llamadas, '/rest/v1/rpc/')
  assertEquals(rpc.length, 1)
  assertStringIncludes(rpc[0].url, '/rpc/contexto_ia_ultima_visita')
  assertEquals(rpc[0].body, { p_paciente_id: 23 })
  const aud = a(llamadas, '/rest/v1/auditoria_ia')
  assertEquals(aud.length, 1)
  assertEquals(aud[0].body.consulta_id, 2214)            // de la RPC, no el 99999 del body
  assertEquals(aud[0].body.medico_id, 'medico-real-uuid')  // de getUser, no del body
  assertEquals(aud[0].body.accion_medico, 'resumen_visita')
  assertEquals(aud[0].body.modelo_ia, 'gpt-4o-mini')
  assertEquals(JSON.parse(aud[0].body.respuesta_ia), RESUMEN_OK)
  assertEquals(a(llamadas, 'expediente_notas').length, 0)  // el consulta_id del body ni se mira
  const oa = a(llamadas, 'api.openai.com')[0].body
  assertEquals([oa.model, oa.max_tokens, oa.messages[0].content], ['gpt-4o-mini', 1500, SYSTEM_PROMPT_RESUMEN])
})

Deno.test('resumen: el JWT del caller llega a la RPC (no service_role)', async () => {
  env()
  const vistos: string[] = []
  const original = globalThis.fetch
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    const h = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined))
    if (url.includes('/rest/v1/rpc/')) { vistos.push(h.get('Authorization') ?? ''); return new Response(JSON.stringify({ sin_visita: true }), { status: 200 }) }
    return new Response(JSON.stringify({ id: 'u' }), { status: 200 })
  }) as typeof fetch
  try {
    await (await handle(req({ modo: 'resumen_visita', paciente_id: 23 }))).json()
  } finally { globalThis.fetch = original }
  assertEquals(vistos, ['Bearer jwt-del-caller'])
})

Deno.test('resumen: sin_visita → 200 {sin_visita:true}, sin OpenAI y sin auditoría', async () => {
  const { status, json, llamadas } = await correr({ modo: 'resumen_visita', paciente_id: 23 }, { rpc: { status: 200, body: { sin_visita: true } } })
  assertEquals([status, json], [200, { sin_visita: true }])
  assertEquals(a(llamadas, 'api.openai.com').length, 0)
  assertEquals(a(llamadas, 'auditoria_ia').length, 0)
})

Deno.test('resumen: salida inválida del modelo → 502 respuesta_ia_invalida, auditada con el texto crudo', async () => {
  const crudo = JSON.stringify({ ...RESUMEN_OK, diagnostico_nuevo: 'x' })
  const { status, json, llamadas } = await correr({ modo: 'resumen_visita', paciente_id: 23 }, { rpc: { status: 200, body: CTX }, openai: crudo })
  assertEquals([status, json], [502, { error: 'respuesta_ia_invalida' }])
  const aud = a(llamadas, 'auditoria_ia')
  assertEquals(aud.length, 1)
  assertEquals(aud[0].body.respuesta_ia, crudo)
  assertEquals(aud[0].body.consulta_id, 2214)
})

Deno.test('resumen: errores de la RPC mapeados con {error}', async () => {
  const casos: [unknown, number, unknown, number][] = [
    [{ code: 'P0001', message: 'no_pertenencia' }, 400, { error: 'no_pertenencia' }, 403],
    [{ code: 'P0001', message: 'consentimiento_revocado' }, 400, { error: 'consentimiento_revocado' }, 403],
    [{ code: 'P0001', message: 'no_auth' }, 400, { error: 'no_auth' }, 401],
    [{ code: '42501', message: 'permission denied for function contexto_ia_ultima_visita' }, 401, { error: 'sin_permiso' }, 403],
    [{ code: 'XX000', message: 'boom' }, 500, { error: 'error_contexto' }, 500],
  ]
  for (const [pgErr, httpRpc, esperado, httpEdge] of casos) {
    const { status, json, llamadas } = await correr({ modo: 'resumen_visita', paciente_id: 23 }, { rpc: { status: httpRpc, body: pgErr } })
    assertEquals([status, json], [httpEdge, esperado], JSON.stringify(pgErr))
    assertEquals(a(llamadas, 'api.openai.com').length + a(llamadas, 'auditoria_ia').length, 0)
  }
})

Deno.test('resumen: paciente_id inválido → 400 sin tocar la RPC', async () => {
  const { status, llamadas } = await correr({ modo: 'resumen_visita', paciente_id: 'x' }, {})
  assertEquals(status, 400)
  assertEquals(a(llamadas, '/rpc/').length, 0)
})

const SUG = JSON.stringify({ disclaimer: 'd', diagnosticos_diferenciales: [], examenes_recomendados: [],
  opciones_farmacologicas: [], contraindicaciones: [], referencias_guias: [], notas_adicionales: '' })

Deno.test('modo actual: sin modo y sin soap sigue dando 400 app_desactualizada', async () => {
  const { status, json, llamadas } = await correr({ paciente_id: 23 }, {})
  assertEquals(status, 400)
  assertEquals(json.error, 'app_desactualizada')
  assertEquals(a(llamadas, '/rpc/').length, 0)
})

Deno.test('modo actual: consulta_id de otra persona/paciente → 400 consulta_invalida, sin OpenAI ni auditoría', async () => {
  const { status, json, llamadas } = await correr(
    { paciente_id: 23, soap: { motivo_consulta: 'x' }, consulta_id: 5 },
    { rpc: { status: 200, body: {} }, notas: [] },
  )
  assertEquals([status, json], [400, { error: 'consulta_invalida' }])
  const sel = a(llamadas, '/rest/v1/expediente_notas')[0]
  assertStringIncludes(sel.url, 'id=eq.5')
  assertStringIncludes(sel.url, 'paciente_id=eq.23')
  assertEquals(a(llamadas, 'api.openai.com').length + a(llamadas, 'auditoria_ia').length, 0)
})

Deno.test('modo actual: consulta_id no numérico → 400 consulta_invalida sin consultar', async () => {
  const { status, json, llamadas } = await correr({ paciente_id: 23, soap: {}, consulta_id: 'abc' }, { rpc: { status: 200, body: {} } })
  assertEquals([status, json], [400, { error: 'consulta_invalida' }])
  assertEquals(a(llamadas, 'expediente_notas').length + a(llamadas, 'api.openai.com').length, 0)
})

Deno.test('modo actual: consulta_id válido → 200 y se audita ese id', async () => {
  const { status, json, llamadas } = await correr(
    { paciente_id: 23, soap: { motivo_consulta: 'x' }, consulta_id: 2214 },
    { rpc: { status: 200, body: {} }, notas: [{ id: 2214 }], openai: SUG },
  )
  assertEquals(status, 200)
  assertEquals(json.modelo, 'gpt-4o-mini')
  assertEquals(json.sugerencias, JSON.parse(SUG))
  const aud = a(llamadas, 'auditoria_ia')[0].body
  assertEquals([aud.consulta_id, aud.modelo_ia, aud.medico_id, aud.accion_medico], [2214, 'gpt-4o-mini', 'medico-real-uuid', undefined])
  assertStringIncludes(a(llamadas, '/rpc/')[0].url, '/rpc/contexto_ia_paciente')
})

Deno.test('modo actual: sin consulta_id → no consulta notas y audita NULL', async () => {
  const { status, llamadas } = await correr({ paciente_id: 23, soap: {} }, { rpc: { status: 200, body: {} }, openai: SUG })
  assertEquals(status, 200)
  assertEquals(a(llamadas, 'expediente_notas').length, 0)
  assertEquals(a(llamadas, 'auditoria_ia')[0].body.consulta_id, null)
})
