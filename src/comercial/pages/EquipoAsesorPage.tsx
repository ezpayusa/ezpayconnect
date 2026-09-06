import { useEffect, useState } from 'react'
import { useParams, Link, Navigate } from 'react-router-dom'
import { ArrowLeft, CheckCircle2, AlertTriangle, CloudOff } from 'lucide-react'
import { useAuth } from '@/hooks/useAuth'
import { jornadasDelDia, visitasDelDia, visitasProximas, asesoresVisibles, asesoresConNombre,
  mapaAsesores, nombreAsesor, type Jornada, type VisitaComercial, type AsesorConNombre } from '../lib/api'
import { fmtFecha, fmtHora } from '../lib/agenda'
import { reportarError } from '../lib/reportarError'

const HOY = () => new Date().toISOString().slice(0, 10)

// Detalle del día de un asesor. Sólo lectura, igual que la lista.
export default function EquipoAsesorPage() {
  const { asesorId = '' } = useParams()
  const { perfil } = useAuth()
  const [nombre, setNombre] = useState<string>('')
  const [jornada, setJornada] = useState<Jornada | null>(null)
  const [visitas, setVisitas] = useState<VisitaComercial[]>([])
  const [proximas, setProximas] = useState<VisitaComercial[]>([])
  const [cargando, setCargando] = useState(true)

  useEffect(() => {
    void (async () => {
      setCargando(true)
      const [a, j, v, px, nom] = await Promise.all([asesoresVisibles(), jornadasDelDia(HOY()), visitasDelDia(HOY()), visitasProximas(HOY()), asesoresConNombre()])
      // El nombre sale de la RPC (mig 283) y el codigo de la ficha; si el asesor no esta en
      // ninguno de los dos, `nombreAsesor` dice "asesor no visible" y no un generico.
      if (nom.error) reportarError(nom.error)
      const codigo = (a.data as unknown as { id: string; codigo_asesor: string }[] | null)
        ?.find(x => x.id === asesorId)?.codigo_asesor
      setNombre(nombreAsesor(asesorId, mapaAsesores(nom.data as AsesorConNombre[] | null), codigo))
      if (j.error) reportarError(j.error)
      else setJornada(((j.data ?? []) as unknown as Jornada[]).find(x => x.asesor_id === asesorId) ?? null)
      if (v.error) reportarError(v.error)
      else setVisitas(((v.data ?? []) as unknown as VisitaComercial[]).filter(x => x.asesor_id === asesorId))
      if (px.error) reportarError(px.error)
      else setProximas(((px.data ?? []) as unknown as VisitaComercial[]).filter(x => x.asesor_id === asesorId))
      setCargando(false)
    })()
  }, [asesorId])

  if (perfil && perfil.rol !== 'supervisor_comercial') return <Navigate to="/comercial/hoy" replace />
  if (cargando) return <p className="text-sm text-gray-500">Cargando…</p>

  return (
    <div className="space-y-4">
      <Link to="/comercial/equipo" className="inline-flex items-center gap-1 text-sm text-[#1E5C8E]">
        <ArrowLeft className="h-4 w-4" /> Volver al equipo
      </Link>

      <section className="rounded-lg border bg-white p-4">
        <h1 className="font-semibold text-gray-900">{nombre}</h1>
        <p className="mt-1 text-sm text-gray-700">
          {jornada
            ? jornada.fin_at
              ? `Jornada de ${new Date(jornada.inicio_at).toLocaleTimeString()} a ${new Date(jornada.fin_at).toLocaleTimeString()}`
              : `Jornada abierta desde las ${new Date(jornada.inicio_at).toLocaleTimeString()}`
            : 'Sin jornada abierta hoy'}
        </p>
        {jornada && !jornada.inicio_con_ubicacion && (
          <p className="mt-0.5 text-xs text-gray-500">Se abrió sin ubicación registrada.</p>
        )}
        {jornada?.notas_cierre && (
          <p className="mt-1 text-xs text-gray-600">Notas de cierre: {jornada.notas_cierre}</p>
        )}
      </section>

      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Visitas de hoy</h2>
          <span className="text-xs text-gray-500">{visitas.length}</span>
        </div>
        {visitas.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">Ninguna registrada hoy.</p>
        ) : (
          <ul className="mt-2 divide-y">
            {visitas.map(v => (
              <li key={v.id} className="py-2">
                <Link to={`/comercial/visitas/${v.id}`} className="block hover:text-[#1E5C8E]">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-gray-900">{v.prospecto?.nombre ?? 'prospecto'}</p>
                      <p className="mt-0.5 text-xs text-gray-500">
                        {v.checkin_at
                          ? <>check-in {new Date(v.checkin_at).toLocaleTimeString()}
                              {v.checkin_distancia_m != null && <> · a {Math.round(v.checkin_distancia_m)} m</>}
                              {v.checkin_precision_m != null && <> · ±{Math.round(v.checkin_precision_m)} m</>}
                              {!v.checkin_con_ubicacion && ' · sin ubicación'}</>
                          : 'sin check-in'}
                      </p>
                    </div>
                    <div className="shrink-0 space-y-1 text-right">
                      {v.checkin_at && (
                        v.checkin_verificado
                          ? <span className="flex items-center justify-end gap-1 text-xs text-green-700"><CheckCircle2 className="h-3.5 w-3.5" />verificada</span>
                          : <span className="flex items-center justify-end gap-1 text-xs text-amber-700"><AlertTriangle className="h-3.5 w-3.5" />sin verificar</span>
                      )}
                      {/* DIFERIDO. Hoy no puede haber ninguno —la cola no existe— pero la UI queda
                          lista: el día que la cola exista, nadie va a volver acá a agregarlo, y un
                          check-in diferido no puede verse igual que uno en línea. */}
                      {v.checkin_origen === 'diferido' && (
                        <span className="flex items-center justify-end gap-1 rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-700"
                          title="Registrado sin conexión y sincronizado después: la hora del servidor es la de sincronización, no la del hecho.">
                          <CloudOff className="h-3 w-3" />diferido
                        </span>
                      )}
                    </div>
                  </div>
                  {!v.checkin_verificado && v.checkin_motivo && (
                    <p className="mt-1 text-xs text-gray-500">Por qué no verificó: {v.checkin_motivo}</p>
                  )}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Próximas</h2>
          <span className="text-xs text-gray-500">{proximas.length}</span>
        </div>
        {/* Sin acciones: el supervisor reprograma o cancela desde la ficha del prospecto. */}
        {proximas.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">Sin visitas agendadas a futuro.</p>
        ) : (
          <ul className="mt-2 divide-y">
            {proximas.slice(0, 3).map(p => (
              <li key={p.id} className="flex items-center gap-2 py-2 text-sm">
                <span className="shrink-0 font-medium text-gray-900">{fmtFecha(p.fecha_planificada)}</span>
                <span className="shrink-0 text-gray-500">{fmtHora(p.hora_planificada)}</span>
                <span className="flex-1 truncate">{p.prospecto?.nombre ?? 'prospecto'}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
