import * as React from 'react'

// Tema oficial EZPayConnect — fallback cuando el tenant no tiene personalización aprobada,
// mientras cargan los datos, o si la lectura falla. Nunca se pintan colores equivocados.
export const TEMA_OFICIAL = {
  primario: '#1E5C8E',
  secundario: '#3A8ABF',
  fondo: '#f9fafb',
  logoUrl: '/ezpayconnect_icono.svg',
} as const

export interface TenantTheme {
  primario: string
  secundario: string
  fondo: string
  logoUrl: string
  /** Nodo DOM del wrapper tematizado; los portales (Dialog/Select) montan aquí para heredar las CSS vars. */
  portalContainer: HTMLElement | null
}

// null fuera de un provider (Admin/Paciente): useTema() cae al tema oficial y los portales usan document.body.
export const TenantThemeContext = React.createContext<TenantTheme | null>(null)

export function useTema(): TenantTheme {
  const ctx = React.useContext(TenantThemeContext)
  return ctx ?? { ...TEMA_OFICIAL, portalContainer: null }
}
