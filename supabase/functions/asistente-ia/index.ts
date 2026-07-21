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
        if (v.presion_arterial != null) partes.push(`PA ${v.presion_arterial}`)
        if (v.frecuencia_cardiaca != null) partes.push(`FC ${v.frecuencia_cardiaca} lpm`)
        if (v.frecuencia_respiratoria != null) partes.push(`FR ${v.frecuencia_respiratoria}`)
        if (v.temperatura != null) partes.push(`T ${v.temperatura} C`)
        if (v.saturacion_o2 != null) partes.push(`SpO2 ${v.saturacion_o2}%`)
        if (v.glucosa != null) partes.push(`Glu ${v.glucosa}`)
        if (v.peso_kg != null) partes.push(`Peso ${v.peso_kg} kg`)
        if (v.talla_cm != null) partes.push(`Talla ${v.talla_cm} cm`)
        if (v.imc != null) partes.push(`IMC ${v.imc}`)
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
  const exaTxt = exa.length
    ? exa.map((e: any) =>
        `- ${fmtFecha(e.fecha_resultado)}: ${e.tipo || 's/t'}${e.descripcion ? ` (${e.descripcion})` : ''} → ${e.resultados || 'sin resultado'}`
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

serve(async (req) => {
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
    const { soap, paciente_id, consulta_id } = await req.json() // medico_id del body se IGNORA a propósito
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

    const userPrompt = buildPrompt(ctxHist, soap)

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
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: SYSTEM_PROMPT },
            { role: 'user', content: userPrompt }
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
      return json({
        error: abortado ? 'asistente_timeout' : 'error_openai',
        message: abortado
          ? 'El asistente de IA tardó demasiado en responder. Intentá de nuevo.'
          : 'No se pudo contactar al asistente de IA. Intentá de nuevo en unos minutos.',
      }, 504)
    }
    clearTimeout(timeoutId)

    let respuestaEstructurada: any
    let fromOpenAI = false

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
      return json({
        error: esCuota ? 'asistente_no_disponible' : 'error_openai',
        message: esCuota
          ? 'El asistente de IA no está disponible en este momento (límite de uso). Intentá más tarde.'
          : 'El asistente de IA tuvo un error. Intentá de nuevo en unos minutos.',
      }, 503)
    } else {
      const openaiData = await openaiRes.json()
      const respuestaTexto = openaiData.choices?.[0]?.message?.content || ''
      fromOpenAI = true

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
    }

    // Auditoria via fetch directo con SERVICE_ROLE (SOLO para esto; NUNCA para el gate).
    // medico_id = identidad verificada (getUser); paciente_id = ya validado por el gate (pertenencia).
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
          body: JSON.stringify({
            medico_id: medicoIdReal,
            paciente_id: pacienteId,
            consulta_id: consulta_id || null,
            prompt: userPrompt,
            respuesta_ia: fromOpenAI ? JSON.stringify(respuestaEstructurada) : '[MOCK - OpenAI quota exceeded]',
            modelo_ia: fromOpenAI ? 'gpt-4o-mini' : 'mock-quota',
          }),
        })
      }
    } catch (auditErr: any) {
      console.error('Auditoria error (no critico):', auditErr?.message ?? auditErr?.code)
    }

    return json({
      sugerencias: respuestaEstructurada,
      modelo: fromOpenAI ? 'gpt-4o-mini' : 'mock-mode',
    })

  } catch (error: any) {
    console.error('Error asistente-ia:', error?.message ?? error?.code)
    return json({ error: error?.message || 'Error interno del servidor' }, 500)
  }
})
