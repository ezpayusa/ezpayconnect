import { useEffect, useState, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { toast } from 'sonner'
import { MapPin, MapPinOff, CheckCircle2, AlertTriangle } from 'lucide-react'
import {
  jornadaDeHoy, visitasDelDia, visitasProximas, abrirJornada, cerrarJornada, configVisitasEfectiva,
  type Jornada, type VisitaComercial,
} from '../lib/api'
import { useAuth } from '@/hooks/useAuth'
import { reportarError } from '../lib/reportarError'
import { pedirUbicacion, coordsDe, avisoPrevio, type EstadoGeo } from '../lib/geo'
import { fmtFecha, fmtHora } from '../lib/agenda'

const HOY = () => new Date().toISOString().slice(0, 10)

// Jornada del día + sus visitas.
//
// DECISIÓN (1): el permiso de ubicación se pide, pero NO bloquea. Si el usuario dice que no, la
// jornada se abre igual y el registro queda marcado como sin coordenada. Un asesor que no puede
// trabajar por un permiso de navegador es un módulo muerto.
export default function HoyPage() {
  const { perfil } = useAuth()
  const [jornada, setJornada] = useState<Jornada | null>(null)
  const [visitas, setVisitas] = useState<VisitaComercial[]>([])
  const [proximas, setProximas] = useState<VisitaComercial[]>([])
  const [geo, setGeo] = useState<EstadoGeo>({ estado: 'inicial' })
  const [precisionMax, setPrecisionMax] = useState<number | null>(null)
  const [cargando, setCargando] = useState(true)
  const [trabajando, setTrabajando] = useState(false)
  const [notas, setNotas] = useState('')

  const cargar = useCallback(async () => {
    setCargando(true)
    const [j, v, cfg, px] = await Promise.all([jornadaDeHoy(perfil?.id), visitasDelDia(HOY()), configVisitasEfectiva(), visitasProximas(HOY())])
    if (j.error) reportarError(j.error); else setJornada((j.data ?? null) as unknown as Jornada | null)
    if (v.error) reportarError(v.error); else setVisitas((v.data ?? []) as unknown as VisitaComercial[])
    if (cfg.data && Array.isArray(cfg.data) && cfg.data[0]) setPrecisionMax(Number(cfg.data[0].precision_max_m))
    if (px.error) reportarError(px.error); else setProximas((px.data ?? []) as unknown as VisitaComercial[])
    setCargando(false)
    // `perfil?.id` en las deps: la primera pasada puede correr sin perfil y jornadaDeHoy devuelve
    // vacío; cuando el perfil llega, se vuelve a cargar.
  }, [perfil?.id])

  useEffect(() => { void cargar() }, [cargar])

  const leerUbicacion = async () => {
    setGeo({ estado: 'pidiendo' })
    setGeo(await pedirUbicacion())
  }

  const onAbrir = async () => {
    setTrabajando(true)
    const g = geo.estado === 'ok' ? geo : await pedirUbicacion()
    setGeo(g)
    const { error } = await abrirJornada(coordsDe(g))
    setTrabajando(false)
    if (error) { reportarError(error, { onRecargar: () => void cargar() }); return }
    toast.success(g.estado === 'ok' ? 'Jornada abierta' : 'Jornada abierta SIN ubicación')
    void cargar()
  }

  const onCerrar = async () => {
    setTrabajando(true)
    const g = geo.estado === 'ok' ? geo : await pedirUbicacion()
    setGeo(g)
    const { error } = await cerrarJornada(coordsDe(g), notas || null)
    setTrabajando(false)
    if (error) { reportarError(error, { onRecargar: () => void cargar() }); return }
    toast.success('Jornada cerrada')
    setNotas('')
    void cargar()
  }

  if (cargando) return <p className="text-sm text-gray-500">Cargando…</p>

  const aviso = avisoPrevio(geo, precisionMax)
  const abierta = jornada != null && jornada.fin_at == null

  return (
    <div className="space-y-4">
      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-center justify-between">
          <h1 className="font-semibold text-gray-900">Jornada de hoy</h1>
          {jornada && (
            <span className={`rounded-full px-2 py-0.5 text-xs ${abierta ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-700'}`}>
              {abierta ? 'Abierta' : 'Cerrada'}
            </span>
          )}
        </div>

        {/* La precisión es un dato, no un detalle: se muestra ANTES de cualquier registro. */}
        <div className="mt-3 rounded border bg-gray-50 p-3 text-sm">
          <div className="flex items-center gap-2">
            {geo.estado === 'ok'
              ? <MapPin className="h-4 w-4 text-green-700" />
              : <MapPinOff className="h-4 w-4 text-gray-500" />}
            <span id="geo-estado" className="text-gray-800">
              {geo.estado === 'ok' && <>Ubicación lista · precisión <b>±{geo.precision_m} m</b>{precisionMax != null && <> (máximo para verificar: {precisionMax} m)</>}</>}
              {geo.estado === 'inicial' && 'Ubicación sin leer todavía'}
              {geo.estado === 'pidiendo' && 'Pidiendo ubicación…'}
              {geo.estado === 'denegado' && 'Permiso de ubicación DENEGADO'}
              {geo.estado === 'no_disponible' && 'Este navegador no ofrece ubicación'}
              {geo.estado === 'error' && geo.mensaje}
            </span>
            <button type="button" onClick={leerUbicacion} className="ml-auto text-xs text-[#1E5C8E] underline">
              Actualizar ubicación
            </button>
          </div>
          {aviso && (
            <p id="geo-aviso" className="mt-2 flex items-start gap-1.5 text-xs text-amber-800">
              <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />{aviso}
            </p>
          )}
        </div>

        {!abierta ? (
          <button type="button" id="btn-abrir" onClick={onAbrir} disabled={trabajando}
            className="mt-3 rounded-md bg-[#1E5C8E] px-4 py-2 text-sm text-white hover:bg-[#17496f] disabled:opacity-50">
            {jornada ? 'La jornada de hoy ya se cerró' : 'Abrir jornada'}
          </button>
        ) : (
          <div className="mt-3 space-y-2">
            <p className="text-xs text-gray-600">
              Abierta a las {new Date(jornada!.inicio_at).toLocaleTimeString()}
              {!jornada!.inicio_con_ubicacion && ' · sin ubicación registrada'}
            </p>
            <input value={notas} onChange={(e) => setNotas(e.target.value)} id="notas_cierre"
              placeholder="Notas de cierre (opcional)" className="w-full rounded border px-2 py-1.5 text-sm" />
            <button type="button" id="btn-cerrar" onClick={onCerrar} disabled={trabajando}
              className="rounded-md border border-[#1E5C8E] px-4 py-2 text-sm text-[#1E5C8E] hover:bg-blue-50 disabled:opacity-50">
              Cerrar jornada
            </button>
          </div>
        )}
      </section>

      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Visitas de hoy</h2>
          <span className="text-xs text-gray-500">{visitas.length}</span>
        </div>
        {visitas.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">
            Ninguna todavía. Se planifican desde la ficha de un prospecto.
          </p>
        ) : (
          <ul className="mt-2 divide-y">
            {visitas.map(v => (
              <li key={v.id}>
                <Link to={`/comercial/visitas/${v.id}`} className="flex items-center gap-2 py-2 text-sm hover:text-[#1E5C8E]">
                  <span className="flex-1 truncate">{v.prospecto?.nombre ?? 'prospecto'}</span>
                  {v.checkin_at && (
                    v.checkin_verificado
                      ? <span className="flex items-center gap-1 text-xs text-green-700"><CheckCircle2 className="h-3.5 w-3.5" />verificada</span>
                      : <span className="flex items-center gap-1 text-xs text-amber-700"><AlertTriangle className="h-3.5 w-3.5" />sin verificar</span>
                  )}
                  <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-700">{v.estado}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Próximas visitas</h2>
          <span className="text-xs text-gray-500">{proximas.length}</span>
        </div>
        {proximas.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">No tenés visitas agendadas a futuro.</p>
        ) : (
          <ul className="mt-2 divide-y">
            {proximas.map(p => (
              <li key={p.id}>
                <Link to={`/comercial/visitas/${p.id}`} className="flex items-center gap-2 py-2 text-sm hover:text-[#1E5C8E]">
                  <span className="shrink-0 font-medium text-gray-900">{fmtFecha(p.fecha_planificada)}</span>
                  <span className="shrink-0 text-gray-500">{fmtHora(p.hora_planificada)}</span>
                  <span className="flex-1 truncate">{p.prospecto?.nombre ?? 'prospecto'}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
