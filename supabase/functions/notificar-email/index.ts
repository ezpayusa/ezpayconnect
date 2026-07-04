// supabase/functions/notificar-email/index.ts
// EMAIL TRANSACCIONAL gateado (calco de enviar-push-notificacion). La llama pg_net desde las RPCs
// DEFINER gateadas notificar_visita_propuesta / notificar_visita_resultado (vía private.email_notificar,
// mig 224) → verify_jwt=false + valida un SECRETO compartido (x-email-secret) server-side.
// Recibe SOLO { visita_id, tipo }. NO acepta a-quién ni qué: re-deriva destinatario + contenido de la
// fila de visitas_agendadas. Cierra el hueco previo (to/subject/html arbitrarios → phishing).

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-email-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

const TIPOS = new Set(['propuesta', 'aprobada', 'rechazada', 'aprobada_clinica', 'cancelada_clinica'])

// --- Plantillas portadas TAL CUAL de src/proveedor/lib/notificaciones.ts (misma interpolación).
//     Única adaptación: VITE_APP_URL (var de build del front) → APP_URL (env de la function). ---
function buildHtmlVisitaPropuesta(props: { medicoNombre: string; visitadorNombre: string; fecha: string; hora: string; tipo: string; notas?: string | null }): string {
  const appUrl = Deno.env.get('APP_URL') || ''
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#1E5C8E;margin-top:0;">Nueva visita propuesta</h2>
      <p><strong>Visitador:</strong> ${props.visitadorNombre}</p>
      <p><strong>Médico:</strong> ${props.medicoNombre}</p>
      <p><strong>Fecha:</strong> ${props.fecha}</p>
      <p><strong>Hora:</strong> ${props.hora}</p>
      <p><strong>Tipo:</strong> ${props.tipo}</p>
      ${props.notas ? `<p><strong>Notas:</strong> ${props.notas}</p>` : ''}
      <div style="margin-top:24px;text-align:center;">
        <a href="${appUrl}/proveedor/visitador/admin-aprobar"
           style="background:#1E5C8E;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;display:inline-block;">
          Revisar visitas
        </a>
      </div>
    </div>
  `
}

function buildHtmlVisitaAprobada(props: { medicoNombre: string; fecha: string; hora: string; comentario?: string | null }): string {
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#16a34a;margin-top:0;">Visita aprobada ✅</h2>
      <p>Tu visita con <strong>${props.medicoNombre}</strong> fue confirmada.</p>
      <p><strong>Fecha:</strong> ${props.fecha}</p>
      <p><strong>Hora:</strong> ${props.hora}</p>
      ${props.comentario ? `<p><strong>Comentario del admin:</strong> ${props.comentario}</p>` : ''}
    </div>
  `
}

function buildHtmlVisitaRechazada(props: { medicoNombre: string; fecha: string; comentario?: string | null }): string {
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#dc2626;margin-top:0;">Visita rechazada ❌</h2>
      <p>Tu visita con <strong>${props.medicoNombre}</strong> no fue aprobada.</p>
      <p><strong>Fecha propuesta:</strong> ${props.fecha}</p>
      ${props.comentario ? `<p><strong>Motivo:</strong> ${props.comentario}</p>` : ''}
    </div>
  `
}

// --- Notificación al lado CLÍNICA/MÉDICO (destinatario del médico visitado). PHI mínimo: sin datos de paciente. ---
function buildHtmlVisitaClinicaAprobada(props: { medicoNombre: string; empresaNom: string; fecha: string; hora: string }): string {
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#16a34a;margin-top:0;">Visita de laboratorio aprobada</h2>
      <p>Se aprobó una visita de <strong>${props.empresaNom}</strong> con <strong>${props.medicoNombre}</strong>.</p>
      <p><strong>Fecha:</strong> ${props.fecha}</p>
      <p><strong>Hora:</strong> ${props.hora}</p>
    </div>
  `
}

function buildHtmlVisitaClinicaCancelada(props: { medicoNombre: string; empresaNom: string; fecha: string; hora: string }): string {
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#dc2626;margin-top:0;">Visita de laboratorio cancelada</h2>
      <p>Se canceló la visita de <strong>${props.empresaNom}</strong> con <strong>${props.medicoNombre}</strong>.</p>
      <p><strong>Fecha:</strong> ${props.fecha}</p>
      <p><strong>Hora:</strong> ${props.hora}</p>
    </div>
  `
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // (1) AUTZ server-to-server: secreto compartido (NO JWT de usuario). Igual que enviar-push-notificacion.
    const secret = Deno.env.get('EMAIL_NOTIF_SECRET')
    if (!secret || req.headers.get('x-email-secret') !== secret) return json({ error: 'No autorizado' }, 401)

    // (2) Entrada: SOLO visita_id + tipo (allowlist dura). Cualquier otro campo del body se ignora.
    let body: any
    try { body = await req.json() } catch { return json({ error: 'Body inválido' }, 400) }
    const visitaId = body?.visita_id
    const tipo: string = body?.tipo
    if (!visitaId || typeof tipo !== 'string' || !TIPOS.has(tipo)) return json({ error: 'visita_id/tipo inválidos' }, 400)

    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } })

    // (3) Re-derivar TODO de la fila (queries separadas, sin embeds, para no depender de relaciones PostgREST).
    const { data: visita } = await supabase
      .from('visitas_agendadas')
      .select('empresa_id, medico_id, cuenta_proveedor_id, fecha_visita, hora_inicio, hora_fin, tipo_visita, notas_empresa, comentario_admin')
      .eq('id', visitaId)
      .maybeSingle()
    if (!visita) return json({ error: 'Visita no encontrada' }, 404)

    const { data: medico } = await supabase.from('perfiles').select('nombre_completo').eq('id', visita.medico_id).maybeSingle()
    const medicoNombre = medico?.nombre_completo || 'Médico'
    const hora = `${visita.hora_inicio} - ${visita.hora_fin}`

    // (3b) NOTIF A CLÍNICA/MÉDICO — fan-out. Destinatarios = fuente ÚNICA public.destinatarios_visita_clinica
    //      (staff secretaria/asistente_medico de la clínica principal, o el médico como fallback). Re-derivado
    //      server-side del visita_id; el caller no aporta destinatarios. Retorna acá (no toca el flujo de abajo).
    if (tipo === 'aprobada_clinica' || tipo === 'cancelada_clinica') {
      const { data: dests } = await supabase.rpc('destinatarios_visita_clinica', { p_visita_id: visitaId })
      const recipients = (dests || []).filter((d: any) => d?.email)
      if (!recipients.length) return json({ success: true, enviados: 0, motivo: 'sin destinatarios con email' })
      const { data: empresa } = await supabase.from('empresas_proveedoras').select('nombre_empresa').eq('id', visita.empresa_id).maybeSingle()
      const empresaNom = empresa?.nombre_empresa || 'un laboratorio'
      const esAprob = tipo === 'aprobada_clinica'
      const subject = `${esAprob ? 'Visita de laboratorio aprobada' : 'Visita de laboratorio cancelada'} - ${medicoNombre}`
      const html = esAprob
        ? buildHtmlVisitaClinicaAprobada({ medicoNombre, empresaNom, fecha: visita.fecha_visita || '', hora })
        : buildHtmlVisitaClinicaCancelada({ medicoNombre, empresaNom, fecha: visita.fecha_visita || '', hora })
      const resendKey = Deno.env.get('RESEND_API_KEY')
      if (!resendKey) return json({ error: 'Servicio de email no configurado' }, 500)
      let enviados = 0, fallidos = 0
      for (const r of recipients) {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ from: 'EzPayConnect <no-reply@ezpayconnect.com>', to: r.email, subject, html }),
        })
        const rdata = await res.json()
        await supabase.from('notificaciones_email').insert({
          destinatario: r.email, asunto: subject, tipo: `visita_${tipo}`,
          estado: res.ok ? 'enviado' : 'fallido', error: res.ok ? null : (rdata?.message || JSON.stringify(rdata)),
          proveedor_id: null, visita_id: visitaId,
        })
        if (res.ok) enviados++; else fallidos++
      }
      console.log(`[notificar-email] ${tipo} | enviados ${enviados} | fallidos ${fallidos}`)
      return json({ success: true, enviados, fallidos })
    }

    // (4) Destinatario + subject + html, mismo mapeo que hacía el front.
    let to: string | null = null
    let subject = ''
    let html = ''

    if (tipo === 'propuesta') {
      const { data: empresa } = await supabase.from('empresas_proveedoras').select('email_contacto').eq('id', visita.empresa_id).maybeSingle()
      const { data: visitador } = await supabase.from('cuentas_proveedor').select('nombre_completo').eq('id', visita.cuenta_proveedor_id).maybeSingle()
      to = empresa?.email_contacto || null
      subject = `Nueva visita propuesta - ${medicoNombre}`
      html = buildHtmlVisitaPropuesta({
        medicoNombre,
        visitadorNombre: visitador?.nombre_completo || 'Visitador',
        fecha: visita.fecha_visita || '',
        hora,
        tipo: visita.tipo_visita || 'presentacion_producto',
        notas: visita.notas_empresa,
      })
    } else {
      const { data: visitador } = await supabase.from('cuentas_proveedor').select('email').eq('id', visita.cuenta_proveedor_id).maybeSingle()
      to = visitador?.email || null
      if (tipo === 'aprobada') {
        subject = `Visita aprobada - ${medicoNombre}`
        html = buildHtmlVisitaAprobada({ medicoNombre, fecha: visita.fecha_visita, hora, comentario: visita.comentario_admin })
      } else {
        subject = `Visita rechazada - ${medicoNombre}`
        html = buildHtmlVisitaRechazada({ medicoNombre, fecha: visita.fecha_visita, comentario: visita.comentario_admin })
      }
    }

    if (!to) return json({ error: 'Sin destinatario derivable' }, 422)

    // (5) Enviar por Resend (RESEND_API_KEY: env de proyecto, sin cambios).
    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    if (!resendApiKey) {
      console.error('[notificar-email] RESEND_API_KEY no configurada')
      return json({ error: 'Servicio de email no configurado' }, 500)
    }
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: 'EzPayConnect <no-reply@ezpayconnect.com>', to, subject, html }),
    })
    const data = await res.json()

    // (6) Log en notificaciones_email (mismo destino que hoy; identidad/visita derivadas, no del body).
    const { error: logError } = await supabase.from('notificaciones_email').insert({
      destinatario: to,
      asunto: subject,
      tipo: `visita_${tipo}`,
      estado: res.ok ? 'enviado' : 'fallido',
      error: res.ok ? null : (data?.message || JSON.stringify(data)),
      proveedor_id: null,
      visita_id: visitaId,
    })
    if (logError) console.error('[notificar-email] Error logueando en BD:', logError)

    if (!res.ok) {
      console.error('[notificar-email] Error Resend:', data)
      return json({ error: 'Error enviando email', details: data }, 500)
    }

    console.log(`[notificar-email] Enviado a ${to} | tipo: visita_${tipo} | id: ${data.id}`)
    return json({ success: true, id: data.id })
  } catch (err: any) {
    console.error('[notificar-email] Error:', err)
    return json({ error: err.message || 'Error interno' }, 500)
  }
})
