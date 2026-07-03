import * as React from 'react'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { TEMA_OFICIAL, TenantThemeContext, type TenantTheme } from './TenantThemeContext'

// Fila del tenant con las columnas de tema (clinicas o empresas_proveedoras). Ambos hooks ya las traen
// en runtime vía select('*') / empresa:empresa_id(*) — sin queries nuevas.
interface FilaTema {
  logo_url: string | null
  color_primario: string | null
  color_secundario: string | null
  color_fondo: string | null
}

// Campo-a-campo: un tenant con solo color_primario seteado conserva logo/secundario/fondo oficiales.
function resolver(v: string | null | undefined, fallback: string): string {
  return v && v.trim() !== '' ? v : fallback
}

function TenantThemeBase({
  tipo, row, children,
}: { tipo: 'clinica' | 'proveedor'; row: FilaTema | null; children: React.ReactNode }) {
  // Callback ref → estado, para que los consumidores del container (Dialog/Select) re-rendericen al montarse.
  const [container, setContainer] = React.useState<HTMLElement | null>(null)

  // row === null durante loading / error / sin fila → todo cae al tema oficial. Nunca undefined, nunca throw.
  const value = React.useMemo<TenantTheme>(() => ({
    primario:   resolver(row?.color_primario,   TEMA_OFICIAL.primario),
    secundario: resolver(row?.color_secundario, TEMA_OFICIAL.secundario),
    fondo:      resolver(row?.color_fondo,      TEMA_OFICIAL.fondo),
    logoUrl:    resolver(row?.logo_url,         TEMA_OFICIAL.logoUrl),
    portalContainer: container,
  }), [row?.color_primario, row?.color_secundario, row?.color_fondo, row?.logo_url, container])

  return (
    <TenantThemeContext.Provider value={value}>
      <div
        ref={setContainer}
        data-tenant-theme={tipo}
        style={{
          // Scoped: las CSS vars heredan solo en este subtree, NUNCA en :root. Los portales que
          // montan aquí (via portalContainer) heredan; los que van a document.body (toasts globales) no.
          '--tenant-primario': value.primario,
          '--tenant-secundario': value.secundario,
          '--tenant-fondo': value.fondo,   // expuesta; aún NO cableada a ningún elemento (fase conservadora)
        } as React.CSSProperties}
      >
        {children}
      </div>
    </TenantThemeContext.Provider>
  )
}

// Adapters: cada uno llama UN solo hook (nunca condicionalmente, respeta las reglas de hooks).
function ClinicaThemeAdapter({ children }: { children: React.ReactNode }) {
  const { clinica } = useClinicaAuth()
  return <TenantThemeBase tipo="clinica" row={clinica}>{children}</TenantThemeBase>
}
function ProveedorThemeAdapter({ children }: { children: React.ReactNode }) {
  const { empresa } = useProveedorAuth()
  return <TenantThemeBase tipo="proveedor" row={empresa}>{children}</TenantThemeBase>
}

// Per-panel: se monta SOLO dentro de ClinicaLayout / ProveedorLayout. Admin y Paciente nunca lo montan
// → su tema es 100% oficial por construcción (no existe context de tenant en su árbol).
export function TenantThemeProvider({
  tipo, children,
}: { tipo: 'clinica' | 'proveedor'; children: React.ReactNode }) {
  return tipo === 'clinica'
    ? <ClinicaThemeAdapter>{children}</ClinicaThemeAdapter>
    : <ProveedorThemeAdapter>{children}</ProveedorThemeAdapter>
}
