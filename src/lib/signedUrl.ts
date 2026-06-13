import { supabase } from '@/lib/supabase'

/**
 * Extrae el path del objeto desde una URL pública almacenada (o devuelve el path
 * tal cual si ya es un path). Soporta filas viejas que guardaron la URL pública.
 */
function extractPath(bucket: string, stored: string): string {
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
