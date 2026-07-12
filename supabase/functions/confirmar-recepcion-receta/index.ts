import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Edge PÚBLICA (verify_jwt=false): el paciente confirma la recepción de su receta SIN sesión,
// desde el link del email. Credencial = confirmacion_token (256 bits) en el querystring.
// Caparazón FINO: toda la lógica (resolver token, expiración, derivar país, idempotencia)
// vive en la RPC confirmar_recepcion_receta (SECURITY DEFINER). No devuelve PHI: solo { estado }.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // 1. Token del querystring. Falta/vacío => mismo estado que token malo (no dar pistas).
    const token = new URL(req.url).searchParams.get('token')?.trim()
    if (!token) return json({ estado: 'token_invalido' }, 400)

    // 2. ip + user_agent para estadística (no son credenciales; la credencial es el token).
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? null
    const ua = req.headers.get('user-agent') ?? null

    // 3. Cliente con service_role (molde de las edges del repo: SB_* con fallback SUPABASE_*).
    const supabase = createClient(
      (Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')) ?? '',
      (Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // 4. Toda la inteligencia está en la RPC. Estado = confirmada|ya_confirmada|token_invalido|sin_pais.
    const { data, error } = await supabase.rpc('confirmar_recepcion_receta', {
      p_token: token, p_ip: ip, p_user_agent: ua,
    })
    if (error) {
      // Fail-safe: no exponer el mensaje crudo al cliente; el error real queda en los logs.
      console.error('[confirmar-recepcion-receta] error RPC:', error)
      return json({ estado: 'error' }, 500)
    }

    return json({ estado: data }, 200)
  } catch (e) {
    console.error('[confirmar-recepcion-receta] error no controlado:', e)
    return json({ estado: 'error' }, 500)
  }
})
