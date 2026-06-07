import { createContext, useContext, useState, useEffect, type ReactNode } from 'react'

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

  const setPaisActivo = (pais: Pais | null) => {
    setPaisState(pais)
    if (pais) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(pais))
    } else {
      localStorage.removeItem(STORAGE_KEY)
    }
  }

  const clearPaisActivo = () => {
    setPaisState(null)
    localStorage.removeItem(STORAGE_KEY)
  }

  return (
    <PaisContext.Provider value={{ paisActivo, setPaisActivo, clearPaisActivo }}>
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
