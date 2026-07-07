import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import type { VisitaAgendada } from '@/proveedor/types/proveedor.types'
import type { PlanAsignacion } from '@/types/planes'
import type { UbicacionVisita } from './useRutaVisitador'
import { toast } from 'sonner'

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
    // pvc = única fuente de visitas (país + bolsa). Se mapea a la forma anidada legacy
    // para no tocar la lógica downstream de planActivo. usadas/restante son DERIVADOS (gate real).
    const { data, error } = await supabase.rpc('get_planes_visitador_proveedor', { p_empresa_id: empresa.id })
    if (error) {
      console.error('Error cargando planes asignados:', error)
      return
    }
    setPlanesAsignados((data || []).map((r: any) => ({
      fecha_fin: r.fecha_fin,
      visitas_usadas: r.usadas,
      plan_configuracion: { plan_base: { tipo: 'visitador', atributos: { visitas_incluidas: r.incluidas } } },
    })) as unknown as PlanAsignacion[])
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
        const { data: medicosData, error: medicosError } = await supabase.rpc('buscar_medicos_proveedor', { p_query: null })
        if (medicosError) {
          // Antes se ignoraba en silencio; ahora se reporta igual que useMedicosDisponibles.
          toast.error('Error buscando médicos')
          console.error(medicosError)
        } else if (medicosData) {
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
      const msg = (error as any).message || ''
      // 23505 = el slot ya fue tomado por otro proveedor entre que lo viste y lo guardaste.
      if ((error as any).code === '23505') {
        toast.error('Ese horario acaba de ser tomado por otro proveedor. Por favor elige otro.', { duration: 6000 })
        return false
      }
      if (msg.includes('SIN_PLAN')) {
        toast.error('Tu empresa no tiene un plan de visitas activo. Contrata un plan para poder agendar.', { duration: 7000 })
        return false
      }
      if (msg.includes('LIMITE_MENSUAL')) {
        toast.error('Alcanzaste el límite de visitas de tu plan este mes. Mejora tu plan para agendar más.', { duration: 7000 })
        return false
      }
      toast.error('Error agendando visita')
      console.error(error)
      return false
    }

    // Agendar-confirmada consume una visita: refrescar el saldo DERIVADO (get_planes_visitador_proveedor
    // / private.pvc_usadas). Ya NO se incrementa planes_asignaciones.visitas_usadas (contador legacy muerto).
    if (estadoFinal === 'confirmada') {
      fetchPlanesAsignados()
    }

    // Notificar al admin si fue propuesta por visitador
    if (!esAdmin && estadoFinal === 'propuesta' && empresa?.email_contacto && insertData) {
      try {
        // Notificación in-app a admins/editores (RPC gateado: gate propuesta_por=auth.uid, deriva destinatarios del ref).
        // El email de "visita propuesta" ahora lo dispara ESTA RPC server-side (mig 224), no el front.
        await supabase.rpc('notificar_visita_propuesta', { p_visita_id: insertData.id })
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
    if (!confirm('¿Cancelar esta visita?')) return false

    setSaving(true)
    try {
      // Ownership + máquina de estados + ventana ahora server-side (RPC cancelar_visita, mig 211):
      // valida que seas el dueño (o super_admin), que el estado sea cancelable y que estés dentro de la
      // ventana de fecha_limite_cancelacion. La ventana ya NO se chequea client-side: la fuente única del
      // texto de error es data.error de la RPC. Ya NO se decrementa visitas_usadas (contador legacy muerto);
      // el saldo real es derivado por get_planes_visitador_proveedor (private.pvc_usadas).
      const { data, error } = await supabase.rpc('cancelar_visita', { p_visita_id: id })
      if (error) throw error                    // RAISE EXCEPTION server-side (ej. 'No autorizado...')
      if (data?.error) {                         // jsonb {error:'Visita no encontrada'|'...fecha límite'|'...estado actual'}
        toast.error(data.error)
        return false
      }

      toast.success('Visita cancelada')
      fetchVisitas()
      fetchPlanesAsignados()                     // refrescar saldo DERIVADO (cancelar libera slot en pvc_usadas)
      return true
    } catch (err: any) {
      // La RPC lanza RAISE EXCEPTION si no sos el dueño ni super_admin (mig 211).
      const msg = typeof err?.message === 'string' && err.message.includes('No autorizado')
        ? 'No tenés permiso para cancelar esta visita.'
        : 'Error cancelando visita'
      toast.error(msg)
      console.error(err)
      return false
    } finally {
      setSaving(false)
    }
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
      // Autorización + cambio de estado ahora server-side vía la RPC hardeneada (migs 075+210):
      // revalida super_admin / (miembro de la empresa AND private.puede_aprobar_visitas) y aplica
      // aprobar/rechazar/modificar atómicamente. Reemplaza el UPDATE directo previo. comentario_admin
      // lo maneja la RPC con COALESCE (si p_comentario es null, preserva el previo en vez de borrarlo).
      // Ya NO se incrementa planes_asignaciones.visitas_usadas (contador legacy roto): el saldo real
      // es derivado por get_planes_visitador_proveedor (private.pvc_usadas).
      const { data, error } = await supabase.rpc('administrar_visita', {
        p_visita_id: id,
        p_accion: accion,
        p_nueva_fecha: cambios?.fecha_visita ?? null,
        p_nueva_hora_inicio: cambios?.hora_inicio ?? null,
        p_nueva_hora_fin: cambios?.hora_fin ?? null,
        p_comentario: cambios?.comentario || null,
      })
      if (error) throw error                    // RAISE EXCEPTION server-side (ej. 'No autorizado...')
      if (data?.error) {                         // jsonb {error:'Visita no encontrada'|'Acción no válida'}
        toast.error(data.error)
        return false
      }

      // Refrescar el saldo DERIVADO de visitas tras aprobar/modificar (aprobar cambia pvc_usadas).
      if (accion === 'aprobar' || accion === 'modificar') {
        fetchPlanesAsignados()
      }

      // Notificar al visitador
      const visita = visitas.find((v) => v.id === id)
      if (visita?.visitador?.email) {
        try {
          if (accion === 'aprobar' || accion === 'modificar') {
            // Notificación in-app al visitador (RPC gateado: rama por visita.estado del ref; gate relación cuenta∈empresa).
            // El email "visita aprobada" ahora lo dispara ESTA RPC server-side (mig 224), no el front.
            await supabase.rpc('notificar_visita_resultado', { p_visita_id: id })

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
            // Notificación in-app al visitador (RPC gateado). El email "visita rechazada" ahora lo dispara
            // ESTA RPC server-side (mig 224), no el front.
            await supabase.rpc('notificar_visita_resultado', { p_visita_id: id })
          }
        } catch (e) {
          console.error('Error notificando visita:', e)
        }
      }

      toast.success(accion === 'aprobar' ? 'Visita aprobada' : accion === 'rechazar' ? 'Visita rechazada' : 'Visita modificada')
      fetchVisitas()
      return true
    } catch (err: any) {
      // La RPC lanza RAISE EXCEPTION en el gate de autorización (mig 210): p.ej. un visitador
      // sin permiso de aprobar que intente llegar acá queda bloqueado server-side.
      const msg = typeof err?.message === 'string' && err.message.includes('No autorizado')
        ? 'No tenés permiso para administrar esta visita.'
        : 'Error administrando visita'
      toast.error(msg)
      console.error(err)
      return false
    } finally {
      setSaving(false)
    }
  }

  const checkinVisita = async (id: string, evidenciaFile?: File): Promise<boolean> => {
    setSaving(true)
    try {
      // 1) Subir la evidencia (opcional) directo al bucket privado — el INSERT ya está acotado por
      //    mig 209 (ownership + path scoping). Guardamos el PATH (no getPublicUrl: bucket privado
      //    desde mig 212). Si el upload falla, seguimos sin evidencia (mismo comportamiento previo).
      let filePath: string | null = null
      if (evidenciaFile) {
        const fileExt = evidenciaFile.name.split('.').pop()
        const path = `${empresa?.id}/${id}/checkin_${Date.now()}.${fileExt}`
        const { error: upError } = await supabase.storage
          .from('evidencias-visitas')
          .upload(path, evidenciaFile, { upsert: true })
        if (upError) {
          toast.error('Error subiendo evidencia')
          console.error(upError)
        } else {
          filePath = path
        }
      }

      // 2) Geolocalización (opcional).
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

      // 3) Registrar el check-in vía RPC hardeneada (mig 213): valida ownership, estado, fecha=hoy,
      //    doble check-in y que el path de evidencia corresponda a la visita. Guarda el PATH.
      const { data, error } = await supabase.rpc('checkin_visita', {
        p_visita_id: id,
        p_evidencia_path: filePath,
        p_lat: lat,
        p_lng: lng,
      })
      if (error) throw error                     // RAISE server-side (ej. 'No autorizado...')
      if (data?.error) { toast.error(data.error); return false }

      toast.success('Check-in registrado')
      fetchVisitas()
      return true
    } catch (err: any) {
      const msg = typeof err?.message === 'string' && err.message.includes('No autorizado')
        ? 'No tenés permiso para hacer check-in de esta visita.'
        : 'Error registrando check-in'
      toast.error(msg)
      console.error(err)
      return false
    } finally {
      setSaving(false)
    }
  }

  const checkoutVisita = async (id: string, notas: string): Promise<boolean> => {
    setSaving(true)
    try {
      // Check-out vía RPC hardeneada (mig 213): valida ownership, estado, check-in previo y doble
      // check-out. Reemplaza el UPDATE directo previo.
      const { data, error } = await supabase.rpc('checkout_visita', {
        p_visita_id: id,
        p_notas: notas,
      })
      if (error) throw error                     // RAISE server-side (ej. 'No autorizado...')
      if (data?.error) { toast.error(data.error); return false }

      toast.success('Check-out registrado')
      fetchVisitas()
      return true
    } catch (err: any) {
      const msg = typeof err?.message === 'string' && err.message.includes('No autorizado')
        ? 'No tenés permiso para hacer check-out de esta visita.'
        : 'Error registrando check-out'
      toast.error(msg)
      console.error(err)
      return false
    } finally {
      setSaving(false)
    }
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
