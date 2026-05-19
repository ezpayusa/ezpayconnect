// supabase/functions/actualizar-configuracion/index.ts
// Dia 19: Edge Function - Actualizar configuracion del sistema
// EzPayConnect

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // GET: Obtener toda la configuracion
    if (req.method === 'GET') {
      const { data, error } = await supabase
        .from('configuracion_sistema')
        .select('*')
        .order('categoria')

      if (error) throw error

      // Organizar por categoria
      const config: Record<string, any[]> = {}
      for (const item of data || []) {
        if (!config[item.categoria]) config[item.categoria] = []
        config[item.categoria].push(item)
      }

      return new Response(
        JSON.stringify({ success: true, data: config }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // POST: Actualizar configuracion
    if (req.method === 'POST') {
      const { configuraciones } = await req.json()

      if (!configuraciones || !Array.isArray(configuraciones)) {
        throw new Error('Se requiere un array de configuraciones')
      }

      const results = []
      for (const config of configuraciones) {
        const { clave, valor } = config
        if (!clave) continue

        const { data, error } = await supabase
          .from('configuracion_sistema')
          .update({ valor })
          .eq('clave', clave)
          .select()
          .single()

        if (error) throw error
        results.push(data)
      }

      return new Response(
        JSON.stringify({ success: true, data: results, mensaje: `${results.length} configuraciones actualizadas` }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    return new Response(
      JSON.stringify({ success: false, error: 'Metodo no soportado' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 405 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
