// enviar-push-notificacion — push TRANSACCIONAL gateado (l.7). La llama pg_net desde una RPC DEFINER
// gateada (no un usuario) → verify_jwt=false + valida un SECRETO compartido (x-push-secret) server-side.
// Recibe SOLO { notification_id, tabla }. NO acepta a-quién ni qué: re-deriva el target y el contenido
// de la fila ya creada por la RPC gateada. Idempotente (push_enviado). Segura por construcción.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { ApplicationServerKeys, generatePushHTTPRequest, setWebCrypto } from 'npm:webpush-webcrypto'

setWebCrypto(globalThis.crypto as any)
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, x-push-secret', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

export interface Deps { admin: any; appKeys: any | null; secret: string | undefined }

const TABLAS = new Set(['notificaciones', 'notificaciones_pacientes'])

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  // (1) AUTZ server-to-server: secreto compartido (NO JWT de usuario)
  if (!deps.secret || req.headers.get('x-push-secret') !== deps.secret) return json({ error: 'No autorizado' }, 401)

  // (2) Entrada: SOLO notification_id + tabla. tabla = allowlist DURA antes de cualquier acceso (2 valores).
  let body: any
  try { body = await req.json() } catch { return json({ error: 'Body inválido' }, 400) }
  const id = body?.notification_id
  const tabla: string = body?.tabla
  if (!id || typeof tabla !== 'string' || !TABLAS.has(tabla)) return json({ error: 'notification_id/tabla inválidos' }, 400)

  // (3) CLAIM ATÓMICO (anti doble-envío, l.47): solo quien pasa push_enviado NULL→now() reclama y envía.
  //     Dos invocaciones concurrentes/retries: solo una matchea, la otra recibe 0 filas → idempotente.
  //     (Trade-off: marca antes de enviar → si el envío falla, no reintenta. Deuda reliability documentada.)
  const cols = 'id, titulo, mensaje, accion_url, ' + (tabla === 'notificaciones' ? 'usuario_id' : 'paciente_id')
  const { data: row, error } = await deps.admin.from(tabla)
    .update({ push_enviado: new Date().toISOString() })
    .eq('id', id).is('push_enviado', null)
    .select(cols).maybeSingle()
  if (error) return json({ error: 'Error reclamando notificación' }, 500)
  if (!row) {
    // no reclamada: o ya enviada (idempotente) o inexistente (404)
    const { data: existe } = await deps.admin.from(tabla).select('id').eq('id', id).maybeSingle()
    return existe ? json({ success: true, idempotente: true, enviados: 0 }) : json({ error: 'Notificación no encontrada' }, 404)
  }

  // (4) Re-derivar el target uuid (push_subscriptions.user_id) de la fila reclamada
  let pushUserId: string | null = null
  if (tabla === 'notificaciones') {
    pushUserId = row.usuario_id
  } else {
    const { data: pac } = await deps.admin.from('pacientes').select('auth_user_id').eq('id', row.paciente_id).maybeSingle()
    pushUserId = pac?.auth_user_id ?? null
  }

  let enviados = 0, fallidos = 0, eliminadas = 0
  if (deps.appKeys && pushUserId) {
    const { data: subs } = await deps.admin.from('push_subscriptions').select('*').eq('user_id', pushUserId)
    for (const sub of subs || []) {
      try {
        const payload = JSON.stringify({ title: row.titulo || 'EzPayConnect', body: row.mensaje || '', url: row.accion_url || '/', tag: `${tabla}-${id}` })
        const { headers, body: pushBody } = await generatePushHTTPRequest({
          applicationServerKeys: deps.appKeys, payload,
          target: { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          adminContact: 'mailto:no-reply@ezpayconnect.com', ttl: 3600,
        })
        const r = await fetch(sub.endpoint, { method: 'POST', headers, body: pushBody })
        if (r.ok) enviados++
        else if ([410, 404, 401].includes(r.status)) { await deps.admin.from('push_subscriptions').delete().eq('id', sub.id); eliminadas++ }
        else fallidos++
      } catch { fallidos++ }
    }
  }
  // idempotencia ya garantizada por el CLAIM atómico del paso (3)
  return json({ success: true, enviados, fallidos, eliminadas })
}

if (import.meta.main) serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Configuración incompleta' }, 503)
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY'); const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY')
    let appKeys: any = null
    if (vapidPrivateKey && vapidPublicKey) appKeys = await ApplicationServerKeys.fromJSON({ publicKey: vapidPublicKey, privateKey: vapidPrivateKey })
    const deps: Deps = {
      admin: createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } }),
      appKeys, secret: Deno.env.get('PUSH_NOTIF_SECRET'),
    }
    return await handle(req, deps)
  } catch (e: any) { return json({ error: e?.message || 'Error interno' }, 500) }
})
