// supabase/functions/enviar-push/index.ts
// RETIRADO (CIERRE FINAL push transaccional, bloque 2). Era un confused-deputy: aceptaba targets y
// contenido del caller con service_role + claves VAPID y mandaba web-push a CUALQUIER destinatario sin
// verificar quién llamaba. El push transaccional ahora va SOLO por enviar-push-notificacion (gateada:
// x-push-secret server-to-server, recibe { notification_id, tabla } y re-deriva target+contenido de la
// fila ya creada por la RPC DEFINER gateada). El promocional va por enviar-push-campana (super_admin).
// Este stub 410 cierra el path inseguro: NO usa service_role, NO claves VAPID, NO consulta/escribe la BD,
// NO toca PHI. (0 callers vivos: el frontend ya no lo invoca; el push lo dispara push_notificar→edge gateada.)

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
        JSON.stringify({ success: false, error: 'Endpoint retirado. El push transaccional va por enviar-push-notificacion (gateada).' }),
        { status: 410, headers: { ...cors, 'Content-Type': 'application/json' } }
      )
)
