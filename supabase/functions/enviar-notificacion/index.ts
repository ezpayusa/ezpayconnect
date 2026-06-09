import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SB_URL") || Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SB_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("[enviar-notificacion] SB_URL/SUPABASE_URL o SB_SERVICE_ROLE_KEY/SUPABASE_SERVICE_ROLE_KEY no configuradas");
      return new Response(
        JSON.stringify({ error: "Configuración incompleta: SB_SERVICE_ROLE_KEY no configurada en secrets de Supabase." }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    let body: any;
    try {
      body = await req.json();
    } catch (e) {
      return new Response(
        JSON.stringify({ error: "Body inválido, se espera JSON" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const {
      usuario_id,
      tipo,
      titulo,
      mensaje,
      accion_url,
      metadata,
      evento_id,
      rol_destinatario,
      nivel_destinatario,
    } = body;

    // Validar campos requeridos
    if (!tipo || !titulo || !mensaje) {
      return new Response(
        JSON.stringify({ error: "Faltan campos requeridos: tipo, titulo, mensaje", recibido: { tipo, titulo, mensaje } }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validar UUID si se proporciona usuario_id
    if (usuario_id && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(usuario_id)) {
      console.warn("[enviar-notificacion] usuario_id no es UUID válido:", usuario_id);
      return new Response(
        JSON.stringify({ error: "usuario_id no es un UUID válido", usuario_id }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Sanitizar metadata
    let safeMetadata = metadata;
    if (metadata !== undefined && metadata !== null && typeof metadata !== 'object') {
      console.warn("[enviar-notificacion] metadata no es objeto, convirtiendo:", metadata);
      safeMetadata = { value: metadata };
    }

    const insertData: any = {
      usuario_id: usuario_id || null,
      tipo,
      titulo,
      mensaje,
      accion_url: accion_url || null,
      metadata: safeMetadata || {},
      evento_id: evento_id || null,
      rol_destinatario: rol_destinatario || null,
      nivel_destinatario: nivel_destinatario || null,
    };

    console.log("[enviar-notificacion] Insertando notificación:", JSON.stringify(insertData));

    const { data, error } = await supabase
      .from("notificaciones")
      .insert(insertData)
      .select()
      .single();

    if (error) {
      console.error("[enviar-notificacion] DB error:", error);
      // Distinguir entre error de configuración (tabla no existe) y error de datos
      const isConfigError = error.code === "42P01" || error.message?.includes("does not exist");
      const status = isConfigError ? 503 : 500;
      const message = isConfigError
        ? "La tabla 'notificaciones' no existe. Verifica que las migraciones estén aplicadas."
        : error.message;
      return new Response(
        JSON.stringify({ error: message, code: error.code, details: error.details }),
        { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log("[enviar-notificacion] Notificación creada:", data?.id);

    return new Response(
      JSON.stringify({ success: true, data }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("[enviar-notificacion] Error inesperado:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Error interno del servidor" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
