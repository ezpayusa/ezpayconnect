import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'

export interface Visitador {
  id: string
  nombre_completo: string
  email: string
  telefono?: string
  rol_en_empresa: string
  created_at: string
  visitas_asignadas?: number
  visitas_completadas?: number
}

export interface Invitacion {
  id: string
  token: string
  email: string
  nombre_completo: string
  telefono?: string
  estado: string
  expires_at: string
  created_at: string
}

export function useVisitadoresEmpresa() {
  const { empresa, cuenta } = useProveedorAuth()
  const [visitadores, setVisitadores] = useState<Visitador[]>([])
  const [invitaciones, setInvitaciones] = useState<Invitacion[]>([])
  const [loading, setLoading] = useState(false)

  const fetchVisitadores = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)

    const { data, error } = await supabase
      .from('cuentas_proveedor')
      .select('*')
      .eq('empresa_id', empresa.id)
      .eq('rol_en_empresa', 'visitador_medico')
      .eq('activo', true)

    if (error) {
      console.error('Error cargando visitadores:', error)
      setLoading(false)
      return
    }

    // Calcular estadísticas por visitador
    const visitadoresConStats = await Promise.all(
      (data || []).map(async (v) => {
        const { count: total } = await supabase
          .from('visitas_agendadas')
          .select('*', { count: 'exact', head: true })
          .eq('cuenta_proveedor_id', v.id)

        const { count: completadas } = await supabase
          .from('visitas_agendadas')
          .select('*', { count: 'exact', head: true })
          .eq('cuenta_proveedor_id', v.id)
          .eq('estado', 'completada')

        return {
          id: v.id,
          nombre_completo: v.nombre_completo,
          email: v.email,
          telefono: v.telefono,
          rol_en_empresa: v.rol_en_empresa,
          created_at: v.created_at,
          visitas_asignadas: total || 0,
          visitas_completadas: completadas || 0,
        }
      })
    )

    setVisitadores(visitadoresConStats)

    // Cargar invitaciones pendientes
    const { data: invData } = await supabase
      .from('invitaciones_visitador')
      .select('*')
      .eq('empresa_id', empresa.id)
      .order('created_at', { ascending: false })

    setInvitaciones(invData || [])
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => {
    fetchVisitadores()
  }, [fetchVisitadores])

  const invitarVisitador = async (email: string, nombre: string, telefono?: string): Promise<{ success: boolean; token?: string; url?: string }> => {
    if (!empresa?.id) return { success: false }

    try {
      const { data, error } = await supabase.functions.invoke('invitar-visitador', {
        body: {
          email,
          nombre_completo: nombre,
          telefono,
          empresa_id: empresa.id,
        },
      })

      if (error || data?.error) {
        toast.error(data?.error || 'Error al crear la invitación')
        return { success: false }
      }

      const baseUrl = window.location.origin
      const url = `${baseUrl}/proveedor/registro-visitador?token=${data.token}`

      toast.success('Invitación creada. Comparte el link con el visitador.')
      fetchVisitadores()
      return { success: true, token: data.token, url }
    } catch (err) {
      console.error('Error invitando:', err)
      toast.error('Error al invitar visitador')
      return { success: false }
    }
  }

  return {
    visitadores,
    invitaciones,
    loading,
    fetchVisitadores,
    invitarVisitador,
  }
}
