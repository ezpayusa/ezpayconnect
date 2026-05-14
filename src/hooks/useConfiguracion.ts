import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

export interface ConfiguracionData {
  id?: string
  doctor_id?: string
  nombre_completo: string
  especialidad: string
  cedula: string
  telefono: string
  email: string
  nombre_clinica: string
  direccion: string
  telefono_clinica: string
  email_clinica: string
  horarios: Record<string, { activo: boolean; inicio: string; fin: string }>
  precios: Record<string, number>
  metodos_pago: Record<string, boolean>
  notificaciones: Record<string, boolean>
}

const defaultConfig: ConfiguracionData = {
  nombre_completo: '',
  especialidad: '',
  cedula: '',
  telefono: '',
  email: '',
  nombre_clinica: '',
  direccion: '',
  telefono_clinica: '',
  email_clinica: '',
  horarios: {
    lunes: { activo: true, inicio: '08:00', fin: '17:00' },
    martes: { activo: true, inicio: '08:00', fin: '17:00' },
    miercoles: { activo: true, inicio: '08:00', fin: '17:00' },
    jueves: { activo: true, inicio: '08:00', fin: '17:00' },
    viernes: { activo: true, inicio: '08:00', fin: '17:00' },
    sabado: { activo: false, inicio: '08:00', fin: '12:00' },
    domingo: { activo: false, inicio: '08:00', fin: '12:00' },
  },
  precios: {
    consulta_general: 150,
    consulta_especialidad: 250,
    receta: 50,
    examen_basico: 100,
    examen_completo: 300,
  },
  metodos_pago: {
    efectivo: true,
    tarjeta: true,
    transferencia: true,
    seguro: false,
    cheque: false,
  },
  notificaciones: {
    email: true,
    sms: false,
    recordatorio_24h: true,
    recordatorio_2h: true,
    confirmacion_automatica: false,
  },
}

export function useConfiguracion() {
  const [config, setConfig] = useState<ConfiguracionData>(defaultConfig)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Cargar configuración del doctor actual
  const cargarConfig = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }

      const { data, error: dbError } = await supabase
        .from('configuracion')
        .select('*')
        .eq('doctor_id', user.id)
        .single()

      if (dbError) {
        if (dbError.code === 'PGRST116') {
          // No hay configuración guardada, usar defaults
          setConfig(prev => ({ ...prev, doctor_id: user.id, email: user.email || '' }))
        } else {
          setError(dbError.message)
        }
      } else if (data) {
        setConfig({
          ...defaultConfig,
          ...data,
          horarios: { ...defaultConfig.horarios, ...data.horarios },
          precios: { ...defaultConfig.precios, ...data.precios },
          metodos_pago: { ...defaultConfig.metodos_pago, ...data.metodos_pago },
          notificaciones: { ...defaultConfig.notificaciones, ...data.notificaciones },
        })
      }
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    cargarConfig()
  }, [cargarConfig])

  // Guardar configuración
  const guardarConfig = useCallback(async (nuevaConfig: Partial<ConfiguracionData>) => {
    setSaving(true)
    setError(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No hay usuario autenticado')

      const configActualizada = {
        ...config,
        ...nuevaConfig,
        doctor_id: user.id,
      }

      // Verificar si ya existe config para este doctor
      const { data: existente } = await supabase
        .from('configuracion')
        .select('id')
        .eq('doctor_id', user.id)
        .single()

      let result
      if (existente) {
        // Actualizar
        result = await supabase
          .from('configuracion')
          .update({
            nombre_completo: configActualizada.nombre_completo,
            especialidad: configActualizada.especialidad,
            cedula: configActualizada.cedula,
            telefono: configActualizada.telefono,
            email: configActualizada.email,
            nombre_clinica: configActualizada.nombre_clinica,
            direccion: configActualizada.direccion,
            telefono_clinica: configActualizada.telefono_clinica,
            email_clinica: configActualizada.email_clinica,
            horarios: configActualizada.horarios,
            precios: configActualizada.precios,
            metodos_pago: configActualizada.metodos_pago,
            notificaciones: configActualizada.notificaciones,
            updated_at: new Date().toISOString(),
          })
          .eq('doctor_id', user.id)
      } else {
        // Insertar nueva
        result = await supabase
          .from('configuracion')
          .insert({
            doctor_id: user.id,
            nombre_completo: configActualizada.nombre_completo,
            especialidad: configActualizada.especialidad,
            cedula: configActualizada.cedula,
            telefono: configActualizada.telefono,
            email: configActualizada.email,
            nombre_clinica: configActualizada.nombre_clinica,
            direccion: configActualizada.direccion,
            telefono_clinica: configActualizada.telefono_clinica,
            email_clinica: configActualizada.email_clinica,
            horarios: configActualizada.horarios,
            precios: configActualizada.precios,
            metodos_pago: configActualizada.metodos_pago,
            notificaciones: configActualizada.notificaciones,
          })
      }

      if (result.error) throw result.error

      setConfig(configActualizada)
      return { success: true }
    } catch (err: any) {
      setError(err.message)
      return { success: false, error: err.message }
    } finally {
      setSaving(false)
    }
  }, [config])

  return {
    config,
    loading,
    saving,
    error,
    cargarConfig,
    guardarConfig,
    setConfig,
  }
}
