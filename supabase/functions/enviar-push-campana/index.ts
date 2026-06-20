// enviar-push-campana — ÚNICO camino al push PROMOCIONAL (l.7), AMBAS audiencias.
// NO acepta lista de destinatarios (a diferencia de enviar-push transaccional, deuda preexistente).
// Recibe SÓLO { solicitud_id }; exige super_admin (JWT verificado server-side); deriva la audiencia de
// una solicitud APROBADA vía drenar_targets_push (claim ATÓMICO FOR UPDATE SKIP LOCKED + opt-out
// re-evaluado por audiencia). Entrega in-app (notificaciones_pacientes / notificaciones) Y web-push.
// El claim atómico hace que dos invocaciones concurrentes NO entreguen dos veces (l.47). Ignora usuario_ids.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { ApplicationServerKeys, generatePushHTTPRequest, setWebCrypto } from 'npm:webpush-webcrypto'

setWebCrypto(globalThis.crypto as any)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

export interface Deps {
  makeUserClient: (authHeader: string) => { auth: { getUser: () => Promise<{ data: { user: any }, error: any }> } }
  admin: any
  appKeys: any | null   // null = VAPID no configurado (in-app sí, web-push se omite)
}

// Handler puro e inyectable (testeable sin red). El borde de autz vive aquí (l.7).
export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  // (1) AUTZ: super_admin con el JWT del caller (no service_role) — l.10
  const authHeader = req.headers.get('Authorization') || ''
  if (!authHeader) return json({ error: 'Falta Authorization' }, 401)
  const { data: { user }, error: userErr } = await deps.makeUserClient(authHeader).auth.getUser()
  if (userErr || !user) return json({ error: 'JWT inválido' }, 401)
  const { data: perfil } = await deps.admin.from('perfiles').select('rol').eq('id', user.id).maybeSingle()
  if (!perfil || perfil.rol !== 'super_admin') return json({ error: 'No autorizado: sólo super_admin' }, 403)

  // (2) Entrada: SÓLO solicitud_id. body.usuario_ids se IGNORA a propósito (l.7).
  let body: any
  try { body = await req.json() } catch { return json({ error: 'Body inválido' }, 400) }
  const solicitudId: string | undefined = body?.solicitud_id
  if (!solicitudId) return json({ error: 'Falta solicitud_id' }, 400)

  // (3) Solicitud APROBADA + cargar titulo/mensaje/url para in-app
  const { data: sol, error: solErr } = await deps.admin
    .from('solicitudes_push').select('id, estado, titulo, mensaje, url').eq('id', solicitudId).maybeSingle()
  if (solErr) return json({ error: 'Error consultando solicitud' }, 500)
  if (!sol) return json({ error: 'Solicitud no encontrada' }, 404)
  if (sol.estado !== 'aprobada') return json({ error: `Solicitud no aprobada (${sol.estado})` }, 409)

  // (4) Claim ATÓMICO (omitido opt-out + reclama vigentes; anti doble-envío concurrente). Sin lista del caller.
  const { data: claimed, error: drnErr } = await deps.admin.rpc('drenar_targets_push', { p_solicitud_id: solicitudId })
  if (drnErr) return json({ error: 'Error drenando: ' + drnErr.message }, 500)

  const resultados = { inapp: 0, web_enviados: 0, web_fallidos: 0, reclamados: (claimed || []).length, eliminadas: 0 }
  for (const c of claimed || []) {
    // (5a) in-app a la tabla correcta por audiencia
    try {
      if (c.audiencia === 'paciente') {
        await deps.admin.from('notificaciones_pacientes').insert({ paciente_id: c.paciente_id, tipo: 'promocion', titulo: sol.titulo, mensaje: sol.mensaje, accion_url: sol.url, leida: false })
      } else {
        await deps.admin.from('notificaciones').insert({ usuario_id: c.usuario_id, tipo: 'promocion', titulo: sol.titulo, mensaje: sol.mensaje, accion_url: sol.url })
      }
      resultados.inapp++
    } catch (_) { /* in-app best-effort */ }

    // (5b) web-push (si VAPID + push_user_id con suscripciones)
    let web = false, falla = false
    if (deps.appKeys && c.push_user_id) {
      const { data: subs } = await deps.admin.from('push_subscriptions').select('*').eq('user_id', c.push_user_id)
      for (const sub of subs || []) {
        try {
          const payload = JSON.stringify({ title: sol.titulo || 'EzPayConnect', body: sol.mensaje || '', url: sol.url || '/', tag: `promo-${solicitudId}` })
          const { headers, body: pushBody } = await generatePushHTTPRequest({
            applicationServerKeys: deps.appKeys, payload,
            target: { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
            adminContact: 'mailto:no-reply@ezpayconnect.com', ttl: 3600,
          })
          const r = await fetch(sub.endpoint, { method: 'POST', headers, body: pushBody })
          if (r.ok) web = true
          else if ([410, 404, 401].includes(r.status)) { await deps.admin.from('push_subscriptions').delete().eq('id', sub.id); resultados.eliminadas++ }
          else falla = true
        } catch { falla = true }
      }
    }
    if (web) resultados.web_enviados++; else if (falla) resultados.web_fallidos++
    await deps.admin.from('envios_push_cola').update({ estado: falla && !web ? 'fallido' : 'enviado', sent_at: new Date().toISOString() }).eq('id', c.cola_id)
  }
  return json({ success: true, resultados })
}

// Wiring real (producción): construye deps desde el entorno. (No corre bajo `deno test`.)
if (import.meta.main) serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY')!
    if (!supabaseUrl || !serviceRoleKey || !anonKey) return json({ error: 'Configuración incompleta' }, 503)
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')
    const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY')
    let appKeys: any = null
    if (vapidPrivateKey && vapidPublicKey) appKeys = await ApplicationServerKeys.fromJSON({ publicKey: vapidPublicKey, privateKey: vapidPrivateKey })
    const deps: Deps = {
      makeUserClient: (authHeader) => createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } }) as any,
      admin: createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } }),
      appKeys,
    }
    return await handle(req, deps)
  } catch (error: any) {
    return json({ error: error?.message || 'Error interno' }, 500)
  }
})
