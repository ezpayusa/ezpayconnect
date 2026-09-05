import { parseFechaLocal } from '@/lib/fecha'

// Helpers PUROS de la agenda de visitas. Sin React, sin supabase: se testean solos.
//
// HOY() se mantiene en UTC a propósito (toISOString), igual que en las páginas: es coherente con
// CURRENT_DATE de la base, que es la que decide PA026 ("fecha pasada") y la adopción por jornada.
// Cambiarlo a hora local es una decisión aparte y no entra en este bloque.
export const HOY = () => new Date().toISOString().slice(0, 10)

/** 'YYYY-MM-DD' -> "jue 05 sep" (local, legible). Si no parsea, devuelve lo que vino. */
export function fmtFecha(iso: string | null | undefined): string {
  if (!iso) return '—'
  try {
    return parseFechaLocal(iso).toLocaleDateString('es', { weekday: 'short', day: '2-digit', month: 'short' })
  } catch {
    return iso
  }
}

/** Postgres devuelve `time` como "HH:MM:SS"; se muestra "HH:mm" o "sin hora". */
export function fmtHora(hora: string | null | undefined): string {
  if (!hora) return 'sin hora'
  return hora.slice(0, 5)
}

/** Para el <input type="time">, que quiere "HH:mm" y no "HH:MM:SS". */
export function horaParaInput(hora: string | null | undefined): string {
  return hora ? hora.slice(0, 5) : ''
}

/** "jue 05 sep · 10:30" / "jue 05 sep · sin hora" */
export function fmtFechaHora(fecha: string, hora: string | null | undefined): string {
  return `${fmtFecha(fecha)} · ${fmtHora(hora)}`
}
