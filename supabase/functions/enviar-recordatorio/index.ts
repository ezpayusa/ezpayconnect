// supabase/functions/enviar-recordatorio/index.ts
// Dia 17: Edge Function - Enviar recordatorio de cita
// EzPayConnect

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

    const { cita_id, tipo_recordatorio, mensaje_personalizado } = await req.json()

    if (!cita_id || !tipo_recordatorio) {
      throw new Error('Faltan campos requeridos: cita_id, tipo_recordatorio')
    }

    const { data: cita, error: citaError } = await supabase
      .from('citas')
      .select('*, paciente:pacientes(nombre, telefono, email), medico:perfiles(nombre)')
      .eq('id', cita_id)
      .single()

    if (citaError || !cita) throw new Error('Cita no encontrada')

    const paciente = cita.paciente
    const medico = cita.medico
    const mensajeDefault = `Hola ${paciente?.nombre || 'Paciente'}, le recordamos su cita medica el ${cita.fecha} a las ${cita.hora} con el Dr. ${medico?.nombre || 'Medico'}. EzPayConnect`
    const mensaje = mensaje_personalizado || mensajeDefault

    const fechaCita = new Date(`${cita.fecha}T${cita.hora || '00:00:00'}`)
    const fechaEnvio = new Date(fechaCita.getTime() - 24 * 60 * 60 * 1000)

    const { data: recordatorio, error: recordatorioError } = await supabase
      .from('recordatorios_citas')
      .insert({
        cita_id,
        paciente_id: cita.paciente_id,
        tipo_recordatorio,
        estado_envio: 'pendiente',
        fecha_programada: fechaEnvio.toISOString(),
        mensaje
      })
      .select()
      .single()

    if (recordatorioError) throw recordatorioError

    let envioResult = null
    if (tipo_recordatorio === 'whatsapp' && paciente?.telefono) {
      try {
        const notifResponse = await fetch(`${supabaseUrl}/functions/v1/enviar-notificacion`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${supabaseServiceKey}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            tipo: 'whatsapp',
            destinatario: paciente.telefono,
            mensaje: mensaje,
            metadata: { cita_id, recordatorio_id: recordatorio.id }
          })
        })

        if (notifResponse.ok) {
          await supabase
            .from('recordatorios_citas')
            .update({ estado_envio: 'enviado', fecha_envio: new Date().toISOString() })
            .eq('id', recordatorio.id)
          envioResult = 'enviado'
        } else {
          envioResult = 'fallido'
        }
      } catch (e) {
        envioResult = 'fallido'
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          recordatorio_id: recordatorio.id,
          estado: envioResult || 'pendiente',
          fecha_programada: fechaEnvio.toISOString(),
          mensaje,
          paciente: paciente?.nombre,
          telefono: paciente?.telefono
        }
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
