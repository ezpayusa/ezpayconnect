import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import type { VisitaAgendada } from '@/proveedor/types/proveedor.types'
import type { PlanAsignacion } from '@/types/planes'
import type { UbicacionVisita } from './useRutaVisitador'
import { toast } from 'sonner'
import { enviarEmail, buildHtmlVisitaPropuesta, buildHtmlVisitaAprobada, buildHtmlVisitaRechazada, crearNotificacionInApp } from '@/proveedor/lib/notificaciones'

export function useVisitasAgendadas() {
  const { empresa, cuenta, puede } = useProveedorAuth()
  const [visitas, setVisitas] = useState<VisitaAgendada[]>([])
  const [planesAsignados, setPlanesAsignados] = useState<PlanAsignacion[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const rol = cuenta?.rol_en_empresa || 'visitador_medico'
  // "esAdmin" aquí = puede aprobar/confirmar visitas y ver las de todo el equipo.
  const esAdmin = puede('visitas.aprobar')

  // Cargar planes asignados (pool compartido de la empresa)
  const fetchPlanesAsignados = useCallback(async () => {
    if (!empresa?.id) return
    const { data, error } = await supabase
      .from('planes_asignaciones')
      .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
      .eq('empresa_id', empresa.id)
      .eq('estado', 'activo')

    if (error) {
      console.error('Error cargando planes asignados:', error)
      return
    }
    setPlanesAsignados((data || []) as PlanAsignacion[])
  }, [empresa?.id])

  const fetchVisitas = useCallback(async () => {
    if (!empresa?.id || !cuenta?.id) return
    setLoading(true)
    
    try {
      // Admin ve todas las visitas de la empresa
      // Visitador ve solo sus visitas (donde él es cuenta_proveedor_id)
      let q = supabase
        .from('visitas_agendadas')
        .select('*')
        .eq('empresa_id', empresa.id)
      
      if (!esAdmin) {
        q = q.eq('cuenta_proveedor_id', cuenta.id)
      }
      
      const { data: visitasRaw, error } = await q.order('fecha_visita', { ascending: false })
      if (error) throw error

      // Obtener nombres de médicos por separado (evita problemas RLS con joins)
      const medicoIds = [...new Set((visitasRaw || []).map((v: any) => v.medico_id).filter(Boolean))]
      let medicosMap: Record<string, { nombre_completo: string; email: string }> = {}
      
      if (medicoIds.length > 0) {
        const { data: medicosData } = await supabase.rpc('buscar_medicos_proveedor', { p_query: null })
        if (medicosData) {
          medicosMap = (medicosData as any[]).reduce((acc, m) => {
            acc[m.id] = { nombre_completo: m.nombre_completo, email: m.email }
            return acc
          }, {})
        }
      }

      // Obtener nombres de visitadores por separado
      const visitadorIds = [...new Set((visitasRaw || []).map((v: any) => v.cuenta_proveedor_id).filter(Boolean))]
      let visitadoresMap: Record<string, { nombre_completo: string; email: string }> = {}
      
      if (visitadorIds.length > 0) {
        const { data: visitadoresData } = await supabase
          .from('cuentas_proveedor')
          .select('id, nombre_completo, email')
          .eq('empresa_id', empresa.id)
          .in('id', visitadorIds)
        if (visitadoresData) {
          visitadoresMap = (visitadoresData as any[]).reduce((acc, v) => {
            acc[v.id] = { nombre_completo: v.nombre_completo, email: v.email }
            return acc
          }, {})
        }
      }

      // Obtener ubicaciones de médicos para esta empresa
      const { data: ubicacionesData } = await supabase
        .from('ubicaciones_medico_proveedor')
        .select('medico_id, direccion, lat, lng')
        .eq('empresa_id', empresa.id)
      
      const ubicacionesMap: Record<string, UbicacionVisita> = {}
      if (ubicacionesData) {
        (ubicacionesData as any[]).forEach((u) => {
          ubicacionesMap[u.medico_id] = { direccion: u.direccion, lat: u.lat, lng: u.lng }
        })
      }

      const mapped = (visitasRaw || []).map((v: any) => ({
        id: v.id,
        empresa_id: empresa.id,
        medico_id: v.medico_id,
        cuenta_proveedor_id: v.cuenta_proveedor_id,
        fecha_visita: v.fecha_visita,
        hora_inicio: v.hora_inicio,
        hora_fin: v.hora_fin,
        tipo_visita: v.tipo_visita,
        estado: v.estado,
        notas_empresa: v.notas_empresa,
        notas_medico: v.notas_medico,
        created_at: v.created_at,
        updated_at: v.updated_at,
        medico: medicosMap[v.medico_id] ? {
          nombre_completo: medicosMap[v.medico_id].nombre_completo,
          email: medicosMap[v.medico_id].email,
        } : undefined,
        ubicacion: ubicacionesMap[v.medico_id] || undefined,
        visitador: visitadoresMap[v.cuenta_proveedor_id] ? {
          nombre_completo: visitadoresMap[v.cuenta_proveedor_id].nombre_completo,
          email: visitadoresMap[v.cuenta_proveedor_id].email,
        } : undefined,
        propuesta_por: v.propuesta_por,
        aprobada_por: v.aprobada_por,
        fecha_aprobacion: v.fecha_aprobacion,
        comentario_admin: v.comentario_admin,
        fecha_limite_cancelacion: v.fecha_limite_cancelacion,
        checkin_fecha: v.checkin_fecha,
        checkin_lat: v.checkin_lat,
        checkin_lng: v.checkin_lng,
        checkin_evidencia_url: v.checkin_evidencia_url,
        checkout_fecha: v.checkout_fecha,
        checkout_notas: v.checkout_notas,
        visita_concretada: v.visita_concretada,
        verificada_por_sistema: v.verificada_por_sistema,
      }))
      
      setVisitas(mapped as VisitaAgendada[])
    } catch (err: any) {
      toast.error('Error cargando visitas')
      console.error(err)
    }
    
    setLoading(false)
  }, [empresa?.id, cuenta?.id, esAdmin])

  useEffect(() => {
    fetchVisitas()
    fetchPlanesAsignados()
  }, [fetchVisitas, fetchPlanesAsignados])

  // Calcular visitas disponibles del pool compartido
  // Solo cuentan las visitas CONFIRMADAS/PENDIENTES/COMPLETADAS contra el plan
  const visitasDisponibles = (() => {
    const planActivo = planesAsignados.find((a) => {
      if (a.fecha_fin && new Date(a.fecha_fin) < new Date()) return false
      return a.plan_configuracion?.plan_base?.tipo === 'visitador'
    })
    if (!planActivo) return 0
    const incluidas = planActivo.plan_configuracion?.plan_base?.atributos?.visitas_incluidas || 0
    return Math.max(0, incluidas - (planActivo.visitas_usadas || 0))
  })()

  // Agendar visita (visitador propone, admin crea confirmada)
  const agendarVisita = async (visita: Partial<VisitaAgendada>, visitadorId?: string): Promise<boolean> => {
    if (!empresa?.id || !cuenta) {
      toast.error('No hay empresa vinculada')
      return false
    }

    // Si es visitador, solo puede proponer (no confirmar)
    // Si es admin, puede confirmar directamente
    const estadoFinal = esAdmin ? (visita.estado || 'confirmada') : 'propuesta'

    // Solo validar límite si el admin está confirmando directamente
    if (esAdmin && estadoFinal === 'confirmada' && visitasDisponibles <= 0) {
      toast.error('No hay visitas disponibles en el plan')
      return false
    }

    setSaving(true)
    const { data: insertData, error } = await supabase.from('visitas_agendadas').insert({
      empresa_id: empresa.id,
      medico_id: visita.medico_id,
      cuenta_proveedor_id: visitadorId || cuenta.id,
      fecha_visita: visita.fecha_visita,
      hora_inicio: visita.hora_inicio,
      hora_fin: visita.hora_fin,
      tipo_visita: visita.tipo_visita || 'presentacion_producto',
      productos_a_presentar: visita.productos_a_presentar || [],
      estado: estadoFinal,
      notas_empresa: visita.notas_empresa || null,
      propuesta_por: !esAdmin ? cuenta.id : null,
      pais_id: empresa.pais_id,
    }).select().single()
    setSaving(false)

    if (error) {
      // 23505 = el slot ya fue tomado por otro proveedor entre que lo viste y lo guardaste.
      if ((error as any).code === '23505') {
        toast.error('Ese horario acaba de ser tomado por otro proveedor. Por favor elige otro.', { duration: 6000 })
        return false
      }
      toast.error('Error agendando visita')
      console.error(error)
      return false
    }

    // Solo consumir visita si es confirmada directamente por admin
    if (estadoFinal === 'confirmada') {
      const planActivo = planesAsignados.find((a) => {
        if (a.fecha_fin && new Date(a.fecha_fin) < new Date()) return false
        return a.plan_configuracion?.plan_base?.tipo === 'visitador'
      })
      if (planActivo?.id) {
        await supabase.from('planes_asignaciones')
          .update({ visitas_usadas: (planActivo.visitas_usadas || 0) + 1 })
          .eq('id', planActivo.id)
        fetchPlanesAsignados()
      }
    }

    // Notificar al admin si fue propuesta por visitador
    if (!esAdmin && estadoFinal === 'propuesta' && empresa?.email_contacto && insertData) {
      try {
        const { data: medicoData } = await supabase
          .from('perfiles')
          .select('nombre_completo')
          .eq('id', visita.medico_id)
          .single()

        await enviarEmail({
          to: empresa.email_contacto,
          subject: `Nueva visita propuesta - ${medicoData?.nombre_completo || 'Médico'}`,
          html: buildHtmlVisitaPropuesta({
            medicoNombre: medicoData?.nombre_completo || 'Médico',
            visitadorNombre: cuenta.nombre_completo,
            fecha: visita.fecha_visita || '',
            hora: `${visita.hora_inicio} - ${visita.hora_fin}`,
            tipo: visita.tipo_visita || 'presentacion_producto',
            notas: visita.notas_empresa,
          }),
          tipo: 'visita_propuesta',
        })

        // Notificación in-app a admins/editores de la empresa
        const { data: admins } = await supabase
          .from('cuentas_proveedor')
          .select('id')
          .eq('empresa_id', empresa.id)
          .in('rol_en_empresa', ['admin', 'editor'])

        for (const admin of admins || []) {
          await crearNotificacionInApp({
            usuario_id: admin.id,
            tipo: 'visita_propuesta',
            titulo: 'Nueva visita propuesta',
            mensaje: `${cuenta.nombre_completo} propuso una visita con ${medicoData?.nombre_completo || 'Médico'} el ${visita.fecha_visita}.`,
            accion_url: '/proveedor/visitador/admin-aprobar',
            metadata: { visita_id: insertData.id },
          })
        }
      } catch (e) {
        console.error('Error notificando propuesta:', e)
      }
    }

    toast.success(esAdmin ? 'Visita agendada' : 'Visita propuesta. Esperando aprobación.')
    fetchVisitas()
    return true
  }

  // Cancelar visita
  const cancelarVisita = async (id: string): Promise<boolean> => {
    const visita = visitas.find((v) => v.id === id)
    if (!visita) {
      toast.error('Visita no encontrada')
      return false
    }

    // Si es propuesta, se puede cancelar libremente
    // Si es confirmada, aplica regla de 3 días hábiles
    if (visita.estado === 'confirmada') {
      const hoy = new Date()
      hoy.setHours(0, 0, 0, 0)
      const limite = visita.fecha_limite_cancelacion ? new Date(visita.fecha_limite_cancelacion) : null
      if (limite && hoy > limite) {
        toast.error('No puedes cancelar esta visita. El plazo de 3 días hábiles ya venció.')
        return false
      }
    }

    if (!confirm('¿Cancelar esta visita?')) return false
    
    const { error } = await supabase.from('visitas_agendadas').update({ estado: 'cancelada' }).eq('id', id)
    if (error) {
      toast.error('Error cancelando visita')
      return false
    }

    // Liberar visita_usada solo si era confirmada
    if (visita.estado === 'confirmada') {
      const planActivo = planesAsignados.find((a) => {
        if (a.fecha_fin && new Date(a.fecha_fin) < new Date()) return false
        return a.plan_configuracion?.plan_base?.tipo === 'visitador'
      })
      if (planActivo?.id && (planActivo.visitas_usadas || 0) > 0) {
        await supabase.from('planes_asignaciones')
          .update({ visitas_usadas: (planActivo.visitas_usadas || 0) - 1 })
          .eq('id', planActivo.id)
        fetchPlanesAsignados()
      }
    }

    toast.success('Visita cancelada')
    fetchVisitas()
    return true
  }

  // Admin: aprobar, rechazar o modificar visita
  const administrarVisita = async (
    id: string,
    accion: 'aprobar' | 'rechazar' | 'modificar',
    cambios?: { fecha_visita?: string; hora_inicio?: string; hora_fin?: string; comentario?: string }
  ): Promise<boolean> => {
    if (!esAdmin) {
      toast.error('No tienes permiso')
      return false
    }

    setSaving(true)
    try {
      let updateData: any = { comentario_admin: cambios?.comentario || null }
      
      if (accion === 'aprobar') {
        updateData.estado = 'confirmada'
        updateData.fecha_aprobacion = new Date().toISOString()
      } else if (accion === 'rechazar') {
        updateData.estado = 'rechazada'
      } else if (accion === 'modificar') {
        if (cambios?.fecha_visita) updateData.fecha_visita = cambios.fecha_visita
        if (cambios?.hora_inicio) updateData.hora_inicio = cambios.hora_inicio
        if (cambios?.hora_fin) updateData.hora_fin = cambios.hora_fin
        updateData.estado = 'confirmada'
        updateData.fecha_aprobacion = new Date().toISOString()
      }

      const { error } = await supabase.from('visitas_agendadas').update(updateData).eq('id', id)
      if (error) throw error

      // Si aprueba o modifica, consumir visita del plan
      if (accion === 'aprobar' || accion === 'modificar') {
        const planActivo = planesAsignados.find((a) => {
          if (a.fecha_fin && new Date(a.fecha_fin) < new Date()) return false
          return a.plan_configuracion?.plan_base?.tipo === 'visitador'
        })
        if (planActivo?.id) {
          await supabase.from('planes_asignaciones')
            .update({ visitas_usadas: (planActivo.visitas_usadas || 0) + 1 })
            .eq('id', planActivo.id)
          fetchPlanesAsignados()
        }
      }

      // Notificar al visitador
      const visita = visitas.find((v) => v.id === id)
      if (visita?.visitador?.email) {
        try {
          if (accion === 'aprobar' || accion === 'modificar') {
            await enviarEmail({
              to: visita.visitador.email,
              subject: `Visita aprobada - ${visita.medico?.nombre_completo || 'Médico'}`,
              html: buildHtmlVisitaAprobada({
                medicoNombre: visita.medico?.nombre_completo || 'Médico',
                fecha: visita.fecha_visita,
                hora: `${visita.hora_inicio} - ${visita.hora_fin}`,
                comentario: cambios?.comentario || visita.comentario_admin,
              }),
              tipo: 'visita_aprobada',
            })

            // Notificación in-app al visitador
            if (visita.cuenta_proveedor_id) {
              await crearNotificacionInApp({
                usuario_id: visita.cuenta_proveedor_id,
                tipo: 'visita_aprobada',
                titulo: 'Visita aprobada',
                mensaje: `Tu visita con ${visita.medico?.nombre_completo || 'Médico'} el ${visita.fecha_visita} fue confirmada.`,
                metadata: { visita_id: id },
              })
            }

            // Programar recordatorio 24h antes
            try {
              await supabase.functions.invoke('programar-recordatorio', {
                body: {
                  tipo: 'visita',
                  referencia_id: id,
                  horas_antes: 24,
                },
              })
            } catch (recErr) {
              console.error('Error programando recordatorio de visita:', recErr)
            }
          } else if (accion === 'rechazar') {
            await enviarEmail({
              to: visita.visitador.email,
              subject: `Visita rechazada - ${visita.medico?.nombre_completo || 'Médico'}`,
              html: buildHtmlVisitaRechazada({
                medicoNombre: visita.medico?.nombre_completo || 'Médico',
                fecha: visita.fecha_visita,
                comentario: cambios?.comentario || visita.comentario_admin,
              }),
              tipo: 'visita_rechazada',
            })

            // Notificación in-app al visitador
            if (visita.cuenta_proveedor_id) {
              await crearNotificacionInApp({
                usuario_id: visita.cuenta_proveedor_id,
                tipo: 'visita_rechazada',
                titulo: 'Visita rechazada',
                mensaje: `Tu visita con ${visita.medico?.nombre_completo || 'Médico'} el ${visita.fecha_visita} no fue aprobada.`,
                metadata: { visita_id: id },
              })
            }
          }
        } catch (e) {
          console.error('Error notificando visita:', e)
        }
      }

      toast.success(accion === 'aprobar' ? 'Visita aprobada' : accion === 'rechazar' ? 'Visita rechazada' : 'Visita modificada')
      fetchVisitas()
      return true
    } catch (err: any) {
      toast.error('Error administrando visita')
      console.error(err)
      return false
    } finally {
      setSaving(false)
    }
  }

  const checkinVisita = async (id: string, evidenciaFile?: File): Promise<boolean> => {
    setSaving(true)
    let evidenciaUrl: string | null = null

    if (evidenciaFile) {
      const fileExt = evidenciaFile.name.split('.').pop()
      const filePath = `${empresa?.id}/${id}/checkin_${Date.now()}.${fileExt}`
      const { error: upError } = await supabase.storage
        .from('evidencias-visitas')
        .upload(filePath, evidenciaFile, { upsert: true })
      if (upError) {
        toast.error('Error subiendo evidencia')
        console.error(upError)
      } else {
        const { data } = supabase.storage.from('evidencias-visitas').getPublicUrl(filePath)
        evidenciaUrl = data.publicUrl
      }
    }

    let lat: number | null = null
    let lng: number | null = null
    try {
      const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, { timeout: 5000 })
      })
      lat = pos.coords.latitude
      lng = pos.coords.longitude
    } catch {
      // Geolocalización opcional
    }

    const { error } = await supabase.from('visitas_agendadas').update({
      checkin_fecha: new Date().toISOString(),
      checkin_lat: lat,
      checkin_lng: lng,
      checkin_evidencia_url: evidenciaUrl,
      estado: 'confirmada',
    }).eq('id', id)

    setSaving(false)
    if (error) {
      toast.error('Error registrando check-in')
      console.error(error)
      return false
    }
    toast.success('Check-in registrado')
    fetchVisitas()
    return true
  }

  const checkoutVisita = async (id: string, notas: string): Promise<boolean> => {
    setSaving(true)
    const { error } = await supabase.from('visitas_agendadas').update({
      checkout_fecha: new Date().toISOString(),
      checkout_notas: notas,
      visita_concretada: true,
      estado: 'completada',
    }).eq('id', id)
    setSaving(false)
    if (error) {
      toast.error('Error registrando check-out')
      console.error(error)
      return false
    }
    toast.success('Check-out registrado')
    fetchVisitas()
    return true
  }

  const fetchSlotsOcupados = async (medicoId: string, fechaInicio: string, fechaFin: string) => {
    const { data, error } = await supabase.rpc('get_slots_ocupados', {
      p_medico_id: medicoId,
      p_fecha_inicio: fechaInicio,
      p_fecha_fin: fechaFin,
    })
    if (error) {
      console.error('Error cargando slots ocupados:', error)
      return []
    }
    return (data || []) as { fecha_visita: string; hora_inicio: string; hora_fin: string }[]
  }

  return {
    visitas,
    planesAsignados,
    visitasDisponibles,
    esAdmin,
    rol,
    loading,
    saving,
    fetchVisitas,
    agendarVisita,
    cancelarVisita,
    administrarVisita,
    checkinVisita,
    checkoutVisita,
    fetchSlotsOcupados,
  }
}
