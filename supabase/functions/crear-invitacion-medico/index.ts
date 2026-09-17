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
    const { pais_id, email, nombre_completo, telefono, especialidad, especialidad_id, clinica_id } = body

    if (!email || !nombre_completo) {
      return new Response(
        JSON.stringify({ error: 'Faltan campos requeridos: email, nombre_completo' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validar al SOLICITANTE: debe ser super_admin, o admin_clinica/gerente de ESA clínica.
    // (Mismo patrón que crear-staff-clinica: el edge corre con service_role, así que el rol del
    //  caller NO lo da el JWT del gateway → hay que derivarlo y validarlo acá. Antes: cualquier
    //  authenticated invitaba.)
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Falta Authorization' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    const token = authHeader.replace('Bearer ', '')
    const { data: { user: solicitante } } = await supabase.auth.getUser(token)
    if (!solicitante) {
      return new Response(JSON.stringify({ error: 'No autenticado' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    const { data: perfilReq } = await supabase.from('perfiles').select('rol, pais_id').eq('id', solicitante.id).maybeSingle()
    let autorizado = perfilReq?.rol === 'super_admin'
    if (!autorizado && (perfilReq?.rol === 'admin_clinica' || perfilReq?.rol === 'gerente')) {
      const { data: rel } = await supabase.rpc('obtener_clinica_usuario', { p_user_id: solicitante.id })
      autorizado = Array.isArray(rel) && rel.some((r: any) => r.clinica_id === clinica_id)
    }
    // admin_pais: autorizado dentro de SU pais. Faltaba — crear-invitacion-clinica ya lo contempla
    // y esta no, asi que el admin_pais tenia el item en el sidebar y recibia 403 al invitar.
    //
    // HAY QUE CUBRIR LOS DOS CAMINOS, no solo la clinica. InvitacionesMedicosPage (admin-ezpay) manda
    // `pais_id` y NO manda `clinica_id`; ClinicaInvitarMedicoPage manda `clinica_id`. Un gate armado
    // solo sobre clinica_id nunca autorizaria justamente la pantalla de admin de pais.
    //
    // Y el pais que se compara es el MISMO que termina en la fila (la logica de `final_pais_id` de
    // mas abajo: body.pais_id, y si no el de la clinica). Si el gate validara un pais y el INSERT
    // guardara otro, el gate no estaria gateando nada.
    if (!autorizado && perfilReq?.rol === 'admin_pais') {
      let paisClinica: string | null = null
      if (clinica_id) {
        const { data: cl } = await supabase.from('clinicas').select('pais_id').eq('id', clinica_id).maybeSingle()
        paisClinica = cl?.pais_id ?? null
      }
      const paisDestino = pais_id || paisClinica
      // admin_pais sin pais es imposible (CHECK admin_pais_requiere_pais, mig 216) pero se corta
      // defensivo: con los dos en null, `null === null` daria true y autorizaria a una cuenta rota.
      autorizado = !!perfilReq?.pais_id && !!paisDestino && perfilReq.pais_id === paisDestino
        // Si ademas viene una clinica, tiene que ser de SU pais. Sin esto un admin de GT podria
        // colgar la invitacion de una clinica de SV mandando pais_id=GT en el body.
        && (!clinica_id || paisClinica === perfilReq.pais_id)
    }
    if (!autorizado) {
      return new Response(JSON.stringify({ error: 'No autorizado para invitar médicos a esta clínica' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
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
        especialidad: especialidad || null,          // texto legacy (en paralelo)
        especialidad_id: especialidad_id || null,     // id del catálogo elegido en el Select (NULL = "sin especialidad")
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
      const registroUrl = `${APP_URL}/registro-medico?token=${invitacion.token}`
      
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
