// Citas de la clínica: los contadores de los chips salen de la lista COMPLETA; el filtro de estado
// solo decide qué se muestra. Antes los dos salían de la lista ya filtrada y con «Solicitadas» activo
// el chip «Todas» marcaba lo mismo que «Solicitadas».
type ConEstado = { estado: string }

export function contarPorEstado(citas: ConEstado[]): Record<string, number> {
  const c: Record<string, number> = { todos: citas.length }
  for (const cita of citas) c[cita.estado] = (c[cita.estado] || 0) + 1
  return c
}

export function filtrarPorEstado<T extends ConEstado>(citas: T[], filtro: string): T[] {
  return filtro === 'todos' ? citas : citas.filter(c => c.estado === filtro)
}
