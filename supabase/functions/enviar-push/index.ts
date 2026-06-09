import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  ApplicationServerKeys,
  generatePushHTTPRequest,
  setWebCrypto,
} from 'npm:webpush-webcrypto'

// Configurar crypto para Deno (webpush-webcrypto necesita esto explícitamente)
setWebCrypto(globalThis.crypto as any)

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
    const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')
    const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY')

    if (!supabaseUrl || !serviceRoleKey) {
      console.error('[enviar-push] SB_URL/SUPABASE_URL o SB_SERVICE_ROLE_KEY/SUPABASE_SERVICE_ROLE_KEY no configuradas')
      return new Response(
        JSON.stringify({ error: 'Configuración incompleta: SB_SERVICE_ROLE_KEY no configurada en secrets de Supabase.' }),
        { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!vapidPrivateKey || !vapidPublicKey) {
      console.warn('[enviar-push] VAPID keys no configuradas. Las notificaciones push estarán deshabilitadas.')
      return new Response(
        JSON.stringify({ 
          success: false, 
          warning: 'VAPID keys no configuradas en secrets. Configura VAPID_PRIVATE_KEY y VAPID_PUBLIC_KEY en el dashboard de Supabase.',
          enviados: 0 
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    let body: any
    try {
      body = await req.json()
    } catch (e) {
      return new Response(
        JSON.stringify({ error: 'Body inválido, se espera JSON' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const {
      usuario_ids,
      titulo,
      mensaje,
      url,
      tag,
    } = body

    if (!usuario_ids || !Array.isArray(usuario_ids) || usuario_ids.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Faltan campos requeridos: usuario_ids (array)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validar UUIDs
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    const idsValidos = usuario_ids.filter((id: string) => uuidRegex.test(id))
    if (idsValidos.length === 0) {
      console.warn('[enviar-push] Ningún usuario_id es UUID válido:', usuario_ids)
      return new Response(
        JSON.stringify({ error: 'Ningún usuario_id es un UUID válido', usuario_ids }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (idsValidos.length < usuario_ids.length) {
      console.warn(`[enviar-push] ${usuario_ids.length - idsValidos.length} IDs filtrados por no ser UUIDs válidos`)
    }

    // Cargar VAPID keys
    let appKeys
    try {
      appKeys = await ApplicationServerKeys.fromJSON({
        publicKey: vapidPublicKey,
        privateKey: vapidPrivateKey,
      })
    } catch (e: any) {
      console.error('[enviar-push] Error cargando VAPID keys:', e)
      return new Response(
        JSON.stringify({ error: 'VAPID keys tienen formato inválido: ' + e.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verificar que la tabla push_subscriptions existe
    const { data: tableCheck, error: tableError } = await supabase
      .from('push_subscriptions')
      .select('id', { count: 'exact', head: true })
      .limit(1)

    if (tableError && tableError.code === '42P01') {
      console.error('[enviar-push] Tabla push_subscriptions no existe')
      return new Response(
        JSON.stringify({ error: 'Tabla push_subscriptions no existe. Aplica la migración 029.' }),
        { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Obtener suscripciones push de los usuarios
    const { data: subscriptions, error: subsError } = await supabase
      .from('push_subscriptions')
      .select('*')
      .in('user_id', idsValidos)

    if (subsError) {
      console.error('[enviar-push] Error DB:', subsError)
      return new Response(
        JSON.stringify({ error: 'Error consultando suscripciones: ' + subsError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!subscriptions || subscriptions.length === 0) {
      console.log('[enviar-push] No hay suscripciones push activas para:', idsValidos)
      return new Response(
        JSON.stringify({ success: true, enviados: 0, mensaje: 'No hay suscripciones push activas para estos usuarios' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`[enviar-push] Enviando a ${subscriptions.length} suscripciones`)

    const payload = JSON.stringify({
      title: titulo || 'EzPayConnect',
      body: mensaje || 'Tienes una nueva notificación',
      url: url || '/paciente/dashboard',
      tag: tag || 'default',
    })

    const resultados = {
      enviados: 0,
      fallidos: 0,
      eliminadas: 0,
    }

    for (const sub of subscriptions) {
      try {
        const { headers, body: pushBody } = await generatePushHTTPRequest({
          applicationServerKeys: appKeys,
          payload,
          target: {
            endpoint: sub.endpoint,
            keys: {
              p256dh: sub.p256dh,
              auth: sub.auth,
            },
          },
          adminContact: 'mailto:no-reply@ezpayconnect.com',
          ttl: 3600,
        })

        const pushRes = await fetch(sub.endpoint, {
          method: 'POST',
          headers,
          body: pushBody,
        })

        if (pushRes.ok) {
          resultados.enviados++
        } else if (pushRes.status === 410 || pushRes.status === 404 || pushRes.status === 401) {
          // Suscripción expirada o inválida: eliminar
          await supabase.from('push_subscriptions').delete().eq('id', sub.id)
          resultados.eliminadas++
        } else {
          const errText = await pushRes.text().catch(() => 'Unknown error')
          console.error(`[enviar-push] Error ${pushRes.status} enviando a ${sub.endpoint}:`, errText)
          resultados.fallidos++
        }
      } catch (pushErr: any) {
        console.error('[enviar-push] Error enviando push:', pushErr)
        resultados.fallidos++
      }
    }

    console.log('[enviar-push] Resultados:', resultados)

    return new Response(
      JSON.stringify({
        success: true,
        resultados,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error: any) {
    console.error('[enviar-push] Error inesperado:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Error interno del servidor' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
