// supabase/functions/generar-receta-pdf/index.ts
// Dia 17: Edge Function - Generar PDF de receta con QR
// EzPayConnect - VERSION CORS CORREGIDA

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import QRCode from 'https://esm.sh/qrcode@1.5.3'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SB_URL') || Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SB_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // El body ya NO es fuente de verdad para medico_id/paciente_id: se derivan de
    // la receta en BD (anti-forja). Del body sólo se usan campos de presentación.
    const { receta_id, medicamentos, diagnostico, indicaciones } = await req.json()

    if (!receta_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Falta campo requerido: receta_id' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // --- Autenticación del caller (el edge corre con service_role, así que el rol
    //     NO lo da el gateway: hay que derivarlo del JWT y validar ownership). ---
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ success: false, error: 'No autenticado' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    const { data: { user: caller } } = await supabase.auth.getUser(authHeader.replace('Bearer ', ''))
    if (!caller) {
      return new Response(JSON.stringify({ success: false, error: 'No autenticado' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Cargar la receta base: su medico_id/paciente_id REALES gobiernan todo.
    const { data: receta } = await supabase
      .from('recetas')
      .select('id, medico_id, paciente_id')
      .eq('id', receta_id)
      .maybeSingle()
    if (!receta) {
      return new Response(JSON.stringify({ success: false, error: 'Receta no encontrada' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // --- Autorización: médico dueño, o super_admin, o admin_clinica/gerente que
    //     comparte clínica con el médico de la receta. ---
    let autorizado = receta.medico_id === caller.id
    if (!autorizado) {
      const { data: perfilCaller } = await supabase
        .from('perfiles').select('rol').eq('id', caller.id).maybeSingle()
      const rol = perfilCaller?.rol
      if (rol === 'super_admin') {
        autorizado = true
      } else if (rol === 'admin_clinica' || rol === 'gerente') {
        const { data: callerCl } = await supabase.rpc('obtener_clinica_usuario', { p_user_id: caller.id })
        const { data: medicoCl } = await supabase.rpc('obtener_clinica_usuario', { p_user_id: receta.medico_id })
        const setCaller = new Set((Array.isArray(callerCl) ? callerCl : []).map((r: any) => r.clinica_id))
        autorizado = Array.isArray(medicoCl) && medicoCl.some((r: any) => setCaller.has(r.clinica_id))
      }
    }
    if (!autorizado) {
      return new Response(JSON.stringify({ success: false, error: 'No autorizado para esta receta' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // A partir de acá se usan SIEMPRE los ids reales de la receta (no los del body).
    const medico_id = receta.medico_id
    const paciente_id = receta.paciente_id

    const { data: paciente } = await supabase
      .from('pacientes')
      .select('nombre, telefono, fecha_nacimiento')
      .eq('id', paciente_id)
      .single()

    const { data: medico } = await supabase
      .from('perfiles')
      .select('nombre, especialidad')
      .eq('id', medico_id)
      .single()

    // Token de despacho FUERTE: lo genera la BD (DEFAULT gen_random_bytes, 256 bits).
    // upsert con ON CONFLICT(receta_base_id) DO NOTHING: 1 receta_avanzada por receta
    // (no se rota el token si ya existe; ver migración 085).
    const { error: insertError } = await supabase
      .from('recetas_avanzadas')
      .upsert({
        receta_base_id: receta_id,
        paciente_id,
        medico_id,
        firma_digital: `FIRMADO-${medico?.nombre || 'Medico'}-${new Date().toISOString()}`,
        estado_dispensacion: 'pendiente'
      }, { onConflict: 'receta_base_id', ignoreDuplicates: true })

    if (insertError) throw insertError

    // Leer el dispatch_token (recién creado o existente) para el QR del PDF.
    const { data: recetaAvanzada, error: selError } = await supabase
      .from('recetas_avanzadas')
      .select('id, dispatch_token, firma_digital')
      .eq('receta_base_id', receta_id)
      .single()

    if (selError || !recetaAvanzada) throw (selError || new Error('No se pudo obtener el token de despacho'))
    const codigoQR = recetaAvanzada.dispatch_token
    // MISMO token, ahora como IMAGEN QR escaneable (SVG inline; sin canvas/PNG → Deno-friendly).
    // El valor codificado es exactamente el dispatch_token (no cambia el token ni su semántica).
    const qrSvg = await QRCode.toString(codigoQR, { type: 'svg', margin: 1, width: 200 })

    const fecha = new Date().toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' })

    const htmlContent = `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Receta Medica - EzPayConnect</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; color: #333; }
.header { text-align: center; border-bottom: 3px solid #00f2ff; padding-bottom: 20px; margin-bottom: 30px; }
.header h1 { color: #00f2ff; margin: 0; font-size: 28px; }
.section { margin-bottom: 25px; }
.section h3 { color: #1a1f2e; border-left: 4px solid #00f2ff; padding-left: 10px; }
.info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
.info-item { background: #f5f5f5; padding: 10px; border-radius: 5px; }
.medicamentos { background: #f0f9ff; padding: 15px; border-radius: 8px; border-left: 4px solid #00f2ff; }
.qr-section { text-align: center; margin-top: 30px; padding: 20px; border: 2px dashed #00f2ff; border-radius: 10px; }
.qr-img { display: inline-block; background: #fff; padding: 10px; border-radius: 5px; }
.qr-img svg { width: 200px; height: 200px; display: block; }
.footer { margin-top: 40px; text-align: center; font-size: 12px; color: #999; border-top: 1px solid #eee; padding-top: 20px; }
.firma { margin-top: 30px; text-align: right; }
.firma-line { border-top: 1px solid #333; width: 200px; display: inline-block; margin-top: 50px; }
</style></head>
<body>
<div class="header"><h1>🏥 EzPayConnect</h1><p>Receta Medica Electronica</p><p>Fecha: ${fecha}</p></div>
<div class="section"><h3>👤 Paciente</h3><div class="info-grid">
<div class="info-item"><strong>Nombre:</strong> ${paciente?.nombre || 'N/A'}</div>
<div class="info-item"><strong>Telefono:</strong> ${paciente?.telefono || 'N/A'}</div>
</div></div>
<div class="section"><h3>👨‍⚕️ Medico</h3><div class="info-grid">
<div class="info-item"><strong>Nombre:</strong> ${medico?.nombre || 'N/A'}</div>
<div class="info-item"><strong>Especialidad:</strong> ${medico?.especialidad || 'N/A'}</div>
</div></div>
<div class="section"><h3>🩺 Diagnostico</h3><div class="medicamentos"><p>${diagnostico || 'No especificado'}</p></div></div>
<div class="section"><h3>💊 Medicamentos</h3><div class="medicamentos"><ul>
${Array.isArray(medicamentos) ? medicamentos.map((m) => `<li>${m}</li>`).join('') : `<li>${medicamentos || 'No especificado'}</li>`}
</ul></div></div>
${indicaciones ? `<div class="section"><h3>📋 Indicaciones</h3><div class="medicamentos"><p>${indicaciones}</p></div></div>` : ''}
<div class="qr-section"><h3>📱 Codigo QR de Verificacion</h3><div class="qr-img">${qrSvg}</div>
<p style="font-size: 12px; color: #666; margin-top: 10px;">Escanea este codigo en farmacia para verificar la receta</p></div>
<div class="firma"><div class="firma-line"></div><p><strong>${medico?.nombre || 'Medico'}</strong></p>
<p style="font-size: 12px; color: #666;">Firma Digital: ${recetaAvanzada?.firma_digital || 'N/A'}</p></div>
<div class="footer"><p>EzPayConnect - Sistema de Gestion Medica</p><p>Esta receta es valida por 30 dias desde la fecha de emision</p></div>
</body></html>`

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          codigo_qr: codigoQR,
          html: htmlContent,
          receta_avanzada_id: recetaAvanzada?.id,
          firma_digital: recetaAvanzada?.firma_digital
        }
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
