import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// CORS acotado (mismo patrón que dictado-voz). Solo orígenes propios (+ DEV_ORIGIN por env solo en dev).
const ALLOWED = ['https://ezpayconnect.vercel.app', 'https://med.ezpayconnect.com']
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

function buildPrompt(ctx: any) {
  return `PACIENTE:
- Edad: ${ctx.edad || 'No especificada'} años
- Genero: ${ctx.genero || 'No especificado'}
- Peso: ${ctx.peso_kg || 'No especificado'} kg
- Alergias: ${ctx.alergias || 'Ninguna conocida'}
- Medicacion actual: ${ctx.medicamentos_actuales || 'Ninguna'}
- Antecedentes: ${ctx.antecedentes || 'No especificados'}

MOTIVO DE CONSULTA:
${ctx.motivo_consulta || 'No especificado'}

SUBJETIVO (lo que refiere el paciente):
${ctx.subjetivo || 'No especificado'}

OBJETIVO (hallazgos de exploracion):
${ctx.objetivo || 'No especificado'}

SIGNOS VITALES:
${ctx.signos_vitales ? `
- Presion arterial: ${ctx.signos_vitales.presion_arterial || 'No tomada'}
- Temperatura: ${ctx.signos_vitales.temperatura || 'No tomada'} C
- Frecuencia cardiaca: ${ctx.signos_vitales.frecuencia_cardiaca || 'No tomada'} lpm
` : 'No registrados'}

Proporciona tu analisis de soporte segun las reglas establecidas.`
}

function mockResponse(motivo: string) {
  const lower = (motivo || '').toLowerCase()
  if (lower.includes('cefalea') || lower.includes('cabeza') || lower.includes('dolor de cabeza')) {
    return {
      disclaimer: "Sugerencia de IA generada automaticamente. NO es un diagnostico medico. El medico tratante debe verificar toda la informacion antes de prescribir.",
      diagnosticos_diferenciales: [
        { nombre: "Cefalea tensional", probabilidad: "Alta", justificacion: "Dolor frontal, paciente joven sin signos de alarma" },
        { nombre: "Cefalea migrañosa", probabilidad: "Media", justificacion: "Cefalea frontal puede ser compatible, faltan datos de aura o fotofobia" },
        { nombre: "Sinusitis", probabilidad: "Baja", justificacion: "Sin datos de congestion nasal o secrecion" }
      ],
      examenes_recomendados: ["Examen fisico neurologico completo", "Signos vitales serializados", "Evaluacion de fondo de ojo"],
      opciones_farmacologicas: [
        { nombre: "Paracetamol", nota: "Analgesico de primera linea. Consultar guia clinica para dosis." },
        { nombre: "Ibuprofeno", nota: "AINS alternativo. Contraindicado si hay alergia o alteracion renal." }
      ],
      contraindicaciones: ["Verificar alergias a AINES antes de prescribir", "Descartar embarazo si aplica"],
      referencias_guias: ["Guia NICE NG150: Headaches in over 12s", "American Headache Society 2023"],
      notas_adicionales: "Solicitar historia completa de sueño, estres y patron del dolor. Considerar imagen si hay signos de alarma."
    }
  }
  return {
    disclaimer: "Sugerencia de IA generada automaticamente. NO es un diagnostico medico. El medico tratante debe verificar toda la informacion antes de prescribir.",
    diagnosticos_diferenciales: [
      { nombre: "Diagnostico diferencial A", probabilidad: "Media", justificacion: "Basado en la informacion limitada proporcionada" }
    ],
    examenes_recomendados: ["Examen fisico completo", "Laboratorios basicos (CBC, quimica sanguinea)"],
    opciones_farmacologicas: [
      { nombre: "Consultar guia clinica", nota: "Se requiere mas informacion para sugerencias farmacologicas especificas." }
    ],
    contraindicaciones: ["Verificar alergias conocidas del paciente antes de cualquier prescripcion"],
    referencias_guias: ["Guia clinica nacional del pais de practica"],
    notas_adicionales: "La informacion proporcionada es insuficiente para un analisis completo. Se recomienda completar la historia clinica."
  }
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
    const { contexto, paciente_id, consulta_id } = await req.json() // medico_id del body se IGNORA a propósito
    if (!contexto) return json({ error: 'Contexto medico requerido' }, 400)
    const pacienteId = Number(paciente_id)
    if (!pacienteId) return json({ error: 'paciente_id requerido' }, 400)

    // GATE PHI: auth + pertenencia + consentimiento 'asistente_ia' (grandfather). Antes del prompt y de OpenAI.
    const { data: gate, error: gErr } = await supa.rpc('gate_accion_phi', {
      p_paciente_id: pacienteId,
      p_permiso_codigo: 'asistente_ia',
    })
    if (gErr) {
      const m = gErr.message || ''
      const code = /consentimiento_revocado/.test(m) ? 'consentimiento_revocado'
        : /no_pertenencia/.test(m) ? 'no_pertenencia'
        : 'no_auth'
      const status = code === 'no_auth' ? 401 : 403
      return json({ error: code }, status)
    }
    if (!gate?.ok) return json({ error: 'gate_denegado' }, 403)

    const userPrompt = buildPrompt(contexto)

    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
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
    })

    let respuestaEstructurada: any
    let fromOpenAI = false

    if (!openaiRes.ok) {
      let errMsg = 'Error en OpenAI'
      try {
        const err = await openaiRes.json()
        errMsg = err.error?.message || `OpenAI HTTP ${openaiRes.status}`
      } catch {
        errMsg = `OpenAI HTTP ${openaiRes.status}: ${await openaiRes.text()}`
      }
      console.error('OpenAI error:', errMsg)

      // Si es error de cuota, usar respuesta mock para no romper la app
      if (errMsg.includes('quota') || errMsg.includes('billing') || errMsg.includes('exceeded')) {
        respuestaEstructurada = mockResponse(contexto.motivo_consulta)
      } else {
        throw new Error(errMsg)
      }
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
      console.error('Auditoria error (no critico):', auditErr?.message || auditErr)
    }

    return json({
      sugerencias: respuestaEstructurada,
      modelo: fromOpenAI ? 'gpt-4o-mini' : 'mock-mode',
    })

  } catch (error: any) {
    console.error('Error asistente-ia:', error?.message || error)
    return json({ error: error?.message || 'Error interno del servidor' }, 500)
  }
})
