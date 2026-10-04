import { combinar, fechaLocalISO } from '@/lib/fecha'

// Clasificación de las citas del paciente por FECHA Y HORA, no solo por estado: una cita "confirmada" de hace tres
// meses que nadie cerró ya no es próxima. La hora es la del navegador (combinar arma un Date LOCAL desde la columna DATE
// y la hora; nada de new Date('YYYY-MM-DD'), que en GT cae en el día anterior).
//
// - inicio = fecha + hora_inicio; fin = fecha + hora_fin (o hora_inicio si no hay hora_fin).
// - Canceladas: cancelada | no_show.
// - Próximas: ni cancelada ni completada, y (fin >= ahora, o en_curso/en_espera DE HOY). Ascendente por inicio.
//   Un en_curso/en_espera de un día anterior es un residuo sin cerrar: va a Pasadas.
// - Pasadas: completada, o el resto no cancelado que ya terminó. Descendente por inicio.
// "Hoy" es el día local de `ahora` (= hoyISO() cuando ahora = new Date(), que es como lo llama el hook); se deriva de
// `ahora` para que la función sea pura y testeable con un ahora fijo.

export interface CitaConHorario {
  fecha: string
  hora_inicio: string | null
  hora_fin?: string | null
  estado: string
}

const CANCELADAS = ['cancelada', 'no_show']
const EN_ATENCION = ['en_curso', 'en_espera']
export const ESTADOS_ACTIVOS = ['solicitada', 'agendada', 'confirmada']
// Estados que en Pasadas significan que nadie cerró la cita: se muestran como "Sin cerrar".
const ESTADOS_SIN_CERRAR = [...ESTADOS_ACTIVOS, ...EN_ATENCION]

export const inicioCita = (c: CitaConHorario): Date => combinar(c.fecha, c.hora_inicio)
export const finCita = (c: CitaConHorario): Date => combinar(c.fecha, c.hora_fin || c.hora_inicio)

/** Una cita en Pasadas que quedó en un estado activo: nadie la cerró. */
export const citaSinCerrar = (c: CitaConHorario): boolean => ESTADOS_SIN_CERRAR.includes(c.estado)

export function clasificarCitas<T extends CitaConHorario>(
  citas: T[],
  ahora: Date
): { proximas: T[]; pasadas: T[]; canceladas: T[] } {
  const t = ahora.getTime()
  const hoy = fechaLocalISO(ahora)
  const proximas: T[] = []
  const pasadas: T[] = []
  const canceladas: T[] = []
  for (const c of citas) {
    if (CANCELADAS.includes(c.estado)) canceladas.push(c)
    else if (c.estado === 'completada') pasadas.push(c)
    else if ((EN_ATENCION.includes(c.estado) && c.fecha === hoy) || finCita(c).getTime() >= t) proximas.push(c)
    else pasadas.push(c)
  }
  proximas.sort((a, b) => inicioCita(a).getTime() - inicioCita(b).getTime())
  pasadas.sort((a, b) => inicioCita(b).getTime() - inicioCita(a).getTime())
  return { proximas, pasadas, canceladas }
}
