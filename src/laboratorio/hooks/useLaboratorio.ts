import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { toast } from 'sonner'
import { hoyISO } from '@/lib/fecha'
import { mensajeErrorOrden, type ItemOrdenExamen } from '@/lib/ordenesExamen'
import { leerResultadoCorreccion, mensajeErrorCorreccion } from '@/lib/correccionResultados'

export interface OrdenExamen {
  id: number
  tipo: string
  descripcion: string | null
  estado: string
  origen: string
  prioridad: string
  fecha_solicitud: string
  fecha_resultado: string | null
  resultados: string | null
  archivo_url: string | null
  paciente_id: number | null
  paciente_nombre: string | null
  paciente_documento: string | null
  paciente_telefono: string | null
  medico_nombre: string | null
  clinica_nombre: string | null
  orden_id: string | null
  catalogo_id: string | null   // mig 332: NULL = examen fuera de catálogo (texto libre)
  liberado_al_paciente: boolean
}

// Una orden agrupa varios exámenes (ítems) en una sola "hoja"
export interface OrdenAgrupada {
  orden_id: string | null
  fecha: string
  origen: string
  prioridad: string
  instrucciones: string | null
  paciente_nombre: string | null
  paciente_id: number | null
  medico_nombre: string | null
  clinica_nombre: string | null
  items: OrdenExamen[]
}

export interface Afiliacion { clinica_id: string; clinica_nombre: string; desde: string }
export interface InvitacionLab { id: string; token: string; clinica_id: string; clinica_nombre: string; created_at: string }
export interface CatalogoItem { id: string; nombre: string; categoria: string | null; activo: boolean }

export function useLaboratorio() {
  const { empresa } = useProveedorAuth()
  const labId = empresa?.id

  const [ordenes, setOrdenes] = useState<OrdenAgrupada[]>([])
  const [afiliaciones, setAfiliaciones] = useState<Afiliacion[]>([])
  const [invitaciones, setInvitaciones] = useState<InvitacionLab[]>([])
  const [catalogo, setCatalogo] = useState<CatalogoItem[]>([])
  const [loading, setLoading] = useState(false)

  const fetchOrdenes = useCallback(async () => {
    if (!labId) return
    setLoading(true)
    const [itemsRes, headersRes] = await Promise.all([
      supabase.from('examenes')
        .select('id, tipo, descripcion, estado, origen, prioridad, fecha_solicitud, fecha_resultado, resultados, archivo_url, paciente_id, paciente_nombre, paciente_documento, paciente_telefono, medico_nombre, clinica_nombre, orden_id, catalogo_id, liberado_al_paciente')
        .eq('laboratorio_id', labId)
        .order('created_at', { ascending: false }),
      supabase.from('ordenes_examen')
        .select('id, created_at, origen, prioridad, instrucciones, paciente_nombre, paciente_id, medico_nombre, clinica_nombre')
        .eq('laboratorio_id', labId)
        .order('created_at', { ascending: false }),
    ])
    if (itemsRes.error) console.error('[lab] items:', itemsRes.error?.message ?? itemsRes.error?.code)
    const items = (itemsRes.data || []) as OrdenExamen[]
    const headers = (headersRes.data || []) as any[]

    const grupos: OrdenAgrupada[] = []
    // Órdenes agrupadas (con cabecera)
    for (const h of headers) {
      const its = items.filter((i) => i.orden_id === h.id)
      if (its.length === 0) continue
      grupos.push({
        orden_id: h.id, fecha: h.created_at, origen: h.origen, prioridad: h.prioridad,
        instrucciones: h.instrucciones, paciente_nombre: h.paciente_nombre, paciente_id: h.paciente_id,
        medico_nombre: h.medico_nombre, clinica_nombre: h.clinica_nombre, items: its,
      })
    }
    // Ítems sueltos (legacy, sin orden_id) → cada uno es su propia "orden"
    for (const i of items.filter((x) => !x.orden_id)) {
      grupos.push({
        orden_id: null, fecha: i.fecha_solicitud, origen: i.origen, prioridad: i.prioridad,
        instrucciones: i.descripcion, paciente_nombre: i.paciente_nombre, paciente_id: i.paciente_id,
        medico_nombre: i.medico_nombre, clinica_nombre: i.clinica_nombre, items: [i],
      })
    }
    setOrdenes(grupos)
    setLoading(false)
  }, [labId])

  const fetchAfiliaciones = useCallback(async () => {
    const { data } = await supabase.rpc('afiliaciones_laboratorio')
    setAfiliaciones(((data || []) as any[]).map((a) => ({
      clinica_id: a.clinica_id, clinica_nombre: a.clinica_nombre, desde: a.desde,
    })))
  }, [])

  const fetchInvitaciones = useCallback(async () => {
    const { data } = await supabase.rpc('invitaciones_laboratorio_pendientes')
    setInvitaciones(((data || []) as any[]).map((i) => ({
      id: i.id, token: i.token, clinica_id: i.clinica_id, clinica_nombre: i.clinica_nombre, created_at: i.created_at,
    })))
  }, [])

  useEffect(() => { if (labId) { fetchOrdenes() } }, [labId, fetchOrdenes])

  // Realtime: refresca la bandeja cuando entra/cambia una orden de este lab (sin refrescar a mano)
  useEffect(() => {
    if (!labId) return
    const channel = supabase
      .channel(`lab_ordenes_${labId}`)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'examenes', filter: `laboratorio_id=eq.${labId}` },
        () => { fetchOrdenes() }
      )
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [labId, fetchOrdenes])

  const cambiarEstado = async (examenId: number, estado: string) => {
    const patch: any = { estado }
    if (estado === 'completado') patch.fecha_resultado = hoyISO()
    const { error } = await supabase.from('examenes').update(patch).eq('id', examenId)
    if (error) { toast.error('No se pudo actualizar: ' + error.message); return false }
    toast.success('Examen actualizado')
    fetchOrdenes()
    return true
  }

  const subirArchivo = async (examenId: number, file: File): Promise<string | null> => {
    if (!labId) return null
    const ext = file.name.split('.').pop() || 'pdf'
    const path = `${labId}/${examenId}-${Date.now()}.${ext}`
    const { error } = await supabase.storage.from('resultados-examenes').upload(path, file, { upsert: false })
    if (error) {
      console.error('[subirArchivo] upload falló', { bucket: 'resultados-examenes', path, labId, file: { name: file.name, type: file.type, size: file.size }, error })
      toast.error(`No se pudo subir el archivo: ${error.message}${(error as any).statusCode ? ' [' + (error as any).statusCode + ']' : ''}`)
      return null
    }
    // Bucket privado (resultados-examenes.public=false): guardar el PATH, NO una URL pública (daría
    // 403 al paciente). Los lectores lo abren con el visor compartido (useVisor), que lo firma a 60 s.
    return path
  }

  const subirResultado = async (examenId: number, resultados: string, archivo?: File | null, tipo?: string) => {
    let archivo_url: string | null = null
    if (archivo) {
      archivo_url = await subirArchivo(examenId, archivo)
      if (!archivo_url) return false // el toast ya se mostró
    }
    const { error } = await supabase.from('examenes').update({
      resultados,
      ...(archivo_url ? { archivo_url } : {}),
      estado: 'completado',
      fecha_resultado: hoyISO(),
    }).eq('id', examenId)
    if (error) {
      console.error('[subirResultado] UPDATE examenes falló', { examenId, error })
      toast.error('No se pudo guardar el resultado: ' + error.message)
      return false
    }
    // Avisar al médico y al paciente: in-app + push server-side y gateado. notificar_resultado_examen
    // empuja vía push_notificar (edge gateado, contenido mínimo) — reemplaza el enviar-push del caller
    // (ids+contenido del cliente). Best-effort: no falla el guardado del resultado.
    try {
      await supabase.rpc('notificar_resultado_examen', { p_examen_id: examenId })
    } catch (e) { console.error('Error notificar_resultado_examen:', e?.message ?? e?.code) }
    toast.success('Resultado enviado')
    fetchOrdenes()
    return true
  }

  // Corrección de un resultado COMPLETADO (mig 335/336). El archivo nuevo se sube primero (mismo path
  // y upsert:false que la carga normal) y la RPC recibe su PATH. Si la RPC rechaza, ese archivo quedó
  // sin referencia: se borra (la policy de DELETE lo permite justamente porque nadie lo referencia)
  // y se muestra el error ORIGINAL de la RPC, no el del borrado.
  const corregirResultado = async (examenId: number, motivo: string, resultados: string, archivo?: File | null) => {
    let path: string | null = null
    if (archivo) {
      path = await subirArchivo(examenId, archivo)
      if (!path) return false // el toast ya se mostró
    }
    const { data, error } = await supabase.rpc('corregir_resultado_examen', {
      p_examen_id: examenId, p_motivo: motivo.trim(), p_resultados: resultados, p_archivo_path: path,
    })
    if (error) {
      if (path) {
        const { error: eDel } = await supabase.storage.from('resultados-examenes').remove([path])
        if (eDel) console.error('[corregirResultado] no se pudo borrar el archivo huérfano', { path, error: eDel })
      }
      console.error('[corregirResultado] RPC falló', { examenId, code: error.code })
      toast.error(mensajeErrorCorreccion(error))
      return false
    }
    const r = leerResultadoCorreccion(data)
    toast.success(r
      ? `Resultado corregido (revisión ${r.revision})${r.notificado ? '. Se notificó al médico y al paciente.' : ''}`
      : 'Resultado corregido')
    fetchOrdenes()
    return true
  }

  // ---- Catálogo de exámenes del laboratorio ----
  const fetchCatalogo = useCallback(async () => {
    if (!labId) return
    const { data } = await supabase
      .from('examenes_catalogo')
      .select('id, nombre, categoria, activo')
      .eq('laboratorio_id', labId)
      .order('categoria', { nullsFirst: false })
      .order('nombre')
    setCatalogo((data || []) as CatalogoItem[])
  }, [labId])

  const crearCatalogo = async (nombre: string, categoria?: string) => {
    if (!labId) return false
    const { error } = await supabase.from('examenes_catalogo').insert({
      laboratorio_id: labId, nombre: nombre.trim(), categoria: categoria?.trim() || null,
    })
    if (error) {
      // 23505 = UNIQUE (laboratorio_id, lower(btrim(nombre))) de la mig 332
      toast.error(error.code === '23505' ? 'Ya existe un examen con ese nombre en tu catálogo' : 'No se pudo agregar: ' + error.message)
      return false
    }
    toast.success('Examen agregado al catálogo')
    fetchCatalogo()
    return true
  }

  const toggleCatalogo = async (id: string, activo: boolean) => {
    const { error } = await supabase.from('examenes_catalogo').update({ activo }).eq('id', id)
    if (error) { toast.error('No se pudo actualizar'); return }
    fetchCatalogo()
  }

  const eliminarCatalogo = async (id: string) => {
    if (!window.confirm('¿Eliminar este examen del catálogo?')) return
    const { error } = await supabase.from('examenes_catalogo').delete().eq('id', id)
    if (error) {
      // 23503 = FK RESTRICT de examenes.catalogo_id (mig 332): un examen ya ordenado no se borra, se desactiva
      if (error.code === '23503') {
        toast.error('Este examen ya fue ordenado y no se puede borrar. Podés desactivarlo.', {
          action: { label: 'Desactivar', onClick: () => { toggleCatalogo(id, false) } },
        })
      } else {
        toast.error('No se pudo eliminar')
      }
      return
    }
    toast.success('Examen eliminado')
    fetchCatalogo()
  }

  const responderInvitacion = async (token: string, aceptar: boolean) => {
    const { error } = await supabase.rpc('responder_invitacion_laboratorio', { p_token: token, p_aceptar: aceptar })
    if (error) { toast.error('Error: ' + error.message); return false }
    toast.success(aceptar ? 'Afiliación aceptada' : 'Invitación rechazada')
    fetchInvitaciones()
    fetchAfiliaciones()
    return true
  }

  const crearWalkIn = async (datos: {
    items: ItemOrdenExamen[]; instrucciones?: string; prioridad?: string
    paciente_nombre: string; paciente_documento?: string; paciente_telefono?: string
  }) => {
    if (!labId) { toast.error('Sin laboratorio'); return false }
    if (datos.items.length === 0) { toast.error('Selecciona al menos un examen'); return false }

    // Una sola RPC atómica (cabecera + ítems): el laboratorio lo deriva el servidor de la cuenta
    // (mi_empresa_proveedor) y exige el permiso walkin_registrar.
    const { error } = await supabase.rpc('crear_orden_examen_walkin', {
      p_items: datos.items,
      p_paciente_nombre: datos.paciente_nombre,
      p_paciente_documento: datos.paciente_documento || null,
      p_paciente_telefono: datos.paciente_telefono || null,
      p_instrucciones: datos.instrucciones || null,
      p_prioridad: datos.prioridad || 'normal',
    })
    if (error) { toast.error(mensajeErrorOrden(error, 'No se pudo crear la orden: ')); return false }

    toast.success('Orden walk-in registrada')
    fetchOrdenes()
    return true
  }

  return {
    ordenes, afiliaciones, invitaciones, catalogo, loading,
    fetchOrdenes, fetchAfiliaciones, fetchInvitaciones, fetchCatalogo,
    cambiarEstado, subirResultado, corregirResultado, responderInvitacion, crearWalkIn,
    crearCatalogo, toggleCatalogo, eliminarCatalogo,
  }
}
