import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    console.error('OPENAI_API_KEY no configurada')
    return new Response(JSON.stringify({
      error: 'OPENAI_API_KEY no configurada. Contacte al administrador.',
      needsConfig: true
    }), {
      status: 503,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const body = await req.json()
    console.log('Request body:', JSON.stringify(body))
    const { contexto, medico_id, paciente_id, consulta_id } = body

    if (!contexto) {
      return new Response(JSON.stringify({ error: 'Contexto medico requerido' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const userPrompt = buildPrompt(contexto)
    console.log('Llamando a OpenAI...')

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

    console.log('OpenAI status:', openaiRes.status)

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
        console.log('Usando respuesta mock por limite de cuota de OpenAI')
        respuestaEstructurada = mockResponse(contexto.motivo_consulta)
      } else {
        throw new Error(errMsg)
      }
    } else {
      const openaiData = await openaiRes.json()
      const respuestaTexto = openaiData.choices?.[0]?.message?.content || ''
      console.log('OpenAI respuesta recibida, length:', respuestaTexto.length)
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

    // Guardar auditoria via fetch directo
    try {
      const supabaseUrl = Deno.env.get('SUPABASE_URL')
      const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
      if (supabaseUrl && supabaseServiceKey) {
        const auditRes = await fetch(`${supabaseUrl}/rest/v1/auditoria_ia`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${supabaseServiceKey}`,
            'apikey': supabaseServiceKey,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          },
          body: JSON.stringify({
            medico_id: medico_id || null,
            paciente_id: paciente_id || null,
            consulta_id: consulta_id || null,
            prompt: userPrompt,
            respuesta_ia: fromOpenAI ? JSON.stringify(respuestaEstructurada) : '[MOCK - OpenAI quota exceeded]',
            modelo_ia: fromOpenAI ? 'gpt-4o-mini' : 'mock-quota',
          }),
        })
        console.log('Auditoria insert status:', auditRes.status)
      }
    } catch (auditErr: any) {
      console.error('Auditoria error (no critico):', auditErr?.message || auditErr)
    }

    console.log('Respondiendo OK')
    return new Response(JSON.stringify({
      sugerencias: respuestaEstructurada,
      modelo: fromOpenAI ? 'gpt-4o-mini' : 'mock-mode',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error: any) {
    console.error('Error asistente-ia:', error?.message || error)
    return new Response(JSON.stringify({ error: error?.message || 'Error interno del servidor' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
