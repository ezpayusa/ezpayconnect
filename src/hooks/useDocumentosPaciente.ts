import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { comprimirImagen } from '@/repartidor/lib/imagen'
import { openSignedUrl } from '@/lib/signedUrl'

const BUCKET = 'pacientes-documentos'

export interface DocumentoPaciente {
  id: number
  tipo: string
  descripcion: string | null
  path: string
  subido_por: string | null
  created_at: string
}

/**
 * Documentos del paciente (PHI, bucket privado). Plomería calcada de useFotoPaciente:
 * path_documento_paciente (RPC deriva clínica + uuid) → upload → registrar_documento_paciente.
 * Lectura por signed URL (openSignedUrl); NUNCA getPublicUrl. Solo staff (gate en los RPCs).
 */
export function useDocumentosPaciente(pacienteId: number | undefined) {
  const [documentos, setDocumentos] = useState<DocumentoPaciente[]>([])
  const [cargando, setCargando] = useState(true)
  const [subiendo, setSubiendo] = useState(false)

  const listar = useCallback(async () => {
    if (!pacienteId) { setDocumentos([]); setCargando(false); return }
    setCargando(true)
    const { data, error } = await supabase.rpc('listar_documentos_paciente', { p_paciente_id: pacienteId })
    if (error) toast.error(error.message)
    setDocumentos(Array.isArray(data) ? (data as DocumentoPaciente[]) : [])
    setCargando(false)
  }, [pacienteId])

  useEffect(() => { listar() }, [listar])

  const subir = useCallback(
    async (pid: number, file: File, tipo: string, descripcion: string | null): Promise<boolean> => {
      const esImagen = file.type.startsWith('image/')
      const esPdf = file.type === 'application/pdf'
      if (!esImagen && !esPdf) { toast.error('Solo se permiten imágenes o PDF'); return false }
      setSubiendo(true)
      try {
        let blob: Blob, ext: string, contentType: string
        if (esImagen) { blob = await comprimirImagen(file); ext = 'jpg'; contentType = 'image/jpeg' }
        else { blob = file; ext = 'pdf'; contentType = 'application/pdf' }

        // 1) path canónico server-side (uuid + clínica derivada). Clave 'path' (confirmada en mig 170).
        const { data: pathData, error: e1 } = await supabase.rpc('path_documento_paciente', {
          p_paciente_id: pid, p_ext: ext,
        })
        if (e1) { toast.error(e1.message); return false }
        const path: string | undefined = pathData?.path
        if (!path) { toast.error('No se pudo derivar la ruta del documento'); return false }

        // 2) subida (upsert:false — cada doc es objeto nuevo con uuid; la storage policy valida la clínica)
        const { error: e2 } = await supabase.storage.from(BUCKET).upload(path, blob, { contentType, upsert: false })
        if (e2) {
          toast.error(/permiso|row-level|not authorized/i.test(e2.message)
            ? 'No tenés permiso para subir documentos de este paciente.'
            : e2.message)
          return false
        }

        // 3) registrar el doc
        const { error: e3 } = await supabase.rpc('registrar_documento_paciente', {
          p_paciente_id: pid, p_tipo: tipo, p_path: path, p_descripcion: descripcion || null,
        })
        if (e3) { toast.error(e3.message); return false }

        toast.success('Documento subido')
        await listar()
        return true
      } finally {
        setSubiendo(false)
      }
    },
    [listar],
  )

  // Misma secuencia que subir() pero devuelve el id del documento registrado (para enlazarlo a un
  // consentimiento). Acepta Blob (FirmaPad) o File (scan). NO valida tipo: el caller decide ext/contentType.
  const subirYDevolverId = useCallback(
    async (pid: number, blobOrFile: Blob | File, ext: string, contentType: string, tipo: string, descripcion: string | null): Promise<number | null> => {
      setSubiendo(true)
      try {
        const { data: pathData, error: e1 } = await supabase.rpc('path_documento_paciente', { p_paciente_id: pid, p_ext: ext })
        if (e1) { toast.error(e1.message); return null }
        const path: string | undefined = pathData?.path
        if (!path) { toast.error('No se pudo derivar la ruta del documento'); return null }
        const { error: e2 } = await supabase.storage.from(BUCKET).upload(path, blobOrFile, { contentType, upsert: false })
        if (e2) { toast.error(/permiso|row-level|not authorized/i.test(e2.message) ? 'No tenés permiso para subir documentos de este paciente.' : e2.message); return null }
        const { data: regData, error: e3 } = await supabase.rpc('registrar_documento_paciente', { p_paciente_id: pid, p_tipo: tipo, p_path: path, p_descripcion: descripcion || null })
        if (e3) { toast.error(e3.message); return null }
        await listar()
        const id = regData?.id
        return typeof id === 'number' ? id : null
      } finally { setSubiendo(false) }
    }, [listar])

  // Lectura: abre el objeto del bucket privado por signed URL (TTL corto). download:true fuerza descarga.
  const abrir = useCallback((path: string, download?: boolean) => {
    return openSignedUrl(BUCKET, path, download ? { download: true } : undefined)
  }, [])

  return { documentos, cargando, subiendo, subir, subirYDevolverId, abrir, recargar: listar }
}
