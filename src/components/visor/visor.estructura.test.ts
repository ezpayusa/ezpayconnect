import { describe, it, expect } from 'vitest'

// ############################################################################################
// Ningún archivo de resultados-examenes se abre por fuera del visor
// ############################################################################################
// PageHeader quedó copiado inline en 60+ lugares de 5 portales porque no se compartió a tiempo, y
// nada avisaba cuando alguien agregaba la copia número 61. Este test es ese aviso para el visor.
//
// `openSignedUrl('resultados-examenes', …)` abre la URL firmada en una pestaña nueva: el bearer queda
// en la barra de direcciones y en el historial del navegador, y el TTL de 120 s no alcanza para
// inspeccionar un RX. El visor firma a 60 s, baja los bytes una vez y muestra desde un `blob:`. Una
// pantalla nueva que vuelva al camino viejo tiene que fallar ACÁ, no seis meses después.
//
// Se cuenta contra los ARCHIVOS, no contra una lista escrita a mano: una lista de memoria tendría el
// mismo defecto que está vigilando.

const RAIZ = 'src'

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
  return salida
}

// Una mención en un COMENTARIO no abre nada. Sin sacarlas, el propio comentario que explica la regla
// haría fallar el test, o —peor— una línea comentada haría creer que hay un camino vivo.
const sinComentarios = (src: string) =>
  src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n')

describe('visor — resultados-examenes sólo se abre por el visor', () => {
  it('ningún .tsx llama openSignedUrl("resultados-examenes", …)', async () => {
    const fs = await import('node:fs')
    const PROHIBIDO = /openSignedUrl\(\s*['"`]resultados-examenes['"`]/g
    const hallazgos: string[] = []
    for (const archivo of await tsxDelProyecto()) {
      // Se recorren las líneas ORIGINALES para reportar el número real del archivo; las de comentario
      // se saltean en el lugar en vez de borrarse, que corría la numeración.
      fs.readFileSync(archivo, 'utf8').split('\n').forEach((linea, i) => {
        if (/^\s*(\/\/|\*|\/\*)/.test(linea)) return
        if (PROHIBIDO.test(linea)) hallazgos.push(`${archivo.replace(/\\/g, '/')}:${i + 1}`)
        PROHIBIDO.lastIndex = 0
      })
    }
    expect(
      hallazgos,
      'Estas pantallas abren un resultado de examen por fuera del visor. Usá `const { abrir, visor } = '
        + "useVisor()` y renderizá `{visor}`; para descargar, `descargarArchivo('resultados-examenes', path)`. "
        + 'Ver src/components/visor/VisorArchivos.tsx.',
    ).toEqual([])
  })

  // CONTROL POSITIVO. Sin esto, el test de arriba también pasaría si alguien BORRA los botones de
  // "Ver archivo" de las pantallas: cero llamadas prohibidas, cero visor, y el médico sin forma de ver
  // el resultado. Las 5 pantallas lectoras medidas el 15-sep tienen que seguir montando el visor.
  it('las 5 pantallas lectoras montan el visor', async () => {
    const fs = await import('node:fs')
    const LECTORAS = [
      'src/pages/ConsultaPage.tsx',
      'src/pages/PacienteDetallePage.tsx',
      'src/webapp/pages/WebAppExamenes.tsx',
      'src/webapp/pages/WebAppHistorial.tsx',
      'src/laboratorio/pages/LabOrdenesPage.tsx',
    ]
    const sinVisor = LECTORAS.filter((f) => {
      const codigo = sinComentarios(fs.readFileSync(f, 'utf8'))
      return !(/\buseVisor\(\)/.test(codigo) && /\{\s*visor\s*\}/.test(codigo))
    })
    expect(sinVisor, 'Estas pantallas lectoras no montan el visor (falta useVisor() o {visor}):').toEqual([])
  })
})
