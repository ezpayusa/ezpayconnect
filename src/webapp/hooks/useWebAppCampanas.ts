import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { CampanaPublicitaria } from '@/webapp/types/webapp.types'

export function useWebAppCampanas(pacienteId: number | undefined, perfil: any) {
  const [campanas, setCampanas] = useState<CampanaPublicitaria[]>([])
  const [loading, setLoading] = useState(true)

  const fetchCampanas = useCallback(async () => {
    if (!pacienteId || !perfil) {
      setCampanas([])
      setLoading(false)
      return
    }

    try {
      setLoading(true)

      const { data, error } = await supabase
        .from('campanas_publicitarias')
        .select('*')
        .eq('activa', true)
        .gte('fecha_fin', new Date().toISOString().split('T')[0])
        .order('created_at', { ascending: false })

      if (error) throw error

      // Filtrar por segmentación
      const filtradas = (data || []).filter((c: any) => {
        // Filtro por género
        if (c.genero_filtro && perfil.genero !== c.genero_filtro) return false

        // Filtro por edad
        if (c.edad_min || c.edad_max) {
          if (!perfil.fecha_nacimiento) return false
          const edad = calcularEdad(perfil.fecha_nacimiento)
          if (c.edad_min && edad < c.edad_min) return false
          if (c.edad_max && edad > c.edad_max) return false
        }

        // Filtro por condición (alergias/notas contienen la condición)
        if (c.condicion_filtro) {
          const texto = `${perfil.alergias || ''} ${perfil.notas || ''}`.toLowerCase()
          if (!texto.includes(c.condicion_filtro.toLowerCase())) return false
        }

        return true
      })

      setCampanas(filtradas)
    } catch (err) {
      console.error('Error cargando campañas:', err)
      setCampanas([])
    } finally {
      setLoading(false)
    }
  }, [pacienteId, perfil])

  useEffect(() => {
    fetchCampanas()
  }, [fetchCampanas])

  const registrarVista = async (campanaId: number, clickeado = false) => {
    if (!pacienteId) return
    try {
      await supabase.from('campana_vistas').upsert({
        campana_id: campanaId,
        paciente_id: pacienteId,
        clickeado,
      }, { onConflict: 'campana_id,paciente_id' })
    } catch (err) {
      console.error('Error registrando vista:', err)
    }
  }

  return { campanas, loading, registrarVista, refetch: fetchCampanas }
}

function calcularEdad(fechaNacimiento: string): number {
  const hoy = new Date()
  const nacimiento = new Date(fechaNacimiento)
  let edad = hoy.getFullYear() - nacimiento.getFullYear()
  const mes = hoy.getMonth() - nacimiento.getMonth()
  if (mes < 0 || (mes === 0 && hoy.getDate() < nacimiento.getDate())) {
    edad--
  }
  return edad
}
