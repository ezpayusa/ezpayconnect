// Mapeo de errores de RPC (PostgREST -> SQLSTATE) a algo que se le pueda mostrar a una persona.
//
// POR QUE EXISTE
// --------------
// Las RPCs del módulo comercial (mig 272) distinguen a propósito 42501 de PA008..PA014, y cada
// PA0xx dice exactamente qué está mal y cómo arreglarlo. Si el front los pinta a todos como
// "error inesperado", ese trabajo se tira. Este módulo es la pieza que decide si sirve.
//
// LA REGLA: SE MIRA `error.code`, NUNCA `error.message`
// ----------------------------------------------------
// Hay cuatro páginas del repo que hacen `/no_autorizado/.test(error.message)`. Eso se rompe el día
// que alguien reformula un mensaje, y se rompe en silencio: el error deja de reconocerse y cae en
// el genérico. PostgREST expone el SQLSTATE en `error.code`, que es un contrato estable.
//
// COMO ENVEJECE
// -------------
// Un `PA0xx` que todavía no está en el mapa NO cae en el genérico: sale marcado como
// `sinMapear`, con el código a la vista y con `reportar: true`. Hoy PA015+ no existen; mañana sí,
// y cuando aparezcan tienen que doler un poco, no desaparecer.

export type DestinoError = 'toast' | 'inline'

export interface ErrorRpcMapeado {
  /** SQLSTATE tal como vino, o null si el error no traía código (p. ej. fallo de red). */
  code: string | null
  /** Texto para mostrar. INVARIANTE: nunca vacío — un toast en blanco es peor que uno genérico. */
  mensaje: string
  /** Dónde va: `inline` cuando el usuario puede corregirlo en un campo; `toast` cuando no. */
  destino: DestinoError
  /** Para `inline`: qué campo del formulario señalar. */
  campo?: string
  /** El cliente quedó desincronizado con la base y conviene recargar esa colección. */
  recargar?: 'catalogo' | 'contactos'
  /** El control debe volver al valor anterior (el cambio no se aplicó). */
  revertir?: boolean
  /** Mandarlo a Sentry: es un bug nuestro o algo que no previmos, no un error del usuario. */
  reportar: boolean
  /** true = es un PA0xx que este mapa todavía no conoce. */
  sinMapear?: boolean
}

const GENERICO = 'No se pudo completar la operación. Intentá de nuevo.'

type Entrada = Omit<ErrorRpcMapeado, 'code' | 'mensaje'> & {
  /** Texto propio. Si falta, se usa el mensaje de la base (los PA0xx ya vienen redactados). */
  texto?: string
}

const MAPA: Record<string, Entrada> = {
  // --- Autorización -------------------------------------------------------------------------
  // 42501 se levanta con el mensaje 'no_autorizado', que no es texto para un usuario. Y es
  // deliberadamente el MISMO error cuando el registro no existe: el front no debe inventar un
  // "no encontrado" que revelaría existencia.
  '42501': { texto: 'No tenés permiso para esta acción.', destino: 'toast', reportar: false },

  // --- Guards de la mig 264: la jerarquía comercial ------------------------------------------
  // Los cinco traen su propio texto explicando qué falla y con qué datos.
  PA001: { destino: 'toast', reportar: false },
  PA002: { destino: 'toast', reportar: false },
  PA003: { destino: 'toast', reportar: false },
  PA004: { destino: 'toast', reportar: false },
  PA005: { destino: 'toast', reportar: false },
  PA006: { destino: 'toast', reportar: false },
  PA007: { destino: 'toast', reportar: false },

  // --- Reglas de negocio de la mig 272 -------------------------------------------------------
  PA008: { destino: 'inline', campo: 'asesor_id', reportar: false },
  PA009: { destino: 'inline', campo: 'asesor_id', reportar: false },
  // el catálogo del cliente quedó viejo: alguien desactivó un tipo o un estado
  PA010: { destino: 'inline', campo: 'catalogo', recargar: 'catalogo', reportar: false },
  // no es un error de sistema: es un campo que falta. Va pegado al campo, no en un toast.
  PA011: { destino: 'inline', campo: 'motivo_perdida', reportar: false },
  // el estado NO cambió: el selector tiene que volver a donde estaba
  PA012: { destino: 'toast', revertir: true, reportar: false },
  // el contacto que el cliente creía de este prospecto es de otro: la lista local miente
  PA013: { destino: 'toast', recargar: 'contactos', reportar: false },
  PA014: { destino: 'inline', campo: 'pais_id', reportar: false },

  // --- Constraints de la base ----------------------------------------------------------------
  // El texto de Postgres nombra el índice; no sirve para mostrar.
  '23505': {
    texto: 'Ya existe un registro con ese valor (el nombre del prospecto en el país, o el código de asesor).',
    destino: 'inline', campo: 'nombre', reportar: false,
  },
  '23514': {
    texto: 'Hay un campo obligatorio vacío o con un valor no permitido.',
    destino: 'inline', campo: 'nombre', reportar: false,
  },
  // Escribir una columna GENERATED. Si aparece es bug nuestro, no del usuario.
  '428C9': { texto: GENERICO, destino: 'toast', reportar: true },
}

const ES_PA = /^PA\d{3}$/

/** Quita el prefijo `PA0xx: ` con que la base numera sus mensajes: es ruido para quien lo lee. */
function sinPrefijo(mensaje: string): string {
  return mensaje.replace(/^PA\d{3}:\s*/, '').trim()
}

function leerCampo(error: unknown, campo: string): string | null {
  if (!error || typeof error !== 'object') return null
  const v = (error as Record<string, unknown>)[campo]
  return typeof v === 'string' && v.trim() !== '' ? v : null
}

/**
 * Traduce un error de `supabase.rpc()` a qué mostrar y dónde.
 * Acepta cualquier cosa: null, un Error de red sin `.code`, o un PostgrestError.
 */
export function mapearErrorRpc(error: unknown): ErrorRpcMapeado {
  const code = leerCampo(error, 'code')
  const mensajeBase = leerCampo(error, 'message')

  // Sin código: fallo de red, timeout, o un throw que no viene de PostgREST. Genérico y a Sentry.
  if (!code) {
    return { code: null, mensaje: GENERICO, destino: 'toast', reportar: true }
  }

  const entrada = MAPA[code]

  if (!entrada) {
    // Un PA0xx que este mapa no conoce NO puede desaparecer en el genérico: el código queda a la
    // vista para que se note y se mapee. Es lo único que hace que este archivo envejezca bien.
    if (ES_PA.test(code)) {
      return {
        code,
        mensaje: mensajeBase ? `[${code} sin mapear] ${sinPrefijo(mensajeBase)}` : `[${code} sin mapear]`,
        destino: 'toast',
        reportar: true,
        sinMapear: true,
      }
    }
    return { code, mensaje: GENERICO, destino: 'toast', reportar: true }
  }

  // INVARIANTE del `mensaje`: texto propio > mensaje de la base > genérico. Nunca vacío, porque
  // un `.code` presente con `.message` en blanco (pasa) renderizaría un toast mudo.
  const mensaje = entrada.texto ?? (mensajeBase ? sinPrefijo(mensajeBase) : '') ?? ''

  return {
    code,
    mensaje: mensaje.trim() !== '' ? mensaje : GENERICO,
    destino: entrada.destino,
    campo: entrada.campo,
    recargar: entrada.recargar,
    revertir: entrada.revertir,
    reportar: entrada.reportar,
  }
}

/** Atajo para las pantallas que sólo necesitan saber si fue un rechazo de autorización. */
export function esNoAutorizado(error: unknown): boolean {
  return leerCampo(error, 'code') === '42501'
}
