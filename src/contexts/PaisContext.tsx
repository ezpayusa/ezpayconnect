import { createContext, useContext, useState, useCallback, useMemo, type ReactNode } from 'react'

interface Pais {
  id: string
  codigo: string
  nombre: string
  moneda: string
  activo: boolean
}

interface PaisContextType {
  paisActivo: Pais | null
  setPaisActivo: (pais: Pais | null) => void
  clearPaisActivo: () => void
}

const PaisContext = createContext<PaisContextType | undefined>(undefined)

const STORAGE_KEY = 'ezpay_pais_activo'

export function PaisProvider({ children }: { children: ReactNode }) {
  const [paisActivo, setPaisState] = useState<Pais | null>(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      return stored ? JSON.parse(stored) : null
    } catch {
      return null
    }
  })

  // useCallback/useMemo: sin esto, setPaisActivo se recreaba en cada render y
  // los useEffect que lo tienen en deps (p.ej. PaisDashboardPage) entraban en
  // bucle infinito (re-fetch sin parar de configuracion_pais).
  const setPaisActivo = useCallback((pais: Pais | null) => {
    setPaisState(pais)
    if (pais) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(pais))
    } else {
      localStorage.removeItem(STORAGE_KEY)
    }
  }, [])

  const clearPaisActivo = useCallback(() => {
    setPaisState(null)
    localStorage.removeItem(STORAGE_KEY)
  }, [])

  const value = useMemo(
    () => ({ paisActivo, setPaisActivo, clearPaisActivo }),
    [paisActivo, setPaisActivo, clearPaisActivo]
  )

  return (
    <PaisContext.Provider value={value}>
      {children}
    </PaisContext.Provider>
  )
}

export function usePaisContext() {
  const context = useContext(PaisContext)
  if (!context) {
    throw new Error('usePaisContext debe usarse dentro de PaisProvider')
  }
  return context
}
