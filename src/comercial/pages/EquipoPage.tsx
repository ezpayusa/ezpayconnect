import { useEffect, useState } from 'react'
import { Link, Navigate } from 'react-router-dom'
import { CheckCircle2, AlertTriangle, Clock } from 'lucide-react'
import { useAuth } from '@/hooks/useAuth'
import { jornadasDelDia, visitasDelDia, visitasProximas, asesoresVisibles, type Jornada, type VisitaComercial } from '../lib/api'
import { fmtFecha, fmtHora } from '../lib/agenda'
import { reportarError } from '../lib/reportarError'

const HOY = () => new Date().toISOString().slice(0, 10)

type Asesor = { id: string; codigo_asesor: string; supervisor_id: string | null
                perfil?: { nombre_completo: string | null; rol: string | null } | null }

// Qué está pasando HOY con el equipo. No es analítica: no hay rangos de fechas ni agregados.
//
// SÓLO LECTURA. En toda esta superficie no hay un solo control que llame a una RPC de escritura de
// visita — ni check-in, ni informe, ni adjuntos. El único write que el supervisor tiene en el
// módulo sigue siendo cambiar el estado de un prospecto y cargar contactos (D1), y eso vive en
// otra pantalla. La barrera real no es esta ausencia de botones: es que guardar_reporte_visita y
// checkin_visita_comercial están atadas a `asesor_id = auth.uid()` y le contestan 42501 (P554, P541).
export default function EquipoPage() {
  const { perfil } = useAuth()
  const [asesores, setAsesores] = useState<Asesor[]>([])
  const [jornadas, setJornadas] = useState<Jornada[]>([])
  const [visitas, setVisitas] = useState<VisitaComercial[]>([])
  const [proximas, setProximas] = useState<VisitaComercial[]>([])
  const [cargando, setCargando] = useState(true)

  useEffect(() => {
    void (async () => {
      setCargando(true)
      const [a, j, v, px] = await Promise.all([asesoresVisibles(), jornadasDelDia(HOY()), visitasDelDia(HOY()), visitasProximas(HOY())])
      if (a.error) reportarError(a.error); else setAsesores((a.data ?? []) as unknown as Asesor[])
      if (j.error) reportarError(j.error); else setJornadas((j.data ?? []) as unknown as Jornada[])
      if (v.error) reportarError(v.error); else setVisitas((v.data ?? []) as unknown as VisitaComercial[])
      if (px.error) reportarError(px.error); else setProximas((px.data ?? []) as unknown as VisitaComercial[])
      setCargando(false)
    })()
  }, [])

  // La ruta es del supervisor. Un asesor que fuerce la URL vuelve a su jornada — y aunque entrara,
  // las policies le devolverían sólo lo suyo.
  if (perfil && perfil.rol !== 'supervisor_comercial') return <Navigate to="/comercial/hoy" replace />
  if (cargando) return <p className="text-sm text-gray-500">Cargando…</p>

  const equipo = asesores.filter(a => a.id !== perfil?.id)

  return (
    <div className="space-y-4">
      <div>
        <h1 className="font-semibold text-gray-900">Mi equipo hoy</h1>
        <p className="mt-0.5 text-xs text-gray-500">{HOY()} · {equipo.length} asesor(es)</p>
      </div>

      {equipo.length === 0 ? (
        <p className="rounded-lg border border-dashed bg-white p-6 text-sm text-gray-600">
          No tenés asesores asignados todavía.
        </p>
      ) : (
        <ul className="space-y-2">
          {equipo.map(a => {
            const j = jornadas.find(x => x.asesor_id === a.id)
            const mias = visitas.filter(x => x.asesor_id === a.id)
            const hechas = mias.filter(x => x.checkin_at != null)
            const sinVerificar = hechas.filter(x => !x.checkin_verificado)
            // agrupado en memoria por asesor, igual que las de hoy: la policy ya trajo la cartera entera
            const prox = proximas.filter(x => x.asesor_id === a.id)
            return (
              <li key={a.id}>
                <Link to={`/comercial/equipo/${a.id}`} className="block rounded-lg border bg-white p-3 hover:border-[#1E5C8E]">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate font-medium text-gray-900">
                        {a.perfil?.nombre_completo ?? a.codigo_asesor}
                      </p>
                      {/* LENGUAJE: informa un hecho, no emite un juicio. "Sin jornada abierta" es
                          lo que quedó registrado; por qué, esta pantalla no lo sabe. */}
                      <p className="mt-0.5 text-xs text-gray-600">
                        {j
                          ? j.fin_at
                            ? `Jornada cerrada a las ${new Date(j.fin_at).toLocaleTimeString()}`
                            : `Jornada abierta desde las ${new Date(j.inicio_at).toLocaleTimeString()}`
                          : 'Sin jornada abierta hoy'}
                        {j && !j.inicio_con_ubicacion && ' · sin ubicación registrada'}
                      </p>
                    </div>
                    <div className="shrink-0 text-right text-xs">
                      <p className="text-gray-700">{hechas.length}/{mias.length} visitas</p>
                      <p className="text-gray-500">Próximas: {prox.length}</p>
                      {prox.slice(0, 3).map(p => (
                        <p key={p.id} className="truncate text-gray-500">{fmtFecha(p.fecha_planificada)} {fmtHora(p.hora_planificada)} · {p.prospecto?.nombre ?? ''}</p>
                      ))}
                      {sinVerificar.length > 0 && (
                        <p className="mt-0.5 flex items-center justify-end gap-1 text-amber-700">
                          <AlertTriangle className="h-3 w-3" />{sinVerificar.length} sin verificar
                        </p>
                      )}
                    </div>
                  </div>
                </Link>
              </li>
            )
          })}
        </ul>
      )}

      <p className="rounded-lg bg-gray-50 p-3 text-xs text-gray-600">
        <Clock className="mr-1 inline h-3 w-3" />
        Esta pantalla muestra lo que quedó <b>registrado</b> hoy. Que no haya jornada abierta no dice
        por qué: puede ser una licencia, una capacitación o un teléfono sin batería.
        Y <b>verificada</b> quiere decir que la ubicación reportada es consistente con la del
        prospecto — no que la visita haya salido bien.
      </p>
      <p className="text-xs text-gray-400">
        <CheckCircle2 className="mr-1 inline h-3 w-3" />Solo lectura.
      </p>
    </div>
  )
}
