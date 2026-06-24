// Utilidades de imagen para la evidencia: validación de tipo/peso (no confiar en `accept`)
// y compresión a un tamaño ACOTADO antes de subir (una foto de cámara puede pesar varios MB).

const RAW_MAX_BYTES = 20 * 1024 * 1024 // tope duro para no cargar en memoria un archivo gigante

/** Valida tipo y peso ANTES de procesar. Devuelve mensaje de error o null si está OK. */
export function validarImagen(file: File): string | null {
  if (!file.type.startsWith('image/')) return 'El archivo no es una imagen.'
  if (file.size > RAW_MAX_BYTES) return 'La imagen es demasiado grande (máx 20 MB).'
  return null
}

/**
 * Reescala la imagen a `maxDim` (lado mayor) y la re-codifica a JPEG `quality`.
 * Garantiza un Blob acotado (~200–500 KB típico) en vez del original de varios MB.
 */
export async function comprimirImagen(file: File, maxDim = 1600, quality = 0.8): Promise<Blob> {
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const fr = new FileReader()
    fr.onload = () => resolve(fr.result as string)
    fr.onerror = () => reject(new Error('No se pudo leer la imagen.'))
    fr.readAsDataURL(file)
  })
  const img = await new Promise<HTMLImageElement>((resolve, reject) => {
    const im = new Image()
    im.onload = () => resolve(im)
    im.onerror = () => reject(new Error('No se pudo procesar la imagen.'))
    im.src = dataUrl
  })
  const scale = Math.min(1, maxDim / Math.max(img.width, img.height))
  const w = Math.max(1, Math.round(img.width * scale))
  const h = Math.max(1, Math.round(img.height * scale))
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('No se pudo procesar la imagen.')
  ctx.drawImage(img, 0, 0, w, h)
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality))
  if (!blob) throw new Error('No se pudo generar la imagen.')
  return blob
}
