// Helpers de fecha en hora LOCAL — fuente única para el frente.
//
// EL BUG que esto evita: la columna `citas.fecha` es `date` ('YYYY-MM-DD', sin hora ni zona).
// `new Date('YYYY-MM-DD')` la parsea como MEDIANOCHE UTC → en GT/Mountain (UTC−6/−7) cae en
// el DÍA ANTERIOR local. Y `toISOString()` sobre un Date local devuelve el día en UTC → en
// Guatemala, después de las 18:00, "hoy" salta a mañana.
//
// REGLA:
//  - Columna DATE ('fecha', 'fecha_visita'): NUNCA `new Date(iso)` ni `toISOString()`.
//    Usar parseFechaLocal / fechaLocalISO / combinar de este módulo.
//  - Columna timestamptz ('llegada_at', 'created_at'): SÍ `new Date()` — ahí el instante
//    absoluto es correcto y la zona la maneja el propio timestamptz.

// 'YYYY-MM-DD' → Date a medianoche LOCAL (no UTC).
export function parseFechaLocal(iso: string): Date {
  const [y, m, d] = iso.split('-').map(Number)
  return new Date(y, m - 1, d)
}

// yyyy-mm-dd en hora LOCAL (no UTC → evita corrimiento de día en TZ negativas).
export function fechaLocalISO(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${dd}`
}

// Hoy como 'YYYY-MM-DD' en hora LOCAL.
export function hoyISO(): string {
  return fechaLocalISO(new Date())
}

// Combina una fecha DATE ('YYYY-MM-DD') con una hora 'HH:MM' en un Date LOCAL.
export function combinar(fechaISO: string, hora: string | null): Date {
  const base = parseFechaLocal(fechaISO)
  const [h, mi] = (hora || '00:00').split(':').map(Number)
  base.setHours(h || 0, mi || 0, 0, 0)
  return base
}
