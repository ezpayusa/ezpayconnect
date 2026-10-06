// Mig 369: el catálogo de exámenes del laboratorio se escribe solo por RPC (crear_examen_catalogo,
// actualizar_examen_catalogo, eliminar_examen_catalogo). Sus rechazos traen errcode EX035-EX039 con un mensaje para el
// usuario; 42501 también. Cualquier otro error se muestra con un texto genérico (sin detalles internos).
//   EX035 sin permiso · EX036 el examen no existe en tu catálogo · EX037 nombre o categoría inválidos
//   EX038 ya fue ordenado: no se borra, se desactiva · EX039 nombre repetido

export const CODIGO_EXAMEN_REFERENCIADO = 'EX038'

const CODIGOS_CON_MENSAJE = new Set(['EX035', 'EX036', 'EX037', 'EX038', 'EX039', '42501'])

export function mensajeErrorCatalogo(error: { code?: string | null; message?: string | null } | null | undefined, generico: string): string {
  if (error?.code && CODIGOS_CON_MENSAJE.has(error.code) && error.message) return error.message
  return generico
}

/** El examen ya fue ordenado: la pantalla ofrece desactivarlo en lugar de borrarlo. */
export function esExamenReferenciado(error: { code?: string | null } | null | undefined): boolean {
  return error?.code === CODIGO_EXAMEN_REFERENCIADO
}
