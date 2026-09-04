import { toast } from 'sonner'
import { mapearErrorRpc, type ErrorRpcMapeado } from '@/lib/erroresRpc'

export type ErrorInline = { campo: string; mensaje: string } | null

type Opciones = {
  /** Dónde dejar el error cuando va inline (pegado a un campo del formulario). */
  setInline?: (v: ErrorInline) => void
  /** El cliente quedó desincronizado: recargar esa colección. */
  onRecargar?: (que: 'catalogo' | 'contactos') => void
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

  if (m.destino === 'inline' && m.campo && opciones.setInline) {
    opciones.setInline({ campo: m.campo, mensaje: m.mensaje })
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
