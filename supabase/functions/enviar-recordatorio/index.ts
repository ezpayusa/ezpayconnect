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

    // GATE DE OWNERSHIP — auth amplio (médico/paciente/clínica), NO super_admin. Se lee la cita con un
    // cliente ANON + JWT del caller: la RLS por-actor de citas ya resuelve "¿es suya?". Si no devuelve
    // fila (RLS la bloqueó o no existe) → 403. Después se usa el service_role (arriba) para derivar e insertar.
    const supabaseAnonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || ''
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, error: 'Falta Authorization' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      )
    }
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(
        JSON.stringify({ success: false, error: 'JWT inválido' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      )
    }
    const { data: citaOwn } = await userClient.from('citas').select('id').eq('id', cita_id).maybeSingle()
    if (!citaOwn) {
      return new Response(
        JSON.stringify({ success: false, error: 'No autorizado sobre esta cita' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 }
      )
    }

    const { data: cita, error: citaError } = await supabase
      .from('citas')
      // FIX embed roto: medico_id → medicos (FK fk_citas_medico), NO perfiles. pacientes no tiene FK → se busca aparte.
      .select('*, medico:medicos(nombre_completo)')
      .eq('id', cita_id)
      .single()

    if (citaError || !cita) throw new Error('Cita no encontrada')

    const { data: paciente } = await supabase.from('pacientes').select('nombre, telefono, email').eq('id', cita.paciente_id).maybeSingle()
    const medico = cita.medico
    const mensajeDefault = `Hola ${paciente?.nombre || 'Paciente'}, le recordamos su cita medica el ${cita.fecha} a las ${cita.hora_inicio} con el Dr. ${medico?.nombre_completo || 'Medico'}. EzPayConnect`
    const mensaje = mensaje_personalizado || mensajeDefault

    const fechaCita = new Date(`${cita.fecha}T${cita.hora_inicio || '00:00:00'}`)
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
