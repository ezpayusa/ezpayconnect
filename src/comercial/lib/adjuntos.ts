import { supabase } from '@/lib/supabase'

// Adjuntos de visita: constantes, validación local, subida con progreso y limpieza del huérfano.
//
// FUENTE ÚNICA DE LAS CONSTANTES
// -------------------------------
// El `accept` del input y la validación previa salen de las MISMAS dos constantes de acá. Escribir
// la lista de mime en el input y otra vez en el if es la forma más barata de que un día acepten
// cosas distintas — y el usuario descubra la diferencia después de subir 40 MB.
//
// Estos valores replican la config del BUCKET (mig 274), que es la autoridad real. No se pueden
// leer desde el cliente: `storage.buckets` no es legible por `authenticated` (medido). Para que la
// duplicación no se pudra en silencio, el harness tiene una probe que PINEA la config del bucket
// contra estos mismos números: si alguien cambia el bucket, el harness se pone rojo y apunta acá.
export const MAX_BYTES_ADJUNTO = 50 * 1024 * 1024 // 50 MB — D6
export const MIME_ADJUNTO = [
  'image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime',
] as const

/** Para el atributo `accept` del <input type="file">. Misma lista, sin copiarla. */
export const ACCEPT_ADJUNTO = MIME_ADJUNTO.join(',')

const MB = (n: number) => `${(n / 1024 / 1024).toFixed(1)} MB`

/**
 * Validación en el CLIENTE. No es un control —el bucket ya impone las dos cosas— sino cortesía
 * cara: un asesor en datos móviles que sube 40 MB durante tres minutos para que lo rechacen al
 * final va a odiar el módulo. Devuelve el motivo, o null si el archivo sirve.
 */
export function validarAdjunto(a: File): string | null {
  if (!(MIME_ADJUNTO as readonly string[]).includes(a.type)) {
    return `Ese tipo de archivo no se puede subir (${a.type || 'desconocido'}). `
      + 'Se aceptan fotos JPG/PNG/WebP y videos MP4/MOV.'
  }
  if (a.size > MAX_BYTES_ADJUNTO) {
    return `El archivo pesa ${MB(a.size)} y el máximo es ${MB(MAX_BYTES_ADJUNTO)}. `
      + 'Grabá el video más corto o bajá la calidad.'
  }
  return null
}

/** El path que valida PA023: segmento 1 = país de la visita, segmento 2 = la visita. */
export function pathDeAdjunto(v: { id: string; pais_id: string }, archivo: File): string {
  const ext = (archivo.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '')
  return `${v.pais_id}/${v.id}/${crypto.randomUUID()}.${ext || 'bin'}`
}

const SUPABASE_URL = 'https://fqnsmvkxsuujahhmpzuk.supabase.co'

/**
 * Sube con PROGRESO REAL. `supabase.storage.upload()` no expone progreso, así que se va por la API
 * REST de storage con XHR, que sí tiene `onprogress`. Una subida de 50 MB en 3G tarda minutos: sin
 * progreso el usuario no sabe si está pasando algo y cancela.
 *
 * Si se corta, rechaza con `{ status: 0 }`, que el mapa de errores ya conoce como
 * "se cortó la subida, no quedó nada guardado".
 */
export function subirConProgreso(
  bucket: string, path: string, archivo: File, onProgreso: (pct: number) => void,
): Promise<{ error: { status: number; message: string } | null }> {
  return new Promise(async (resolve) => {
    const { data: sesion } = await supabase.auth.getSession()
    const token = sesion.session?.access_token
    if (!token) { resolve({ error: { status: 401, message: 'sin sesión' } }); return }

    const xhr = new XMLHttpRequest()
    xhr.open('POST', `${SUPABASE_URL}/storage/v1/object/${bucket}/${path}`, true)
    xhr.setRequestHeader('Authorization', `Bearer ${token}`)
    xhr.setRequestHeader('x-upsert', 'false')
    if (archivo.type) xhr.setRequestHeader('Content-Type', archivo.type)
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) onProgreso(Math.round((e.loaded / e.total) * 100))
    }
    xhr.onload = () =>
      resolve(xhr.status >= 200 && xhr.status < 300
        ? { error: null }
        : { error: { status: xhr.status, message: xhr.responseText?.slice(0, 300) || 'error de storage' } })
    // Corte de red y cancelación entran por acá: status 0.
    xhr.onerror = () => resolve({ error: { status: 0, message: 'se cortó la conexión' } })
    xhr.onabort = () => resolve({ error: { status: 0, message: 'subida cancelada' } })
    xhr.send(archivo)
  })
}

/**
 * ORDEN: SUBIR PRIMERO, REGISTRAR DESPUÉS, y si el registro falla BORRAR el objeto en el mismo
 * catch. El orden inverso —registrar y después subir— deja una FILA FANTASMA apuntando a un objeto
 * que no existe: peor, porque la UI la renderiza como un adjunto y parece pérdida de datos.
 * Un huérfano en el bucket, en cambio, no se ve en ningún lado — y por eso hay que limpiarlo acá,
 * porque nadie más lo va a hacer.
 *
 * El DELETE lo habilita la mig 276, acotado a objetos NO registrados: se puede limpiar lo que
 * nunca llegó a ser evidencia y es imposible borrar lo que sí.
 */
export async function subirAdjuntoVisita(
  v: { id: string; pais_id: string }, archivo: File, onProgreso: (pct: number) => void,
): Promise<{ error: unknown | null; huerfano?: string }> {
  const path = pathDeAdjunto(v, archivo)

  const up = await subirConProgreso('visitas-comerciales', path, archivo, onProgreso)
  if (up.error) return { error: up.error }

  const reg = await supabase.rpc('registrar_adjunto_visita', {
    p_visita_id: v.id, p_storage_path: path,
    p_mime: archivo.type || null, p_bytes: archivo.size,
  })
  if (reg.error) {
    // COMPENSACIÓN. Si el borrado también falla, se devuelve el path para que la UI pueda decirlo:
    // un huérfano conocido es deuda; uno silencioso es basura que nadie va a encontrar.
    const del = await supabase.storage.from('visitas-comerciales').remove([path])
    return { error: reg.error, huerfano: del.error ? path : undefined }
  }
  return { error: null }
}

/**
 * URL firmada para ver un adjunto. El bucket es privado, así que no hay otra forma.
 *
 * TTL = 300 s (5 minutos). Una URL firmada es un BEARER: quien la tenga lee el objeto sin importar
 * su rol. Cinco minutos alcanzan para abrir un video de 50 MB en una conexión mala y dejan poco
 * margen si el link se filtra. Se pide EN EL MOMENTO del clic y sólo vive en el estado de React:
 * no va a localStorage, ni a sessionStorage, ni a la URL de la página. Al cerrar sesión el
 * componente se desmonta y ese estado desaparece con él.
 * Lo que sí puede quedar en el caché del navegador son los BYTES ya descargados, como con
 * cualquier archivo abierto — pero la capacidad de volver a pedirlo muere con el TTL.
 */
export const TTL_FIRMA_S = 300

export async function urlFirmada(path: string) {
  return supabase.storage.from('visitas-comerciales').createSignedUrl(path, TTL_FIRMA_S)
}
