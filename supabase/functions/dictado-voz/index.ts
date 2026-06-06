import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const apiKey = Deno.env.get('OPENAI_API_KEY')
  if (!apiKey) {
    return new Response(JSON.stringify({
      error: 'OPENAI_API_KEY no configurada',
      needsConfig: true
    }), {
      status: 503,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const formData = await req.formData()
    const audioFile = formData.get('audio') as File | null

    if (!audioFile) {
      return new Response(JSON.stringify({ error: 'No se envió archivo de audio' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Validar tamaño (max 10MB)
    if (audioFile.size > 10 * 1024 * 1024) {
      return new Response(JSON.stringify({ error: 'Archivo de audio demasiado grande (max 10MB)' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Enviar a Whisper
    const whisperForm = new FormData()
    whisperForm.append('file', audioFile, 'audio.webm')
    whisperForm.append('model', 'whisper-1')
    whisperForm.append('language', 'es')
    whisperForm.append('response_format', 'json')

    const whisperRes = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
      },
      body: whisperForm,
    })

    if (!whisperRes.ok) {
      const err = await whisperRes.json().catch(() => ({}))
      const errMsg = err.error?.message || `Whisper HTTP ${whisperRes.status}`
      console.error('Whisper error:', errMsg)
      throw new Error(errMsg)
    }

    const whisperData = await whisperRes.json()
    const texto = whisperData.text || ''

    return new Response(JSON.stringify({
      texto: texto.trim(),
      modelo: 'whisper-1',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error: any) {
    console.error('Error dictado-voz:', error?.message || error)
    return new Response(JSON.stringify({ error: error?.message || 'Error interno del servidor' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
