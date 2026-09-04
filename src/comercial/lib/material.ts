import { supabase } from '@/lib/supabase'
import { subirConProgreso } from './adjuntos'

// Material comercial: constantes, validación, subida y firma.
//
// POR QUÉ ESTO NO ES `adjuntos.ts` CON UN PARÁMETRO
// --------------------------------------------------
// Lo único que comparten es el TRANSPORTE —`subirConProgreso`, que es XHR contra la API REST de
// storage y no sabe nada de reglas—. Todo lo demás es distinto y tiene que poder cambiar por
// separado:
//   * la lista de mime: acá entra PDF, en evidencia de visita NO;
//   * la forma del path: {pais_id}/... contra {pais_id}/{visita_id}/...;
//   * quién puede subir: admin de país contra el asesor dueño de la visita.
// Una función común con banderitas terminaría decidiendo las dos reglas en el mismo `if`, y el día
// que una cambie habría que acordarse de la otra.
export const MAX_BYTES_MATERIAL = 50 * 1024 * 1024 // 50 MB — D6
export const MIME_MATERIAL = [
  'image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime', 'application/pdf',
] as const
export const ACCEPT_MATERIAL = MIME_MATERIAL.join(',')

const MB = (n: number) => `${(n / 1024 / 1024).toFixed(1)} MB`

/** Validación local: cortesía cara, no control. El bucket impone las dos cosas igual. */
export function validarMaterial(a: File): string | null {
  if (!(MIME_MATERIAL as readonly string[]).includes(a.type)) {
    return `Ese tipo de archivo no se puede subir (${a.type || 'desconocido'}). `
      + 'Se aceptan PDF, fotos JPG/PNG/WebP y videos MP4/MOV.'
  }
  if (a.size > MAX_BYTES_MATERIAL) {
    return `El archivo pesa ${MB(a.size)} y el máximo es ${MB(MAX_BYTES_MATERIAL)}.`
  }
  return null
}

/** El path que valida la RPC: segmento 1 = país. No lleva segmento de visita — es otra regla. */
export function pathDeMaterial(paisId: string, archivo: File): string {
  const ext = (archivo.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '')
  return `${paisId}/${crypto.randomUUID()}.${ext || 'bin'}`
}

export type Material = {
  id: string
  pais_id: string
  titulo: string
  descripcion: string | null
  storage_path: string
  mime: string | null
  bytes: number | null
  activo: boolean
  created_at: string
}

const COLS_MATERIAL = 'id,pais_id,titulo,descripcion,storage_path,mime,bytes,activo,created_at'

/**
 * Sin filtro de país ni de `activo` en el cliente: los pone la policy (mig 278). El admin del país
 * ve todo —necesita ver lo desactivado para reactivarlo— y el resto ve sólo lo activo.
 * El `.eq('pais_id')` de la pantalla de admin es un selector de vista, igual que en prospectos.
 */
export async function listarMaterial() {
  return supabase.from('material_comercial').select(COLS_MATERIAL).order('created_at', { ascending: false })
}

export async function listarMaterialDePais(paisId: string) {
  return supabase.from('material_comercial').select(COLS_MATERIAL)
    .eq('pais_id', paisId).order('created_at', { ascending: false })
}

/** Sube y registra. Mismo orden y misma compensación que los adjuntos, por la misma razón. */
export async function subirMaterial(
  p: { paisId: string; titulo: string; descripcion?: string | null },
  archivo: File, onProgreso: (pct: number) => void,
): Promise<{ error: unknown | null; huerfano?: string }> {
  const path = pathDeMaterial(p.paisId, archivo)

  const up = await subirConProgreso('material-comercial', path, archivo, onProgreso)
  if (up.error) return { error: up.error }

  const reg = await supabase.rpc('guardar_material_comercial', {
    p_titulo: p.titulo, p_pais_id: p.paisId, p_storage_path: path,
    p_descripcion: p.descripcion ?? null, p_mime: archivo.type || null, p_bytes: archivo.size,
  })
  if (reg.error) {
    // OJO: el bucket `material-comercial` NO tiene policy de DELETE (la 276 sólo agregó una para
    // `visitas-comerciales`, acotada a huérfanos). Así que este intento puede no prosperar, y por
    // eso se devuelve el path: un huérfano conocido es deuda, uno silencioso es basura.
    const del = await supabase.storage.from('material-comercial').remove([path])
    return { error: reg.error, huerfano: del.error ? path : undefined }
  }
  return { error: null }
}

export async function activarMaterial(id: string, activo: boolean) {
  return supabase.rpc('activar_material_comercial', { p_material_id: id, p_activo: activo })
}

/** Mismo TTL y misma regla que los adjuntos: se pide al hacer clic y no se persiste en ningún lado. */
export const TTL_FIRMA_MATERIAL_S = 300

export async function urlFirmadaMaterial(path: string) {
  return supabase.storage.from('material-comercial').createSignedUrl(path, TTL_FIRMA_MATERIAL_S)
}
