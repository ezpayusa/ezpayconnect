import { describe, it, expect } from 'vitest'
import {
  accesoEmpresa,
  portalBase,
  rutaEstado,
  rutaPermitidaEnOnboarding,
  RUTAS_ONBOARDING,
  RUTAS_ONBOARDING_POR_PORTAL,
  type PortalBase,
} from './estadoEmpresa'

// ############################################################################################
// La regla de acceso por estado es CORTESÍA que calca al servidor (mig 322). Dos cosas se miden:
//   1. accesoEmpresa mapea cada estado igual que el servidor (incluye null y un valor desconocido:
//      fail-closed).
//   2. Cada ruta de RUTAS_ONBOARDING existe REALMENTE en el router — si una se renombra, un
//      pendiente/suspendida queda sin salida. Test estructural contra src/App.tsx, misma idea que
//      src/pages/notificaciones.estructura.test.ts.
// ############################################################################################

describe('accesoEmpresa — calca la regla del servidor', () => {
  it('activa → operativa', () => {
    expect(accesoEmpresa('activa')).toBe('operativa')
  })

  it('pendiente y suspendida → onboarding', () => {
    expect(accesoEmpresa('pendiente')).toBe('onboarding')
    expect(accesoEmpresa('suspendida')).toBe('onboarding')
  })

  it('rechazada → bloqueada', () => {
    expect(accesoEmpresa('rechazada')).toBe('bloqueada')
  })

  it('null / undefined → bloqueada (fail-closed)', () => {
    expect(accesoEmpresa(null)).toBe('bloqueada')
    expect(accesoEmpresa(undefined)).toBe('bloqueada')
  })

  it('un valor desconocido → bloqueada (fail-closed)', () => {
    expect(accesoEmpresa('activo')).toBe('bloqueada') // typo cercano a 'activa'
    expect(accesoEmpresa('cualquier-cosa')).toBe('bloqueada')
    expect(accesoEmpresa('')).toBe('bloqueada')
  })
})

describe('helpers de ruta', () => {
  it('portalBase reconoce cada portal y cae en /proveedor por defecto', () => {
    expect(portalBase('/proveedor/dashboard')).toBe('/proveedor')
    expect(portalBase('/farmacia/perfil')).toBe('/farmacia')
    expect(portalBase('/laboratorio/estado')).toBe('/laboratorio')
    expect(portalBase('/otra/cosa')).toBe('/proveedor')
  })

  it('rutaEstado apunta al estado del portal correcto', () => {
    expect(rutaEstado('/farmacia/pagos')).toBe('/farmacia/estado')
    expect(rutaEstado('/laboratorio/perfil')).toBe('/laboratorio/estado')
    expect(rutaEstado('/proveedor/dashboard')).toBe('/proveedor/estado')
  })

  it('rutaPermitidaEnOnboarding acepta las de onboarding y sus sub-rutas, rechaza el resto', () => {
    expect(rutaPermitidaEnOnboarding('/proveedor/perfil')).toBe(true)
    expect(rutaPermitidaEnOnboarding('/proveedor/checkout')).toBe(true)
    expect(rutaPermitidaEnOnboarding('/farmacia/pagos')).toBe(true)
    expect(rutaPermitidaEnOnboarding('/laboratorio/estado')).toBe(true)
    // sub-ruta
    expect(rutaPermitidaEnOnboarding('/proveedor/perfil/editar')).toBe(true)
    // no permitidas
    expect(rutaPermitidaEnOnboarding('/proveedor/productos')).toBe(false)
    expect(rutaPermitidaEnOnboarding('/laboratorio/pagos')).toBe(false) // lab no tiene pagos
    expect(rutaPermitidaEnOnboarding('/farmacia/checkout')).toBe(false) // farmacia no tiene checkout
  })

  it('cada portal permite al menos su pantalla de estado y su perfil', () => {
    for (const base of Object.keys(RUTAS_ONBOARDING_POR_PORTAL) as PortalBase[]) {
      expect(RUTAS_ONBOARDING_POR_PORTAL[base]).toContain('estado')
      expect(RUTAS_ONBOARDING_POR_PORTAL[base]).toContain('perfil')
    }
  })
})

describe('estructural — cada ruta de onboarding existe en el router', () => {
  // Marcador de comentario que abre el bloque de rutas de cada portal en App.tsx, y el corte hasta
  // el siguiente bloque `{/* === ... === */}`.
  const MARCADOR: Record<PortalBase, string> = {
    '/proveedor': 'RUTAS PORTAL PROVEEDORES',
    '/laboratorio': 'RUTAS PORTAL LABORATORIO',
    '/farmacia': 'PORTAL FARMACIA',
  }

  async function bloquesPorPortal(): Promise<Record<PortalBase, string>> {
    const fs = await import('node:fs')
    const src = fs.readFileSync('src/App.tsx', 'utf8')
    const salida = {} as Record<PortalBase, string>
    for (const base of Object.keys(MARCADOR) as PortalBase[]) {
      const inicio = src.indexOf(MARCADOR[base])
      expect(inicio, `No se encontró el bloque del portal ${base} (marcador "${MARCADOR[base]}")`).toBeGreaterThanOrEqual(0)
      const siguiente = src.indexOf('{/* ===', inicio + 1)
      salida[base] = src.slice(inicio, siguiente === -1 ? undefined : siguiente)
    }
    return salida
  }

  it('el portal declara su ruta padre y cada sufijo de onboarding como <Route path="...">', async () => {
    const bloques = await bloquesPorPortal()
    const faltantes: string[] = []
    for (const base of Object.keys(RUTAS_ONBOARDING_POR_PORTAL) as PortalBase[]) {
      const bloque = bloques[base]
      if (!bloque.includes(`path="${base}/*"`)) {
        faltantes.push(`${base} (falta la ruta padre path="${base}/*")`)
      }
      for (const sufijo of RUTAS_ONBOARDING_POR_PORTAL[base]) {
        if (!bloque.includes(`path="${sufijo}"`)) {
          faltantes.push(`${base}/${sufijo}`)
        }
      }
    }
    expect(
      faltantes,
      'Estas rutas de onboarding no están montadas en su portal (App.tsx). Si se renombró una, un '
        + 'pendiente/suspendida queda sin salida: volvé a montarla o actualizá RUTAS_ONBOARDING_POR_PORTAL.',
    ).toEqual([])
  })

  it('RUTAS_ONBOARDING plano coincide con el mapa por portal', () => {
    const esperado = (Object.entries(RUTAS_ONBOARDING_POR_PORTAL) as [PortalBase, string[]][])
      .flatMap(([base, sufijos]) => sufijos.map((s) => `${base}/${s}`))
      .sort()
    expect([...RUTAS_ONBOARDING].sort()).toEqual(esperado)
  })
})
