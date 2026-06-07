import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from './usePaisFiltro'
import type { Factura } from '@/types'

export function useFacturas(pacienteId?: number) {
  const [facturas, setFacturas] = useState<Factura[]>([])
  const [loading, setLoading] = useState(true)
  const { paisId } = usePaisFiltro()

  const fetchFacturas = useCallback(async () => {
    setLoading(true)

    let query = supabase
      .from('facturas')
      .select(`*, pacientes(nombre, apellido)`)
      .order('fecha_emision', { ascending: false })

    if (pacienteId) {
      query = query.eq('paciente_id', pacienteId)
    }
    if (paisId) {
      query = query.eq('pais_id', paisId)
    }

    const { data, error } = await query

    if (error) {
      console.error('Error fetching facturas:', error)
    } else {
      const mapped = (data || []).map((f: any) => ({
        ...f,
        paciente_nombre: f.pacientes?.nombre + ' ' + f.pacientes?.apellido
      }))
      setFacturas(mapped)
    }
    setLoading(false)
  }, [pacienteId])

  useEffect(() => { fetchFacturas() }, [fetchFacturas])

  const createFactura = async (factura: Partial<Factura>) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesión' }

    if (!factura.paciente_id || !factura.concepto || !factura.precio_unitario) {
      return { error: 'Paciente, concepto y precio son requeridos' }
    }

    const { data, error } = await supabase.from('facturas').insert({
      paciente_id: factura.paciente_id,
      concepto: factura.concepto,
      cantidad: factura.cantidad || 1,
      precio_unitario: factura.precio_unitario,
      descuento: factura.descuento || 0,
      metodo_pago: factura.metodo_pago || null,
      estado: factura.estado || 'pendiente',
      notas: factura.notas || null,
      medico_id: user.id,
      pais_id: paisId,
    }).select().single()

    if (!error && data) {
      setFacturas(prev => [data, ...prev])
    }

    return { data, error }
  }

  const updateFactura = async (id: number, updates: Partial<Factura>) => {
    const { data, error } = await supabase.from('facturas').update(updates).eq('id', id).select().single()
    if (!error && data) {
      setFacturas(prev => prev.map(f => f.id === id ? data : f))
    }
    return { data, error }
  }

  const deleteFactura = async (id: number) => {
    const { error } = await supabase.from('facturas').delete().eq('id', id)
    if (!error) {
      setFacturas(prev => prev.filter(f => f.id !== id))
    }
    return { error }
  }

  return { facturas, loading, fetchFacturas, createFactura, updateFactura, deleteFactura }
}
