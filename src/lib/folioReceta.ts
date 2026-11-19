// H12: folio oficial de una receta, el mismo en el aviso, el detalle, el PDF y la impresión.
//
// Desde la mig 395, emitir_receta arma el folio y lo guarda en recetas.folio:
//   COALESCE(cedula_profesional, 'SINCED') || '-' || lpad(correlativo, 6, '0') || '-' || to_char(now(), 'YYYYMMDD')
// (now() en la sesión de la base, que corre en UTC). Para las recetas anteriores:
//   - con numero_correlativo (emitidas por emitir_receta antes de la 395): se reconstruye con la
//     misma fórmula, tomando la fecha de created_at en UTC y la cédula actual del médico;
//   - sin numero_correlativo (anteriores a la numeración): se identifica por el id, marcado como tal.
//
// La edge supabase/functions/generar-pdf-receta/index.ts replica esta lógica (no puede importar
// desde src/): si se cambia acá, hay que cambiarla allá.

export interface RecetaParaFolio {
  id: number
  folio?: string | null
  numero_correlativo?: number | null
  created_at: string
}

/** AAAAMMDD de una fecha ISO, en UTC. */
function fechaUTC(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso.slice(0, 10).replace(/-/g, '')
  const mm = String(d.getUTCMonth() + 1).padStart(2, '0')
  const dd = String(d.getUTCDate()).padStart(2, '0')
  return `${d.getUTCFullYear()}${mm}${dd}`
}

export function folioReceta(r: RecetaParaFolio, cedula?: string | null): string {
  if (r.folio) return r.folio
  if (r.numero_correlativo != null) {
    return `${cedula || 'SINCED'}-${String(r.numero_correlativo).padStart(6, '0')}-${fechaUTC(r.created_at)}`
  }
  return `REC-${String(r.id).padStart(6, '0')} (anterior a la numeración)`
}
