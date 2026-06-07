import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'

export interface PlanPublicidadConfigRow {
  id: number
  pais_id: string
  pais_nombre?: string
  pais_codigo?: string
  plan_publicidad_id: number
  plan_nombre?: string
  precio_local: number
  moneda_local: string
  activo: boolean
  created_at: string
}

export function usePlanesPublicidadConfig() {
  const [configs, setConfigs] = useState<PlanPublicidadConfigRow[]>([])
  const [paises, setPaises] = useState<{ id: string; nombre: string; codigo: string; moneda: string }[]>([])
  const [planesBase, setPlanesBase] = useState<{ id: number; nombre: string; orden: number }[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchPaises = useCallback(async () => {
    const { data } = await supabase
      .from('configuracion_pais')
      .select('id, nombre, codigo, moneda')
      .eq('activo', true)
      .order('nombre')
    setPaises(data || [])
  }, [])

  const fetchPlanesBase = useCallback(async () => {
    const { data } = await supabase
      .from('planes_publicidad')
      .select('id, nombre, orden')
      .eq('activo', true)
      .order('orden')
    setPlanesBase(data || [])
  }, [])

  const fetchConfigs = useCallback(async () => {
    setLoading(true)
    // Query separada: planes_publicidad_config
    const { data: configsData, error } = await supabase
      .from('planes_publicidad_config')
      .select('*')
      .order('created_at')

    if (error) {
      toast.error('Error cargando configuraciones')
      console.error(error)
      setLoading(false)
      return
    }

    // Enriquecer con nombres de país y plan
    const paisesMap = new Map(paises.map((p) => [p.id, p]))
    const planesMap = new Map(planesBase.map((p) => [p.id, p]))

    const enriched = (configsData || []).map((c: any) => ({
      ...c,
      pais_nombre: paisesMap.get(c.pais_id)?.nombre || c.pais_id,
      pais_codigo: paisesMap.get(c.pais_id)?.codigo || '',
      plan_nombre: planesMap.get(c.plan_publicidad_id)?.nombre || `Plan #${c.plan_publicidad_id}`,
    }))

    setConfigs(enriched)
    setLoading(false)
  }, [paises, planesBase])

  useEffect(() => {
    fetchPaises()
    fetchPlanesBase()
  }, [fetchPaises, fetchPlanesBase])

  useEffect(() => {
    if (paises.length > 0 && planesBase.length > 0) {
      fetchConfigs()
    }
  }, [paises, planesBase, fetchConfigs])

  const updateConfig = async (id: number, updates: Partial<PlanPublicidadConfigRow>) => {
    setSaving(true)
    const { error } = await supabase
      .from('planes_publicidad_config')
      .update(updates)
      .eq('id', id)

    if (error) {
      toast.error('Error guardando: ' + error.message)
      setSaving(false)
      return false
    }

    setConfigs((prev) => prev.map((c) => (c.id === id ? { ...c, ...updates } : c)))
    toast.success('Guardado correctamente')
    setSaving(false)
    return true
  }

  const crearConfigParaPais = async (paisId: string) => {
    setSaving(true)
    const { data: paisData } = await supabase
      .from('configuracion_pais')
      .select('moneda')
      .eq('id', paisId)
      .single()

    const moneda = paisData?.moneda || 'GTQ'

    const inserts = planesBase.map((p) => ({
      pais_id: paisId,
      plan_publicidad_id: p.id,
      precio_local: 0,
      moneda_local: moneda,
      activo: true,
    }))

    const { error } = await supabase.from('planes_publicidad_config').insert(inserts)

    if (error) {
      toast.error('Error creando configuraciones: ' + error.message)
      setSaving(false)
      return false
    }

    toast.success('Configuraciones creadas')
    await fetchConfigs()
    setSaving(false)
    return true
  }

  return {
    configs,
    paises,
    planesBase,
    loading,
    saving,
    fetchConfigs,
    updateConfig,
    crearConfigParaPais,
  }
}
