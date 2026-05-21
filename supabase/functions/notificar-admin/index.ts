// ============================================
// Edge Function: notificar-admin
// Crea notificaciones distribuidas por jerarquía
// + Dispara email automático via enviar-notificacion
// ============================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ============================================
// MAPEO: Tipo de evento → Rol directo responsable
// ============================================
const MAPEO_ROLES: Record<string, { rol: string; nivel: number }> = {
  empleado: { rol: "admin", nivel: 4 },
  venta: { rol: "vendedor", nivel: 2 },
  plan: { rol: "admin", nivel: 4 },
  reporte: { rol: "gerente", nivel: 3 },
};

// ============================================
// MAPEO: Tipo de evento → Template de email
// ============================================
const EMAIL_TEMPLATES: Record<string, { subject: string; body: string }> = {
  empleado: {
    subject: "Nuevo empleado registrado - EZPayConnect",
    body: "Se ha registrado un nuevo empleado en el sistema. Requiere revisión y activación.",
  },
  venta: {
    subject: "Nueva venta de plan completada - EZPayConnect",
    body: "Se ha completado una nueva venta de plan. Verifica los detalles de la transacción.",
  },
  plan: {
    subject: "Nuevo plan creado - EZPayConnect",
    body: "Un nuevo plan ha sido creado en el sistema. Revisa la configuración.",
  },
  reporte: {
    subject: "Reporte generado - EZPayConnect",
    body: "Un nuevo reporte ha sido generado y está listo para su revisión.",
  },
};

serve(async (req) => {
  // --- CORS ---
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const body = await req.json();
    const { tipo, titulo, mensaje, metadata = {}, accion_url = null } = body;

    // --- Validaciones ---
    if (!tipo || !titulo || !mensaje) {
      return new Response(
        JSON.stringify({ error: "Faltan campos requeridos: tipo, titulo, mensaje" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    const configRol = MAPEO_ROLES[tipo];
    if (!configRol) {
      return new Response(
        JSON.stringify({ error: `Tipo de notificación no soportado: ${tipo}` }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // --- Generar evento_id único para agrupar ---
    const evento_id = crypto.randomUUID();

    // ============================================
    // PASO 1: Buscar usuarios con rol directo
    // ============================================
    const { data: directos, error: errDirectos } = await supabase
      .from("perfiles")
      .select("id, email, nombre, rol, rol_id")
      .eq("rol", configRol.rol)
      .eq("activo", true);

    if (errDirectos) throw errDirectos;

       // ============================================
    // PASO 2: Buscar superiores jerárquicos (nivel > directo)
    // ============================================
    // Primero obtener los roles superiores
    const { data: rolesSuperiores, error: errRoles } = await supabase
      .from("roles")
      .select("nombre, nivel")
      .gt("nivel", configRol.nivel);

    if (errRoles) throw errRoles;

    const nombresSuperiores = rolesSuperiores?.map((r) => r.nombre) || [];
    
    let superioresFinal = [];
    if (nombresSuperiores.length > 0) {
      const { data: sups, error: errSups } = await supabase
        .from("perfiles")
        .select("id, email, nombre, rol, rol_id")
        .in("rol", nombresSuperiores)
        .eq("activo", true);

      if (errSups) throw errSups;
      superioresFinal = sups || [];
    }

    // ============================================
    // PASO 3: Crear notificaciones para todos
    // ============================================
    const notificaciones = [];
    const destinatariosIds = [];
    const emails = [];

    // Notificaciones para rol directo
    for (const user of directos || []) {
      notificaciones.push({
        usuario_id: user.id,
        tipo,
        titulo,
        mensaje,
        estado: "pendiente",
        leida: false,
        evento_id,
        rol_destinatario: configRol.rol,
        nivel_destinatario: configRol.nivel,
        accion_url,
        metadata,
      });
      destinatariosIds.push(user.id);
      if (user.email) emails.push({ email: user.email, nombre: user.nombre, rol: user.rol });
    }

    // Notificaciones para superiores
    for (const user of superioresFinal || []) {
      notificaciones.push({
        usuario_id: user.id,
        tipo,
        titulo: `${titulo} [Seguimiento]`,
        mensaje: `${mensaje}\n\nEsta notificación es para seguimiento jerárquico. El rol responsable (${configRol.rol}) debe atenderla.`,
        estado: "pendiente",
        leida: false,
        evento_id,
        rol_destinatario: user.rol,
        nivel_destinatario: 0, // Se actualiza abajo
        accion_url,
        metadata: { ...metadata, es_seguimiento: true, rol_responsable: configRol.rol },
      });
      destinatariosIds.push(user.id);
      if (user.email) emails.push({ email: user.email, nombre: user.nombre, rol: user.rol });
    }

    // Actualizar nivel_destinatario para superiores
    if (superioresFinal && superioresFinal.length > 0) {
      const { data: rolesData } = await supabase
        .from("roles")
        .select("nombre, nivel");
      
      const nivelMap = new Map(rolesData?.map((r) => [r.nombre, r.nivel]) || []);
      
      for (const n of notificaciones) {
        if (n.rol_destinatario !== configRol.rol) {
          n.nivel_destinatario = nivelMap.get(n.rol_destinatario) || 0;
        }
      }
    }

    // ============================================
    // PASO 4: Insertar notificaciones en BD
    // ============================================
    const { data: insertadas, error: errInsert } = await supabase
      .from("notificaciones")
      .insert(notificaciones)
      .select();

    if (errInsert) throw errInsert;

    // ============================================
    // PASO 5: Disparar emails automáticos
    // ============================================
    const template = EMAIL_TEMPLATES[tipo];
    const emailPromises = emails.map(async (dest) => {
      try {
        await fetch(`${SUPABASE_URL}/functions/v1/enviar-notificacion`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          },
          body: JSON.stringify({
            to: dest.email,
            subject: template.subject,
            body: `
Hola ${dest.nombre || "Administrador"},

${template.body}

Detalles:
- Tipo: ${tipo}
- Título: ${titulo}
- Mensaje: ${mensaje}

${accion_url ? `Ver detalles: ${accion_url}` : ""}

---
Este es un mensaje automático de EZPayConnect.
            `.trim(),
            metadata: { tipo, evento_id, rol_destinatario: dest.rol },
          }),
        });
        return { email: dest.email, status: "enviado" };
      } catch (e) {
        return { email: dest.email, status: "error", error: e.message };
      }
    });

    const emailResults = await Promise.allSettled(emailPromises);

    // ============================================
    // RESPUESTA
    // ============================================
    return new Response(
      JSON.stringify({
        success: true,
        evento_id,
        notificaciones_creadas: insertadas?.length || 0,
        destinatarios: destinatariosIds,
        emails_enviados: emailResults.filter((r) => r.status === "fulfilled").length,
        emails_fallidos: emailResults.filter((r) => r.status === "rejected").length,
        detalle_emails: emailResults,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message || "Error interno" }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
});