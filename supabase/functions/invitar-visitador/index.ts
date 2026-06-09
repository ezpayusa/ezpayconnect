import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Obtener JWT del usuario autenticado
    const authHeader = req.headers.get('authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Token inválido' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const body = await req.json()
    const { email, nombre_completo, telefono, empresa_id } = body

    if (!email || !nombre_completo || !empresa_id) {
      return new Response(JSON.stringify({ error: 'Email, nombre y empresa_id son obligatorios' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Verificar que el usuario es admin/editor de la empresa
    const { data: cuenta, error: cuentaError } = await supabase
      .from('cuentas_proveedor')
      .select('rol_en_empresa')
      .eq('id', user.id)
      .eq('empresa_id', empresa_id)
      .eq('activo', true)
      .single()

    if (cuentaError || !cuenta || !['admin', 'editor'].includes(cuenta.rol_en_empresa)) {
      return new Response(JSON.stringify({ error: 'No tienes permisos para invitar visitadores en esta empresa' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      })
    }

    // Verificar que el email no tenga una invitación pendiente
    const { data: existente } = await supabase
      .from('invitaciones_visitador')
      .select('id')
      .eq('email', email)
      .eq('empresa_id', empresa_id)
      .eq('estado', 'pendiente')
      .maybeSingle()

    if (existente) {
      return new Response(JSON.stringify({ error: 'Ya existe una invitación pendiente para este email' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Crear invitación
    const { data: invitacion, error: insertError } = await supabase
      .from('invitaciones_visitador')
      .insert({
        empresa_id,
        email,
        nombre_completo,
        telefono: telefono || null,
      })
      .select('token')
      .single()

    if (insertError || !invitacion) {
      console.error('Error insertando invitación:', insertError)
      return new Response(JSON.stringify({ error: 'Error al crear la invitación' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }

    return new Response(
      JSON.stringify({
        token: invitacion.token,
        message: 'Invitación creada exitosamente',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Error invitar-visitador:', err)
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
