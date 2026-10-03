// Nombre del laboratorio en "En proveedores" (búsqueda del médico, mig 354).
//
// El médico no lee empresas_proveedoras (RLS): el embed empresa:empresa_id(...) le llega null. El nombre sale de la
// RPC DEFINER nombre_empresa_por_productos, que solo devuelve (empresa_id, nombre_empresa) de empresas con productos
// que el médico ve. Las empresas afines NO las filtra el cliente: la barrera es la RLS ("Médico ve productos activos"
// excluye afines y exige rol médico/super_admin), y la RPC tampoco devuelve nombre de una afín.

type ConEmpresa = { empresa_id?: string | null; empresa?: { nombre_empresa?: string | null } | null }

/** Ids de empresa distintos y no vacíos de una lista de productos. */
export function idsEmpresa(productos: ConEmpresa[]): string[] {
  return [...new Set(productos.map((p) => p.empresa_id).filter((x): x is string => !!x))]
}

/**
 * Completa empresa.nombre_empresa con lo que devolvió la RPC. Un producto cuya empresa no vino en la respuesta queda
 * como estaba (best-effort: si la RPC falla, la lista no se pierde).
 */
export function conNombreEmpresa<T extends ConEmpresa>(
  productos: T[],
  filas: Array<{ empresa_id: string; nombre_empresa: string | null }> | null | undefined,
): T[] {
  const mapa = new Map((filas ?? []).filter((f) => f?.empresa_id && f.nombre_empresa).map((f) => [f.empresa_id, f.nombre_empresa as string]))
  if (mapa.size === 0) return productos
  return productos.map((p) =>
    p.empresa_id && mapa.has(p.empresa_id)
      ? { ...p, empresa: { ...(p.empresa ?? {}), nombre_empresa: mapa.get(p.empresa_id) } }
      : p,
  )
}
