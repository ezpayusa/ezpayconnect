import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { to, subject, html, tipo } = await req.json()

    if (!to || !subject || !html) {
      return new Response(
        JSON.stringify({ error: 'Faltan campos: to, subject, html' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    if (!resendApiKey) {
      console.error('[notificar-email] RESEND_API_KEY no configurada')
      return new Response(
        JSON.stringify({ error: 'Servicio de email no configurado' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'EzPayConnect <no-reply@ezpayconnect.com>',
        to,
        subject,
        html,
      }),
    })

    const data = await res.json()

    if (!res.ok) {
      console.error('[notificar-email] Error Resend:', data)
      return new Response(
        JSON.stringify({ error: 'Error enviando email', details: data }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // Log opcional en consola
    console.log(`[notificar-email] Enviado a ${to} | tipo: ${tipo || 'general'} | id: ${data.id}`)

    return new Response(
      JSON.stringify({ success: true, id: data.id }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (err: any) {
    console.error('[notificar-email] Error:', err)
    return new Response(
      JSON.stringify({ error: err.message || 'Error interno' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
