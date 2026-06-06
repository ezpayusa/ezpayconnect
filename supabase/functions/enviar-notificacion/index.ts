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
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const body = await req.json();
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

    if (!tipo || !titulo || !mensaje) {
      return new Response(
        JSON.stringify({ error: "Faltan campos requeridos: tipo, titulo, mensaje" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data, error } = await supabase
      .from("notificaciones")
      .insert({
        usuario_id: usuario_id || null,
        tipo,
        titulo,
        mensaje,
        accion_url: accion_url || null,
        metadata: metadata || {},
        evento_id: evento_id || null,
        rol_destinatario: rol_destinatario || null,
        nivel_destinatario: nivel_destinatario || null,
      })
      .select()
      .single();

    if (error) throw error;

    return new Response(
      JSON.stringify({ success: true, data }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("[enviar-notificacion] Error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
