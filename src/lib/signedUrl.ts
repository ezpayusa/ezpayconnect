import { supabase } from '@/lib/supabase'

/**
 * Extrae el path del objeto desde una URL pública almacenada (o devuelve el path
 * tal cual si ya es un path). Soporta filas viejas que guardaron la URL pública.
 */
export function extractPath(bucket: string, stored: string): string {
  const marker = `/${bucket}/`
  const i = stored.indexOf(marker)
  return i !== -1 ? stored.slice(i + marker.length) : stored
}

/**
 * Genera una signed URL para un objeto de un bucket PRIVADO y la abre/descarga.
 * La firma la hace el cliente con `createSignedUrl`, que EXIGE permiso SELECT sobre
 * el objeto vía la RLS de storage.objects → un usuario sin derecho no puede firmar.
 * TTL corto (120 s). Si el usuario no tiene acceso, avisa y no abre nada.
 */
export async function openSignedUrl(
  bucket: string,
  stored: string | null,
  opts?: { download?: boolean }
): Promise<void> {
  if (!stored) return
  const path = extractPath(bucket, stored)
  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(path, 120, opts?.download ? { download: true } : undefined)
  if (error || !data?.signedUrl) {
    console.error('No se pudo firmar la URL:', error?.message)
    alert('No tienes acceso a este archivo o no se pudo generar el enlace.')
    return
  }
  window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
}

// ############################################################################################
// VISOR: firmar → bajar los bytes UNA vez → mostrar desde blob:
// ############################################################################################
// `openSignedUrl` de arriba abre la URL firmada en una pestaña nueva: el bearer queda en la barra de
// direcciones y en el historial, y a los 120 s la pestaña deja de poder pedir nada — un PDF grande
// lo nota al hacer scroll, porque el visor nativo baja las páginas por range requests.
//
// Acá la URL firmada vive SOLO en una variable local de `obtenerBlob`: se usa para un único fetch y se
// descarta. Nunca llega al estado de React, ni al DOM, ni a localStorage, ni a la URL de la página.
// Lo que se muestra es un `blob:` de ESTA pestaña, que el visor revoca al cerrar o cambiar de archivo.
//
// TTL = 60 s: sólo tiene que cubrir el INICIO de la descarga, no la inspección. Una vez que los bytes
// están en memoria, zoom, pan y rotación no vuelven a pedir nada.
//
// CORS medido el 15-sep contra storage (/object/sign/…): GET 200 con Access-Control-Allow-Origin: *,
// desde med.ezpayconnect.com y desde un origen de preview. Los ERRORES también traen ACAO: * (400
// InvalidJWT), así que el fetch puede leer status y cuerpo y distinguir "firma vencida" de "red".
// No se manda `credentials`: con ACAO: * el navegador rechaza credenciales, y la firma ya autoriza.
export const TTL_VISOR_S = 60

export type MotivoFalla = 'sin_acceso' | 'no_existe' | 'red' | 'desconocido'
export type ResultadoBlob =
  | { ok: true; blob: Blob }
  | { ok: false; motivo: MotivoFalla; detalle: string }

async function firmar(bucket: string, path: string): Promise<{ url: string } | { error: string }> {
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, TTL_VISOR_S)
  if (error || !data?.signedUrl) return { error: error?.message ?? 'sin url' }
  return { url: data.signedUrl }
}

/**
 * Firma y baja el archivo. Si la firma venció entre firmar y bajar (400 InvalidJWT, p. ej. una red
 * muy lenta), vuelve a firmar UNA vez. `createSignedUrl` exige SELECT sobre el objeto vía la RLS de
 * storage.objects: si no firma, es "sin acceso" y no se reintenta.
 */
export async function obtenerBlob(bucket: string, stored: string, signal?: AbortSignal): Promise<ResultadoBlob> {
  const path = extractPath(bucket, stored)
  for (let intento = 0; intento < 2; intento++) {
    const f = await firmar(bucket, path)
    if ('error' in f) return { ok: false, motivo: 'sin_acceso', detalle: f.error }
    let resp: Response
    try {
      resp = await fetch(f.url, { signal })
    } catch (e) {
      if ((e as Error)?.name === 'AbortError') throw e
      return { ok: false, motivo: 'red', detalle: (e as Error)?.message ?? 'fetch falló' }
    }
    if (resp.ok) return { ok: true, blob: await resp.blob() }
    const cuerpo = await resp.text().catch(() => '')
    if (resp.status === 400 && /InvalidJWT|expired/i.test(cuerpo) && intento === 0) continue
    if (resp.status === 404 || /not.?found/i.test(cuerpo)) return { ok: false, motivo: 'no_existe', detalle: cuerpo.slice(0, 200) }
    if (resp.status === 401 || resp.status === 403) return { ok: false, motivo: 'sin_acceso', detalle: cuerpo.slice(0, 200) }
    return { ok: false, motivo: 'desconocido', detalle: `HTTP ${resp.status} ${cuerpo.slice(0, 200)}` }
  }
  return { ok: false, motivo: 'desconocido', detalle: 'la firma venció dos veces seguidas' }
}

/** Nombre de archivo para la descarga: el último segmento del path. */
export function nombreDeArchivo(bucket: string, stored: string): string {
  const path = extractPath(bucket, stored)
  return path.split('/').pop() || 'archivo'
}

/**
 * Guarda un blob como archivo SIN que el bearer toque la URL: un <a download> apuntando al `blob:`
 * local, que se revoca apenas se dispara. El `?download=` de storage abriría la URL firmada en otra
 * pestaña, que es justo lo que este módulo evita.
 */
export function guardarBlob(blob: Blob, nombre: string): void {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nombre
  a.rel = 'noopener'
  document.body.appendChild(a)
  a.click()
  a.remove()
  // Diferido: revocar en el mismo tick puede cancelar la descarga en algunos navegadores.
  setTimeout(() => URL.revokeObjectURL(url), 30_000)
}

/** Descargar desde un botón que no tiene el blob a mano (el "Descargar" al lado de "Ver archivo"). */
export async function descargarArchivo(bucket: string, stored: string | null): Promise<ResultadoBlob | null> {
  if (!stored) return null
  const r = await obtenerBlob(bucket, stored)
  if (r.ok) guardarBlob(r.blob, nombreDeArchivo(bucket, stored))
  return r
}

// "sin_acceso" cubre también "no existe" A PROPÓSITO. Medido el 15-sep: firmar un objeto inexistente y
// firmar uno existente sin permiso devuelven la MISMA respuesta (400, NoSuchKey, "Object not found").
// Storage esconde la existencia detrás de la RLS —y está bien que lo haga—, así que el cliente no
// puede distinguirlos y el mensaje no debe fingir que sí.
export const MENSAJE_FALLA: Record<MotivoFalla, string> = {
  sin_acceso: 'No tienes acceso a este archivo o ya no está disponible.',
  // Sólo llega acá si el objeto desapareció ENTRE firmar y bajar (la firma sí se emitió).
  no_existe: 'El archivo ya no está disponible.',
  red: 'No se pudo descargar el archivo. Revisa tu conexión e intenta de nuevo.',
  desconocido: 'No se pudo abrir el archivo.',
}
