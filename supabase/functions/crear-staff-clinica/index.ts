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
      return new Response(
        JSON.stringify({ error: "SB_SERVICE_ROLE_KEY no configurada en secrets" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const body = await req.json();
    const { email, nombre_completo, rol, telefono, clinica_id, pais_id, clinica_nombre } = body;

    if (!email || !nombre_completo || !rol || !clinica_id) {
      return new Response(
        JSON.stringify({ error: "Faltan campos: email, nombre_completo, rol, clinica_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    if (!["secretaria", "asistente"].includes(rol)) {
      return new Response(
        JSON.stringify({ error: "rol inválido (secretaria|asistente)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 0. Validar al SOLICITANTE: debe ser admin_clinica/gerente de ESA clínica, o super_admin.
    //    (obtener_clinica_usuario solo prueba pertenencia, NO rol → exigimos también el rol.)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Falta Authorization" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const token = authHeader.replace("Bearer ", "");
    const { data: { user: solicitante } } = await supabase.auth.getUser(token);
    if (!solicitante) {
      return new Response(JSON.stringify({ error: "No autenticado" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const { data: perfilReq } = await supabase.from("perfiles").select("rol").eq("id", solicitante.id).maybeSingle();
    let autorizado = perfilReq?.rol === "super_admin";
    if (!autorizado && (perfilReq?.rol === "admin_clinica" || perfilReq?.rol === "gerente")) {
      const { data: rel } = await supabase.rpc("obtener_clinica_usuario", { p_user_id: solicitante.id });
      autorizado = Array.isArray(rel) && rel.some((r: any) => r.clinica_id === clinica_id);
    }
    if (!autorizado) {
      return new Response(JSON.stringify({ error: "No autorizado para crear staff en esta clínica" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // 1. Crear usuario en Auth (service role; auto-confirma email)
    const password = Math.random().toString(36).slice(-8) + "A1!";
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (authError) {
      const dup = authError.message?.toLowerCase().includes("already");
      return new Response(
        JSON.stringify({ error: dup ? "Este email ya está registrado" : authError.message }),
        { status: dup ? 409 : 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const userId = authData.user!.id;

    // 2. Crear perfil con el ROL REAL del staff (mapeo UI → roles_catalogo, mig 160).
    //    'asistente'  → 'asistente_medico' (captura signos vitales, Ola 1).
    //    'secretaria' → 'secretaria'       (capa administrativa; NO captura vitales).
    //    La UI valida arriba rol ∈ {secretaria, asistente}, así que el mapeo es total.
    //    La pertenencia de clínica NO depende del rol: se otorga en el paso 3 (medico_clinicas).
    const rolPersistido = rol === "asistente" ? "asistente_medico" : "secretaria";
    const { error: perfilError } = await supabase.from("perfiles").insert({
      id: userId,
      email,
      nombre_completo,
      telefono: telefono || null,
      rol: rolPersistido,
      pais_id: pais_id || null,
      activo: true,
    });
    if (perfilError) {
      // Rollback del usuario auth si el perfil falla
      await supabase.auth.admin.deleteUser(userId).catch(() => {});
      return new Response(
        JSON.stringify({ error: "Error creando perfil: " + perfilError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2.5 Crear fila en `medicos` — requisito del schema: medico_clinicas.medico_id
    //     tiene FK a `medicos`. Sin esto, la asociación a la clínica (paso 3) falla
    //     y el staff queda con rol pero SIN acceso de clínica.
    const { error: medError } = await supabase.from("medicos").insert({
      id: userId,
      clinica_id,
      nombre_completo,
    });
    if (medError) {
      await supabase.from("perfiles").delete().eq("id", userId);
      await supabase.auth.admin.deleteUser(userId).catch(() => {});
      return new Response(
        JSON.stringify({ error: "Error creando registro médico: " + medError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Asociar a la clínica (medico_clinicas). Si falla, revertir todo: un staff
    //    sin asociación no tendría acceso de clínica, así que no lo dejamos a medias.
    const { error: asocError } = await supabase.rpc("asociar_medico_clinica", {
      p_medico_id: userId,
      p_clinica_id: clinica_id,
      p_es_principal: false,
    });
    if (asocError) {
      await supabase.from("medicos").delete().eq("id", userId);
      await supabase.from("perfiles").delete().eq("id", userId);
      await supabase.auth.admin.deleteUser(userId).catch(() => {});
      return new Response(
        JSON.stringify({ error: "Error asociando a la clínica: " + asocError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. Email con credenciales (best-effort)
    let emailEnviado = false;
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    if (resendApiKey) {
      try {
        const res = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from: "EzPayConnect <no-reply@ezpayconnect.com>",
            to: email,
            subject: "Bienvenido a EzPayConnect — Credenciales de acceso",
            html: `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
              <h2 style="color:#1E5C8E;margin-top:0;">¡Bienvenido a EzPayConnect!</h2>
              <p>Hola <strong>${nombre_completo}</strong>,</p>
              <p>Has sido registrado como <strong>${rol}</strong>${clinica_nombre ? ` en <strong>${clinica_nombre}</strong>` : ""}.</p>
              <div style="background:#f3f4f6;padding:12px;border-radius:6px;margin:12px 0;">
                <p><strong>Email:</strong> ${email}</p>
                <p><strong>Contraseña temporal:</strong> ${password}</p>
              </div>
              <p><a href="https://ezpayconnect.vercel.app/login" style="color:#1E5C8E;">Iniciar sesión</a></p>
              <p style="color:#6b7280;font-size:12px;">Te recomendamos cambiar tu contraseña al iniciar sesión.</p>
            </div>`,
          }),
        });
        emailEnviado = res.ok;
      } catch (e) {
        console.error("[crear-staff-clinica] Error enviando email:", e);
      }
    }

    return new Response(
      JSON.stringify({ success: true, user_id: userId, password, email_enviado: emailEnviado }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("[crear-staff-clinica] Error inesperado:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Error interno" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
