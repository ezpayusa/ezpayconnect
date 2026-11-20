// Nombre del médico con el prefijo «Dr.», sin repetirlo: si el nombre ya empieza con «Dr.», «Dra.»,
// «Dr » o «Dra » (sin importar mayúsculas), se deja como está. Fuente única para el panel clínico,
// la receta (detalle y PDF) y la app del paciente; evita el «Dr. Dr. …».
const YA_TIENE_PREFIJO = /^dra?(\.|\s)/i

export function nombreMedicoConPrefijo(nombre: string | null | undefined, siVacio = 'Médico'): string {
  const n = (nombre ?? '').trim()
  if (!n) return siVacio
  return YA_TIENE_PREFIJO.test(n) ? n : `Dr. ${n}`
}
