// Edge Function: listar-empleados
// Lista todos los empleados ignorando RLS (usa Service Role Key)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Crear cliente Supabase con Service Role Key
    const supabaseUrl = (Deno.env.get("SB_URL") || Deno.env.get("SUPABASE_URL")) ?? "";
    const supabaseServiceKey = (Deno.env.get("SB_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) ?? "";
    const supabaseAnonKey = (Deno.env.get("SB_ANON_KEY") || Deno.env.get("SUPABASE_ANON_KEY")) ?? "";
    const supabaseAdmin = createClient(
      supabaseUrl,
      supabaseServiceKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    );

    // GATE DE AUTORIZACIÓN — esta función usa service_role (bypass RLS) y exponía TODOS los perfiles de
    // TODOS los países sin validar al caller. Ahora se exige super_admin verificado server-side con el
    // JWT del caller (mismo patrón que reportes-ezpay): se valida el JWT con un cliente anon (NO
    // service_role) y recién ahí se lee perfiles.rol. (El filtro por país es diseño futuro, no esta pieza.)
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Falta Authorization" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: "JWT inválido" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const { data: perfilCaller } = await supabaseAdmin.from("perfiles").select("rol").eq("id", user.id).maybeSingle();
    if (!perfilCaller || perfilCaller.rol !== "super_admin") {
      return new Response(JSON.stringify({ error: "No autorizado: sólo super_admin" }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Obtener todos los perfiles (ignora RLS)
    const { data: perfiles, error: perfilesError } = await supabaseAdmin
      .from("perfiles")
      .select("*")
      .order("created_at", { ascending: false });

    if (perfilesError) {
      console.error("Error obteniendo perfiles:", perfilesError);
      return new Response(
        JSON.stringify({ error: perfilesError.message }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: perfiles || [],
        count: perfiles?.length || 0,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error inesperado:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Error interno del servidor" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
