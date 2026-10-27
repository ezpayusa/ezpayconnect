import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// URL canónica de la app en producción (constante, NO env var: evita links rotos en silencio).
// Las edges no pueden importar de src/lib/app-url.ts, así que se define aquí.
const APP_URL = 'https://med.ezpayconnect.com'

const LOG = '[crear-invitacion-clinica]'

function responder(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function interno(): Response {
  return responder(500, { error: 'Error interno' })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const resendApiKey = Deno.env.get('RESEND_API_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    console.error(`${LOG} configuracion incompleta`)
    return interno()
  }

  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const body = await req.json()
    const { pais_id, email, nombre_clinica, nombre_contacto, direccion, telefono, num_medicos, num_secretarias, num_admin } = body

    if (!pais_id || !email || !nombre_clinica) {
      return responder(400, { error: 'Faltan campos requeridos: pais_id, email, nombre_clinica' })
    }

    // Validar al SOLICITANTE antes de generar la invitación. (Mismo patrón que crear-invitacion-medico
    //  y reportes-ezpay: el edge corre con service_role, así que el rol del caller NO lo da el JWT del
    //  gateway → hay que derivarlo y validarlo acá. Antes: cualquier authenticated invitaba clínicas.)
    //  A diferencia de médico, acá se ONBOARDEA una clínica NUEVA (no hay clinica_id / ownership que medir):
    //  autorizado = super_admin (global) o admin_pais acotado al pais_id de la invitación (fail-closed).
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return responder(401, { error: 'Falta Authorization' })
    }
    const token = authHeader.replace('Bearer ', '')
    const { data: { user: solicitante } } = await supabase.auth.getUser(token)
    if (!solicitante) {
      return responder(401, { error: 'No autenticado' })
    }
    const { data: perfilReq } = await supabase.from('perfiles').select('rol, pais_id').eq('id', solicitante.id).maybeSingle()
    let autorizado = perfilReq?.rol === 'super_admin'
    if (!autorizado && perfilReq?.rol === 'admin_pais') {
      // admin_pais sin país es imposible (CHECK admin_pais_requiere_pais, mig 216) pero se corta defensivo.
      autorizado = !!perfilReq?.pais_id && perfilReq.pais_id === pais_id
    }
    if (!autorizado) {
      return responder(403, { error: 'No autorizado para invitar clínicas' })
    }

    // Invitaciones 'pendiente' del mismo email: una VIGENTE bloquea (como siempre); una VENCIDA no bloquea
    // y pasa a 'expirada' antes de crear la nueva.
    const emailNorm = email.toLowerCase()
    const { data: pendientes, error: pendError } = await supabase
      .from('invitaciones_clinica')
      .select('id, expires_at')
      .eq('email', emailNorm)
      .eq('estado', 'pendiente')
    if (pendError || !Array.isArray(pendientes)) {
      console.error(`${LOG} lectura de pendientes fallida`, pendError?.code ?? '-')
      return interno()
    }

    const ahora = Date.now()
    const vigentes = pendientes.filter((p) => new Date(p.expires_at).getTime() > ahora)
    if (vigentes.length > 0) {
      return responder(409, { error: 'Ya existe una invitación pendiente para este email' })
    }

    const vencidas = pendientes.map((p) => p.id)
    if (vencidas.length > 0) {
      const { data: expiradas, error: expError } = await supabase
        .from('invitaciones_clinica')
        .update({ estado: 'expirada' })
        .in('id', vencidas)
        .eq('estado', 'pendiente')
        .lte('expires_at', new Date(ahora).toISOString())
        .select('id')
      if (expError || !Array.isArray(expiradas) || expiradas.length !== vencidas.length) {
        // otra request cambió esas filas entretanto: no se crea nada
        console.error(`${LOG} expiracion de vencidas no coincide`, expError?.code ?? '-')
        return interno()
      }
    }

    // Crear invitación (created_by = el solicitante resuelto del JWT, nunca del body)
    const { data: invitacion, error: insertError } = await supabase
      .from('invitaciones_clinica')
      .insert({
        pais_id,
        email: emailNorm,
        nombre_clinica,
        nombre_contacto: nombre_contacto || null,
        direccion: direccion || null,
        telefono: telefono || null,
        num_medicos: num_medicos || 1,
        num_secretarias: num_secretarias || 0,
        num_admin: num_admin || 0,
        estado: 'pendiente',
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        created_by: solicitante.id,
      })
      .select()
      .single()

    if (insertError || !invitacion?.token) {
      console.error(`${LOG} insert de invitacion fallido`, insertError?.code ?? '-')
      return responder(500, { error: 'Error creando invitación' })
    }

    // Enviar email con link de registro
    if (resendApiKey) {
      const registroUrl = `${APP_URL}/registro-clinica?token=${invitacion.token}`

      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'EzPayConnect <no-reply@ezpayconnect.com>',
          to: email,
          subject: 'Has sido invitado a registrar tu Clínica en EzPayConnect',
          html: `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
            <h2 style="color:#1E5C8E;margin-top:0;">¡Bienvenido a EzPayConnect!</h2>
            <p>Hola <strong>${nombre_contacto || nombre_clinica}</strong>,</p>
            <p>Has sido invitado a registrar <strong>${nombre_clinica}</strong> en EzPayConnect.</p>
            <p>Haz clic en el siguiente enlace para completar el registro:</p>
            <a href="${registroUrl}" style="display:inline-block;padding:12px 24px;background:#1E5C8E;color:white;text-decoration:none;border-radius:6px;margin:16px 0;">Completar Registro</a>
            <p style="color:#6b7280;font-size:12px;">Este enlace expira en 7 días.</p>
            <p style="color:#6b7280;font-size:12px;">EzPayConnect</p>
          </div>`,
        }),
      })
    }

    return responder(200, {
      success: true,
      data: {
        invitacion_id: invitacion.id,
        token: invitacion.token,
        email: invitacion.email,
        expires_at: invitacion.expires_at,
      },
    })
  } catch (_e) {
    console.error(`${LOG} error no controlado`)
    return interno()
  }
})
