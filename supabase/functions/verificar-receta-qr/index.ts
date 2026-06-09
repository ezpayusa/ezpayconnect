// supabase/functions/verificar-receta-qr/index.ts
// Dia 18: Edge Function - Verificar receta por codigo QR
// EzPayConnect

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
    const supabaseServiceKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const { codigo_qr } = await req.json()
    if (!codigo_qr) throw new Error('Se requiere el codigo QR')

    const { data: receta, error: recetaError } = await supabase
      .from('recetas_avanzadas')
      .select('*, paciente:pacientes(nombre, telefono), medico:perfiles(nombre, especialidad)')
      .eq('codigo_qr', codigo_qr)
      .single()

    if (recetaError || !receta) throw new Error('Receta no encontrada. Codigo QR invalido.')

    if (receta.estado_dispensacion === 'dispensada') {
      const { data: dispensacion } = await supabase
        .from('dispensaciones')
        .select('*, farmacia:farmacias(nombre)')
        .eq('receta_avanzada_id', receta.id)
        .order('fecha_dispensacion', { ascending: false })
        .limit(1)
        .single()

      return new Response(
        JSON.stringify({ success: true, data: { receta, estado: 'ya_dispensada', dispensacion, mensaje: 'Esta receta ya fue dispensada anteriormente' } }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    const { data: medicamentos } = await supabase
      .from('farmacia_medicamentos')
      .select('*, farmacia:farmacias(id, nombre)')
      .gt('stock_actual', 0)
      .eq('activo', true)

    return new Response(
      JSON.stringify({ success: true, data: { receta, estado: 'pendiente', medicamentos_disponibles: medicamentos || [], mensaje: 'Receta valida. Lista para dispensar.' } }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
