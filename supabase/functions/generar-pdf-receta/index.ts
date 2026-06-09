// supabase/functions/generar-receta-pdf/index.ts
// Dia 17: Edge Function - Generar PDF de receta con QR
// EzPayConnect - VERSION CORS CORREGIDA

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

    const { receta_id, paciente_id, medico_id, medicamentos, diagnostico, indicaciones } = await req.json()

    if (!receta_id || !paciente_id || !medico_id) {
      throw new Error('Faltan campos requeridos: receta_id, paciente_id, medico_id')
    }

    const codigoQR = `EZP-${Date.now()}-${Math.random().toString(36).substring(2, 8).toUpperCase()}`

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

    const { data: recetaAvanzada, error: insertError } = await supabase
      .from('recetas_avanzadas')
      .insert({
        receta_base_id: receta_id,
        paciente_id,
        medico_id,
        codigo_qr: codigoQR,
        firma_digital: `FIRMADO-${medico?.nombre || 'Medico'}-${new Date().toISOString()}`,
        estado_dispensacion: 'pendiente'
      })
      .select()
      .single()

    if (insertError) throw insertError

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
.qr-code { font-family: monospace; font-size: 14px; background: #1a1f2e; color: #00f2ff; padding: 10px; border-radius: 5px; display: inline-block; }
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
<div class="qr-section"><h3>📱 Codigo QR de Verificacion</h3><div class="qr-code">${codigoQR}</div>
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
