import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import type { DisponibilidadMedico } from '@/proveedor/types/proveedor.types'

const DIAS = [
  'Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'
]

export function useDisponibilidadMedico() {
  const [disponibilidad, setDisponibilidad] = useState<DisponibilidadMedico[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchDisponibilidad = useCallback(async () => {
    setLoading(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setLoading(false); return }

    const { data, error } = await supabase
      .from('disponibilidad_medico')
      .select('*')
      .eq('medico_id', user.id)
      .eq('activo', true)
      .order('dia_semana', { ascending: true })
      .order('hora_inicio', { ascending: true })

    if (error) {
      toast.error('Error cargando disponibilidad')
      console.error(error)
    } else {
      setDisponibilidad(data || [])
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchDisponibilidad()
  }, [fetchDisponibilidad])

  const crearSlot = async (slot: Partial<DisponibilidadMedico>) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return false

    setSaving(true)
    const { error } = await supabase.from('disponibilidad_medico').insert({
      medico_id: user.id,
      dia_semana: slot.dia_semana,
      hora_inicio: slot.hora_inicio,
      hora_fin: slot.hora_fin,
      duracion_slot: slot.duracion_slot || 30,
      clinica_id: slot.clinica_id || null,
      activo: true,
    })
    setSaving(false)

    if (error) {
      toast.error('Error guardando disponibilidad')
      console.error(error)
      return false
    }

    toast.success('Disponibilidad agregada')
    fetchDisponibilidad()
    return true
  }

  const eliminarSlot = async (id: string) => {
    if (!confirm('¿Eliminar este horario?')) return false
    const { error } = await supabase.from('disponibilidad_medico').delete().eq('id', id)
    if (error) {
      toast.error('Error eliminando horario')
      return false
    }
    toast.success('Horario eliminado')
    fetchDisponibilidad()
    return true
  }

  return {
    disponibilidad,
    loading,
    saving,
    DIAS,
    fetchDisponibilidad,
    crearSlot,
    eliminarSlot,
  }
}
