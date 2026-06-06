import { supabase } from '@/lib/supabase'

const FUNCTION_URL_EMAIL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/notificar-email`
const FUNCTION_URL_NOTIF = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/enviar-notificacion`

async function getAuthHeaders() {
  const { data } = await supabase.auth.getSession()
  return {
    'Authorization': `Bearer ${data.session?.access_token || ''}`,
    'Content-Type': 'application/json',
  }
}

export async function crearNotificacionInApp(params: {
  usuario_id: string
  tipo: string
  titulo: string
  mensaje: string
  accion_url?: string
  metadata?: Record<string, any>
}): Promise<boolean> {
  try {
    const res = await fetch(FUNCTION_URL_NOTIF, {
      method: 'POST',
      headers: await getAuthHeaders(),
      body: JSON.stringify(params),
    })

    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      console.error('[crearNotificacionInApp] Error:', err)
      return false
    }

    return true
  } catch (err) {
    console.error('[crearNotificacionInApp] Excepción:', err)
    return false
  }
}

export async function enviarEmail(params: {
  to: string
  subject: string
  html: string
  tipo?: string
}): Promise<boolean> {
  try {
    const res = await fetch(FUNCTION_URL_EMAIL, {
      method: 'POST',
      headers: await getAuthHeaders(),
      body: JSON.stringify(params),
    })

    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      console.error('[enviarEmail] Error:', err)
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
