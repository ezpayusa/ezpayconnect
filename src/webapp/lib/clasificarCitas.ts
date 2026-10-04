import { combinar } from '@/lib/fecha'

// Clasificación de las citas del paciente por FECHA Y HORA, no solo por estado: una cita "confirmada" de hace tres
// meses que nadie cerró ya no es próxima. La hora es la del navegador (combinar arma un Date LOCAL desde la columna DATE
// y la hora; nada de new Date('YYYY-MM-DD'), que en GT cae en el día anterior).
//
// - inicio = fecha + hora_inicio; fin = fecha + hora_fin (o hora_inicio si no hay hora_fin).
// - Canceladas: cancelada | no_show.
// - Próximas: ni cancelada ni completada, y (fin >= ahora, o en_curso, o en_espera). Ascendente por inicio.
// - Pasadas: completada, o (no cancelada, fin < ahora y no en_curso/en_espera). Descendente por inicio.

export interface CitaConHorario {
  fecha: string
  hora_inicio: string | null
  hora_fin?: string | null
  estado: string
}

const CANCELADAS = ['cancelada', 'no_show']
const EN_ATENCION = ['en_curso', 'en_espera']
// Estados que todavía esperan algo: en Pasadas se muestran como "Sin cerrar".
export const ESTADOS_ACTIVOS = ['solicitada', 'agendada', 'confirmada']

export const inicioCita = (c: CitaConHorario): Date => combinar(c.fecha, c.hora_inicio)
export const finCita = (c: CitaConHorario): Date => combinar(c.fecha, c.hora_fin || c.hora_inicio)

/** Una cita en Pasadas que quedó en un estado activo: nadie la cerró. */
export const citaSinCerrar = (c: CitaConHorario): boolean => ESTADOS_ACTIVOS.includes(c.estado)

export function clasificarCitas<T extends CitaConHorario>(
  citas: T[],
  ahora: Date
): { proximas: T[]; pasadas: T[]; canceladas: T[] } {
  const t = ahora.getTime()
  const proximas: T[] = []
  const pasadas: T[] = []
  const canceladas: T[] = []
  for (const c of citas) {
    if (CANCELADAS.includes(c.estado)) canceladas.push(c)
    else if (c.estado === 'completada') pasadas.push(c)
    else if (EN_ATENCION.includes(c.estado) || finCita(c).getTime() >= t) proximas.push(c)
    else pasadas.push(c)
  }
  proximas.sort((a, b) => inicioCita(a).getTime() - inicioCita(b).getTime())
  pasadas.sort((a, b) => inicioCita(b).getTime() - inicioCita(a).getTime())
  return { proximas, pasadas, canceladas }
}
