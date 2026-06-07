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
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const body = await req.json()
    const { token, password, nombre_contacto, telefono } = body

    if (!token || !password) {
      return new Response(
        JSON.stringify({ error: 'Token y contraseña son requeridos' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Validar invitación
    const { data: invitacion, error: invError } = await supabase
      .from('invitaciones_clinica')
      .select('*')
      .eq('token', token)
      .eq('estado', 'pendiente')
      .gt('expires_at', new Date().toISOString())
      .single()

    if (invError || !invitacion) {
      return new Response(
        JSON.stringify({ error: 'Invitación no válida o expirada' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Crear usuario en Auth
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email: invitacion.email,
      password,
      email_confirm: true,
    })

    if (authError) {
      if (authError.message?.includes('already')) {
        return new Response(
          JSON.stringify({ error: 'Este email ya está registrado. Inicia sesión.' }),
          { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      console.error('[registrar-clinica-invitacion] Auth error:', authError)
      return new Response(
        JSON.stringify({ error: 'Error creando usuario', details: authError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const userId = authData.user!.id

    // 3. Insertar en perfiles primero
    await supabase.from('perfiles').insert({
      id: userId,
      email: invitacion.email,
      nombre_completo: nombre_contacto || invitacion.nombre_contacto || invitacion.nombre_clinica,
      rol: 'admin_clinica',
      pais_id: invitacion.pais_id,
      activo: true,
    }).select()

    // 4. Llamar función SQL para completar registro
    const { data: result, error: rpcError } = await supabase.rpc('registrar_clinica_desde_invitacion', {
      p_token: token,
      p_user_id: userId,
      p_email: invitacion.email,
      p_nombre_contacto: nombre_contacto || invitacion.nombre_contacto,
      p_telefono: telefono || invitacion.telefono,
    })

    if (rpcError) {
      console.error('[registrar-clinica-invitacion] RPC error:', rpcError)
      return new Response(
        JSON.stringify({ error: 'Error completando registro', details: rpcError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          clinica_id: result,
          email: invitacion.email,
        },
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error: any) {
    console.error('[registrar-clinica-invitacion] Error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
