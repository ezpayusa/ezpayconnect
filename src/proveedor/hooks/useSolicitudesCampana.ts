import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import type { SolicitudCampana } from '@/proveedor/types/proveedor.types'
import { toast } from 'sonner'

export function useSolicitudesCampana() {
  const { empresa, cuenta } = useProveedorAuth()
  const [solicitudes, setSolicitudes] = useState<SolicitudCampana[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchSolicitudes = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('solicitudes_campana')
      .select('*')
      .eq('empresa_id', empresa.id)
      .order('created_at', { ascending: false })

    if (error) {
      toast.error('Error cargando campañas')
      console.error(error)
    } else {
      setSolicitudes(data || [])
    }
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => {
    fetchSolicitudes()
  }, [fetchSolicitudes])

  const crearSolicitud = async (
    campana: Partial<SolicitudCampana>,
    imagenFile?: File | null
  ): Promise<boolean> => {
    if (!empresa?.id || !cuenta) {
      toast.error('No hay empresa vinculada')
      return false
    }

    setSaving(true)
    let imagen_url: string | null = campana.imagen_url || null

    if (imagenFile) {
      const fileExt = imagenFile.name.split('.').pop()
      const fileName = `${empresa.id}/${Date.now()}.${fileExt}`
      const { error: uploadError } = await supabase.storage
        .from('campanas')
        .upload(fileName, imagenFile, { upsert: true })

      if (uploadError) {
        toast.error('Error subiendo imagen')
        console.error(uploadError)
        setSaving(false)
        return false
      }

      const { data: publicUrlData } = supabase.storage.from('campanas').getPublicUrl(fileName)
      imagen_url = publicUrlData.publicUrl
    }

    const { error } = await supabase.from('solicitudes_campana').insert({
      empresa_id: empresa.id,
      cuenta_proveedor_id: cuenta.id,
      titulo: campana.titulo || '',
      descripcion: campana.descripcion || null,
      tipo: campana.tipo || 'general',
      imagen_url,
      link_url: campana.link_url || null,
      fecha_inicio: campana.fecha_inicio,
      fecha_fin: campana.fecha_fin,
      condicion_filtro: campana.condicion_filtro || null,
      genero_filtro: campana.genero_filtro || null,
      edad_min: campana.edad_min || null,
      edad_max: campana.edad_max || null,
      estado: 'enviada',
    })

    setSaving(false)
    if (error) {
      toast.error('Error creando campaña')
      console.error(error)
      return false
    }

    toast.success('Campaña enviada a revisión')
    fetchSolicitudes()
    return true
  }

  const actualizarSolicitud = async (
    id: string,
    campana: Partial<SolicitudCampana>,
    imagenFile?: File | null
  ): Promise<boolean> => {
    setSaving(true)
    let imagen_url: string | null | undefined = campana.imagen_url

    if (imagenFile) {
      const fileExt = imagenFile.name.split('.').pop()
      const fileName = `${empresa?.id}/${Date.now()}.${fileExt}`
      const { error: uploadError } = await supabase.storage
        .from('campanas')
        .upload(fileName, imagenFile, { upsert: true })

      if (uploadError) {
        toast.error('Error subiendo imagen')
        console.error(uploadError)
        setSaving(false)
        return false
      }

      const { data: publicUrlData } = supabase.storage.from('campanas').getPublicUrl(fileName)
      imagen_url = publicUrlData.publicUrl
    }

    const updateData: any = {
      titulo: campana.titulo,
      descripcion: campana.descripcion,
      tipo: campana.tipo,
      link_url: campana.link_url,
      fecha_inicio: campana.fecha_inicio,
      fecha_fin: campana.fecha_fin,
      condicion_filtro: campana.condicion_filtro,
      genero_filtro: campana.genero_filtro,
      edad_min: campana.edad_min,
      edad_max: campana.edad_max,
    }
    if (imagen_url !== undefined) updateData.imagen_url = imagen_url

    const { error } = await supabase.from('solicitudes_campana').update(updateData).eq('id', id)
    setSaving(false)

    if (error) {
      toast.error('Error actualizando campaña')
      console.error(error)
      return false
    }

    toast.success('Campaña actualizada')
    fetchSolicitudes()
    return true
  }

  const eliminarSolicitud = async (id: string): Promise<boolean> => {
    if (!confirm('¿Eliminar esta campaña?')) return false
    const { error } = await supabase.from('solicitudes_campana').delete().eq('id', id)
    if (error) {
      toast.error('Error eliminando campaña')
      return false
    }
    toast.success('Campaña eliminada')
    fetchSolicitudes()
    return true
  }

  return {
    solicitudes,
    loading,
    saving,
    fetchSolicitudes,
    crearSolicitud,
    actualizarSolicitud,
    eliminarSolicitud,
  }
}
