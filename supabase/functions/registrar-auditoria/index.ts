import { createClient } from "supabase";

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
    const anonKey = Deno.env.get("SB_ANON_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const body = await req.json();
    // usuario_id/usuario_email/usuario_nombre del body se IGNORAN: la identidad SIEMPRE se deriva del
    // JWT del caller (abajo), nunca del body. Cierra la forja de logs atribuidos a otra persona.
    const {
      accion,
      entidad,
      entidad_id,
      detalle,
      ip_address,
      user_agent,
    } = body;

    if (!accion || !entidad) {
      return new Response(
        JSON.stringify({ error: "Faltan campos requeridos: accion, entidad" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // GATE — authenticated (cualquier rol) con identidad derivada del JWT, NO super_admin-exclusivo.
    // Se valida el JWT con un cliente anon (getUser) y se deriva usuario_email/nombre de perfiles.
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Falta Authorization" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return new Response(
        JSON.stringify({ error: "JWT inválido" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    // Identidad server-side desde perfiles (admin client, bypass RLS).
    const { data: perfilCaller } = await supabase
      .from("perfiles")
      .select("email, nombre_completo")
      .eq("id", user.id)
      .maybeSingle();

    const { data, error } = await supabase
      .from("auditoria_logs")
      .insert({
        usuario_id: user.id,
        usuario_email: perfilCaller?.email ?? user.email ?? null,
        usuario_nombre: perfilCaller?.nombre_completo ?? user.email ?? null,
        accion,
        entidad,
        entidad_id,
        detalle: detalle || {},
        ip_address,
        user_agent,
      })
      .select()
      .single();

    if (error) throw error;

    return new Response(
      JSON.stringify({ success: true, data }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});