import { toast } from 'sonner'
import { mapearErrorRpc, type ErrorRpcMapeado } from '@/lib/erroresRpc'

export type ErrorInline = { campo: string; mensaje: string } | null

type Opciones = {
  /** Dónde dejar el error cuando va inline (pegado a un campo del formulario). */
  setInline?: (v: ErrorInline) => void
  /** El cliente quedó desincronizado: recargar esa colección. */
  onRecargar?: (que: 'catalogo' | 'contactos' | 'jornada' | 'visita') => void
  /** El cambio no se aplicó: devolver el control a su valor anterior. */
  onRevertir?: () => void
}

// Único punto por el que las pantallas del módulo muestran un error de RPC. No hay ni un
// `toast.error('algo salió mal')` suelto: si lo hubiera, el trabajo de la mig 272 —que distingue
// 42501 de PA008..PA014— se perdería justo en el último metro.
//
// Este archivo hace SOLO el despacho a la UI. La decisión de qué significa cada código vive en
// src/lib/erroresRpc.ts, que es puro y está testeado; acá no se agrega ni un `if (code === ...)`.
export function reportarError(error: unknown, opciones: Opciones = {}): ErrorRpcMapeado {
  const m = mapearErrorRpc(error)

  // DECISIÓN (4): en este frente NO hay cola diferida. Si no hay red, el check-in FALLA — y el
  // mensaje lo dice, en vez del genérico "intentá de nuevo" que sugiere que se guardó algo.
  // El chequeo vive acá y no en erroresRpc.ts porque ese módulo es puro (mapea SQLSTATE) y
  // `navigator` no lo es. La cola es su propio frente: mezclarla escondería bugs de las dos.
  if (m.code === null && typeof navigator !== 'undefined' && navigator.onLine === false) {
    const sinRed = 'Estás sin conexión. Esto necesita red y NO queda guardado para después: '
      + 'volvé a intentarlo cuando tengas señal.'
    toast.error(sinRed)
    return { ...m, mensaje: sinRed, reportar: false }
  }

  // Un error inline vive pegado a un campo. Si además pide RECARGAR, ese campo puede desaparecer
  // en la recarga —es justo lo que pasa con el 23505 del informe: la ficha se refresca, el
  // formulario se reemplaza por el informe existente y el mensaje se va con él sin que nadie lo
  // haya leído. En ese caso va inline Y en toast: el toast sobrevive al re-render.
  const anclaEfimera = m.destino === 'inline' && m.recargar != null
  if (m.destino === 'inline' && m.campo && opciones.setInline) {
    opciones.setInline({ campo: m.campo, mensaje: m.mensaje })
    if (anclaEfimera) toast.error(m.mensaje)
  } else {
    toast.error(m.mensaje)
  }

  if (m.recargar && opciones.onRecargar) opciones.onRecargar(m.recargar)
  if (m.revertir && opciones.onRevertir) opciones.onRevertir()

  // `reportar` marca lo que es bug nuestro o código no previsto (un PA0xx sin mapear incluido).
  // Sentry se inicializa en main.tsx; acá alcanza con dejarlo en consola con el código a la vista.
  if (m.reportar) console.error('[comercial] error de RPC sin manejo específico:', m.code, error)

  return m
}
