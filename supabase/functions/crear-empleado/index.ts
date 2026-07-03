import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Create Supabase admin client with Service Role Key
    const supabaseUrl = (Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')) ?? ''
    const supabaseServiceKey = (Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) ?? ''
    const supabaseAnonKey = (Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY')) ?? ''
    const supabaseAdmin = createClient(
      supabaseUrl,
      supabaseServiceKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    )

    // GATE DE AUTORIZACIÓN — cierra el hueco más grave: esta función usa service_role (bypass RLS) y
    // podía crear una cuenta con rol='super_admin' desde cualquier usuario logueado (hasta un paciente),
    // porque NO validaba al caller. Ahora se exige super_admin verificado server-side con el JWT del
    // caller (mismo patrón que reportes-ezpay / enviar-push-campana): se valida el JWT con un cliente
    // anon (NO service_role) y recién ahí se lee perfiles.rol con el admin client.
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader) {
      return new Response(JSON.stringify({ success: false, error: 'Falta Authorization' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(JSON.stringify({ success: false, error: 'JWT inválido' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }
    const { data: perfilCaller } = await supabaseAdmin.from('perfiles').select('rol').eq('id', user.id).maybeSingle()
    if (!perfilCaller || perfilCaller.rol !== 'super_admin') {
      return new Response(JSON.stringify({ success: false, error: 'No autorizado: sólo super_admin crea empleados' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 })
    }

    // 2. Get request body
    const { email, password, nombre_completo, nombre, rol_id, asignado_por } = await req.json()

    // 3. Validate required fields
    if (!email || !password || !nombre_completo || !rol_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Faltan campos obligatorios: email, password, nombre_completo, rol_id' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 4. Create user in Auth with admin privileges (bypasses email confirmation)
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // Auto-confirm email (no verification needed)
      user_metadata: {
        nombre_completo,
      },
    })

    if (authError) {
      return new Response(
        JSON.stringify({ success: false, error: 'Error creando usuario en Auth: ' + authError.message }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    const userId = authData.user.id

    // 5. Get role name
    const { data: rolData, error: rolError } = await supabaseAdmin
      .from('roles')
      .select('nombre')
      .eq('id', rol_id)
      .single()

    if (rolError) {
      // Rollback: delete auth user if role not found
      await supabaseAdmin.auth.admin.deleteUser(userId)
      return new Response(
        JSON.stringify({ success: false, error: 'Rol no encontrado. Usuario revertido.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 6. Insert profile in perfiles table
    const { error: perfilError } = await supabaseAdmin
      .from('perfiles')
      .insert({
        id: userId,
        email,
        nombre_completo,
        nombre: nombre || nombre_completo,
        rol: rolData.nombre,
        activo: true,
      })

    if (perfilError) {
      // Rollback: delete auth user if profile insert fails
      await supabaseAdmin.auth.admin.deleteUser(userId)
      return new Response(
        JSON.stringify({ success: false, error: 'Error creando perfil: ' + perfilError.message + '. Usuario revertido.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 7. Assign role in usuario_roles
    const { error: usuarioRolError } = await supabaseAdmin
      .from('usuario_roles')
      .insert({
        usuario_id: userId,
        rol_id: rol_id,
        asignado_por: asignado_por || userId,
        fecha_asignacion: new Date().toISOString(),
        activo: true,
      })

    if (usuarioRolError) {
      console.warn('Error asignando rol (no critico):', usuarioRolError.message)
    }

    // 8. Log audit en auditoria_logs (estructura correcta)
    await supabaseAdmin
      .from('auditoria_logs')
      .insert({
        usuario_id: asignado_por,
        usuario_email: email,
        usuario_nombre: nombre_completo,
        accion: 'crear_empleado',
        entidad: 'empleado',
        entidad_id: userId,
        detalle: { 
          email: email, 
          nombre_completo: nombre_completo, 
          rol: rolData.nombre,
          creado_por: asignado_por 
        },
        ip_address: req.headers.get('x-forwarded-for') || req.headers.get('cf-connecting-ip') || 'unknown',
      })

    // 9. NOTIFICAR ADMIN - Nuevo empleado registrado
    try {
      const supabaseUrl = (Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')) ?? ''
      const serviceRoleKey = (Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) ?? ''
      
      await fetch(`${supabaseUrl}/functions/v1/notificar-admin`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${serviceRoleKey}`,
        },
        body: JSON.stringify({
          tipo: 'empleado',
          titulo: 'Nuevo empleado registrado',
          mensaje: `${nombre_completo} fue registrado como ${rolData.nombre}`,
          metadata: {
            empleado_id: userId,
            nombre: nombre_completo,
            rol: rolData.nombre,
            email: email,
            creado_por: asignado_por,
          },
          accion_url: '/admin-ezpay/usuarios',
        }),
      })
    } catch (notifError: any) {
      console.warn('Error enviando notificacion admin (no critico):', notifError.message)
    }

    // 10. Return success
    return new Response(
      JSON.stringify({
        success: true,
        data: {
          id: userId,
          email,
          nombre_completo,
          rol: rolData.nombre,
        },
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error: any) {
    return new Response(
      JSON.stringify({ success: false, error: error.message || 'Error inesperado' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})