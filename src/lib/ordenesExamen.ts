// Órdenes de examen (mig 332): se crean SOLO por RPC — crear_orden_examen_medico (ConsultaPage) y
// crear_orden_examen_walkin (portal del laboratorio). Cada ítem trae exactamente UNA clave:
//   { catalogo_id } → examen del catálogo; el nombre lo copia el servidor desde examenes_catalogo.
//   { nombre }      → examen fuera de catálogo (queda con catalogo_id NULL).
export type ItemOrdenExamen = { catalogo_id: string } | { nombre: string }

/** Ítems a partir de los ids de catálogo marcados y los nombres escritos a mano. */
export function armarItemsOrden(catalogoIds: Iterable<string>, nombresLibres: string[]): ItemOrdenExamen[] {
  return [
    ...Array.from(catalogoIds, (catalogo_id) => ({ catalogo_id })),
    ...nombresLibres.map((s) => s.trim()).filter(Boolean).map((nombre) => ({ nombre })),
  ]
}

/** "Otros exámenes (uno por línea)" → nombres recortados, sin líneas vacías. */
export function lineasExamenes(texto: string): string[] {
  return texto.split('\n').map((s) => s.trim()).filter(Boolean)
}

/** Los rechazos EXnnn de las RPCs traen el mensaje para el usuario en español: se muestran tal cual. */
export function mensajeErrorOrden(error: { code?: string; message: string }, prefijo: string): string {
  return error.code?.startsWith('EX') ? error.message : prefijo + error.message
}
