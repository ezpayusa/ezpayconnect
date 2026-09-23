import { describe, it, expect } from 'vitest'

// ############################################################################################
// ProveedorNotificacionesPage llama useProveedorNotificaciones(), que HACE THROW si no está dentro
// de ProveedorNotificacionesProvider. Ese provider lo monta el layout, no la página. Si una ruta
// monta esa página bajo un layout que NO provee el contexto, la ruta crashea en runtime
// (fue el caso de /farmacia/notificaciones, preexistente).
//
// Regla estructural: TODA ruta de App.tsx cuyo element sea <ProveedorNotificacionesPage/> tiene que
// estar bajo un layout que monte <ProveedorNotificacionesProvider>. Sin lista escrita a mano: los
// layouts que proveen se detectan leyendo los archivos, y el layout de cada ruta se saca del texto
// de App.tsx. Misma idea que src/pages/notificaciones.estructura.test.ts.
// ############################################################################################

const RAIZ = 'src'

async function archivosTsx(): Promise<string[]> {
  const fs = await import('node:fs')
  const path = await import('node:path')
  const out: string[] = []
  const walk = (dir: string) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name)
      if (e.isDirectory()) walk(p)
      else if (e.name.endsWith('.tsx')) out.push(p)
    }
  }
  walk(RAIZ)
  return out.map((f) => f.replace(/\\/g, '/'))
}

// Nombre de componente = basename sin .tsx (App.tsx importa cada layout con ese nombre por default).
const nombreComponente = (ruta: string): string => ruta.split('/').pop()!.replace(/\.tsx$/, '')

describe('ProveedorNotificacionesPage siempre bajo un layout que provee el contexto', () => {
  it('cada ruta con ProveedorNotificacionesPage cuelga de un layout que monta el provider', async () => {
    const fs = await import('node:fs')

    // 1) Layouts que MONTAN el provider (detectado del archivo, no de una lista).
    const layoutsConProvider = new Set<string>()
    for (const f of await archivosTsx()) {
      if (!/\/layout\/.*Layout\.tsx$/.test(f)) continue
      const src = fs.readFileSync(f, 'utf8')
      if (src.includes('<ProveedorNotificacionesProvider')) {
        layoutsConProvider.add(nombreComponente(f))
      }
    }
    // Control mínimo (desacoplado del número de portales): si no detectamos NINGUNO, el recorrido se
    // rompió. La regla real la hace la aserción por-ruta de más abajo.
    expect(
      layoutsConProvider.size,
      'Ningún *Layout.tsx monta <ProveedorNotificacionesProvider>. Se rompió el recorrido de archivos.',
    ).toBeGreaterThanOrEqual(1)

    // 2) En App.tsx, cada uso de la página → el layout más cercano hacia atrás (su ruta padre).
    const app = fs.readFileSync('src/App.tsx', 'utf8')
    const usos = [...app.matchAll(/element=\{<ProveedorNotificacionesPage\s*\/>\}/g)]
    expect(
      usos.length,
      'No se encontró ninguna ruta con ProveedorNotificacionesPage en App.tsx (¿cambió el nombre?).',
    ).toBeGreaterThanOrEqual(1)

    const layoutRe = /<(\w+Layout)\s*\/>/g
    const sinProvider: string[] = []
    for (const uso of usos) {
      const idx = uso.index ?? 0
      // Último <XxxLayout /> declarado ANTES de esta ruta = el layout que la envuelve.
      let layout: string | null = null
      for (const m of app.matchAll(layoutRe)) {
        if ((m.index ?? 0) < idx) layout = m[1]
        else break
      }
      if (!layout || !layoutsConProvider.has(layout)) {
        sinProvider.push(`${layout ?? '(sin layout)'} @ index ${idx}`)
      }
    }
    expect(
      sinProvider,
      'Estas rutas montan ProveedorNotificacionesPage bajo un layout que NO provee '
        + 'ProveedorNotificacionesProvider → crash en runtime (useProveedorNotificaciones fuera de '
        + 'contexto). Montá el provider en ese layout, como ProveedorLayout/LaboratorioLayout/FarmaciaLayout.',
    ).toEqual([])
  })
})
