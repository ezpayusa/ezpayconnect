import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { usePaisFiltro } from './usePaisFiltro'

export interface Clinica {
  id: string
  doctor_id: string
  nombre: string
  direccion: string
  telefono: string
  email: string
  horarios: Record<string, { activo: boolean; inicio: string; fin: string }>
  activa: boolean
  created_at: string
}

const defaultHorarios = {
  lunes: { activo: true, inicio: '08:00', fin: '17:00' },
  martes: { activo: true, inicio: '08:00', fin: '17:00' },
  miercoles: { activo: true, inicio: '08:00', fin: '17:00' },
  jueves: { activo: true, inicio: '08:00', fin: '17:00' },
  viernes: { activo: true, inicio: '08:00', fin: '17:00' },
  sabado: { activo: false, inicio: '08:00', fin: '12:00' },
  domingo: { activo: false, inicio: '08:00', fin: '12:00' },
}

export function useClinicas() {
  const [clinicas, setClinicas] = useState<Clinica[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { paisId } = usePaisFiltro()

  const cargarClinicas = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }

      const { data, error: dbError } = await supabase
        .from('clinicas')
        .select('*')
        .eq('doctor_id', user.id)
        .order('created_at', { ascending: true })

      if (dbError) throw dbError

      setClinicas(data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    cargarClinicas()
  }, [cargarClinicas])

  const crearClinica = useCallback(async (clinica: Partial<Clinica>) => {
    setSaving(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No hay usuario autenticado')

      // Si es la primera clínica, activarla automáticamente
      const esPrimera = clinicas.length === 0

      // Crear vía RPC canónica: clínica (dueño=doctor_id) + membresía (es_principal) ATÓMICAS.
      // Reemplaza el insert directo a clinicas, que dejaba al dueño SIN membresía (modelo inconsistente).
      const { data: nuevaId, error: rpcError } = await supabase.rpc('crear_clinica_con_dueno', {
        p_doctor_id: user.id,
        p_nombre: clinica.nombre || 'Nueva Clínica',
        p_pais_id: paisId,
        p_direccion: clinica.direccion || '',
        p_telefono: clinica.telefono || '',
        p_email: clinica.email || '',
      })
      if (rpcError) throw rpcError

      // La RPC no maneja horarios ni el flag activa; preservamos el comportamiento previo del hook.
      const { data, error: updError } = await supabase
        .from('clinicas')
        .update({ horarios: clinica.horarios || defaultHorarios, activa: esPrimera })
        .eq('id', nuevaId)
        .eq('doctor_id', user.id)
        .select()
        .single()

      if (updError) throw updError
      if (data) {
        setClinicas(prev => [...prev, data])
      }

      return { success: true, data }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    } finally {
      setSaving(false)
    }
  }, [clinicas.length, paisId])

  const actualizarClinica = useCallback(async (id: string, cambios: Partial<Clinica>) => {
    setSaving(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No hay usuario autenticado')

      const { error: dbError } = await supabase
        .from('clinicas')
        .update({
          ...cambios,
          updated_at: new Date().toISOString(),
        })
        .eq('id', id)
        .eq('doctor_id', user.id)

      if (dbError) throw dbError

      setClinicas(prev => prev.map(c => c.id === id ? { ...c, ...cambios } : c))
      return { success: true }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    } finally {
      setSaving(false)
    }
  }, [])

  const eliminarClinica = useCallback(async (id: string) => {
    setSaving(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No hay usuario autenticado')

      // Verificar si es la clínica activa
      const clinicaAEliminar = clinicas.find(c => c.id === id)

      const { error: dbError } = await supabase
        .from('clinicas')
        .delete()
        .eq('id', id)
        .eq('doctor_id', user.id)

      if (dbError) throw dbError

      setClinicas(prev => {
        const nuevasClinicas = prev.filter(c => c.id !== id)

        // Si eliminamos la activa y quedan otras, activar la primera
        if (clinicaAEliminar?.activa && nuevasClinicas.length > 0) {
          const primera = nuevasClinicas[0]
          // Actualizar en Supabase
          supabase
            .from('clinicas')
            .update({ activa: true })
            .eq('id', primera.id)
            .then(() => {
              // Actualizar config
              supabase
                .from('configuracion')
                .update({ clinica_activa_id: primera.id })
                .eq('doctor_id', user.id)
                .then()
            })

          return nuevasClinicas.map((c, i) => i === 0 ? { ...c, activa: true } : c)
        }

        return nuevasClinicas
      })

      return { success: true }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    } finally {
      setSaving(false)
    }
  }, [clinicas])

  const setClinicaActiva = useCallback(async (clinicaId: string) => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No hay usuario autenticado')

      // Desactivar TODAS las clínicas del doctor primero
      const { error: errorDesactivar } = await supabase
        .from('clinicas')
        .update({ activa: false })
        .eq('doctor_id', user.id)

      if (errorDesactivar) throw errorDesactivar

      // Activar solo la seleccionada
      const { error: errorActivar } = await supabase
        .from('clinicas')
        .update({ activa: true })
        .eq('id', clinicaId)
        .eq('doctor_id', user.id)

      if (errorActivar) throw errorActivar

      // Actualizar config con la clínica activa
      const { error: errorConfig } = await supabase
        .from('configuracion')
        .update({ clinica_activa_id: clinicaId })
        .eq('doctor_id', user.id)

      if (errorConfig) throw errorConfig

      // Actualizar estado local
      setClinicas(prev => prev.map(c => ({
        ...c,
        activa: c.id === clinicaId
      })))

      return { success: true }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    }
  }, [])

  return {
    clinicas,
    loading,
    saving,
    error,
    cargarClinicas,
    crearClinica,
    actualizarClinica,
    eliminarClinica,
    setClinicaActiva,
  }
}