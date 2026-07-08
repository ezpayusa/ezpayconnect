import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// CORS acotado: solo orígenes propios (no '*'). Si el Origin no está en la allowlist, se devuelve el 1ro.
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
  if (!apiKey) return json({ error: 'OPENAI_API_KEY no configurada', needsConfig: true }, 503)

  const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY')
  if (!supabaseUrl || !anonKey) return json({ error: 'config_supabase' }, 503)

  // Client con el JWT del caller (NO service_role) → auth.uid() = el caller dentro del RPC gate.
  const supa = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } })

  try {
    const formData = await req.formData()
    const audioFile = formData.get('audio') as File | null
    const pacienteId = Number(formData.get('paciente_id'))

    if (!pacienteId) return json({ error: 'paciente_id requerido' }, 400)
    if (!audioFile) return json({ error: 'No se envió archivo de audio' }, 400)
    if (audioFile.size > 10 * 1024 * 1024) return json({ error: 'Archivo de audio demasiado grande (max 10MB)' }, 400)

    // GATE PHI: auth + pertenencia + consentimiento 'grabacion_consulta' (grandfather). Antes de tocar Whisper.
    const { data: gate, error: gErr } = await supa.rpc('gate_accion_phi', {
      p_paciente_id: pacienteId,
      p_permiso_codigo: 'grabacion_consulta',
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

    // Enviar a Whisper (intacto). No se loguea el audio ni PHI.
    const whisperForm = new FormData()
    whisperForm.append('file', audioFile, 'audio.webm')
    whisperForm.append('model', 'whisper-1')
    whisperForm.append('language', 'es')
    whisperForm.append('response_format', 'json')

    const whisperRes = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}` },
      body: whisperForm,
    })

    if (!whisperRes.ok) {
      const err = await whisperRes.json().catch(() => ({}))
      const errMsg = err.error?.message || `Whisper HTTP ${whisperRes.status}`
      console.error('Whisper error, status:', whisperRes.status)
      throw new Error(errMsg)
    }

    const whisperData = await whisperRes.json()
    const texto = whisperData.text || ''

    return json({ texto: texto.trim(), modelo: 'whisper-1' })

  } catch (error: any) {
    console.error('Error dictado-voz:', error?.message ?? error?.code)
    return json({ error: error?.message || 'Error interno del servidor' }, 500)
  }
})
