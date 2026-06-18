import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import { toast } from 'sonner'
import type { PlanBase, PlanConfiguracion } from '@/types/planes'

// Fila pvc (única fuente de visitas: país + bolsa). incluidas/restante NULL = ilimitado.
interface PvcRow {
  id: string
  pais_id: string
  pais_nombre: string
  cantidad_visitas_incluidas: number | null
  visitas_usadas: number
  restante: number | null
  ilimitado: boolean
  fecha_inicio: string
  fecha_fin: string
  estado: string
}

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
  const [planesAsignados, setPlanesAsignados] = useState<PvcRow[]>([])
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
      setPlanesAsignados(rows.map((r: any): PvcRow => ({
        id: r.pvc_id,
        pais_id: r.pais_id,
        pais_nombre: r.pais_nombre,
        cantidad_visitas_incluidas: r.incluidas,   // null = ilimitado
        visitas_usadas: r.usadas,
        restante: r.restante,                       // null = ilimitado
        ilimitado: r.ilimitado,
        fecha_inicio: r.fecha_inicio,
        fecha_fin: r.fecha_fin,
        estado: r.estado,
      })))
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

  // Bolsa restante = Σ restante de pvc activos (DERIVADO del gate real; ilimitado no suma número)
  const visitasDisponibles = planesAsignados
    .filter((a) => a.estado === 'activo' && !a.ilimitado)
    .reduce((acc, a) => acc + Math.max(0, a.restante ?? 0), 0)
  const tieneIlimitado = planesAsignados.some((a) => a.estado === 'activo' && a.ilimitado)

  // planesContratados (lo que VisitadorPlanesPage espera: cantidad_visitas_incluidas, fecha_fin, estado)
  const planesContratadosLegacy = planesAsignados.map((a) => ({
    id: a.id,
    empresa_id: '',
    plan_visitador_id: 0,
    pais_id: a.pais_id as any,
    cantidad_visitas_incluidas: a.cantidad_visitas_incluidas, // null = ilimitado
    visitas_usadas: a.visitas_usadas,
    precio_pagado: 0,
    fecha_inicio: a.fecha_inicio,
    fecha_fin: a.fecha_fin,
    estado: a.estado as any,
    pais_nombre: a.pais_nombre,
    restante: a.restante,
    ilimitado: a.ilimitado,
    created_at: '',
    updated_at: '',
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
    tieneIlimitado,
    loading,
    recargar: cargarTodo,
    fetchPlanesContratados: fetchPlanesAsignados,
  }
}
