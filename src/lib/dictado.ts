// H4: el dictado por voz AGREGA al texto del campo en lugar de reemplazarlo.
//   - si el dictado viene vacío (o solo espacios), el campo no cambia;
//   - si el campo está vacío (o solo tiene espacios), queda el dictado;
//   - si no, el texto actual sin espacios finales + salto de línea + el dictado.
export function agregarDictado(actual: string, nuevo: string): string {
  if (!nuevo || nuevo.trim() === '') return actual
  if (!actual || actual.trim() === '') return nuevo
  return `${actual.trimEnd()}\n${nuevo}`
}
