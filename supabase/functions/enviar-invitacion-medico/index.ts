// supabase/functions/enviar-invitacion-medico/index.ts
// CORREO DE INVITACION DE MEDICO, server-to-server (mig 378). La llama pg_net desde private.invitacion_email_notificar,
// que disparan las RPCs aprobar_solicitud_alta / reenviar_solicitud_alta despues del COMMIT. verify_jwt=false y valida
// un SECRETO compartido (x-email-secret, el mismo de notificar-email).
// Recibe SOLO { invitacion_id }. Destinatario, nombre y token se re-derivan de la fila de invitaciones_medico.
// Idempotente: reclama la fila con email_enviado_at (UPDATE ... WHERE email_enviado_at IS NULL); si Resend falla,
// libera el claim para que un reintento pueda enviar.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// URL canonica de la app en produccion (constante, NO env var: evita links rotos en silencio), igual que
// crear-invitacion-medico.
const APP_URL = 'https://med.ezpayconnect.com'
const FROM = 'EzPayConnect <no-reply@ezpayconnect.com>'
const ASUNTO = 'Has sido invitado a unirte a EzPayConnect como Médico'
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } })

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')

// Comparacion en tiempo constante: se comparan los SHA-256 (siempre 32 bytes), asi la longitud del secreto
// recibido no cambia el tiempo de la comparacion.
async function secretoValido(recibido: string | null, esperado: string): Promise<boolean> {
  const enc = new TextEncoder()
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(recibido ?? '')),
    crypto.subtle.digest('SHA-256', enc.encode(esperado)),
  ])
  const x = new Uint8Array(a), y = new Uint8Array(b)
  let diff = recibido === null ? 1 : 0
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i]
  return diff === 0
}

// Misma plantilla que crear-invitacion-medico; el nombre va escapado.
function buildHtmlInvitacion(nombre: string, registroUrl: string): string {
  return `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
            <h2 style="color:#1E5C8E;margin-top:0;">¡Bienvenido a EzPayConnect!</h2>
            <p>Hola <strong>${esc(nombre)}</strong>,</p>
            <p>Has sido invitado a registrarte como médico en EzPayConnect.</p>
            <p>Haz clic en el siguiente enlace para completar tu registro:</p>
            <a href="${registroUrl}" style="display:inline-block;padding:12px 24px;background:#1E5C8E;color:white;text-decoration:none;border-radius:6px;margin:16px 0;">Completar Registro</a>
            <p style="color:#6b7280;font-size:12px;">Este enlace expira en 7 días.</p>
            <p style="color:#6b7280;font-size:12px;">EzPayConnect</p>
          </div>`
}

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    // (1) AUTZ server-to-server: secreto compartido (NO JWT de usuario), mismo que notificar-email.
    const secret = Deno.env.get('EMAIL_NOTIF_SECRET')
    if (!secret || !(await secretoValido(req.headers.get('x-email-secret'), secret))) return json({ error: 'No autorizado' }, 401)

    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    if (!resendApiKey) {
      console.error('[enviar-invitacion-medico] RESEND_API_KEY no configurada')
      return json({ error: 'Servicio de email no configurado' }, 500)
    }

    // (2) Entrada: SOLO invitacion_id. Cualquier otro campo del body se ignora.
    let body: any
    try { body = await req.json() } catch { return json({ error: 'Body inválido' }, 400) }
    const invitacionId = body?.invitacion_id
    if (typeof invitacionId !== 'string' || !UUID_RE.test(invitacionId)) return json({ error: 'invitacion_id inválido' }, 400)

    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } })

    // (3) Re-derivar de la fila.
    const { data: inv, error: invError } = await supabase
      .from('invitaciones_medico')
      .select('id, estado, expires_at, email_enviado_at')
      .eq('id', invitacionId)
      .maybeSingle()
    if (invError) {
      console.error('[enviar-invitacion-medico] Error leyendo la invitación:', invError.code)
      return json({ error: 'Error interno' }, 500)
    }
    if (!inv) return json({ enviado: false, motivo: 'no_existe' })
    if (inv.estado !== 'pendiente') return json({ enviado: false, motivo: 'no_pendiente' })
    if (new Date(inv.expires_at).getTime() <= Date.now()) return json({ enviado: false, motivo: 'vencida' })

    // (4) Claim: solo una llamada envia el correo de esta invitacion.
    const claimAt = new Date().toISOString()
    const { data: claim, error: claimError } = await supabase
      .from('invitaciones_medico')
      .update({ email_enviado_at: claimAt })
      .eq('id', invitacionId)
      .eq('estado', 'pendiente')
      .is('email_enviado_at', null)
      .select('id, email, nombre_completo, token')
    if (claimError) {
      console.error('[enviar-invitacion-medico] Error en el claim:', claimError.code)
      return json({ error: 'Error interno' }, 500)
    }
    if (!claim || claim.length === 0) return json({ enviado: false, motivo: 'ya_enviado' })
    const fila = claim[0]

    // (5) Enviar por Resend.
    const registroUrl = `${APP_URL}/registro-medico?token=${fila.token}`
    let ok = false
    let status = 0
    let errorEnvio: string | null = null
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: FROM, to: fila.email, subject: ASUNTO, html: buildHtmlInvitacion(fila.nombre_completo, registroUrl) }),
      })
      status = res.status
      ok = res.ok
      if (!ok) {
        const data = await res.json().catch(() => null)
        errorEnvio = data?.message || data?.name || `HTTP ${status}`
      }
    } catch (_e) {
      errorEnvio = 'Error de red con el proveedor de email'
    }

    // (6) Si fallo, liberar el claim (solo si sigue siendo el nuestro) para que un reintento pueda enviar.
    if (!ok) {
      const { error: liberarError } = await supabase
        .from('invitaciones_medico')
        .update({ email_enviado_at: null })
        .eq('id', invitacionId)
        .eq('email_enviado_at', claimAt)
      if (liberarError) console.error('[enviar-invitacion-medico] Error liberando el claim:', liberarError.code)
    }

    // (7) Log en notificaciones_email.
    const { error: logError } = await supabase.from('notificaciones_email').insert({
      destinatario: fila.email,
      asunto: ASUNTO,
      tipo: 'invitacion_medico',
      estado: ok ? 'enviado' : 'fallido',
      error: ok ? null : errorEnvio,
      proveedor_id: null,
      visita_id: null,
    })
    if (logError) console.error('[enviar-invitacion-medico] Error logueando en BD:', logError.code)

    if (!ok) {
      console.error('[enviar-invitacion-medico] Error de Resend, status:', status)
      return json({ enviado: false, motivo: 'error_envio' }, 502)
    }
    return json({ enviado: true })
  } catch (_err) {
    console.error('[enviar-invitacion-medico] Error interno')
    return json({ error: 'Error interno' }, 500)
  }
})
