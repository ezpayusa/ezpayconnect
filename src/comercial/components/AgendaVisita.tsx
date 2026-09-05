import { useState } from 'react'
import { toast } from 'sonner'
import { CalendarPlus, CalendarClock, XCircle } from 'lucide-react'
import { planificarVisita, reprogramarVisita, cancelarVisita, type VisitaComercial } from '../lib/api'
import { reportarError, type ErrorInline } from '../lib/reportarError'
import { HOY, fmtFecha, fmtHora, horaParaInput } from '../lib/agenda'

// Piezas compartidas de la agenda: el formulario fecha+hora y las acciones sobre una visita
// planificada. Viven acá para que ProspectoFichaPage y VisitaFichaPage no tengan dos copias que
// un día acepten cosas distintas.
//
// Los botones se muestran a asesor y supervisor por igual: quién puede agendar/reprogramar/
// cancelar lo decide la RPC (puede_gestionar_prospecto -> 42501). El `disabled` mientras corre
// es cortesía, no protección.

type Coords = { fecha: string; hora: string | null }

/**
 * Formulario fecha (min = hoy, default = hoy) + hora opcional. No llama a nada: entrega los
 * valores a `onSubmit` y muestra el error inline que le pasen.
 */
export function FormFechaHora(props: {
  label: string
  onSubmit: (v: Coords) => Promise<void>
  onCancel?: () => void
  inicial?: Coords
  error?: ErrorInline
  busy?: boolean
  idPrefix?: string
}) {
  const { label, onSubmit, onCancel, inicial, error, busy, idPrefix = 'agenda' } = props
  const [fecha, setFecha] = useState(inicial?.fecha ?? HOY())
  const [hora, setHora] = useState(horaParaInput(inicial?.hora))
  const err = (campo: string) =>
    error && error.campo === campo ? <p className="mt-1 text-xs text-red-600">{error.mensaje}</p> : null

  return (
    <div className="rounded border bg-gray-50 p-3">
      <div className="grid gap-2 sm:grid-cols-2">
        <div>
          <label className="text-xs text-gray-600">Fecha</label>
          <input type="date" id={`${idPrefix}-fecha`} value={fecha} min={HOY()}
            onChange={(e) => setFecha(e.target.value)}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          {err('fecha')}
        </div>
        <div>
          <label className="text-xs text-gray-600">Hora (opcional)</label>
          <input type="time" id={`${idPrefix}-hora`} value={hora}
            onChange={(e) => setHora(e.target.value)}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
        </div>
      </div>
      {/* 23505 y PA027 no apuntan a un campo concreto del form: van acá, debajo de los dos. */}
      {err('visita')}
      {err('nombre')}
      <div className="mt-2 flex gap-2">
        <button type="button" id={`${idPrefix}-confirmar`} disabled={busy || !fecha}
          onClick={() => void onSubmit({ fecha, hora: hora || null })}
          className="rounded-md bg-[#1E5C8E] px-3 py-1.5 text-sm text-white hover:bg-[#17496f] disabled:opacity-50">
          {busy ? 'Guardando…' : label}
        </button>
        {onCancel && (
          <button type="button" onClick={onCancel} disabled={busy}
            className="rounded-md border border-gray-300 px-3 py-1.5 text-sm text-gray-700 disabled:opacity-50">
            Cerrar
          </button>
        )}
      </div>
    </div>
  )
}

/**
 * Botón "Agendar visita" + su formulario. Llama a planificar_visita.
 * El 23505 (ya hay una visita ese día) se muestra con TEXTO DE CONTEXTO acá: el mapa de errores
 * sigue genérico a propósito, porque desde el mapa no se puede saber qué UNIQUE fue.
 */
export function AgendarVisita(props: { prospectoId: string; label?: string; onAgendada?: () => void }) {
  const { prospectoId, label = 'Agendar visita', onAgendada } = props
  const [abierto, setAbierto] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<ErrorInline>(null)

  const onSubmit = async ({ fecha, hora }: Coords) => {
    setError(null); setBusy(true)
    const { error: e } = await planificarVisita(prospectoId, fecha, hora)
    setBusy(false)
    if (e) {
      const m = reportarError(e, { setInline: setError })
      if (m.code === '23505') {
        setError({ campo: 'nombre', mensaje: 'Ya hay una visita para este prospecto ese día.' })
      }
      return
    }
    toast.success(`Visita agendada para ${fmtFecha(fecha)}${hora ? ' ' + fmtHora(hora) : ''}`)
    setAbierto(false)
    onAgendada?.()
  }

  if (!abierto) {
    return (
      <button type="button" id="btn-agendar" onClick={() => { setError(null); setAbierto(true) }}
        className="inline-flex items-center gap-1 rounded-md border border-[#1E5C8E] px-3 py-1.5 text-sm text-[#1E5C8E] hover:bg-blue-50">
        <CalendarPlus className="h-4 w-4" />{label}
      </button>
    )
  }
  return (
    <FormFechaHora label="Agendar" onSubmit={onSubmit} onCancel={() => setAbierto(false)}
      error={error} busy={busy} idPrefix="agendar" />
  )
}

/**
 * Acciones sobre una visita PLANIFICADA: Reprogramar (mismo form) y Cancelar (motivo obligatorio,
 * confirmación inline). Los errores PA026/PA027/42501 quedan inline en la fila.
 * No renderiza nada si la visita no está planificada: en ese estado no hay nada que hacer.
 */
export function AccionesVisitaPlanificada(props: { visita: VisitaComercial; onCambio?: () => void }) {
  const { visita, onCambio } = props
  const [modo, setModo] = useState<null | 'reprogramar' | 'cancelar'>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<ErrorInline>(null)
  const [motivo, setMotivo] = useState('')

  if (visita.estado !== 'planificada') return null

  const cerrar = () => { setModo(null); setError(null); setMotivo('') }

  const onReprogramar = async ({ fecha, hora }: Coords) => {
    setError(null); setBusy(true)
    const { error: e } = await reprogramarVisita(visita.id, fecha, hora)
    setBusy(false)
    if (e) {
      const m = reportarError(e, { setInline: setError })
      if (m.code === '23505') setError({ campo: 'nombre', mensaje: 'Ya hay una visita para este prospecto ese día.' })
      return
    }
    toast.success(`Visita reprogramada para ${fmtFecha(fecha)}${hora ? ' ' + fmtHora(hora) : ''}`)
    cerrar(); onCambio?.()
  }

  const onCancelar = async () => {
    setError(null)
    if (!motivo.trim()) { setError({ campo: 'motivo', mensaje: 'Decí por qué se cancela.' }); return }
    setBusy(true)
    const { error: e } = await cancelarVisita(visita.id, motivo.trim())
    setBusy(false)
    if (e) { reportarError(e, { setInline: setError }); return }
    toast.success('Visita cancelada')
    cerrar(); onCambio?.()
  }

  return (
    <div className="mt-2">
      {modo === null && (
        <div className="flex gap-2">
          <button type="button" data-testid={`btn-reprogramar-${visita.id}`} onClick={() => setModo('reprogramar')}
            className="inline-flex items-center gap-1 rounded border border-gray-300 px-2 py-1 text-xs text-gray-700 hover:bg-gray-50">
            <CalendarClock className="h-3.5 w-3.5" />Reprogramar
          </button>
          <button type="button" data-testid={`btn-cancelar-${visita.id}`} onClick={() => setModo('cancelar')}
            className="inline-flex items-center gap-1 rounded border border-red-300 px-2 py-1 text-xs text-red-700 hover:bg-red-50">
            <XCircle className="h-3.5 w-3.5" />Cancelar
          </button>
        </div>
      )}
      {modo === 'reprogramar' && (
        <FormFechaHora label="Reprogramar" onSubmit={onReprogramar} onCancel={cerrar}
          inicial={{ fecha: visita.fecha_planificada, hora: visita.hora_planificada }}
          error={error} busy={busy} idPrefix={`reprog-${visita.id}`} />
      )}
      {modo === 'cancelar' && (
        <div className="rounded border border-red-200 bg-red-50 p-3">
          <p className="text-sm text-red-900">¿Cancelar la visita del {fmtFecha(visita.fecha_planificada)}? Contá por qué:</p>
          <input value={motivo} onChange={(e) => setMotivo(e.target.value)} data-testid={`motivo-${visita.id}`}
            placeholder="Motivo (obligatorio)" className="mt-2 w-full rounded border px-2 py-1.5 text-sm" />
          {error && <p className="mt-1 text-xs text-red-600">{error.mensaje}</p>}
          <div className="mt-2 flex gap-2">
            <button type="button" onClick={cerrar} disabled={busy}
              className="rounded border border-gray-300 px-3 py-1 text-xs text-gray-700 disabled:opacity-50">Volver</button>
            <button type="button" data-testid={`confirmar-cancelar-${visita.id}`} onClick={() => void onCancelar()} disabled={busy}
              className="rounded bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-700 disabled:opacity-50">
              {busy ? 'Cancelando…' : 'Cancelar visita'}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
