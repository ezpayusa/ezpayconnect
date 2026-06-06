import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'

export interface UbicacionMedico {
  ubicacion_id: string
  medico_id: string
  nombre_completo: string
  email: string
  direccion: string | null
  lat: number | null
  lng: number | null
  notas: string | null
  updated_at: string
}

export interface UbicacionInput {
  direccion: string
  lat?: number | null
  lng?: number | null
  notas?: string
}

export function useUbicacionesMedico() {
  const { empresa } = useProveedorAuth()
  const [ubicaciones, setUbicaciones] = useState<UbicacionMedico[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchUbicaciones = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase.rpc('get_ubicaciones_con_medico', {
      p_empresa_id: empresa.id,
    })
    if (error) {
      toast.error('Error cargando ubicaciones')
      console.error(error)
    } else {
      setUbicaciones((data || []) as UbicacionMedico[])
    }
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => {
    fetchUbicaciones()
  }, [fetchUbicaciones])

  const guardarUbicacion = async (medicoId: string, datos: UbicacionInput): Promise<boolean> => {
    if (!empresa?.id) return false
    setSaving(true)

    // Upsert: si ya existe ubicación para este medico+empresa, actualizar; si no, insertar
    const { data: existente } = await supabase
      .from('ubicaciones_medico_proveedor')
      .select('id')
      .eq('empresa_id', empresa.id)
      .eq('medico_id', medicoId)
      .maybeSingle()

    let error
    if (existente?.id) {
      const { error: updError } = await supabase
        .from('ubicaciones_medico_proveedor')
        .update({
          direccion: datos.direccion || null,
          lat: datos.lat ?? null,
          lng: datos.lng ?? null,
          notas: datos.notas || null,
        })
        .eq('id', existente.id)
      error = updError
    } else {
      const { error: insError } = await supabase
        .from('ubicaciones_medico_proveedor')
        .insert({
          empresa_id: empresa.id,
          medico_id: medicoId,
          direccion: datos.direccion || null,
          lat: datos.lat ?? null,
          lng: datos.lng ?? null,
          notas: datos.notas || null,
        })
      error = insError
    }

    setSaving(false)
    if (error) {
      toast.error('Error guardando ubicación')
      console.error(error)
      return false
    }

    toast.success('Ubicación guardada')
    fetchUbicaciones()
    return true
  }

  const eliminarUbicacion = async (ubicacionId: string): Promise<boolean> => {
    if (!confirm('¿Eliminar esta ubicación?')) return false
    setSaving(true)
    const { error } = await supabase
      .from('ubicaciones_medico_proveedor')
      .delete()
      .eq('id', ubicacionId)
    setSaving(false)
    if (error) {
      toast.error('Error eliminando ubicación')
      console.error(error)
      return false
    }
    toast.success('Ubicación eliminada')
    fetchUbicaciones()
    return true
  }

  // Geocodificación vía Edge Function de Supabase (evita CORS del navegador)
  const geocodificar = async (direccion: string): Promise<{ lat: number; lng: number } | null> => {
    try {
      const { data, error } = await supabase.functions.invoke('geocodificar', {
        body: { direccion },
      })
      if (error || !data || data.error) {
        console.error('Error geocodificando:', error || data?.error)
        return null
      }
      return { lat: data.lat, lng: data.lng }
    } catch (err) {
      console.error('Error geocodificando:', err)
      return null
    }
  }

  return {
    ubicaciones,
    loading,
    saving,
    fetchUbicaciones,
    guardarUbicacion,
    eliminarUbicacion,
    geocodificar,
  }
}
