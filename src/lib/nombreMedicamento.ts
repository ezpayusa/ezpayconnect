// Nombre de un medicamento del catálogo para mostrar: «Genérico (Comercial)» cuando hay nombre
// comercial; si no, solo el genérico. Mismo formato que ya se guardaba en el ítem de la receta.
export function nombreMedicamentoConComercial(med: { nombre_generico: string; nombre_comercial?: string | null }): string {
  const comercial = med.nombre_comercial?.trim()
  return comercial ? `${med.nombre_generico} (${comercial})` : med.nombre_generico
}
