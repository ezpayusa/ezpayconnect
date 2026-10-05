// Definición única de "campaña vigente" en el front: activa y con hoy dentro de [fecha_inicio, fecha_fin], ambos incluidos.
// "Hoy" es el día LOCAL (hoyISO). La RLS del viewer y los banners todavía comparan contra CURRENT_DATE / UTC:
// unificar ese criterio queda pendiente para después del 11-oct.
import { hoyISO } from '@/lib/fecha'

export function esCampanaVigente(
  c: { activa: boolean | null | undefined; fecha_inicio: string | null | undefined; fecha_fin: string | null | undefined },
  hoy: string = hoyISO()
): boolean {
  if (c.activa !== true) return false
  const inicio = (c.fecha_inicio ?? '').slice(0, 10)
  const fin = (c.fecha_fin ?? '').slice(0, 10)
  const dia = hoy.slice(0, 10)
  if (!inicio || !fin || inicio > fin) return false
  return inicio <= dia && dia <= fin
}
