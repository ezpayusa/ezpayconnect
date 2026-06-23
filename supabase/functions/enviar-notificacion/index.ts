// supabase/functions/enviar-notificacion/index.ts
// RETIRADO (CIERRE FINAL push transaccional, bloque 2). Era un confused-deputy: aceptaba
// { usuario_id, tipo, titulo, mensaje, accion_url } con service_role e insertaba notificaciones
// para CUALQUIER usuario sin verificar quién llamaba ni si tenía relación con el destinatario.
// Las notificaciones in-app ahora se crean SOLO por RPCs SECURITY DEFINER gateados (notificar_*),
// que validan emisor↔destinatario y derivan el contenido de la fila ya creada. Este stub 410 cierra
// el path inseguro: NO usa service_role, NO consulta/escribe la BD, NO toca PHI. (Bloque 3 ya borró
// los 2 helpers de frontend que la invocaban; 0 callers vivos.)

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
        JSON.stringify({ success: false, error: 'Endpoint retirado. Las notificaciones se crean server-side por RPCs gateados.' }),
        { status: 410, headers: { ...cors, 'Content-Type': 'application/json' } }
      )
)
