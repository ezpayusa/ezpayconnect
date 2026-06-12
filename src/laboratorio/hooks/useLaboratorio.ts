import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { toast } from 'sonner'

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
}

export interface Afiliacion { clinica_id: string; clinica_nombre: string; desde: string }
export interface InvitacionLab { id: string; token: string; clinica_id: string; clinica_nombre: string; created_at: string }

export function useLaboratorio() {
  const { empresa } = useProveedorAuth()
  const labId = empresa?.id

  const [ordenes, setOrdenes] = useState<OrdenExamen[]>([])
  const [afiliaciones, setAfiliaciones] = useState<Afiliacion[]>([])
  const [invitaciones, setInvitaciones] = useState<InvitacionLab[]>([])
  const [loading, setLoading] = useState(false)

  const fetchOrdenes = useCallback(async () => {
    if (!labId) return
    setLoading(true)
    const { data, error } = await supabase
      .from('examenes')
      .select('id, tipo, descripcion, estado, origen, prioridad, fecha_solicitud, fecha_resultado, resultados, archivo_url, paciente_id, paciente_nombre, paciente_documento, paciente_telefono, medico_nombre, clinica_nombre')
      .eq('laboratorio_id', labId)
      .order('created_at', { ascending: false })
    if (error) console.error('[lab] ordenes:', error)
    setOrdenes((data || []) as OrdenExamen[])
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

  const cambiarEstado = async (ordenId: number, estado: string) => {
    const patch: any = { estado }
    if (estado === 'completado') patch.fecha_resultado = new Date().toISOString().slice(0, 10)
    const { error } = await supabase.from('examenes').update(patch).eq('id', ordenId)
    if (error) { toast.error('No se pudo actualizar: ' + error.message); return false }
    toast.success('Orden actualizada')
    fetchOrdenes()
    return true
  }

  const subirResultado = async (ordenId: number, resultados: string, archivo_url?: string) => {
    const { error } = await supabase.from('examenes').update({
      resultados,
      archivo_url: archivo_url || null,
      estado: 'completado',
      fecha_resultado: new Date().toISOString().slice(0, 10),
    }).eq('id', ordenId)
    if (error) { toast.error('No se pudo guardar el resultado: ' + error.message); return false }
    // Avisar al médico y al paciente (RPC security definer)
    try { await supabase.rpc('notificar_resultado_examen', { p_examen_id: ordenId }) } catch (e) { console.error(e) }
    toast.success('Resultado enviado')
    fetchOrdenes()
    return true
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
    tipo: string; descripcion?: string; prioridad?: string
    paciente_nombre: string; paciente_documento?: string; paciente_telefono?: string
  }) => {
    if (!labId) { toast.error('Sin laboratorio'); return false }
    const { error } = await supabase.from('examenes').insert({
      laboratorio_id: labId,
      tipo: datos.tipo,
      descripcion: datos.descripcion || null,
      prioridad: datos.prioridad || 'normal',
      origen: 'walk_in',
      estado: 'recibida',
      paciente_nombre: datos.paciente_nombre,
      paciente_documento: datos.paciente_documento || null,
      paciente_telefono: datos.paciente_telefono || null,
    })
    if (error) { toast.error('No se pudo crear: ' + error.message); return false }
    toast.success('Orden walk-in registrada')
    fetchOrdenes()
    return true
  }

  return {
    ordenes, afiliaciones, invitaciones, loading,
    fetchOrdenes, fetchAfiliaciones, fetchInvitaciones,
    cambiarEstado, subirResultado, responderInvitacion, crearWalkIn,
  }
}
