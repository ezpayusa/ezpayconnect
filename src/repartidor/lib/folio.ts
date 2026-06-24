// Helpers de PRESENTACIÓN: folio de entrega y referencia de cobro DERIVADOS del id (decisión Oscar A1/B1).
// NO se persisten, NO son identificadores en RPCs — el `id` interno sigue siendo la clave real. Centralizado acá
// para no hardcodear el formato por pantalla. El prefijo de país por defecto es GT (app GT-only hoy); se puede
// pasar el código real de `configuracion_pais.codigo` cuando una superficie lo tenga disponible.

const PAIS_DEFAULT = 'GT'

/** Folio legible de la entrega, ej. "GT-51". Derivado del id; sólo presentación. */
export function folioEntrega(id: number, paisCodigo?: string | null): string {
  return `${paisCodigo || PAIS_DEFAULT}-${id}`
}

/** Referencia de cobro legible, ej. "COB-51" (1 cobro por entrega → el id es único). Sólo presentación. */
export function refCobro(entregaId: number): string {
  return `COB-${entregaId}`
}
