import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { supabase } from '@/lib/supabase'
import { useConsentimientoGate } from '@/hooks/useConsentimientoGate'
import { motivoErrorAsistenteIA } from '@/lib/errorAsistenteIA'
import { AlertTriangle, History, Loader2, RefreshCw, ShieldOff } from 'lucide-react'

// Resumen IA de la ÚLTIMA visita (fase 1): edge asistente-ia en modo 'resumen_visita', que arma el
// contexto con contexto_ia_ultima_visita (mig 339) y gatea con gate_accion_phi('asistente_ia').
// Se genera SOLO con click (cada llamada cuesta tokens): sin auto-carga ni reintento automático.
// Montarlo con key={pacienteId} para no arrastrar un resumen de un paciente a otro.

interface Resumen {
  resumen: string
  hallazgos_clave: string[]
  signos_vitales_relevantes: string[]
  pendientes_seguimiento: string[]
  datos_faltantes: string[]
}

interface ResultadoResumen {
  cita_id: number
  fecha: string | null
  hora_inicio: string | null
  medico_nombre: string | null
  corregida: boolean
  resumen: Resumen
}

const lista = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])

// 'YYYY-MM-DD' de la cita es una fecha de calendario: se arma en local para que no corra un día por TZ.
function fechaVisita(f: string | null): string {
  const m = f ? /^(\d{4})-(\d{2})-(\d{2})/.exec(f) : null
  if (!m) return 'Fecha no registrada'
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
    .toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' })
}

const SECCIONES: { clave: keyof Omit<Resumen, 'resumen'>; titulo: string }[] = [
  { clave: 'hallazgos_clave', titulo: 'Hallazgos clave' },
  { clave: 'signos_vitales_relevantes', titulo: 'Signos vitales relevantes' },
  { clave: 'pendientes_seguimiento', titulo: 'Pendientes de seguimiento' },
  { clave: 'datos_faltantes', titulo: 'Datos faltantes en la nota' },
]

export default function ResumenUltimaVisita({ pacienteId }: { pacienteId: number }) {
  // Mismo gate UX que AsistenteIA (la barrera real la aplica el edge).
  const { permitido, cargando: cargandoConsent, error: errorConsent, recargar } = useConsentimientoGate(pacienteId)
  const iaBloqueada = !permitido('asistente_ia')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [sinVisita, setSinVisita] = useState(false)
  const [resultado, setResultado] = useState<ResultadoResumen | null>(null)

  const generar = async () => {
    setLoading(true)
    setError('')
    setSinVisita(false)
    setResultado(null)
    try {
      const { data, error: invokeError } = await supabase.functions.invoke('asistente-ia', {
        body: { modo: 'resumen_visita', paciente_id: pacienteId },
      })
      if (invokeError || !data || typeof data !== 'object' || 'error' in data) {
        setError(await motivoErrorAsistenteIA(invokeError, data))
        return
      }
      if (data.sin_visita === true) {
        setSinVisita(true)
        return
      }
      const r = data.resumen ?? {}
      setResultado({
        cita_id: data.cita_id,
        fecha: data.fecha ?? null,
        hora_inicio: data.hora_inicio ?? null,
        medico_nombre: data.medico_nombre ?? null,
        corregida: data.corregida === true,
        resumen: {
          resumen: typeof r.resumen === 'string' ? r.resumen : '',
          hallazgos_clave: lista(r.hallazgos_clave),
          signos_vitales_relevantes: lista(r.signos_vitales_relevantes),
          pendientes_seguimiento: lista(r.pendientes_seguimiento),
          datos_faltantes: lista(r.datos_faltantes),
        },
      })
    } catch (e) {
      setError(await motivoErrorAsistenteIA(e))
    } finally {
      setLoading(false)
    }
  }

  const deshabilitado = loading || cargandoConsent || iaBloqueada || errorConsent

  return (
    <div className="space-y-3">
      <div className="bg-purple-50 border border-purple-200 rounded-lg p-3 text-xs text-purple-700 flex items-start gap-2">
        <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
        <p>Resumen generado por IA a partir de la nota registrada. Verificá contra el expediente antes de usarlo.</p>
      </div>

      {errorConsent ? (
        <div className="flex items-center justify-between gap-2 rounded-md border border-red-200 bg-red-50 p-3">
          <span className="flex items-center gap-2 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4 shrink-0" /> No se pudo verificar el consentimiento de IA
          </span>
          <Button variant="outline" size="sm" onClick={() => recargar()}>Reintentar</Button>
        </div>
      ) : iaBloqueada ? (
        <div className="flex items-center gap-2 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-3 py-2">
          <ShieldOff className="h-4 w-4 shrink-0" />
          El paciente revocó el uso de IA. Captúralo en Consentimiento.
        </div>
      ) : null}

      <Button
        type="button"
        onClick={generar}
        disabled={deshabilitado}
        variant="outline"
        className="w-full border-purple-300 text-purple-700 hover:bg-purple-50"
      >
        {loading ? (
          <Loader2 className="h-4 w-4 animate-spin mr-2" />
        ) : resultado ? (
          <RefreshCw className="h-4 w-4 mr-2" />
        ) : (
          <History className="h-4 w-4 mr-2" />
        )}
        {loading ? 'Generando resumen...' : resultado ? 'Volver a generar' : 'Resumen de la última visita'}
      </Button>

      {error && (
        <div role="alert" className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {sinVisita && (
        <div className="bg-slate-50 border border-slate-200 rounded-lg p-3 text-sm text-slate-600">
          El paciente no tiene visitas completadas con nota registrada
        </div>
      )}

      {resultado && (
        <div className="rounded-lg border border-slate-200 p-3 space-y-3 text-sm">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-medium text-slate-800">
              {fechaVisita(resultado.fecha)}
              {resultado.hora_inicio ? ` · ${resultado.hora_inicio.slice(0, 5)}` : ''}
            </span>
            {resultado.medico_nombre && <span className="text-xs text-slate-500">{resultado.medico_nombre}</span>}
            {resultado.corregida && (
              <Badge variant="outline" className="border-amber-300 bg-amber-50 text-amber-800 text-[10px]">Nota corregida</Badge>
            )}
          </div>

          {resultado.resumen.resumen && <p className="text-slate-700 whitespace-pre-line">{resultado.resumen.resumen}</p>}

          {SECCIONES.filter(s => resultado.resumen[s.clave].length > 0).map(s => (
            <div key={s.clave}>
              <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">{s.titulo}</h4>
              <ul className="list-disc pl-5 space-y-0.5 text-slate-700">
                {resultado.resumen[s.clave].map((item, i) => <li key={i}>{item}</li>)}
              </ul>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
