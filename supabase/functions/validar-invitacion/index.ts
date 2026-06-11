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

    const { token } = await req.json()

    if (!token) {
      return new Response(JSON.stringify({ error: 'Token requerido' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    const { data: invitacion, error } = await supabase
      .from('invitaciones_visitador')
      .select('*, empresa:empresa_id(nombre_empresa)')
      .eq('token', token)
      .eq('estado', 'pendiente')
      .gt('expires_at', new Date().toISOString())
      .single()

    if (error || !invitacion) {
      return new Response(JSON.stringify({ error: 'Invitación no válida o expirada' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    return new Response(
      JSON.stringify({
        valid: true,
        email: invitacion.email,
        nombre_completo: invitacion.nombre_completo,
        telefono: invitacion.telefono,
        rol: invitacion.rol,
        empresa_nombre: invitacion.empresa?.nombre_empresa,
        expires_at: invitacion.expires_at,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Error validar-invitacion:', err)
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
