import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';
import type { VercelRequest, VercelResponse } from '@vercel/node';

// Roles clínicos/administrativos autorizados a enviar facturas por email (cierra el open-relay).
const ROLES_AUTORIZADOS = ['medico', 'super_admin', 'admin_clinica', 'gerente', 'secretaria', 'contador'];

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // TODO el cuerpo va dentro del try: cualquier rechazo async debe salir como JSON legible,
  // NUNCA como el 500 opaco genérico de Vercel. (Mismo patrón que api/send-receta.ts.)
  try {
    // --- Autenticación + rol. Fail-closed. ---
    const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
    const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY;
    if (!supabaseUrl || !supabaseAnonKey) {
      console.error('[send-factura] faltan SUPABASE_URL/SUPABASE_ANON_KEY en env');
      return res.status(500).json({ error: 'Autenticación no configurada' });
    }
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({ error: 'No autenticado' });
    }
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const userResult = await supabase.auth.getUser().catch((e: any) => {
      console.error('[send-factura] getUser lanzó:', e?.message ?? e);
      return null;
    });
    if (!userResult) {
      return res.status(500).json({ error: 'No se pudo verificar el usuario' });
    }
    const { data: { user }, error: authError } = userResult;
    if (authError || !user) {
      console.error('[send-factura] getUser sin usuario:', authError?.message ?? authError);
      return res.status(401).json({ error: 'No se pudo verificar el usuario' });
    }

    const { data: perfil, error: perfilError } = await supabase
      .from('perfiles').select('rol').eq('id', user.id).maybeSingle();
    if (perfilError) {
      console.error('[send-factura] error consultando perfil:', perfilError?.message ?? perfilError);
      return res.status(500).json({ error: 'No se pudo consultar el perfil' });
    }
    if (!perfil || !ROLES_AUTORIZADOS.includes(perfil.rol)) {
      return res.status(403).json({ error: 'No autorizado para enviar facturas' });
    }

    const {
      to, facturaId, pacienteNombre, medicoNombre,
      concepto, cantidad, precioUnitario, descuento, total,
      moneda, fecha, estado, metodoPago, notas,
    } = req.body;

    if (!to || !pacienteNombre || !concepto || total == null) {
      return res.status(400).json({ error: 'Faltan datos requeridos' });
    }

    const sim = moneda || 'Q';
    const n = (v: any) => Number(v || 0).toFixed(2);
    const cant = Number(cantidad || 1);
    const precio = Number(precioUnitario || 0);
    const desc = Number(descuento || 0);
    const subtotal = cant * precio;
    const fechaTxt = fecha
      ? new Date(fecha).toLocaleDateString('es-GT', { year: 'numeric', month: 'long', day: 'numeric' })
      : new Date().toLocaleDateString('es-GT', { year: 'numeric', month: 'long', day: 'numeric' });

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Factura - EzPayConnect</title>
      </head>
      <body style="margin: 0; padding: 0; font-family: Arial, sans-serif; background: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background: white;">
          <div style="background: linear-gradient(135deg, #1E5C8E, #3A8ABF); padding: 30px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px;">EzPayConnect</h1>
            <p style="color: rgba(255,255,255,0.8); margin: 5px 0 0 0; font-size: 14px;">Software Médico</p>
          </div>

          <div style="padding: 30px;">
            <h2 style="color: #1a2a3a; margin: 0 0 20px 0;">Factura${facturaId ? ' #' + facturaId : ''}</h2>

            <div style="background: #e8f0f8; padding: 15px; border-radius: 8px; margin-bottom: 20px;">
              <p style="margin: 0; color: #1a2a3a;"><strong>Paciente:</strong> ${pacienteNombre}</p>
              ${medicoNombre ? `<p style="margin: 5px 0 0 0; color: #8a9aaa; font-size: 13px;"><strong>Médico:</strong> ${medicoNombre}</p>` : ''}
              <p style="margin: 5px 0 0 0; color: #8a9aaa; font-size: 13px;"><strong>Fecha:</strong> ${fechaTxt}</p>
              ${estado ? `<p style="margin: 5px 0 0 0; color: #8a9aaa; font-size: 13px;"><strong>Estado:</strong> ${estado}</p>` : ''}
              ${metodoPago ? `<p style="margin: 5px 0 0 0; color: #8a9aaa; font-size: 13px;"><strong>Método de pago:</strong> ${metodoPago}</p>` : ''}
            </div>

            <table style="width: 100%; border-collapse: collapse; margin: 20px 0;">
              <thead>
                <tr style="background: #1E5C8E; color: white;">
                  <th style="padding: 12px; text-align: left;">Concepto</th>
                  <th style="padding: 12px; text-align: center;">Cantidad</th>
                  <th style="padding: 12px; text-align: right;">Precio Unit.</th>
                  <th style="padding: 12px; text-align: right;">Total</th>
                </tr>
              </thead>
              <tbody>
                <tr style="border-bottom: 1px solid #e8f0f8;">
                  <td style="padding: 12px; color: #1a2a3a;">${concepto}</td>
                  <td style="padding: 12px; text-align: center; color: #1a2a3a;">${cant}</td>
                  <td style="padding: 12px; text-align: right; color: #1a2a3a;">${sim}${n(precio)}</td>
                  <td style="padding: 12px; text-align: right; color: #1a2a3a;">${sim}${n(subtotal)}</td>
                </tr>
              </tbody>
            </table>

            <div style="border-top: 1px solid #e8f0f8; padding-top: 15px;">
              <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
                <span style="color: #8a9aaa;">Subtotal:</span>
                <span style="color: #1a2a3a;">${sim}${n(subtotal)}</span>
              </div>
              ${desc > 0 ? `<div style="display: flex; justify-content: space-between; margin-bottom: 6px;"><span style="color: #8a9aaa;">Descuento:</span><span style="color: #ef4444;">-${sim}${n(desc)}</span></div>` : ''}
              <div style="display: flex; justify-content: space-between; border-top: 1px solid #e8f0f8; padding-top: 10px; margin-top: 6px;">
                <span style="font-weight: bold; color: #1E5C8E; font-size: 18px;">TOTAL:</span>
                <span style="font-weight: bold; color: #1E5C8E; font-size: 18px;">${sim}${n(total)}</span>
              </div>
            </div>

            ${notas ? `
              <div style="margin-top: 25px; padding: 15px; background: #f5f5f5; border-radius: 4px;">
                <h4 style="color: #1a2a3a; margin: 0 0 8px 0; font-size: 14px;">Notas</h4>
                <p style="margin: 0; color: #8a9aaa; font-size: 14px;">${notas}</p>
              </div>
            ` : ''}

            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e8f0f8; text-align: center;">
              <p style="color: #8a9aaa; font-size: 12px; margin: 0;">Este es un email automático de EzPayConnect.</p>
              <p style="color: #8a9aaa; font-size: 12px; margin: 5px 0 0 0;">Por favor no responda a este correo.</p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `;

    const resend = new Resend(process.env.RESEND_API_KEY);
    const { data, error } = await resend.emails.send({
      from: process.env.FROM_EMAIL || 'no-reply@ezpayconnect.com',
      to: [to],
      subject: `Factura${facturaId ? ' #' + facturaId : ''} - ${pacienteNombre} - EzPayConnect`,
      html,
    });

    if (error) {
      console.error('Error enviando factura por email:', error?.name, (error as any)?.statusCode);
      return res.status(500).json({ error: 'Error al enviar email', details: error });
    }

    return res.status(200).json({
      success: true,
      message: 'Factura enviada exitosamente',
      emailId: data?.id,
    });

  } catch (error) {
    console.error('[send-factura] error no controlado:', error);
    return res.status(500).json({ error: 'Error interno del servidor' });
  }
}
