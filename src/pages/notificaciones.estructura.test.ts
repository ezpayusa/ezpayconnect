import { describe, it, expect } from 'vitest'

// ############################################################################################
// Una notificación con accion_url tiene que poder abrirse
// ############################################################################################
// `notificaciones.accion_url` existe desde hace un año y la mitad de las pantallas la ignoraba.
// NotificacionesPage —la del médico— la traía en cada fila y no hacía nada con ella: el único
// onClick era "marcar como leída". La mig 312 hizo que el resultado de examen apunte a
// /medico/pacientes/<id>/detalle, y ese destino no se usaba desde la campana, sólo desde el push.
//
// El problema no es que una pantalla esté mal: es que nada avisa cuando la siguiente nace igual.
// Mismo espíritu que src/components/visor/visor.estructura.test.ts.
//
// Son DOS reglas distintas a propósito:
//   1. Regresión — se cuenta contra los ARCHIVOS, sin lista escrita a mano. Toda pantalla que HOY
//      nombra accion_url tiene que navegar con ella. Si alguien saca el navigate, falla acá.
//   2. Censo — las pantallas de notificaciones que NO navegan están enumeradas CON SU RAZÓN. Una
//      lista de memoria tiene el mismo defecto que está vigilando, así que se la trata como la
//      DEUDA del harness: si una entrada EMPIEZA a navegar, el test también falla y hay que
//      sacarla a mano. Actualizarla es un acto deliberado, no un efecto colateral.

const RAIZ = 'src'

// `navigate(x.accion_url)`, en cualquiera de sus formas vivas: con `!`, dentro de un if de una
// línea, o separado del if por un bloque.
const NAVEGA = /navigate\(\s*[A-Za-z_$][\w$]*\.accion_url/

async function tsxDelProyecto(): Promise<string[]> {
  const fs = await import('node:fs')
  const path = await import('node:path')
  const salida: string[] = []
  const recorrer = (dir: string) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name)
      if (e.isDirectory()) recorrer(p)
      else if (e.name.endsWith('.tsx') && !e.name.endsWith('.test.tsx')) salida.push(p)
    }
  }
  recorrer(RAIZ)
  return salida.map((f) => f.replace(/\\/g, '/'))
}

// Una mención en un COMENTARIO no navega a ningún lado. Sin sacarlas, el propio comentario que
// explica la regla haría fallar el test, o —peor— una línea comentada haría creer que el camino
// está vivo.
const sinComentarios = (src: string) =>
  src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n')

// Pantallas de notificaciones que NO navegan con accion_url, cada una con su motivo. NO es una
// lista de perdón: el segundo test verifica que la razón siga siendo cierta.
const SIN_NAVEGACION: Record<string, string> = {
  'src/components/NotificacionesBadge.tsx':
    'código muerto: no lo importa nadie. El test verifica que siga sin importarse — el día que se '
    + 'monte en algún layout, hay que hacerlo navegar o sacarlo de esta lista a conciencia.',
  'src/proveedor/context/ProveedorNotificacionesContext.tsx':
    'es un contexto, no una pantalla: sólo cuenta no leídas. Quien navega es '
    + 'ProveedorNotificacionesPage.tsx, y la regla 1 lo cubre.',
  'src/pages/admin-ezpay/NotificacionesPage.tsx':
    'HUECO REAL, sin arreglar: la lista del admin ignora accion_url y sus botones sólo cambian '
    + 'estado (marcarLeida / marcarEnProceso / marcarCompletada). La campana del admin '
    + '(NavbarAdmin.tsx) sí navega, así que el destino no está perdido del todo. Deuda anotada.',
}

describe('notificaciones — accion_url se usa donde existe', () => {
  // ---- REGLA 1: regresión, sin lista ----
  it('toda pantalla que nombra accion_url navega con ella', async () => {
    const fs = await import('node:fs')
    const sinNavegar: string[] = []
    let conAccionUrl = 0
    for (const archivo of await tsxDelProyecto()) {
      const codigo = sinComentarios(fs.readFileSync(archivo, 'utf8'))
      if (!codigo.includes('accion_url')) continue
      conAccionUrl++
      if (!NAVEGA.test(codigo)) sinNavegar.push(archivo)
    }

    // Control positivo: si el recorrido no encuentra NADA, el test de arriba pasaría vacío. Las 5
    // lectoras medidas el 20-sep son el piso.
    expect(
      conAccionUrl,
      'Ningún .tsx nombra accion_url. O el recorrido se rompió, o alguien borró las 5 pantallas '
        + 'que la leían. Las dos cosas son un problema.',
    ).toBeGreaterThanOrEqual(5)

    expect(
      sinNavegar,
      'Estas pantallas nombran accion_url pero no navegan con ella. El patrón es: '
        + '`if (!n.leida) await marcarLeida(n.id); if (n.accion_url) navigate(n.accion_url)`. '
        + 'Ver src/clinica/layout/ClinicaNotificacionesDropdown.tsx.',
    ).toEqual([])
  })

  // ---- REGLA 2: censo de pantallas de notificaciones ----
  it('toda pantalla de notificaciones navega, o está en el censo con su razón', async () => {
    const fs = await import('node:fs')
    const pantallas = (await tsxDelProyecto()).filter((f) => /Notificacion/i.test(f))

    expect(
      pantallas.length,
      'No se encontró ninguna pantalla de notificaciones: el filtro por nombre dejó de matchear.',
    ).toBeGreaterThanOrEqual(5)

    const huerfanas = pantallas.filter((f) => {
      const codigo = sinComentarios(fs.readFileSync(f, 'utf8'))
      return !NAVEGA.test(codigo) && !(f in SIN_NAVEGACION)
    })
    expect(
      huerfanas,
      'Pantalla(s) de notificaciones que no navegan con accion_url y no están en el censo. '
        + 'O le agregás el navigate, o la sumás a SIN_NAVEGACION de este archivo escribiendo POR QUÉ.',
    ).toEqual([])

    // Y al revés: una entrada del censo que empezó a navegar tiene que salir de la lista, igual
    // que una roja de la DEUDA del harness que sale verde. Si no, el censo se llena de mentiras.
    const yaNavegan = Object.keys(SIN_NAVEGACION).filter((f) => {
      if (!fs.existsSync(f)) return false
      return NAVEGA.test(sinComentarios(fs.readFileSync(f, 'utf8')))
    })
    expect(
      yaNavegan,
      'Estas están en SIN_NAVEGACION pero YA navegan con accion_url. Sacalas de la lista.',
    ).toEqual([])

    // Un archivo del censo que ya no existe también tiene que salir.
    const inexistentes = Object.keys(SIN_NAVEGACION).filter((f) => !fs.existsSync(f))
    expect(inexistentes, 'Estas del censo ya no existen. Sacalas de la lista.').toEqual([])
  })

  // ---- la razón de NotificacionesBadge, verificada ----
  it('NotificacionesBadge sigue sin usarse (si se monta, hay que hacerlo navegar)', async () => {
    const fs = await import('node:fs')
    const importadores: string[] = []
    for (const archivo of await tsxDelProyecto()) {
      if (archivo.endsWith('src/components/NotificacionesBadge.tsx')) continue
      if (/NotificacionesBadge/.test(sinComentarios(fs.readFileSync(archivo, 'utf8')))) {
        importadores.push(archivo)
      }
    }
    expect(
      importadores,
      'NotificacionesBadge.tsx dejó de ser código muerto: alguien lo montó. No usa accion_url, '
        + 'así que su campana abriría notificaciones que no llevan a ningún lado. Agregale el '
        + 'navigate y sacalo de SIN_NAVEGACION.',
    ).toEqual([])
  })
})
