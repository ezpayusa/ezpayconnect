import { supabase } from '@/lib/supabase'

// crearNotificacionInApp eliminado (CIERRE FINAL push-tx, bloque 3): helper muerto que invocaba la edge
// enviar-notificacion (ahora stub-410). Las notifs de campañas/pagos/visitas van por RPCs DEFINER gateados.

export async function enviarEmail(params: {
  to: string
  subject: string
  html: string
  tipo?: string
}): Promise<boolean> {
  try {
    const { error } = await supabase.functions.invoke('notificar-email', {
      body: params,
    })

    if (error) {
      console.error('[enviarEmail] Error:', error)
      return false
    }

    return true
  } catch (err) {
    console.error('[enviarEmail] Excepción:', err)
    return false
  }
}

export function buildHtmlVisitaPropuesta(props: {
  medicoNombre: string
  visitadorNombre: string
  fecha: string
  hora: string
  tipo: string
  notas?: string | null
}): string {
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#1E5C8E;margin-top:0;">Nueva visita propuesta</h2>
      <p><strong>Visitador:</strong> ${props.visitadorNombre}</p>
      <p><strong>Médico:</strong> ${props.medicoNombre}</p>
      <p><strong>Fecha:</strong> ${props.fecha}</p>
      <p><strong>Hora:</strong> ${props.hora}</p>
      <p><strong>Tipo:</strong> ${props.tipo}</p>
      ${props.notas ? `<p><strong>Notas:</strong> ${props.notas}</p>` : ''}
      <div style="margin-top:24px;text-align:center;">
        <a href="${import.meta.env.VITE_APP_URL || ''}/proveedor/visitador/admin-aprobar" 
           style="background:#1E5C8E;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;display:inline-block;">
          Revisar visitas
        </a>
      </div>
    </div>
  `
}

export function buildHtmlVisitaAprobada(props: {
  medicoNombre: string
  fecha: string
  hora: string
  comentario?: string | null
}): string {
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#16a34a;margin-top:0;">Visita aprobada ✅</h2>
      <p>Tu visita con <strong>${props.medicoNombre}</strong> fue confirmada.</p>
      <p><strong>Fecha:</strong> ${props.fecha}</p>
      <p><strong>Hora:</strong> ${props.hora}</p>
      ${props.comentario ? `<p><strong>Comentario del admin:</strong> ${props.comentario}</p>` : ''}
    </div>
  `
}

export function buildHtmlVisitaRechazada(props: {
  medicoNombre: string
  fecha: string
  comentario?: string | null
}): string {
  return `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
      <h2 style="color:#dc2626;margin-top:0;">Visita rechazada ❌</h2>
      <p>Tu visita con <strong>${props.medicoNombre}</strong> no fue aprobada.</p>
      <p><strong>Fecha propuesta:</strong> ${props.fecha}</p>
      ${props.comentario ? `<p><strong>Motivo:</strong> ${props.comentario}</p>` : ''}
    </div>
  `
}
