import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { comprimirImagen } from '@/repartidor/lib/imagen'
import { useDocumentosPaciente } from '@/hooks/useDocumentosPaciente'
import type { PermisoCatalogo, ConsentimientoVigente } from '@/webapp/hooks/useConsentimientoPaciente'

export type { PermisoCatalogo, ConsentimientoVigente }

/**
 * Captura PRESENCIAL de consentimiento (staff). Espejo de useConsentimientoPaciente pero con vía presencial:
 * conceder = capturar UNA prueba (firma PNG o scan) → documento_id → registrar_consentimiento(concedido=true).
 * revocar = registrar_consentimiento(concedido=false) sin prueba. Reusa subirYDevolverId de useDocumentosPaciente.
 */
export function useConsentimientoPresencial(pacienteId: number | undefined) {
  const [catalogo, setCatalogo] = useState<PermisoCatalogo[]>([])
  const [estado, setEstado] = useState<ConsentimientoVigente[]>([])
  const [cargando, setCargando] = useState(true)
  // Instanciado adentro para encapsular subirYDevolverId; su listar() de documentos es inocuo aquí.
  const { subirYDevolverId, subiendo } = useDocumentosPaciente(pacienteId)

  const cargarCatalogo = useCallback(async () => {
    const { data, error } = await supabase
      .from('consentimiento_permisos')
      .select('codigo,version,etiqueta,texto_legal')
      .eq('activo', true)
      .order('codigo', { ascending: true })
      .order('version', { ascending: false })
    if (error) { toast.error(error.message); return }
    const rows = Array.isArray(data) ? (data as PermisoCatalogo[]) : []
    // Dedup: una fila por codigo = mayor version activa (espejo del resolver server-side).
    const vistos = new Set<string>()
    const ultimas = rows.filter((r) => (vistos.has(r.codigo) ? false : (vistos.add(r.codigo), true)))
    ultimas.sort((a, b) => a.etiqueta.localeCompare(b.etiqueta))
    setCatalogo(ultimas)
  }, [])

  const cargarEstado = useCallback(async () => {
    if (!pacienteId) { setEstado([]); return }
    const { data, error } = await supabase.rpc('estado_consentimiento_paciente', { p_paciente_id: pacienteId })
    if (error) { toast.error(error.message); return }
    setEstado(Array.isArray(data) ? (data as ConsentimientoVigente[]) : [])
  }, [pacienteId])

  const recargar = useCallback(async () => {
    setCargando(true)
    await Promise.all([cargarCatalogo(), cargarEstado()])
    setCargando(false)
  }, [cargarCatalogo, cargarEstado])

  useEffect(() => { recargar() }, [recargar])

  const etiquetaDe = useCallback((codigo: string) => catalogo.find((p) => p.codigo === codigo)?.etiqueta || codigo, [catalogo])

  // Conceder con firma manuscrita (PNG del FirmaPad). via='presencial_firma'.
  const concederConFirma = useCallback(async (pid: number, codigo: string, blobPng: Blob): Promise<boolean> => {
    const id = await subirYDevolverId(pid, blobPng, 'png', 'image/png', 'consentimiento_firmado', `Consentimiento: ${etiquetaDe(codigo)}`)
    if (!id) return false
    const { error } = await supabase.rpc('registrar_consentimiento', {
      p_paciente_id: pid, p_permiso_codigo: codigo, p_concedido: true, p_via: 'presencial_firma', p_documento_id: id,
    })
    if (error) { toast.error(error.message); return false }
    toast.success('Consentimiento registrado (firma)')
    await cargarEstado()
    return true
  }, [subirYDevolverId, etiquetaDe, cargarEstado])

  // Conceder con papel escaneado (imagen comprimida o PDF raw). via='presencial_papel'.
  const concederConScan = useCallback(async (pid: number, codigo: string, file: File): Promise<boolean> => {
    const esImagen = file.type.startsWith('image/')
    const esPdf = file.type === 'application/pdf'
    if (!esImagen && !esPdf) { toast.error('Solo se permiten imágenes o PDF'); return false }
    let blob: Blob, ext: string, contentType: string
    if (esImagen) { blob = await comprimirImagen(file); ext = 'jpg'; contentType = 'image/jpeg' }
    else { blob = file; ext = 'pdf'; contentType = 'application/pdf' }
    const id = await subirYDevolverId(pid, blob, ext, contentType, 'consentimiento_firmado', `Consentimiento: ${etiquetaDe(codigo)}`)
    if (!id) return false
    const { error } = await supabase.rpc('registrar_consentimiento', {
      p_paciente_id: pid, p_permiso_codigo: codigo, p_concedido: true, p_via: 'presencial_papel', p_documento_id: id,
    })
    if (error) { toast.error(error.message); return false }
    toast.success('Consentimiento registrado (papel)')
    await cargarEstado()
    return true
  }, [subirYDevolverId, etiquetaDe, cargarEstado])

  // Revocar (sin prueba). Append-only: nueva fila concedido=false.
  const revocar = useCallback(async (pid: number, codigo: string): Promise<boolean> => {
    const { error } = await supabase.rpc('registrar_consentimiento', {
      p_paciente_id: pid, p_permiso_codigo: codigo, p_concedido: false, p_via: 'presencial_papel', p_documento_id: null,
    })
    if (error) { toast.error(error.message); return false }
    toast.success('Autorización revocada')
    await cargarEstado()
    return true
  }, [cargarEstado])

  return { catalogo, estado, cargando, subiendo, concederConFirma, concederConScan, revocar, recargar }
}
