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

    // A1: el body ya NO aporta contenido clinico. Solo receta_id.
    // medicamentos/diagnostico/indicaciones se IGNORAN si vienen (backwards-compatible
    // con el front viejo). Todo el contenido se lee de la BD con service_role.
    const { receta_id } = await req.json()

    if (!receta_id || !/^\d+$/.test(String(receta_id))) {
      return new Response(
        JSON.stringify({ success: false, error: 'receta_id invalido o ausente' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }
    const recetaIdNum = Number(receta_id)

    // --- Autenticacion del caller (el edge corre con service_role, asi que el rol
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
    // A1: se traen tambien los campos clinicos REALES de la fila.
    const { data: receta } = await supabase
      .from('recetas')
      .select('id, medico_id, paciente_id, diagnostico, instrucciones_generales, estado, created_at')
      .eq('id', recetaIdNum)
      .maybeSingle()
    if (!receta) {
      return new Response(JSON.stringify({ success: false, error: 'Receta no encontrada' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // --- Autorizacion: medico dueno, o super_admin, o admin_clinica/gerente que
    //     comparte clinica con el medico de la receta. ---
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

    const medico_id = receta.medico_id
    const paciente_id = receta.paciente_id

    const { data: paciente } = await supabase
      .from('pacientes')
      .select('nombre, apellido, telefono, fecha_nacimiento')
      .eq('id', paciente_id)
      .single()

    // A1 FIX: 'especialidad' NO existe en perfiles. El select roto hacia que
    // `medico` fuera null y el HTML imprimiera "N/A" en nombre y especialidad,
    // y que la firma cayera SIEMPRE al literal 'Medico'.
    const { data: medico } = await supabase
      .from('perfiles')
      .select('nombre_completo, nombre')
      .eq('id', medico_id)
      .maybeSingle()

    const { data: medicoRec } = await supabase
      .from('medicos')
      .select('especialidad, cedula_profesional')
      .eq('id', medico_id)
      .maybeSingle()

    const medicoNombre = medico?.nombre_completo || medico?.nombre || 'Medico'

    // A1 FIX: LOS MEDICAMENTOS VIVEN EN receta_items. La edge NUNCA los leia.
    // recetas.medicamentos es jsonb DEFAULT '[]' -> truthy en JS -> el fallback
    // del front nunca disparaba -> el documento salia con la lista VACIA.
    const { data: items } = await supabase
      .from('receta_items')
      .select('nombre_medicamento, dosis, frecuencia, duracion, instrucciones, cantidad')
      .eq('receta_id', recetaIdNum)
      .order('id', { ascending: true })

    const itemsArr = Array.isArray(items) ? items : []

    // Token de despacho FUERTE: lo genera la BD (DEFAULT gen_random_bytes, 256 bits).
    // upsert con ON CONFLICT(receta_base_id) DO NOTHING: 1 receta_avanzada por receta.
    // Post-cutover emitir_receta ya creo la fila (con firma y emitida_at) -> esto es no-op.
    // Se conserva (decision A) para no romper las recetas emitidas por el camino viejo.
    const { error: insertError } = await supabase
      .from('recetas_avanzadas')
      .upsert({
        receta_base_id: recetaIdNum,
        paciente_id,
        medico_id,
        firma_digital: `FIRMADO-${medicoNombre}-${new Date().toISOString()}`,
        estado_dispensacion: 'pendiente'
      }, { onConflict: 'receta_base_id', ignoreDuplicates: true })

    if (insertError) throw insertError

    const { data: recetaAvanzada, error: selError } = await supabase
      .from('recetas_avanzadas')
      .select('id, dispatch_token, firma_digital, dispatch_token_expira_at')
      .eq('receta_base_id', recetaIdNum)
      .single()

    if (selError || !recetaAvanzada) throw (selError || new Error('No se pudo obtener el token de despacho'))
    const codigoQR = recetaAvanzada.dispatch_token
    const qrSvg = await QRCode.toString(codigoQR, { type: 'svg', margin: 1, width: 200 })

    const esc = (s: unknown) =>
      String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

    const fechaEmision = receta.created_at
      ? new Date(receta.created_at).toLocaleDateString('es-GT', { day: 'numeric', month: 'long', year: 'numeric' })
      : 'N/A'

    const vence = recetaAvanzada.dispatch_token_expira_at
      ? new Date(recetaAvanzada.dispatch_token_expira_at).toLocaleDateString('es-GT', { day: 'numeric', month: 'long', year: 'numeric' })
      : 'N/A'

    const pacienteNombre = [paciente?.nombre, paciente?.apellido].filter(Boolean).join(' ') || 'N/A'

    // A1 FIX: sin invenciones. Si no hay diagnostico, se dice que no hay.
    // 'indicaciones' NO EXISTE como columna en recetas: la instruccion general
    // vive en recetas.instrucciones_generales; la posologia, en cada item.
    const filasMed = itemsArr.length > 0
      ? itemsArr.map((m: any) => `<tr>
          <td>${esc(m.nombre_medicamento)}</td>
          <td>${esc(m.dosis)}</td>
          <td>${esc(m.frecuencia)}</td>
          <td>${esc(m.duracion || '-')}</td>
          <td>${esc(m.cantidad ?? '-')}</td>
          <td>${esc(m.instrucciones || '-')}</td>
        </tr>`).join('')
      : `<tr><td colspan="6" style="text-align:center;color:#b00">Esta receta no tiene medicamentos registrados</td></tr>`

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
table.meds { width: 100%; border-collapse: collapse; font-size: 14px; }
table.meds th { background: #1a1f2e; color: #fff; padding: 8px; text-align: left; }
table.meds td { border-bottom: 1px solid #e5e5e5; padding: 8px; }
.nota { background: #f0f9ff; padding: 15px; border-radius: 8px; border-left: 4px solid #00f2ff; }
.qr-section { text-align: center; margin-top: 30px; padding: 20px; border: 2px dashed #00f2ff; border-radius: 10px; }
.qr-img { display: inline-block; background: #fff; padding: 10px; border-radius: 5px; }
.qr-img svg { width: 200px; height: 200px; display: block; }
.footer { margin-top: 40px; text-align: center; font-size: 12px; color: #999; border-top: 1px solid #eee; padding-top: 20px; }
.firma { margin-top: 30px; text-align: right; }
.firma-line { border-top: 1px solid #333; width: 240px; display: inline-block; margin-top: 50px; }
</style></head>
<body>
<div class="header"><h1>EzPayConnect</h1><p>Receta Medica Electronica</p><p>Fecha de emision: ${esc(fechaEmision)}</p></div>

<div class="section"><h3>Paciente</h3><div class="info-grid">
<div class="info-item"><strong>Nombre:</strong> ${esc(pacienteNombre)}</div>
<div class="info-item"><strong>Telefono:</strong> ${esc(paciente?.telefono || 'N/A')}</div>
</div></div>

<div class="section"><h3>Medico</h3><div class="info-grid">
<div class="info-item"><strong>Nombre:</strong> ${esc(medicoNombre)}</div>
<div class="info-item"><strong>Especialidad:</strong> ${esc(medicoRec?.especialidad || 'N/A')}</div>
<div class="info-item"><strong>Colegiado:</strong> ${esc(medicoRec?.cedula_profesional || 'No registrado')}</div>
</div></div>

<div class="section"><h3>Diagnostico</h3><div class="nota">
<p>${receta.diagnostico ? esc(receta.diagnostico) : '<em>No especificado</em>'}</p>
</div></div>

<div class="section"><h3>Medicamentos Prescritos</h3>
<table class="meds">
<thead><tr><th>Medicamento</th><th>Dosis</th><th>Frecuencia</th><th>Duracion</th><th>Cant.</th><th>Instrucciones</th></tr></thead>
<tbody>${filasMed}</tbody>
</table></div>

${receta.instrucciones_generales ? `<div class="section"><h3>Instrucciones Generales</h3><div class="nota"><p>${esc(receta.instrucciones_generales)}</p></div></div>` : ''}

<div class="qr-section"><h3>Codigo QR de Verificacion</h3><div class="qr-img">${qrSvg}</div>
<p style="font-size: 12px; color: #666; margin-top: 10px;">Escanea este codigo en farmacia para despachar la receta</p></div>

<div class="firma"><div class="firma-line"></div>
<p><strong>${esc(medicoNombre)}</strong></p>
<p style="font-size: 12px; color: #666;">${esc(medicoRec?.cedula_profesional ? 'Colegiado ' + medicoRec.cedula_profesional : 'Firma y Sello Medico')}</p>
</div>

<div class="footer"><p>EzPayConnect - Documento generado electronicamente</p>
<p>Valida para despacho hasta el ${esc(vence)}</p></div>
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
