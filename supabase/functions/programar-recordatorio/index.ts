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
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const { cita_id, paciente_id, tipo_recordatorio, horas_antes } = await req.json()

    if (!cita_id || !paciente_id) {
      throw new Error('Faltan campos requeridos: cita_id, paciente_id')
    }

    // Obtener datos de la cita SIN join (evita error de foreign key)
    const { data: cita, error: citaError } = await supabase
      .from('citas')
      .select('*')
      .eq('id', cita_id)
      .single()

    if (citaError || !cita) throw new Error('Cita no encontrada')

    // Obtener paciente
    const { data: paciente } = await supabase
      .from('pacientes')
      .select('nombre, telefono')
      .eq('id', cita.paciente_id)
      .single()

    // Obtener médico de AMBAS tablas (medicos primero, perfiles fallback)
    let medico = null
    const { data: medicoNuevo } = await supabase
      .from('medicos')
      .select('nombre_completo')
      .eq('id', cita.medico_id)
      .single()
    
    if (medicoNuevo) {
      medico = { nombre: medicoNuevo.nombre_completo }
    } else {
      const { data: medicoViejo } = await supabase
        .from('perfiles')
        .select('nombre')
        .eq('id', cita.medico_id)
        .single()
      if (medicoViejo) medico = medicoViejo
    }

    // Calcular fecha de envio (24 horas antes por defecto)
    const horas = horas_antes || 24
    const fechaCita = new Date(`${cita.fecha}T${cita.hora_inicio || '00:00:00'}`)
    const fechaEnvio = new Date(fechaCita.getTime() - horas * 60 * 60 * 1000)

    // Crear mensaje
    const mensaje = `Hola ${paciente?.nombre || 'Paciente'}, le recordamos su cita medica el ${cita.fecha} a las ${cita.hora_inicio || 'hora por confirmar'} con el Dr. ${medico?.nombre || 'Medico'}. EzPayConnect`

    // Insertar en recordatorios_programados
    const { data: recordatorio, error: recError } = await supabase
      .from('recordatorios_programados')
      .insert({
        cita_id: String(cita_id),
        paciente_id: String(paciente_id),
        tipo_recordatorio: tipo_recordatorio || 'whatsapp',
        estado: 'pendiente',
        fecha_envio_programada: fechaEnvio.toISOString(),
        mensaje
      })
      .select()
      .single()

    if (recError) throw recError

    // Si es WhatsApp y hay telefono, enviar inmediatamente
    let envioInmediato = null
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
            .from('recordatorios_programados')
            .update({ estado: 'enviado', fecha_envio_real: new Date().toISOString() })
            .eq('id', recordatorio.id)
          envioInmediato = 'enviado'
        }
      } catch (e) {
        envioInmediato = 'pendiente'
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          recordatorio_id: recordatorio.id,
          estado: envioInmediato || 'pendiente',
          fecha_envio_programada: fechaEnvio.toISOString(),
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