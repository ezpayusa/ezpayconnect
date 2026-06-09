import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const body = await req.json()
    const { pais_id, email, nombre_completo, telefono, especialidad, clinica_id } = body

    if (!email || !nombre_completo) {
      return new Response(
        JSON.stringify({ error: 'Faltan campos requeridos: email, nombre_completo' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Si no viene pais_id, intentar obtenerlo de la clinica
    let final_pais_id = pais_id
    if (!final_pais_id && clinica_id) {
      const { data: clinica } = await supabase.from('clinicas').select('pais_id').eq('id', clinica_id).single()
      if (clinica) final_pais_id = clinica.pais_id
    }

    if (!final_pais_id) {
      return new Response(
        JSON.stringify({ error: 'Se requiere pais_id o clinica_id válida' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verificar que el email no tenga una invitación pendiente
    const { data: existente } = await supabase
      .from('invitaciones_medico')
      .select('id')
      .eq('email', email.toLowerCase())
      .eq('estado', 'pendiente')
      .single()

    if (existente) {
      return new Response(
        JSON.stringify({ error: 'Ya existe una invitación pendiente para este email' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Crear invitación
    const { data: invitacion, error: insertError } = await supabase
      .from('invitaciones_medico')
      .insert({
        pais_id: final_pais_id,
        email: email.toLowerCase(),
        nombre_completo,
        telefono: telefono || null,
        especialidad: especialidad || null,
        clinica_id: clinica_id || null,
        estado: 'pendiente',
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      })
      .select()
      .single()

    if (insertError) {
      console.error('[crear-invitacion-medico] Error:', insertError)
      return new Response(
        JSON.stringify({ error: 'Error creando invitación', details: insertError }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Enviar email con link de registro
    if (resendApiKey) {
      const registroUrl = `https://ezpayconnect.vercel.app/registro-medico?token=${invitacion.token}`
      
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'EzPayConnect <no-reply@ezpayconnect.com>',
          to: email,
          subject: 'Has sido invitado a unirte a EzPayConnect como Médico',
          html: `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
            <h2 style="color:#1E5C8E;margin-top:0;">¡Bienvenido a EzPayConnect!</h2>
            <p>Hola <strong>${nombre_completo}</strong>,</p>
            <p>Has sido invitado a registrarte como médico en EzPayConnect.</p>
            <p>Haz clic en el siguiente enlace para completar tu registro:</p>
            <a href="${registroUrl}" style="display:inline-block;padding:12px 24px;background:#1E5C8E;color:white;text-decoration:none;border-radius:6px;margin:16px 0;">Completar Registro</a>
            <p style="color:#6b7280;font-size:12px;">Este enlace expira en 7 días.</p>
            <p style="color:#6b7280;font-size:12px;">EzPayConnect</p>
          </div>`,
        }),
      })
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          invitacion_id: invitacion.id,
          token: invitacion.token,
          email: invitacion.email,
          expires_at: invitacion.expires_at,
        },
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error: any) {
    console.error('[crear-invitacion-medico] Error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
