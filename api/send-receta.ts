import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';
import type { VercelRequest, VercelResponse } from '@vercel/node';

const resend = new Resend(process.env.RESEND_API_KEY);

// Roles clínicos autorizados a enviar recetas por email.
const ROLES_AUTORIZADOS = ['medico', 'super_admin', 'admin_clinica', 'gerente'];

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Solo permitir POST
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // --- Autenticación + rol (cierra el open-relay de emails). Fail-closed. ---
  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('send-receta: faltan SUPABASE_URL/SUPABASE_ANON_KEY en env');
    return res.status(500).json({ error: 'Autenticación no configurada' });
  }
  const authHeader = req.headers.authorization;
  if (!authHeader) {
    return res.status(401).json({ error: 'No autenticado' });
  }
  // Cliente con el token del caller: getUser lo valida y la RLS de perfiles
  // (auth.uid()=id) permite leer el propio rol sin service_role.
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return res.status(401).json({ error: 'No autenticado' });
  }
  const { data: perfil } = await supabase
    .from('perfiles').select('rol').eq('id', user.id).maybeSingle();
  if (!perfil || !ROLES_AUTORIZADOS.includes(perfil.rol)) {
    return res.status(403).json({ error: 'No autorizado para enviar recetas' });
  }

  try {
    const { 
      to, 
      pacienteNombre, 
      medicoNombre, 
      medicamentos, 
      instruccionesGenerales,
      solicitarConfirmacion 
    } = req.body;

    if (!to || !pacienteNombre || !medicamentos) {
      return res.status(400).json({ error: 'Faltan datos requeridos' });
    }

    // Generar HTML del email
    const medicamentosHTML = medicamentos.map((med: any, idx: number) => `
      <tr style="border-bottom: 1px solid #e8f0f8;">
        <td style="padding: 12px; font-weight: bold; color: #1E5C8E;">${idx + 1}. ${med.nombre_medicamento}</td>
      </tr>
      <tr>
        <td style="padding: 0 12px 12px 12px;">
          <p style="margin: 4px 0; color: #1a2a3a;"><strong>Dosis:</strong> ${med.dosis || 'N/A'}</p>
          <p style="margin: 4px 0; color: #1a2a3a;"><strong>Frecuencia:</strong> ${med.frecuencia || 'N/A'}</p>
          <p style="margin: 4px 0; color: #1a2a3a;"><strong>Duración:</strong> ${med.duracion || 'N/A'}</p>
          <p style="margin: 4px 0; color: #1a2a3a;"><strong>Cantidad:</strong> ${med.cantidad || 1}</p>
          ${med.instrucciones ? `<p style="margin: 4px 0; color: #8a9aaa;"><em>Instrucciones: ${med.instrucciones}</em></p>` : ''}
        </td>
      </tr>
    `).join('');

    const confirmacionHTML = solicitarConfirmacion ? `
      <div style="margin-top: 30px; padding: 20px; background: #e8f0f8; border-radius: 8px; text-align: center;">
        <p style="margin: 0 0 15px 0; color: #1a2a3a;">Por favor, confirma que recibiste esta receta:</p>
        <a href="https://ezpayconnect.vercel.app/confirmar-receta?email=${encodeURIComponent(to)}" 
           style="display: inline-block; padding: 12px 30px; background: #1E5C8E; color: white; text-decoration: none; border-radius: 6px; font-weight: bold;">
          Confirmar Recepción
        </a>
      </div>
    ` : '';

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Receta Médica - EzPayConnect</title>
      </head>
      <body style="margin: 0; padding: 0; font-family: Arial, sans-serif; background: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background: white;">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #1E5C8E, #3A8ABF); padding: 30px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px;">EzPayConnect</h1>
            <p style="color: rgba(255,255,255,0.8); margin: 5px 0 0 0; font-size: 14px;">Software Médico</p>
          </div>

          <!-- Content -->
          <div style="padding: 30px;">
            <h2 style="color: #1a2a3a; margin: 0 0 20px 0;">Receta Médica</h2>

            <div style="background: #e8f0f8; padding: 15px; border-radius: 8px; margin-bottom: 20px;">
              <p style="margin: 0; color: #1a2a3a;"><strong>Paciente:</strong> ${pacienteNombre}</p>
              <p style="margin: 5px 0 0 0; color: #8a9aaa; font-size: 13px;"><strong>Médico:</strong> ${medicoNombre || 'Doctor'}</p>
              <p style="margin: 5px 0 0 0; color: #8a9aaa; font-size: 13px;"><strong>Fecha:</strong> ${new Date().toLocaleDateString('es-GT', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}</p>
            </div>

            <h3 style="color: #1E5C8E; font-size: 16px; margin: 25px 0 15px 0;">Medicamentos Prescritos</h3>
            <table style="width: 100%; border-collapse: collapse;">
              ${medicamentosHTML}
            </table>

            ${instruccionesGenerales ? `
              <div style="margin-top: 25px; padding: 15px; background: #fff8e1; border-left: 4px solid #f59e0b; border-radius: 4px;">
                <h4 style="color: #1a2a3a; margin: 0 0 10px 0; font-size: 14px;">Instrucciones Generales</h4>
                <p style="margin: 0; color: #1a2a3a; font-size: 14px;">${instruccionesGenerales}</p>
              </div>
            ` : ''}

            ${confirmacionHTML}

            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e8f0f8; text-align: center;">
              <p style="color: #8a9aaa; font-size: 12px; margin: 0;">Este es un email automático de EzPayConnect.</p>
              <p style="color: #8a9aaa; font-size: 12px; margin: 5px 0 0 0;">Por favor no responda a este correo.</p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `;

    // Enviar email
    const { data, error } = await resend.emails.send({
      from: process.env.FROM_EMAIL || 'no-reply@ezpayconnect.com',
      to: [to],
      subject: `Receta Médica - ${pacienteNombre} - EzPayConnect`,
      html: html,
    });

    if (error) {
      console.error('Error enviando email:', error);
      return res.status(500).json({ error: 'Error al enviar email', details: error });
    }

    return res.status(200).json({ 
      success: true, 
      message: 'Receta enviada exitosamente',
      emailId: data?.id 
    });

  } catch (error) {
    console.error('Error en API:', error);
    return res.status(500).json({ error: 'Error interno del servidor' });
  }
}
