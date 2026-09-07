import { supabase } from '@/lib/supabase'
import { subirConProgreso } from './adjuntos'

// Tarjeta pública del asesor (D11): lectura de la ficha propia, consentimiento, rotación del token
// y foto.
//
// POR QUÉ ESTE ARCHIVO NO ES `api.ts`
// ------------------------------------
// `api.ts` lee la CARTERA: lo que la policy le deje ver al que consulta, que para un supervisor es
// su equipo entero. Acá el sujeto es siempre UNO —el asesor logueado— y las cuatro RPCs operan
// sobre `auth.uid()` sin tomar id. Mezclarlos haría que la misma capa devolviera a veces "lo mío" y
// a veces "lo de mi gente" según la función, que es la confusión que este módulo viene evitando.
//
// POR QUÉ ACÁ SÍ HAY UN `.eq('id', ...)` Y EN `api.ts` NO
// --------------------------------------------------------
// No es un permiso duplicado: es el mismo caso que `jornadaDeHoy`. La policy
// `asesores_perfil_select` le deja ver al supervisor las fichas de su equipo, y esta pantalla es
// **SU tarjeta**, no la de ellos. Sin el filtro, un supervisor abriría "Mi tarjeta" y vería la
// primera ficha que devuelva la consulta, que puede ser la de cualquiera de sus asesores. El `.eq`
// SELECCIONA CUÁL de las filas permitidas se muestra; sólo puede achicar lo que la policy ya
// concedió.

/** Columnas de tarjeta. El token es una credencial: no se pide si no se va a mostrar. */
const COLS_TARJETA =
  'id,codigo_asesor,tarjeta_token,tarjeta_publica,tarjeta_consentimiento_at,tarjeta_token_rotado_at,foto_publica_path,activo'

export type FichaTarjeta = {
  id: string
  codigo_asesor: string
  tarjeta_token: string
  tarjeta_publica: boolean
  tarjeta_consentimiento_at: string | null
  tarjeta_token_rotado_at: string | null
  foto_publica_path: string | null
  activo: boolean
}

/**
 * La ficha del asesor logueado. Devuelve `data: null` sin consultar si todavía no hay id —el perfil
 * llega asincrónico— para no disparar una consulta sin filtro que traería fichas ajenas.
 */
export async function miFichaTarjeta(asesorId: string | null | undefined) {
  if (!asesorId) return { data: null, error: null }
  return supabase.from('asesores_perfil').select(COLS_TARJETA)
    .eq('id', asesorId).maybeSingle()
}

/** Encender o apagar el consentimiento. Opera sobre auth.uid(): no toma id de asesor. */
export async function tarjetaSetConsentimiento(activo: boolean) {
  return supabase.rpc('tarjeta_set_consentimiento', { p_activo: activo })
}

/**
 * Rotar el token. Devuelve `void`: el token nuevo NO viene en la respuesta, así que quien llama
 * tiene que recargar la ficha. Es a propósito —la RPC no devuelve credenciales— y por eso está
 * escrito acá, donde se ve.
 */
export async function tarjetaRotarToken() {
  return supabase.rpc('tarjeta_rotar_token')
}

/** Registrar (o borrar, con `null`) el path de la foto. */
export async function guardarFotoPublica(path: string | null) {
  return supabase.rpc('guardar_foto_publica_asesor', { p_path: path })
}

// ============================================================================================
// Foto
// ============================================================================================

// Replican la config del BUCKET `tarjetas-asesor` (mig 289), que es la autoridad real y no se puede
// leer desde el cliente (`storage.buckets` no es legible por `authenticated`). Misma decisión que
// en adjuntos.ts y material.ts: UNA sola fuente para el `accept` del input y para la validación.
//
// SIN SVG, y no por olvido: un SVG es código y esta imagen la sirve nuestra edge desde nuestro
// dominio. El bucket también lo rechaza.
export const MAX_BYTES_FOTO = 2 * 1024 * 1024 // 2 MB — mig 289
export const MIME_FOTO = ['image/jpeg', 'image/png', 'image/webp'] as const
export const ACCEPT_FOTO = MIME_FOTO.join(',')

const MB = (n: number) => `${(n / 1024 / 1024).toFixed(1)} MB`

/** Validación local: cortesía cara, no control. El bucket impone las dos cosas igual. */
export function validarFoto(a: File): string | null {
  if (!(MIME_FOTO as readonly string[]).includes(a.type)) {
    return `Ese tipo de archivo no se puede usar como foto (${a.type || 'desconocido'}). `
      + 'Se aceptan JPG, PNG y WebP.'
  }
  if (a.size > MAX_BYTES_FOTO) {
    return `La foto pesa ${MB(a.size)} y el máximo es ${MB(MAX_BYTES_FOTO)}. `
      + 'Sacale una con menos resolución o recortala.'
  }
  return null
}

/**
 * El path que valida PA032: segmento 1 = el propio id, segmento 2 = el archivo.
 *
 * UUID NUEVO EN CADA SUBIDA, no un nombre fijo tipo `foto.jpg`. Con nombre fijo, cambiar la foto
 * dejaría la misma URL y habría que pelearse con todas las cachés del camino para que el cambio se
 * vea; con uuid, el path viejo simplemente deja de estar referenciado.
 */
export function pathDeFoto(asesorId: string, archivo: File): string {
  const ext = (archivo.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '')
  return `${asesorId}/${crypto.randomUUID()}.${ext || 'bin'}`
}

/**
 * ORDEN: SUBIR PRIMERO, REGISTRAR DESPUÉS, y si el registro falla BORRAR el objeto en el mismo
 * catch. Mismo criterio que `subirAdjuntoVisita`: el orden inverso deja la ficha apuntando a un
 * objeto inexistente, y eso la edge lo sirve como 404 — la tarjeta quedaría sin foto y con un path
 * guardado que nadie sabe que está roto. Un huérfano en el bucket, en cambio, no se ve en ningún
 * lado; por eso se limpia acá, porque nadie más lo va a hacer.
 *
 * El DELETE lo habilita `tarjeta_foto_owner_delete` (mig 289), acotada al propio prefijo.
 */
export async function subirFotoPublica(
  asesorId: string, archivo: File, onProgreso: (pct: number) => void,
): Promise<{ error: unknown | null; huerfano?: string; path?: string }> {
  const path = pathDeFoto(asesorId, archivo)

  const up = await subirConProgreso('tarjetas-asesor', path, archivo, onProgreso)
  if (up.error) return { error: up.error }

  const reg = await guardarFotoPublica(path)
  if (reg.error) {
    // Si el borrado también falla se devuelve el path: un huérfano conocido es deuda, uno
    // silencioso es basura que nadie va a encontrar.
    const del = await supabase.storage.from('tarjetas-asesor').remove([path])
    return { error: reg.error, huerfano: del.error ? path : undefined }
  }
  return { error: null, path }
}

/**
 * URL firmada para que el asesor vea SU foto en esta pantalla. El bucket es privado y la policy
 * `tarjeta_foto_owner_select` sólo le deja leer su propio prefijo.
 *
 * TTL = 300 s, y la misma regla que en adjuntos.ts: una URL firmada es un BEARER, así que se pide
 * en el momento, vive sólo en el estado de React y NO va a localStorage, ni a sessionStorage, ni a
 * la URL de la página.
 *
 * OJO — ESTA NO ES LA URL PÚBLICA DE LA TARJETA. La que ve el prospecto es `/t/<token>?formato=foto`
 * y la sirve la edge bajo el gate del consentimiento. Ésta es sólo para la vista previa del dueño:
 * si se filtrara, expone la foto por 5 minutos y no la tarjeta.
 */
export const TTL_FIRMA_FOTO_S = 300

export async function urlFirmadaFoto(path: string) {
  return supabase.storage.from('tarjetas-asesor').createSignedUrl(path, TTL_FIRMA_FOTO_S)
}

/**
 * La URL pública de la tarjeta. Se arma con el origin del navegador y no con una constante: en
 * preview de Vercel el dominio es otro, y un link copiado que apunte a producción desde un preview
 * es peor que uno que no funcione, porque parece que anduvo.
 */
export function urlPublicaTarjeta(token: string): string {
  const origen = typeof window !== 'undefined' ? window.location.origin : ''
  return `${origen}/t/${encodeURIComponent(token)}`
}
