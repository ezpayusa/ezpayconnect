// supabase/functions/registrar-dispensacion/index.ts
// RETIRADO (Inc.4 saneo QR). El registro de despacho ahora va por el RPC SECURITY
// DEFINER registrar_dispensacion (token fuerte + permiso recetas_dispensar +
// aislamiento por farmacia, POR ÍTEM). Este stub 410 cierra el path inseguro: NO usa
// service_role, NO consulta/escribe la BD, NO toca PHI. Source original en commit 968fb02.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve((req) =>
  req.method === 'OPTIONS'
    ? new Response('ok', { headers: cors })
    : new Response(
        JSON.stringify({ success: false, error: 'Endpoint retirado. Actualiza la página (Ctrl+F5) para usar el nuevo despacho.' }),
        { status: 410, headers: { ...cors, 'Content-Type': 'application/json' } }
      )
)
