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
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const { data: pendientes, error: queryError } = await supabase
      .from('recordatorios')
      .select('*')
      .eq('estado', 'pendiente')
      .lte('fecha_envio_programada', new Date().toISOString())
      .limit(100)

    if (queryError) throw queryError

    const resultados = {
      procesados: 0,
      enviados: 0,
      fallidos: 0,
      detalles: [] as any[],
    }

    for (const rec of pendientes || []) {
      resultados.procesados++
      let emailEnviado = false
      let notifCreada = false
      let errorMsg: string | null = null

      try {
        if (rec.tipo === 'cita' && rec.cita_id) {
          // Obtener cita SIN joins (evita error de relación en schema cache)
          const { data: cita } = await supabase
            .from('citas')
            .select('*')
            .eq('id', rec.cita_id)
            .single()

          if (cita) {
            // Obtener paciente por separado
            const { data: paciente } = await supabase
              .from('pacientes')
              .select('nombre, email')
              .eq('id', cita.paciente_id)
              .single()

            // Obtener médico por separado
            const { data: medico } = await supabase
              .from('medicos')
              .select('nombre_completo, email, id')
              .eq('id', cita.medico_id)
              .single()

            const pacienteEmail = paciente?.email
            const medicoId = medico?.id
            const destinatario = rec.destinatario_email || pacienteEmail

            if (destinatario && resendApiKey) {
              const emailResult = await sendEmailDirect({
                resendApiKey,
                to: destinatario,
                subject: 'Recordatorio de cita médica — EzPayConnect',
                html: `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
                  <h2 style="color:#1E5C8E;margin-top:0;">Recordatorio de cita</h2>
                  <p>${rec.mensaje}</p>
                  <p style="color:#6b7280;font-size:12px;">EzPayConnect</p>
                </div>`,
                tipo: 'recordatorio_cita',
                supabase,
                metadata: { cita_id: rec.cita_id },
              })
              emailEnviado = emailResult.success
              if (!emailResult.success) errorMsg = emailResult.error
            }

            if (medicoId) {
              const { error: notifError } = await supabase.from('notificaciones').insert({
                usuario_id: medicoId,
                tipo: 'recordatorio_cita',
                titulo: 'Recordatorio de cita médica',
                mensaje: rec.mensaje,
                metadata: { cita_id: rec.cita_id },
              })
              notifCreada = !notifError
              if (notifError && !errorMsg) errorMsg = notifError.message
            }
          }
        } else if (rec.tipo === 'visita' && rec.visita_id) {
          // Obtener visita SIN joins
          const { data: visita } = await supabase
            .from('visitas_agendadas')
            .select('*')
            .eq('id', rec.visita_id)
            .single()

          if (visita) {
            // Obtener visitador por separado
            const { data: visitador } = await supabase
              .from('cuentas_proveedor')
              .select('nombre_completo, email, id')
              .eq('id', visita.cuenta_proveedor_id)
              .single()

            const visitadorEmail = visitador?.email
            const visitadorId = visitador?.id
            const destinatario = rec.destinatario_email || visitadorEmail

            if (destinatario && resendApiKey) {
              const emailResult = await sendEmailDirect({
                resendApiKey,
                to: destinatario,
                subject: 'Recordatorio de visita programada — EzPayConnect',
                html: `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
                  <h2 style="color:#1E5C8E;margin-top:0;">Recordatorio de visita</h2>
                  <p>${rec.mensaje}</p>
                  <p style="color:#6b7280;font-size:12px;">EzPayConnect</p>
                </div>`,
                tipo: 'recordatorio_visita',
                supabase,
                metadata: { visita_id: rec.visita_id },
              })
              emailEnviado = emailResult.success
              if (!emailResult.success) errorMsg = emailResult.error
            }

            if (visitadorId) {
              const { error: notifError } = await supabase.from('notificaciones').insert({
                usuario_id: visitadorId,
                tipo: 'recordatorio_visita',
                titulo: 'Recordatorio de visita programada',
                mensaje: rec.mensaje,
                metadata: { visita_id: rec.visita_id },
              })
              notifCreada = !notifError
              if (notifError && !errorMsg) errorMsg = notifError.message
            }
          }
        }

        const nuevoEstado = emailEnviado || notifCreada ? 'enviado' : 'fallido'
        await supabase
          .from('recordatorios')
          .update({
            estado: nuevoEstado,
            fecha_envio_real: new Date().toISOString(),
            error: errorMsg,
          })
          .eq('id', rec.id)

        if (nuevoEstado === 'enviado') resultados.enviados++
        else resultados.fallidos++
      } catch (procErr: any) {
        resultados.fallidos++
        await supabase
          .from('recordatorios')
          .update({ estado: 'fallido', fecha_envio_real: new Date().toISOString(), error: procErr.message })
          .eq('id', rec.id)
      }
    }

    return new Response(
      JSON.stringify({ success: true, resultados }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error: any) {
    console.error('[procesar-recordatorios] Error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function sendEmailDirect(params: {
  resendApiKey: string
  to: string
  subject: string
  html: string
  tipo: string
  supabase: any
  metadata?: any
}): Promise<{ success: boolean; error?: string }> {
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${params.resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'EzPayConnect <no-reply@ezpayconnect.com>',
        to: params.to,
        subject: params.subject,
        html: params.html,
      }),
    })

    const data = await res.json()

    await params.supabase.from('notificaciones_email').insert({
      destinatario: params.to,
      asunto: params.subject,
      tipo: params.tipo || 'general',
      estado: res.ok ? 'enviado' : 'fallido',
      error: res.ok ? null : (data?.message || JSON.stringify(data)),
      proveedor_id: params.metadata?.proveedor_id || null,
      visita_id: params.metadata?.visita_id || null,
    })

    if (!res.ok) {
      return { success: false, error: data?.message || JSON.stringify(data) }
    }

    return { success: true }
  } catch (err: any) {
    await params.supabase.from('notificaciones_email').insert({
      destinatario: params.to,
      asunto: params.subject,
      tipo: params.tipo || 'general',
      estado: 'fallido',
      error: err.message,
    })
    return { success: false, error: err.message }
  }
}
