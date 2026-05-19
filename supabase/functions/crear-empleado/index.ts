// Edge Function: crear-empleado
// Soluciona el error foreign key perfiles_id_fkey
// Crea usuario en auth.users, perfil en perfiles, y asigna rol en usuario_roles

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
    const { email, password, nombre_completo, nombre, rol_id, asignado_por } = await req.json();

    // Validar campos requeridos
    if (!email || !password || !rol_id) {
      return new Response(
        JSON.stringify({ error: "Faltan campos requeridos: email, password, rol_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Crear cliente Supabase con Service Role Key
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    );

    // 1. Crear usuario en auth.users
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // Confirmar email automáticamente
      user_metadata: {
        nombre_completo: nombre_completo || nombre || email,
      },
    });

    if (authError) {
      console.error("Error creando usuario en auth:", authError);
      return new Response(
        JSON.stringify({ error: authError.message }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = authData.user.id;
    console.log("✅ Usuario creado en auth.users:", userId);

    // 2. Obtener información del rol
    const { data: rolData, error: rolError } = await supabaseAdmin
      .from("roles")
      .select("nombre")
      .eq("id", rol_id)
      .single();

    if (rolError) {
      console.error("Error obteniendo rol:", rolError);
      // No fallamos aquí, continuamos sin el nombre del rol
    }

    const nombreRol = rolData?.nombre || "empleado";

    // 3. Insertar perfil en public.perfiles
    const { data: perfilData, error: perfilError } = await supabaseAdmin
      .from("perfiles")
      .insert({
        id: userId,
        email: email,
        nombre_completo: nombre_completo || nombre || email.split("@")[0],
        nombre: nombre || nombre_completo || email.split("@")[0],
        rol: nombreRol,
        rol_id: rol_id,
        activo: true,
      })
      .select()
      .single();

    if (perfilError) {
      console.error("Error creando perfil:", perfilError);
      // Si falla el perfil, intentamos eliminar el usuario de auth para mantener consistencia
      await supabaseAdmin.auth.admin.deleteUser(userId);
      return new Response(
        JSON.stringify({ error: `Error creando perfil: ${perfilError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log("✅ Perfil creado en public.perfiles");

    // 4. Asignar rol en public.usuario_roles
    const { data: usuarioRolData, error: usuarioRolError } = await supabaseAdmin
      .from("usuario_roles")
      .insert({
        usuario_id: userId,
        rol_id: rol_id,
        asignado_por: asignado_por || null,
        activo: true,
      })
      .select()
      .single();

    if (usuarioRolError) {
      console.error("Error asignando rol:", usuarioRolError);
      // No eliminamos el usuario aquí, el perfil ya existe. El admin puede reasignar manualmente.
      return new Response(
        JSON.stringify({ 
          error: `Usuario y perfil creados, pero error asignando rol: ${usuarioRolError.message}`,
          userId,
          perfilId: perfilData.id 
        }),
        { status: 207, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log("✅ Rol asignado en usuario_roles");

    return new Response(
      JSON.stringify({
        success: true,
        message: "Empleado creado exitosamente",
        data: {
          userId,
          email,
          nombre_completo: perfilData.nombre_completo,
          rol: nombreRol,
          rol_id: rol_id,
          perfil: perfilData,
          usuario_rol: usuarioRolData,
        },
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
