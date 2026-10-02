import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// CORS acotado (mismo patrón que dictado-voz). Solo orígenes propios (+ DEV_ORIGIN por env solo en dev).
const ALLOWED = ['https://med.ezpayconnect.com']
const DEV_ORIGIN = Deno.env.get('DEV_ORIGIN') // p.ej. http://localhost:5173 — solo en dev; borrar la env antes de go-live
const ALLOWLIST = DEV_ORIGIN ? [...ALLOWED, DEV_ORIGIN] : ALLOWED

function buildCors(origin: string | null) {
  const allow = origin && ALLOWLIST.includes(origin) ? origin : ALLOWED[0]
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

const SYSTEM_PROMPT = `Eres un asistente medico de soporte. NO eres un medico. NO diagnostiques. NO prescribas medicamentos directamente.

Tu funcion es sugerir posibles diagnosticos diferenciales y opciones de tratamiento segun guias clinicas estandar, basandote UNICAMENTE en la informacion proporcionada.

Reglas estrictas:
1. Siempre incluye un disclaimer de que esto es solo de apoyo
2. Nunca sugieras dosis especificas sin mencionar "consultar guia clinica"
3. Si hay informacion insuficiente, indica que faltan datos
4. Menciona siempre contraindicaciones basadas en alergias/medicacion actual
5. Formato de respuesta en JSON estricto

Responde UNICAMENTE con este JSON (sin markdown, sin texto adicional):
{
  "disclaimer": "string",
  "diagnosticos_diferenciales": [{"nombre": "string", "probabilidad": "string", "justificacion": "string"}],
  "examenes_recomendados": ["string"],
  "opciones_farmacologicas": [{"nombre": "string", "nota": "string"}],
  "contraindicaciones": ["string"],
  "referencias_guias": ["string"],
  "notas_adicionales": "string"
}`

// Fusiona contexto histórico server-side (ctxHist, del RPC contexto_ia_paciente) + SOAP en vivo (del body).
// NO aplana vitales: itera la serie ≤5. Cada sección vacía/null → 'No registrados'.
function buildPrompt(ctxHist: any, soap: any) {
  const h = ctxHist || {}
  const demo = h.demografia || {}
  const ant = h.antecedentes || {}
  const sp = soap || {}

  const fmtFecha = (f: any) => {
    if (!f) return 's/f'
    const s = String(f)
    return s.length >= 10 ? s.slice(0, 10) : s
  }

  // SIGNOS VITALES RECIENTES (serie/tendencia)
  const vit = Array.isArray(h.signos_vitales_recientes) ? h.signos_vitales_recientes : []
  const vitalesTxt = vit.length
    ? vit.map((v: any) => {
        const partes: string[] = []
        // Unidades canonicas de signos_vitales: la mig 330 las exige por CHECK (rangos sv_*_rango).
        if (v.presion_arterial != null) partes.push(`PA ${v.presion_arterial} mmHg`)
        if (v.frecuencia_cardiaca != null) partes.push(`FC ${v.frecuencia_cardiaca} lpm`)
        if (v.frecuencia_respiratoria != null) partes.push(`FR ${v.frecuencia_respiratoria} rpm`)
        if (v.temperatura != null) partes.push(`Temp ${v.temperatura} °C`)
        if (v.saturacion_o2 != null) partes.push(`SpO2 ${v.saturacion_o2} %`)
        if (v.glucosa != null) partes.push(`Glucosa ${v.glucosa} mg/dL`)
        if (v.peso_kg != null) partes.push(`Peso ${v.peso_kg} kg`)
        if (v.talla_cm != null) partes.push(`Talla ${v.talla_cm} cm`)
        if (v.imc != null) partes.push(`IMC ${v.imc} kg/m2`)
        return `- ${fmtFecha(v.fecha_toma)}: ${partes.length ? partes.join(', ') : 'sin valores'}`
      }).join('\n')
    : 'No registrados'

  // DIAGNÓSTICOS PREVIOS
  const dx = Array.isArray(h.diagnosticos_recientes) ? h.diagnosticos_recientes : []
  const dxTxt = dx.length
    ? dx.map((d: any) =>
        `- ${fmtFecha(d.fecha)} | Motivo: ${d.motivo_consulta || 's/d'} | S: ${d.subjetivo || 's/d'} | O: ${d.objetivo || 's/d'} | A: ${d.analisis || 's/d'} | Dx: ${d.diagnostico || 's/d'} | Plan: ${d.plan || 's/d'}`
      ).join('\n')
    : 'No registrados'

  // MEDICACIÓN RECETADA ACTIVA (por receta → items)
  const meds = Array.isArray(h.medicacion_recetada_activa) ? h.medicacion_recetada_activa : []
  const medsTxt = meds.length
    ? meds.map((r: any) => {
        const items = Array.isArray(r.items) ? r.items : []
        const itemsTxt = items.length
          ? items.map((it: any) =>
              `    · ${it.medicamento || 's/n'}${it.dosis ? ` ${it.dosis}` : ''}${it.frecuencia ? ` c/${it.frecuencia}` : ''}${it.duracion ? ` x${it.duracion}` : ''}`
            ).join('\n')
          : '    · (sin items detallados)'
        return `- Receta ${fmtFecha(r.fecha)}:\n${itemsTxt}`
      }).join('\n')
    : 'No registrados'

  // EXÁMENES RECIENTES
  const exa = Array.isArray(h.examenes_recientes) ? h.examenes_recientes : []
  // Desde el frente 6, el laboratorio puede cerrar un examen con SOLO el archivo y el texto vacío:
  // en la mayoría de los exámenes el PDF es el resultado. Decirle al modelo "sin resultado" en ese
  // caso es FALSO y peor que callar — razonaría sobre un paciente al que le faltan estudios que
  // están hechos. `tiene_archivo` lo agrega contexto_ia_paciente en la mig 313 (un booleano, no la
  // URL: este texto va dentro de un prompt a un modelo de terceros).
  const resultadoDeExamen = (e: any) =>
    e.resultados || (e.tiene_archivo ? 'resultado disponible en archivo adjunto (ver PDF)' : 'sin resultado')
  const exaTxt = exa.length
    ? exa.map((e: any) =>
        `- ${fmtFecha(e.fecha_resultado)}: ${e.tipo || 's/t'}${e.descripcion ? ` (${e.descripcion})` : ''} → ${resultadoDeExamen(e)}`
      ).join('\n')
    : 'No registrados'

  return `PACIENTE:
- Edad: ${demo.edad != null ? demo.edad : 'No especificada'} años
- Genero: ${demo.genero || 'No especificado'}
- Tipo de sangre: ${demo.tipo_sangre || 'No especificado'}
- Alergias: ${h.alergias || 'Ninguna conocida'}
- Medicacion en uso (declarada en ficha): ${h.medicacion_en_uso || 'Ninguna'}
- Antecedentes personales: ${ant.personales || 'No especificados'}
- Antecedentes familiares: ${ant.familiares || 'No especificados'}

MOTIVO DE CONSULTA (EN VIVO):
${sp.motivo_consulta || 'No especificado'}

SUBJETIVO (EN VIVO, lo que refiere el paciente):
${sp.subjetivo || 'No especificado'}

OBJETIVO (EN VIVO, hallazgos de exploracion):
${sp.objetivo || 'No especificado'}

SIGNOS VITALES RECIENTES (serie/tendencia, mas reciente primero):
${vitalesTxt}

CONSULTAS PREVIAS (SOAP):
${dxTxt}

MEDICACION RECETADA ACTIVA:
${medsTxt}

EXAMENES RECIENTES:
${exaTxt}

Proporciona tu analisis de soporte segun las reglas establecidas.`
}

// ============================================================================================
// MODO resumen_visita (fase 1, mig 339): resumen de la ULTIMA visita del paciente para el médico.
// El contexto lo arma contexto_ia_ultima_visita, que gatea con gate_accion_phi('asistente_ia')
// ANTES de leer; el edge la llama con el JWT del caller, igual que contexto_ia_paciente.
// Las piezas puras van exportadas para test.ts (deno test, sin red).
// ============================================================================================

export const MODO_RESUMEN_VISITA = 'resumen_visita'

export const SYSTEM_PROMPT_RESUMEN = `Eres un asistente de documentacion clinica. Redactas, en espanol, un resumen de la ULTIMA visita de un paciente para el medico tratante, que lo va a leer antes de volver a atenderlo.

Reglas estrictas:
1. Basate EXCLUSIVAMENTE en los datos recibidos. No inventes, no completes ni supongas nada que no este escrito.
2. NO diagnostiques de nuevo ni propongas diagnosticos distintos a los registrados. Si citas un diagnostico, es el que escribio el medico.
3. NO prescribas ni sugieras medicamentos, dosis ni tratamientos nuevos. Si la nota menciona un tratamiento, solo reportalo.
4. Si un campo viene como "No registrado", nombralo en datos_faltantes. No lo rellenes.
5. Si la nota fue corregida despues de cerrada, dilo en el resumen.
6. pendientes_seguimiento solo recoge lo que la propia nota deja pendiente (plan, controles, examenes pedidos). Si no hay, deja la lista vacia.
7. signos_vitales_relevantes: valores tal como vienen, con su unidad y fecha de toma. Sin interpretar mas alla de lo que dice la nota.

Responde UNICAMENTE con este JSON (sin markdown, sin texto adicional, sin claves extra):
{
  "resumen": "string",
  "hallazgos_clave": ["string"],
  "signos_vitales_relevantes": ["string"],
  "pendientes_seguimiento": ["string"],
  "datos_faltantes": ["string"]
}`

export type ResumenVisita = {
  resumen: string
  hallazgos_clave: string[]
  signos_vitales_relevantes: string[]
  pendientes_seguimiento: string[]
  datos_faltantes: string[]
}

const CLAVES_RESUMEN = [
  'resumen', 'hallazgos_clave', 'signos_vitales_relevantes', 'pendientes_seguimiento', 'datos_faltantes',
] as const

// Decide el modo ANTES del chequeo de soap: sólo 'resumen_visita' exacto entra al modo nuevo. Cualquier
// otra cosa (sin modo, modo desconocido) sigue por el camino actual, con su contrato intacto.
export function decidirModo(body: unknown): 'resumen_visita' | 'asistente' {
  if (body && typeof body === 'object' && !Array.isArray(body) &&
      (body as Record<string, unknown>).modo === MODO_RESUMEN_VISITA) return 'resumen_visita'
  return 'asistente'
}

// Id de fila (bigint/serial) que llega por el body: entero positivo seguro, o null.
export function idPositivo(v: unknown): number | null {
  const n = typeof v === 'number' ? v : (typeof v === 'string' && v.trim() !== '' ? Number(v) : NaN)
  return Number.isSafeInteger(n) && n > 0 ? n : null
}

// consulta_id del modo actual: ausente (null/undefined) = se audita NULL como hasta hoy;
// presente = tiene que ser un id válido, si no es consulta_invalida.
export function parsearConsultaId(v: unknown): { presente: false } | { presente: true; id: number | null } {
  if (v === undefined || v === null) return { presente: false }
  return { presente: true, id: idPositivo(v) }
}

// Error de la RPC de contexto → respuesta HTTP. Los motivos del gate viajan en el mensaje del RAISE
// (P0001); el 42501 es el de un rol sin EXECUTE (anon). Lo no reconocido devuelve null y el caller
// responde 500 error_contexto, como hoy.
export function mapearErrorRpc(err: { message?: string; code?: string } | null | undefined):
  { status: number; error: string } | null {
  if (!err) return null
  const m = err.message || ''
  if (/no_pertenencia/.test(m)) return { status: 403, error: 'no_pertenencia' }
  if (/consentimiento_revocado/.test(m)) return { status: 403, error: 'consentimiento_revocado' }
  if (/no_auth/.test(m)) return { status: 401, error: 'no_auth' }
  if (err.code === '42501') return { status: 403, error: 'sin_permiso' }
  if (/paciente_no_encontrado/.test(m)) return { status: 404, error: 'paciente_no_encontrado' }
  return null
}

// Prompt de usuario del resumen, a partir del JSON de contexto_ia_ultima_visita. Todo campo vacío se
// escribe 'No registrado' para que el modelo lo liste en datos_faltantes en vez de rellenarlo.
// El nombre del médico NO va al prompt: no le sirve al resumen y no tiene por qué salir a un tercero.
export function buildPromptResumen(ctx: any): string {
  const c = ctx || {}
  const p = c.paciente || {}
  const u = c.unidades_signos_vitales || {}
  const txt = (v: unknown) => (v === null || v === undefined || String(v).trim() === '' ? 'No registrado' : String(v).trim())
  const fecha = (f: unknown) => (f ? String(f).slice(0, 10) : 's/f')
  const hora = (h: unknown) => (h ? String(h).slice(0, 5) : '')

  const campos: [string, string, string][] = [
    ['presion_arterial', 'PA', 'mmHg'], ['frecuencia_cardiaca', 'FC', 'lpm'],
    ['frecuencia_respiratoria', 'FR', 'rpm'], ['temperatura', 'Temp', '°C'],
    ['saturacion_o2', 'SpO2', '%'], ['glucosa', 'Glucosa', 'mg/dL'],
    ['peso_kg', 'Peso', 'kg'], ['talla_cm', 'Talla', 'cm'], ['imc', 'IMC', 'kg/m2'],
  ]
  const vit = Array.isArray(c.signos_vitales) ? c.signos_vitales : []
  const vitalesTxt = vit.length
    ? vit.map((v: any) => {
        const partes = campos
          .filter(([k]) => v[k] !== null && v[k] !== undefined && v[k] !== '')
          .map(([k, et, unidad]) => `${et} ${v[k]} ${u[k] || unidad}`)
        const toma = String(v.fecha_toma || '').replace('T', ' ').slice(0, 16) || 's/f'
        return `- ${toma} (${v.estado || 'sin estado'}): ${partes.length ? partes.join(', ') : 'sin valores'}`
      }).join('\n')
    : 'No registrado'

  return `VISITA: ${fecha(c.fecha)}${hora(c.hora_inicio) ? ` ${hora(c.hora_inicio)}` : ''}
NOTA CORREGIDA DESPUES DE CERRADA: ${c.corregida === true ? 'Si' : 'No'}

PACIENTE:
- Edad: ${p.edad != null ? `${p.edad} años` : 'No registrado'}
- Genero: ${txt(p.genero)}
- Tipo de sangre: ${txt(p.tipo_sangre)}
- Alergias: ${txt(p.alergias)}
- Medicacion en uso (declarada en ficha): ${txt(p.medicacion_en_uso)}
- Antecedentes personales: ${txt(p.antecedentes_personales)}
- Antecedentes familiares: ${txt(p.antecedentes_familiares)}

NOTA DE LA VISITA (SOAP):
- Motivo de consulta: ${txt(c.motivo_consulta)}
- Subjetivo: ${txt(c.subjetivo)}
- Objetivo: ${txt(c.objetivo)}
- Analisis: ${txt(c.analisis)}
- Diagnostico: ${txt(c.diagnostico)}
- Plan: ${txt(c.plan)}
- Nota libre: ${txt(c.nota)}

SIGNOS VITALES DE ESA VISITA (hora de toma en UTC; validados primero, luego mas reciente primero):
${vitalesTxt}

Redacta el resumen segun las reglas establecidas.`
}

// Forma EXACTA de la salida del modelo: las 5 claves, ni una más, con sus tipos.
export function validarResumen(v: unknown): ResumenVisita | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null
  const o = v as Record<string, unknown>
  const claves = Object.keys(o)
  if (claves.length !== CLAVES_RESUMEN.length || !CLAVES_RESUMEN.every((k) => claves.includes(k))) return null
  if (typeof o.resumen !== 'string' || o.resumen.trim() === '') return null
  for (const k of CLAVES_RESUMEN.slice(1)) {
    const a = o[k]
    if (!Array.isArray(a) || !a.every((x) => typeof x === 'string')) return null
  }
  return o as unknown as ResumenVisita
}

// Texto crudo de OpenAI → resumen validado o null. Sin rescate por regex: o es el JSON exacto o no sirve.
export function parsearResumen(texto: string): ResumenVisita | null {
  try {
    return validarResumen(JSON.parse(texto))
  } catch {
    return null
  }
}

// ============================================================================================
// Piezas compartidas por los dos modos: llamada a OpenAI (mismo modelo/timeout/max_tokens) y auditoría.
// ============================================================================================

const MODELO_IA = 'gpt-4o-mini'

type ResultadoOpenAI = { ok: true; texto: string } | { ok: false; status: number; body: Record<string, unknown> }

async function llamarOpenAI(apiKey: string, system: string, user: string): Promise<ResultadoOpenAI> {
  // Timeout duro: abortar si OpenAI tarda demasiado (no colgar la edge hasta su wall-clock).
  const ac = new AbortController()
  const timeoutId = setTimeout(() => ac.abort(), 25000)
  let openaiRes: Response
  try {
    openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODELO_IA,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user }
        ],
        temperature: 0.3,
        max_tokens: 1500,
        response_format: { type: 'json_object' },
      }),
      signal: ac.signal,
    })
  } catch (e: any) {
    clearTimeout(timeoutId)
    const abortado = e?.name === 'AbortError'
    console.error('OpenAI fetch error:', abortado ? 'timeout' : (e?.message ?? e))
    return {
      ok: false, status: 504, body: {
        error: abortado ? 'asistente_timeout' : 'error_openai',
        message: abortado
          ? 'El asistente de IA tardó demasiado en responder. Intentá de nuevo.'
          : 'No se pudo contactar al asistente de IA. Intentá de nuevo en unos minutos.',
      },
    }
  }
  clearTimeout(timeoutId)

  if (!openaiRes.ok) {
    let errMsg = 'Error en OpenAI'
    try {
      const err = await openaiRes.json()
      errMsg = err.error?.message || `OpenAI HTTP ${openaiRes.status}`
    } catch {
      errMsg = `OpenAI HTTP ${openaiRes.status}`
    }
    console.error('OpenAI error, status:', openaiRes.status)
    // FAIL-CLOSED: NUNCA devolver una sugerencia clínica falsa. Ante cualquier error de OpenAI
    // (cuota, billing, rate-limit 429...) se responde error honesto -> el front muestra el estado de error.
    const esCuota = openaiRes.status === 429 || /quota|billing|exceeded|rate limit/i.test(errMsg)
    return {
      ok: false, status: 503, body: {
        error: esCuota ? 'asistente_no_disponible' : 'error_openai',
        message: esCuota
          ? 'El asistente de IA no está disponible en este momento (límite de uso). Intentá más tarde.'
          : 'El asistente de IA tuvo un error. Intentá de nuevo en unos minutos.',
      },
    }
  }

  const openaiData = await openaiRes.json()
  return { ok: true, texto: openaiData.choices?.[0]?.message?.content || '' }
}

// Auditoria via fetch directo con SERVICE_ROLE (SOLO para esto; NUNCA para el gate).
// medico_id = identidad verificada (getUser); paciente_id = ya validado por el gate (pertenencia).
async function auditar(supabaseUrl: string, fila: Record<string, unknown>) {
  try {
    const serviceKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (supabaseUrl && serviceKey) {
      await fetch(`${supabaseUrl}/rest/v1/auditoria_ia`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${serviceKey}`,
          'apikey': serviceKey,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: JSON.stringify(fila),
      })
    }
  } catch (auditErr: any) {
    console.error('Auditoria error (no critico):', auditErr?.message ?? auditErr?.code)
  }
}

export async function handle(req: Request): Promise<Response> {
  const corsHeaders = buildCors(req.headers.get('Origin'))
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // AUTH: exigir el JWT del caller (verify_jwt=true ya lo exige en el gateway; acá doble defensa).
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'no_auth' }, 401)

  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    console.error('OPENAI_API_KEY no configurada')
    return json({ error: 'OPENAI_API_KEY no configurada. Contacte al administrador.', needsConfig: true }, 503)
  }

  const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY')
  if (!supabaseUrl || !anonKey) return json({ error: 'config_supabase' }, 503)

  // Client con el JWT del caller (NO service_role) → para getUser + gate_accion_phi.
  const supa = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } })

  // IDENTIDAD REAL: el medico_id de la auditoría sale del auth server (getUser), NO del body (no falsificable).
  const { data: userData, error: uErr } = await supa.auth.getUser()
  if (uErr || !userData?.user) return json({ error: 'no_auth' }, 401)
  const medicoIdReal = userData.user.id

  try {
    const body = await req.json()

    // MODO resumen_visita: se resuelve ANTES del chequeo de soap. Sólo se lee paciente_id; consulta_id,
    // medico_id y soap del body se ignoran (la nota sale de la RPC, no del caller).
    if (decidirModo(body) === 'resumen_visita') {
      const pacienteIdResumen = idPositivo(body.paciente_id)
      if (!pacienteIdResumen) return json({ error: 'paciente_id requerido' }, 400)

      const { data: ctx, error: rErr } = await supa.rpc('contexto_ia_ultima_visita', { p_paciente_id: pacienteIdResumen })
      if (rErr) {
        const mapeado = mapearErrorRpc(rErr)
        if (mapeado) return json({ error: mapeado.error }, mapeado.status)
        console.error('contexto_ia_ultima_visita error:', rErr?.message ?? rErr?.code)
        return json({ error: 'error_contexto' }, 500)
      }
      if (!ctx || typeof ctx !== 'object') return json({ error: 'error_contexto' }, 500)
      // Sin visita: ni OpenAI ni auditoría (no salió nada del paciente hacia un tercero).
      if (ctx.sin_visita === true) return json({ sin_visita: true })

      const promptResumen = buildPromptResumen(ctx)
      const r = await llamarOpenAI(apiKey, SYSTEM_PROMPT_RESUMEN, promptResumen)
      if (!r.ok) return json(r.body, r.status)

      const resumen = parsearResumen(r.texto)
      await auditar(supabaseUrl, {
        medico_id: medicoIdReal,
        paciente_id: pacienteIdResumen,
        consulta_id: ctx.nota_id ?? null, // nota_id DEVUELTO por la RPC, nunca del body
        accion_medico: MODO_RESUMEN_VISITA,
        prompt: promptResumen,
        respuesta_ia: resumen ? JSON.stringify(resumen) : r.texto,
        modelo_ia: MODELO_IA,
      })
      if (!resumen) return json({ error: 'respuesta_ia_invalida' }, 502)

      return json({
        sin_visita: false,
        cita_id: ctx.cita_id,
        fecha: ctx.fecha,
        hora_inicio: ctx.hora_inicio,
        medico_nombre: ctx.medico_nombre,
        corregida: ctx.corregida === true,
        resumen,
      })
    }

    const { soap, paciente_id, consulta_id } = body // medico_id del body se IGNORA a propósito
    const pacienteId = Number(paciente_id)
    if (!pacienteId) return json({ error: 'paciente_id requerido' }, 400)

    // GUARD DE VENTANA (deploy coordinado edge→front): si el front viejo aún manda 'contexto' y no 'soap',
    // fallar ruidoso. NO opinar sin SOAP en vivo.
    if (!soap || typeof soap !== 'object' || Array.isArray(soap)) {
      return json({ error: 'app_desactualizada', message: 'Recarga la página para actualizar el asistente.' }, 400)
    }

    // GATE ÚNICO: contexto_ia_paciente gatea internamente con gate_accion_phi('asistente_ia') ANTES de leer.
    // Se llama con el client anon+JWT del caller (NO service_role). Nada llega a OpenAI antes de esto;
    // el SOAP del body solo se usa DESPUÉS de que el RPC devolvió OK (su gate protege también el camino del SOAP).
    const { data: ctxHist, error: ctxErr } = await supa.rpc('contexto_ia_paciente', { p_paciente_id: pacienteId })
    if (ctxErr) {
      const m = ctxErr.message || ''
      if (/no_pertenencia/.test(m)) return json({ error: 'no_pertenencia' }, 403)
      if (/consentimiento_revocado/.test(m)) return json({ error: 'consentimiento_revocado' }, 403)
      if (/no_auth/.test(m)) return json({ error: 'no_auth' }, 401)
      console.error('contexto_ia_paciente error:', ctxErr?.message ?? ctxErr?.code)
      return json({ error: 'error_contexto' }, 500)
    }

    // consulta_id del body: si viene, tiene que ser una nota de ESTE paciente que el caller pueda leer
    // (cliente del usuario, o sea RLS). Antes se auditaba tal cual llegaba.
    const cons = parsearConsultaId(consulta_id)
    let consultaIdAuditada: number | null = null
    if (cons.presente) {
      if (cons.id === null) return json({ error: 'consulta_invalida' }, 400)
      const { data: nota, error: nErr } = await supa
        .from('expediente_notas').select('id')
        .eq('id', cons.id).eq('paciente_id', pacienteId)
        .maybeSingle()
      if (nErr) {
        console.error('validacion consulta_id error:', nErr?.message ?? nErr?.code)
        return json({ error: 'error_contexto' }, 500)
      }
      if (!nota) return json({ error: 'consulta_invalida' }, 400)
      consultaIdAuditada = cons.id
    }

    const userPrompt = buildPrompt(ctxHist, soap)

    const r = await llamarOpenAI(apiKey, SYSTEM_PROMPT, userPrompt)
    if (!r.ok) return json(r.body, r.status)
    const respuestaTexto = r.texto

    let respuestaEstructurada: any
    try {
      respuestaEstructurada = JSON.parse(respuestaTexto)
    } catch {
      const jsonMatch = respuestaTexto.match(/\{[\s\S]*\}/)
      if (jsonMatch) {
        respuestaEstructurada = JSON.parse(jsonMatch[0])
      } else {
        respuestaEstructurada = {
          disclaimer: "Sugerencia de IA generada automaticamente. NO reemplaza la evaluacion medica.",
          diagnosticos_diferenciales: [],
          examenes_recomendados: [],
          opciones_farmacologicas: [],
          contraindicaciones: [],
          referencias_guias: [],
          notas_adicionales: respuestaTexto
        }
      }
    }

    await auditar(supabaseUrl, {
      medico_id: medicoIdReal,
      paciente_id: pacienteId,
      consulta_id: consultaIdAuditada,
      prompt: userPrompt,
      respuesta_ia: JSON.stringify(respuestaEstructurada),
      modelo_ia: MODELO_IA,
    })

    return json({
      sugerencias: respuestaEstructurada,
      modelo: MODELO_IA,
    })

  } catch (error: any) {
    console.error('Error asistente-ia:', error?.message ?? error?.code)
    return json({ error: error?.message || 'Error interno del servidor' }, 500)
  }
}

if (import.meta.main) serve(handle)
