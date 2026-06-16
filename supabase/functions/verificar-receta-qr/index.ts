// supabase/functions/verificar-receta-qr/index.ts
// RETIRADO (Inc.4 saneo QR). El despacho ahora va por el RPC SECURITY DEFINER
// verificar_receta_despacho (token fuerte + permiso recetas_dispensar + aislamiento
// por farmacia). Este stub 410 cierra el path inseguro EZP-: NO usa service_role,
// NO consulta la BD, NO devuelve PHI. Source original recuperable en commit 968fb02.

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
