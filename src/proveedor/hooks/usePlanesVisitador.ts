import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'
import type { PlanBase, PlanConfiguracion, PlanAsignacion } from '@/types/planes'

export interface PlanProveedorDisponible {
  configId: string
  nombre: string
  descripcion: string
  precio: number
  moneda: string
  atributos: Record<string, any>
  planBase: PlanBase
  configuracion: PlanConfiguracion
}

export function usePlanesVisitador() {
  const { empresa } = useProveedorAuth()
  const [planesDisponibles, setPlanesDisponibles] = useState<PlanProveedorDisponible[]>([])
  const [planesAsignados, setPlanesAsignados] = useState<PlanAsignacion[]>([])
  const [loading, setLoading] = useState(false)

  // Cargar planes disponibles (del admin) para tipo 'visitador'
  const fetchPlanesDisponibles = useCallback(async () => {
    try {
      // 1. Leer planes_base de tipo visitador
      const { data: baseData, error: baseError } = await supabase
        .from('planes_base')
        .select('*')
        .eq('activo', true)
        .eq('tipo', 'visitador')

      if (baseError) throw baseError
      const bases = (baseData || []) as PlanBase[]
      if (bases.length === 0) {
        setPlanesDisponibles([])
        return
      }

      // 2. Leer configuraciones de esos planes (filtrado por país de la empresa)
      if (!empresa?.pais_id) {
        setPlanesDisponibles([])
        return
      }
      const baseIds = bases.map((b) => b.id)
      const { data: configData, error: configError } = await supabase
        .from('planes_configuracion')
        .select('*')
        .eq('activo', true)
        .eq('pais_id', empresa.pais_id)
        .in('plan_base_id', baseIds)

      if (configError) throw configError
      const configs = (configData || []) as PlanConfiguracion[]

      const mapeados: PlanProveedorDisponible[] = configs
        .map((c) => {
          const base = bases.find((b) => b.id === c.plan_base_id)
          if (!base) return null
          return {
            configId: c.id,
            nombre: base.nombre,
            descripcion: base.descripcion,
            precio: c.precio_local ?? c.precio_anual ?? base.precio_base ?? 0,
            moneda: c.moneda_local ?? base.moneda ?? 'GTQ',
            atributos: base.atributos || {},
            planBase: base,
            configuracion: c,
          }
        })
        .filter(Boolean) as PlanProveedorDisponible[]

      setPlanesDisponibles(mapeados)
    } catch (err: any) {
      toast.error('Error cargando planes disponibles')
      console.error(err)
    }
  }, [empresa])

  // Cargar planes asignados a la empresa proveedora vía RPC (evita problemas RLS con joins)
  const fetchPlanesAsignados = useCallback(async () => {
    if (!empresa?.id) return
    try {
      const { data, error } = await supabase.rpc('get_planes_visitador_proveedor', {
        p_empresa_id: empresa.id,
      })
      if (error) throw error

      const rows = (data || []) as any[]
      const asigs: PlanAsignacion[] = rows.map((row: any) => ({
        id: row.asignacion_id,
        plan_config_id: row.plan_config_id,
        estado: row.estado,
        fecha_inicio: row.fecha_inicio,
        fecha_fin: row.fecha_fin,
        visitas_usadas: row.visitas_usadas,
        precio_aplicado: row.precio_aplicado,
        moneda: row.moneda,
        plan_configuracion: row.plan_config_id
          ? {
              id: row.plan_config_id,
              plan_base: {
                nombre: row.plan_nombre,
                descripcion: row.plan_descripcion,
                atributos: {
                  visitas_incluidas: row.visitas_incluidas,
                  duracion_dias: row.duracion_dias,
                },
                tipo: 'visitador',
              } as any,
            }
          : undefined,
      }))

      setPlanesAsignados(asigs)
    } catch (err: any) {
      toast.error('Error cargando planes asignados')
      console.error(err)
    }
  }, [empresa?.id])

  const cargarTodo = useCallback(async () => {
    setLoading(true)
    await Promise.all([fetchPlanesDisponibles(), fetchPlanesAsignados()])
    setLoading(false)
  }, [fetchPlanesDisponibles, fetchPlanesAsignados])

  useEffect(() => {
    cargarTodo()
  }, [cargarTodo])

  // Calcular visitas disponibles desde planes_asignaciones activos de tipo visitador
  const visitasDisponibles = planesAsignados
    .filter((a) => {
      if (a.estado !== 'activo') return false
      if (a.fecha_fin && new Date(a.fecha_fin) < new Date()) return false
      const tipoPlan = a.plan_configuracion?.plan_base?.tipo
      return tipoPlan === 'visitador'
    })
    .reduce((acc, a) => {
      const visitasIncluidas = a.plan_configuracion?.plan_base?.atributos?.visitas_incluidas || 0
      const usadas = a.visitas_usadas || 0
      return acc + Math.max(0, visitasIncluidas - usadas)
    }, 0)

  // Para compatibilidad con componentes existentes que esperan planesContratados
  const planesContratadosLegacy = planesAsignados
    .filter((a) => a.plan_configuracion?.plan_base?.tipo === 'visitador')
    .map((a) => ({
      id: a.id,
      empresa_id: a.empresa_id || '',
      plan_visitador_id: 0,
      pais_id: null as number | null,
      cantidad_visitas_incluidas: a.plan_configuracion?.plan_base?.atributos?.visitas_incluidas || 0,
      visitas_usadas: a.visitas_usadas || 0,
      precio_pagado: a.precio_aplicado || 0,
      fecha_inicio: a.fecha_inicio,
      fecha_fin: a.fecha_fin || a.fecha_inicio,
      estado: a.estado as any,
      created_at: a.created_at || '',
      updated_at: a.updated_at || '',
    }))

  return {
    // Nuevos datos dinámicos
    planesDisponibles,
    planesAsignados,
    // Legacy compat
    planesBase: planesDisponibles.map((p) => ({
      id: p.configId,
      nombre: p.nombre,
      descripcion: p.descripcion,
      cantidad_visitas: p.atributos.visitas_incluidas || 0,
      precio_referencia: p.precio,
      moneda: p.moneda,
      duracion_dias: p.atributos.duracion_dias || 30,
    })),
    planesContratados: planesContratadosLegacy,
    visitasDisponibles,
    loading,
    recargar: cargarTodo,
    fetchPlanesContratados: fetchPlanesAsignados,
  }
}
