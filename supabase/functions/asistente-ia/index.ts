import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ContextoMedico {
  edad?: number
  genero?: string
  peso_kg?: number
  motivo_consulta?: string
  subjetivo?: string
  objetivo?: string
  signos_vitales?: {
    presion_arterial?: string
    temperatura?: number
    frecuencia_cardiaca?: number
  }
  alergias?: string
  medicamentos_actuales?: string
  antecedentes?: string
}

const SYSTEM_PROMPT = `Eres un asistente médico de soporte. NO eres un médico. NO diagnostiques. NO prescribas medicamentos directamente.

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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    return new Response(JSON.stringify({
      error: 'OPENAI_API_KEY no configurada. Contacte al administrador.',
      needsConfig: true
    }), {
      status: 503,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const { contexto, medico_id, paciente_id, consulta_id } = await req.json()

    if (!contexto) {
      return new Response(JSON.stringify({ error: 'Contexto medico requerido' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const ctx = contexto as ContextoMedico

    const userPrompt = `PACIENTE:
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

    // Llamar a OpenAI
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
      }),
    })

    if (!openaiRes.ok) {
      const err = await openaiRes.json()
      throw new Error(err.error?.message || 'Error en OpenAI')
    }

    const openaiData = await openaiRes.json()
    const respuestaTexto = openaiData.choices?.[0]?.message?.content || ''

    // Parsear JSON de la respuesta
    let respuestaEstructurada: any
    try {
      // A veces OpenAI devuelve markdown ```json ... ```
      const jsonMatch = respuestaTexto.match(/\{[\s\S]*\}/)
      respuestaEstructurada = jsonMatch ? JSON.parse(jsonMatch[0]) : JSON.parse(respuestaTexto)
    } catch {
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

    // Guardar auditoria
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (supabaseUrl && supabaseServiceKey) {
      const supabase = createClient(supabaseUrl, supabaseServiceKey)
      await supabase.from('auditoria_ia').insert({
        medico_id: medico_id || null,
        paciente_id: paciente_id || null,
        consulta_id: consulta_id || null,
        prompt: userPrompt,
        respuesta_ia: respuestaTexto,
        modelo_ia: 'gpt-4o-mini',
      })
    }

    return new Response(JSON.stringify({
      sugerencias: respuestaEstructurada,
      modelo: 'gpt-4o-mini',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('Error asistente-ia:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
