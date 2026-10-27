// registrar-clinica-invitacion v19 (mig 385).
// Pre-gate de solo lectura ANTES de crear el usuario de auth; la RPC registrar_clinica_desde_invitacion crea perfil,
// medicos, clínica y membresía en una transacción; si la RPC falla, se borra el usuario recién creado.
// Respuestas: { ok: true, clinica_id } o { error: 'RC00x' | 'ERROR_INTERNO' }. Nunca se devuelven errores crudos.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const LOG = '[registrar-clinica-invitacion]'
const ERROR_INTERNO = 'ERROR_INTERNO'
// RC001 invitación inexistente/vencida/usada; RC002 correo distinto; RC003 cuenta ya existente; RC004 datos inválidos
const ESTADO_RC: Record<string, number> = { RC001: 404, RC002: 400, RC003: 409, RC004: 400 }
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PASSWORD_MIN = 6

function responder(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function errorRC(code: string): Response {
  return responder(ESTADO_RC[code] ?? 500, { error: code in ESTADO_RC ? code : ERROR_INTERNO })
}

function interno(): Response {
  return responder(500, { error: ERROR_INTERNO })
}

function texto(v: unknown): string {
  return typeof v === 'string' ? v.trim() : ''
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SB_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    console.error(`${LOG} configuracion incompleta`)
    return interno()
  }

  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return errorRC('RC004')
    }
    if (!body || typeof body !== 'object') return errorRC('RC004')

    const token = texto(body.token)
    const password = typeof body.password === 'string' ? body.password : ''
    const email = texto(body.email).toLowerCase()
    const nombreContacto = texto(body.nombre_contacto)
    const telefono = texto(body.telefono)

    // ---------------- PRE-GATE (solo lectura: ninguna rama crea nada) ----------------
    // 1) invitación existente, pendiente y vigente → si no, RC001
    if (!UUID_RE.test(token)) return errorRC('RC001')
    const { data: invitacion, error: invError } = await supabase
      .from('invitaciones_clinica')
      .select('email, nombre_contacto, estado, expires_at')
      .eq('token', token)
      .maybeSingle()
    if (invError) {
      console.error(`${LOG} lectura de invitacion fallida`, invError.code ?? '-')
      return interno()
    }
    if (
      !invitacion ||
      invitacion.estado !== 'pendiente' ||
      !invitacion.expires_at ||
      new Date(invitacion.expires_at).getTime() <= Date.now()
    ) {
      return errorRC('RC001')
    }
    const emailInvitacion = texto(invitacion.email).toLowerCase()

    // 2) correo del body = correo de la invitación → si no, RC002 (faltante = dato inválido, RC004)
    if (!email) return errorRC('RC004')
    if (!emailInvitacion || email !== emailInvitacion) return errorRC('RC002')

    // 3) nombre de contacto (el del body o, si viene vacío, el de la invitación) → si no, RC004
    if (!nombreContacto && !texto(invitacion.nombre_contacto)) return errorRC('RC004')

    // 4) contraseña presente y con al menos PASSWORD_MIN caracteres → si no, RC004
    if (password.length < PASSWORD_MIN) return errorRC('RC004')

    // ---------------- ALTA ----------------
    // La cuenta existente se detecta acá (no hay pre-chequeo): createUser falla sin crear nada.
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email: emailInvitacion,
      password,
      email_confirm: true,
    })
    if (authError || !authData?.user?.id) {
      // códigos de ErrorCode de @supabase/auth-js (lib/error-codes.d.ts); en los dos no se creó nada
      if (authError?.code === 'email_exists') return errorRC('RC003')
      if (authError?.code === 'weak_password') return errorRC('RC004')
      console.error(`${LOG} createUser fallido`, authError?.code ?? authError?.status ?? '-')
      return interno()
    }
    const userId = authData.user.id

    const { data: clinicaId, error: rpcError } = await supabase.rpc('registrar_clinica_desde_invitacion', {
      p_token: token,
      p_user_id: userId,
      p_email: email,
      p_nombre_contacto: nombreContacto || null,
      p_telefono: telefono || null,
    })

    if (rpcError) {
      // compensación: la RPC revirtió su transacción; se borra el usuario de auth recién creado
      const { error: delError } = await supabase.auth.admin.deleteUser(userId)
      if (delError) {
        console.error(`${LOG} compensacion fallida: usuario de auth sin borrar`, userId, delError.code ?? delError.status ?? '-')
        return interno()
      }
      const code = typeof rpcError.code === 'string' && /^RC00[1-4]$/.test(rpcError.code) ? rpcError.code : ''
      if (!code) console.error(`${LOG} rpc fallida`, rpcError.code ?? '-')
      return code ? errorRC(code) : interno()
    }

    if (typeof clinicaId !== 'string' || !UUID_RE.test(clinicaId)) {
      // la RPC terminó sin error pero sin uuid: no se compensa (su transacción pudo haber confirmado)
      console.error(`${LOG} rpc sin clinica_id`, userId)
      return interno()
    }

    return responder(200, { ok: true, clinica_id: clinicaId })
  } catch (_e) {
    console.error(`${LOG} error no controlado`)
    return interno()
  }
})
