// supabase/functions/reportes-resumen/index.ts
// Dia 16: Edge Function - Reporte Resumen Mensual
// EzPayConnect — Actualizado: sin facturacion

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
    const mes = url.searchParams.get('mes') // YYYY-MM o 'current'
    const medicoId = url.searchParams.get('medico_id')

    let query = supabase.from('v_resumen_mensual').select('*')

    if (mes && mes !== 'current') {
      query = query.eq('mes', `${mes}-01`)
    } else if (mes === 'current') {
      const now = new Date()
      const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`
      query = query.eq('mes', currentMonth)
    }

    const { data: resumen, error: resumenError } = await query.order('mes', { ascending: false })

    if (resumenError) throw resumenError

    let medicoStats = null
    if (medicoId) {
      const { data: medico, error: medicoError } = await supabase
        .from('v_estadisticas_medico')
        .select('*')
        .eq('medico_id', medicoId)
        .single()

      if (!medicoError) medicoStats = medico
    }

    const { count: totalPacientes } = await supabase
      .from('pacientes')
      .select('*', { count: 'exact', head: true })

    const { count: totalMedicos } = await supabase
      .from('perfiles')
      .select('*', { count: 'exact', head: true })
      .eq('rol', 'medico')

    const { count: citasHoy } = await supabase
      .from('citas')
      .select('*', { count: 'exact', head: true })
      .eq('fecha', new Date().toISOString().split('T')[0])

    const { count: recetasTotal } = await supabase
      .from('recetas')
      .select('*', { count: 'exact', head: true })

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          resumen_mensual: resumen || [],
          medico_seleccionado: medicoStats,
          kpis: {
            total_pacientes: totalPacientes || 0,
            total_medicos: totalMedicos || 0,
            citas_hoy: citasHoy || 0,
            recetas_total: recetasTotal || 0,
          }
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
