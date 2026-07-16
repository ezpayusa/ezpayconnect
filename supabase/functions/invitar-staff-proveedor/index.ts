// supabase/functions/invitar-staff-proveedor/index.ts
// Invitación Opción B (staff de proveedor: farmacia v1; generalizada a cualquier tipo CON catálogo).
// La edge hace SOLO lo que SQL no puede (auth.admin.createUser); la autz crítica vive en el RPC DEFINER
// `vincular_membresia_proveedor` (gate invitador=usuarios_roles, empresa/tipo derivados de él, rol∈catálogo,
// guard 1:1). El RPC se llama CON el JWT del invitador → auth.uid()=invitador (gate real, no service_role).
//
// D1 (3 ramas): (i) email nuevo → createUser + RPC; (ii) auth user existe SIN membresía → solo RPC (sin
//   createUser, sin tocar su credencial); (iii) auth user CON membresía → RPC raise 23505 → 409.
// D2 (Fase D — cierra la deuda Ola-4): usuario NUEVO se crea SIN password usable y recibe un link de RECOVERY
//   al /set-password (el redirectTo debe estar en additional_redirect_urls de Supabase Auth). Usuario EXISTENTE (ii)
//   NO recibe credencial: solo aviso "fuiste agregado". El flag must_change_password se conserva como belt: el guard
//   MustChangePasswordGuard fuerza el cambio si el usuario ingresa sin clave propia, y SetPasswordPage lo limpia al setear.
//
// ORDEN (fix de seguridad): el PRE-GATE (autorizar_invitacion_staff, con el JWT del invitador) corre ANTES
// de createUser → un caller no-admin se rechaza SIN crear auth user ni enviar email (no timing-enum).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

// URL canónica de la app en producción (constante, NO env var: evita links rotos en silencio).
// Las edges no pueden importar de src/lib/app-url.ts, así que se define aquí.
const APP_URL = 'https://med.ezpayconnect.com'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const url = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey = Deno.env.get('SB_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY')!
    if (!url || !serviceKey || !anonKey) return json({ error: 'Config incompleta (service/anon key)' }, 503)

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Falta Authorization' }, 401)

    // admin (service_role) SOLO para auth.admin.*; el RPC corre con el JWT del invitador (gate real).
    const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } })
    const asCaller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const { data: { user: solicitante } } = await admin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (!solicitante) return json({ error: 'No autenticado' }, 401)

    const body = await req.json().catch(() => null)
    const email = (body?.email ?? '').toString().toLowerCase().trim()
    const nombre = (body?.nombre_completo ?? '').toString().trim() || null
    const rol = body?.rol
    const telefono = body?.telefono ?? null
    // 3.2: sucursal opcional al invitar (aditivo; null = sin sucursal = empresa-wide/grandfather)
    const sucursalId = (body?.sucursal_id === undefined || body?.sucursal_id === null || body?.sucursal_id === '')
      ? null : Number(body.sucursal_id)
    if (!email || !rol) return json({ error: 'Faltan campos: email, rol' }, 400)

    // (1) PRE-GATE (ANTES de createUser): autz del invitador. No-admin / rol fuera de catálogo → corta YA,
    //     sin crear auth user ni enviar email. Corre con el JWT del invitador (auth.uid()=solicitante).
    const { data: gateData, error: gateErr } = await asCaller.rpc('autorizar_invitacion_staff', { p_rol: rol })
    if (gateErr) {
      const code = (gateErr as any).code
      const status = (code === '22023' || code === '42501') ? 403 : code === '28000' ? 401 : 400
      return json({ error: gateErr.message, code }, status)
    }
    const tipoEmpresa = (gateData as any)?.tipo as string | undefined
    const portalPath = tipoEmpresa === 'farmacia' ? '/farmacia'
      : tipoEmpresa === 'laboratorio_clinico' ? '/laboratorio' : '/proveedor'

    // (2) Resolver/crear el auth user (solo tras pasar el pre-gate). Temp pwd SOLO si es usuario nuevo (rama i).
    let targetUid: string | null = null
    let creado = false
    // Fase D: sin password usable. El usuario nuevo setea su clave via el link de recovery (email de abajo).
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: { must_change_password: true },
    })
    if (!createErr && created?.user) {
      targetUid = created.user.id; creado = true              // rama (i)
    } else if (createErr && (createErr.message || '').toLowerCase().includes('already')) {
      creado = false                                          // rama (ii)/(iii): el RPC resuelve uid por email
    } else if (createErr) {
      return json({ error: createErr.message }, 400)
    }

    // (3) Vínculo de membresía: re-gatea + resuelve uid POR EMAIL (sin uid caller-supplied) + 1:1 + insert.
    const { data: vinc, error: rpcErr } = await asCaller.rpc('vincular_membresia_proveedor', {
      p_email: email, p_rol: rol, p_nombre: nombre, p_telefono: telefono, p_sucursal_id: sucursalId,
    })
    if (rpcErr) {
      if (creado && targetUid) await admin.auth.admin.deleteUser(targetUid).catch(() => {})  // rollback rama (i)
      const code = (rpcErr as any).code
      const status = code === '23505' ? 409 : (code === '22023' || code === '42501') ? 403 : code === '28000' ? 401 : 400
      return json({ error: rpcErr.message, code }, status)
    }

    // Fase D: link de recovery -> /set-password (reemplaza el password temporal en texto plano).
    let setPasswordLink: string | null = null
    if (creado) {
      const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
        type: 'recovery',
        email,
        options: { redirectTo: `${APP_URL}/set-password?next=${encodeURIComponent(portalPath)}` },
      })
      if (linkErr) console.error('[invitar-staff-proveedor] generateLink:', linkErr)
      else setPasswordLink = (linkData as any)?.properties?.action_link ?? null
    }

    // (4) Entrega: NUEVO → credencial temporal por email (jamás en el JSON); EXISTENTE → solo aviso.
    let emailEnviado = false
    const resendKey = Deno.env.get('RESEND_API_KEY')
    if (resendKey) {
      const subject = creado ? 'EzPayConnect — Tu acceso' : 'EzPayConnect — Fuiste agregado a una empresa'
      const html = creado
        ? `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
             <h2 style="color:#1E5C8E;margin-top:0;">Bienvenido a EzPayConnect</h2>
             <p>Hola${nombre ? ` <strong>${nombre}</strong>` : ''}, fuiste agregado como <strong>${rol}</strong>.</p>
             <p>Para ingresar, establecé tu contraseña:</p>
             <p><a href="${setPasswordLink ?? APP_URL + '/login'}" style="display:inline-block;background:#1E5C8E;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none;">Establecer contraseña</a></p>
             <p style="color:#6b7280;font-size:12px;">Email de acceso: ${email}</p>
             ${setPasswordLink ? `<p style="color:#6b7280;font-size:12px;word-break:break-all;">O copiá este enlace: ${setPasswordLink}</p>` : ''}
           </div>`
        : `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
             <h2 style="color:#1E5C8E;margin-top:0;">Fuiste agregado a una empresa</h2>
             <p>Hola${nombre ? ` <strong>${nombre}</strong>` : ''}, ya tienes acceso como <strong>${rol}</strong>.</p>
             <p>Ingresá con tu <strong>cuenta existente</strong> (tu contraseña no cambió).</p>
             <p><a href="${APP_URL}/proveedor/login" style="color:#1E5C8E;">Iniciar sesión</a></p>
           </div>`
      try {
        const r = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ from: 'EzPayConnect <no-reply@ezpayconnect.com>', to: email, subject, html }),
        })
        emailEnviado = r.ok
      } catch (e) { console.error('[invitar-staff-proveedor] email:', e) }
    }

    // D2: el JSON NUNCA incluye la contraseña.
    return json({ success: true, branch: creado ? 'nuevo' : 'vinculado', email_enviado: emailEnviado, empresa: (vinc as any)?.empresa_id })
  } catch (e: any) {
    console.error('[invitar-staff-proveedor] inesperado:', e)
    return json({ error: e?.message || 'Error interno' }, 500)
  }
})
