import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { Paciente } from '@/types'

export function usePacientes() {
  const [pacientes, setPacientes] = useState<Paciente[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchPacientes = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('pacientes')
      .select('*')
      .eq('activo', true)
      .order('created_at', { ascending: false })
    if (error) setError(error.message)
    else setPacientes(data || [])
    setLoading(false)
  }, [])

  useEffect(() => { fetchPacientes() }, [fetchPacientes])

  const createPaciente = async (paciente: Partial<Paciente>) => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return { error: 'Debes iniciar sesion para crear pacientes' }
    
    if (!paciente.nombre || !paciente.apellido) {
      return { error: 'Nombre y apellido son requeridos' }
    }
    
    const { data, error } = await supabase.from('pacientes').insert({
      nombre: paciente.nombre,
      apellido: paciente.apellido,
      fecha_nacimiento: paciente.fecha_nacimiento || null,
      genero: paciente.genero || null,
      telefono: paciente.telefono || null,
      email: paciente.email || null,
      direccion: paciente.direccion || null,
      emergencia_nombre: paciente.emergencia_nombre || null,
      emergencia_telefono: paciente.emergencia_telefono || null,
      alergias: paciente.alergias || null,
      notas: paciente.notas || null,
      medico_id: user.id,
      activo: true
    }).select().single()
    
    if (error) {
      console.error('Error creating paciente:', error)
      return { data: null, error: `Error: ${error.message} (${error.code})` }
    }
    
    setPacientes(prev => [data, ...prev])
    return { data, error: null }
  }

  const updatePaciente = async (id: number, updates: Partial<Paciente>) => {
    const { data, error } = await supabase.from('pacientes').update(updates).eq('id', id).select().single()
    if (!error) setPacientes(prev => prev.map(p => p.id === id ? data : p))
    return { data, error }
  }

  const deletePaciente = async (id: number) => {
    const { error } = await supabase.from('pacientes').update({ activo: false }).eq('id', id)
    if (!error) setPacientes(prev => prev.filter(p => p.id !== id))
    return { error }
  }

  return { pacientes, loading, error, fetchPacientes, createPaciente, updatePaciente, deletePaciente }
}
