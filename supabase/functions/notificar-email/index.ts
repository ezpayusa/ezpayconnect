import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { to, subject, html, tipo, metadata } = await req.json()

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
        from: 'EzPayConnect <onboarding@resend.dev>',
        to,
        subject,
        html,
      }),
    })

    const data = await res.json()

    // Log en BD (notificaciones_email)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const logPayload = {
      destinatario: to,
      asunto: subject,
      tipo: tipo || 'general',
      estado: res.ok ? 'enviado' : 'fallido',
      error: res.ok ? null : (data?.message || JSON.stringify(data)),
      proveedor_id: metadata?.proveedor_id || null,
      visita_id: metadata?.visita_id || null,
    }

    const { error: logError } = await supabase.from('notificaciones_email').insert(logPayload)
    if (logError) {
      console.error('[notificar-email] Error logueando en BD:', logError)
    }

    if (!res.ok) {
      console.error('[notificar-email] Error Resend:', data)
      return new Response(
        JSON.stringify({ error: 'Error enviando email', details: data }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

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
