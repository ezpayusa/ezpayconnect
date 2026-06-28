import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { validarImagen, comprimirImagen } from '@/repartidor/lib/imagen'
import { extractPath } from '@/lib/signedUrl'

const BUCKET = 'pacientes-fotos'

/**
 * Foto de perfil del paciente (PHI, bucket privado). Flujo de 3 pasos:
 * path_foto_paciente (RPC deriva la clínica server-side) → upload jpeg upsert → set_foto_paciente (persiste).
 * Lectura SIEMPRE por signed URL (createSignedUrl); NUNCA getPublicUrl.
 */
export function useFotoPaciente() {
  const [subiendo, setSubiendo] = useState(false)

  const subirFoto = useCallback(async (pacienteId: number, file: File): Promise<string | null> => {
    const err = validarImagen(file)
    if (err) { toast.error(err); return null }
    setSubiendo(true)
    try {
      const blob = await comprimirImagen(file) // jpeg q0.8, maxDim 1600
      // 1) path canónico derivado server-side (no se arma con la clínica del usuario)
      const { data: pathData, error: e1 } = await supabase.rpc('path_foto_paciente', { p_paciente_id: pacienteId })
      if (e1) { toast.error(e1.message); return null }
      const path: string = pathData.path
      // 2) subida (la storage policy valida el 1er segmento = clínica)
      const { error: e2 } = await supabase.storage.from(BUCKET).upload(path, blob, { contentType: 'image/jpeg', upsert: true })
      if (e2) {
        toast.error(/permiso|row-level|not authorized/i.test(e2.message)
          ? 'No tenés permiso para subir la foto de este paciente.'
          : e2.message)
        return null
      }
      // 3) persistir foto_path
      const { error: e3 } = await supabase.rpc('set_foto_paciente', { p_paciente_id: pacienteId, p_path: path })
      if (e3) { toast.error(e3.message); return null }
      toast.success('Foto actualizada')
      return path
    } finally {
      setSubiendo(false)
    }
  }, [])

  // Genera la signed URL string para usar como <img src> (NO abre ventana, a diferencia de openSignedUrl).
  const urlFirmadaFoto = useCallback(async (fotoPath: string | null): Promise<string | null> => {
    if (!fotoPath) return null
    const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(extractPath(BUCKET, fotoPath), 120)
    if (error || !data?.signedUrl) return null
    return data.signedUrl
  }, [])

  return { subirFoto, urlFirmadaFoto, subiendo }
}
