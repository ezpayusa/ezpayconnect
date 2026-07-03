// supabase/functions/reportes-detalle/index.ts
// Dia 16: Edge Function - Reporte Detalle Filtrable
// EzPayConnect — Version sin joins (evita errores de FK)

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
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // GATE DE AUTORIZACIÓN — solo super_admin. Esta función usa service_role (bypass RLS) sin validar
    // al caller (mismo patrón que reportes-ezpay): se valida el JWT con un cliente anon (getUser) y el
    // rol se lee con el admin client.
    const supabaseAnonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || ''
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader) {
      return new Response(JSON.stringify({ success: false, error: 'Falta Authorization' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }
    const userClient = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(JSON.stringify({ success: false, error: 'JWT inválido' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }
    const { data: perfilCaller } = await supabase.from('perfiles').select('rol').eq('id', user.id).maybeSingle()
    if (!perfilCaller || perfilCaller.rol !== 'super_admin') {
      return new Response(JSON.stringify({ success: false, error: 'No autorizado: sólo super_admin' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 })
    }

    const url = new URL(req.url)

    const tipo = url.searchParams.get('tipo') || 'citas'
    const fechaDesde = url.searchParams.get('fecha_desde')
    const fechaHasta = url.searchParams.get('fecha_hasta')
    const medicoId = url.searchParams.get('medico_id')
    const estado = url.searchParams.get('estado')
    const pacienteId = url.searchParams.get('paciente_id')
    const limit = parseInt(url.searchParams.get('limit') || '100')
    const offset = parseInt(url.searchParams.get('offset') || '0')

    let data = null
    let count = 0
    let error = null

    switch (tipo) {
      case 'citas': {
        let query = supabase
          .from('citas')
          .select('*', { count: 'exact' })

        if (fechaDesde) query = query.gte('fecha', fechaDesde)
        if (fechaHasta) query = query.lte('fecha', fechaHasta)
        if (medicoId) query = query.eq('medico_id', medicoId)
        if (estado) query = query.eq('estado', estado)
        if (pacienteId) query = query.eq('paciente_id', pacienteId)

        const result = await query.range(offset, offset + limit - 1).order('fecha', { ascending: false })
        data = result.data
        count = result.count || 0
        error = result.error
        break
      }

      case 'pacientes': {
        let query = supabase
          .from('v_pacientes_actividad')
          .select('*', { count: 'exact' })

        if (fechaDesde) query = query.gte('ultima_cita', fechaDesde)
        if (fechaHasta) query = query.lte('ultima_cita', fechaHasta)

        const result = await query.range(offset, offset + limit - 1).order('ultima_cita', { ascending: false })
        data = result.data
        count = result.count || 0
        error = result.error
        break
      }

      case 'recetas': {
        let query = supabase
          .from('recetas')
          .select('*', { count: 'exact' })

        if (fechaDesde) query = query.gte('created_at', `${fechaDesde}T00:00:00`)
        if (fechaHasta) query = query.lte('created_at', `${fechaHasta}T23:59:59`)
        if (medicoId) query = query.eq('medico_id', medicoId)
        if (pacienteId) query = query.eq('paciente_id', pacienteId)

        const result = await query.range(offset, offset + limit - 1).order('created_at', { ascending: false })
        data = result.data
        count = result.count || 0
        error = result.error
        break
      }

      default:
        throw new Error('Tipo de reporte no valido. Use: citas | pacientes | recetas')
    }

    if (error) throw error

    return new Response(
      JSON.stringify({
        success: true,
        data: data || [],
        pagination: {
          total: count,
          limit,
          offset,
          has_more: (offset + limit) < count
        },
        filtros_aplicados: {
          tipo,
          fecha_desde: fechaDesde,
          fecha_hasta: fechaHasta,
          medico_id: medicoId,
          estado,
          paciente_id: pacienteId
        }
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
