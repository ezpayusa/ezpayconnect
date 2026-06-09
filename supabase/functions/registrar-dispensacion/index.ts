// supabase/functions/registrar-dispensacion/index.ts
// Dia 18: Edge Function - Registrar dispensacion de receta
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

    const { receta_avanzada_id, farmacia_id, paciente_id, medico_id, codigo_qr, medicamentos_dispensados, total_dispensado, estado_dispensacion, motivo_rechazo, farmaceutico_nombre } = await req.json()

    if (!receta_avanzada_id || !farmacia_id || !paciente_id) throw new Error('Faltan campos requeridos')

    for (const item of medicamentos_dispensados || []) {
      const { data: med } = await supabase
        .from('farmacia_medicamentos')
        .select('stock_actual, nombre_medicamento')
        .eq('farmacia_id', farmacia_id)
        .eq('nombre_medicamento', item.nombre)
        .eq('activo', true)
        .single()

      if (!med) throw new Error(`Medicamento "${item.nombre}" no encontrado en farmacia`)
      if (med.stock_actual < item.cantidad) throw new Error(`Stock insuficiente para "${item.nombre}". Disponible: ${med.stock_actual}, Solicitado: ${item.cantidad}`)
    }

    const { data: dispensacion, error: dispError } = await supabase
      .from('dispensaciones')
      .insert({
        receta_avanzada_id, farmacia_id, paciente_id, medico_id, codigo_qr,
        medicamentos_dispensados, cantidad_items: medicamentos_dispensados?.length || 0,
        total_dispensado, estado_dispensacion: estado_dispensacion || 'completada',
        motivo_rechazo, farmaceutico_nombre, fecha_dispensacion: new Date().toISOString()
      })
      .select()
      .single()

    if (dispError) throw dispError

    return new Response(
      JSON.stringify({ success: true, data: { dispensacion, mensaje: 'Dispensacion registrada exitosamente', medicamentos: medicamentos_dispensados } }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
