import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowLeft, CheckCircle2, AlertTriangle, MapPinOff } from 'lucide-react'
import { useAuth } from '@/hooks/useAuth'
import {
  obtenerProspecto, listarContactos, listarEstados, listarTipos,
  cambiarEstado, guardarContacto, actualizarProspecto, visitasDelProspecto,
  type Prospecto, type Contacto, type ItemCatalogo, type VisitaComercial,
} from '../lib/api'
import { AgendarVisita, AccionesVisitaPlanificada } from '../components/AgendaVisita'
import { fmtFecha, fmtHora } from '../lib/agenda'
import { reportarError, type ErrorInline } from '../lib/reportarError'

// Ficha: datos + estado + contactos. Misma ruta para asesor y supervisor.
//
// D1: el supervisor cambia estado y carga contactos, pero NO edita los datos del prospecto. Acá el
// bloque de datos le sale en solo lectura — POR COMODIDAD. La protección real es que
// actualizar_prospecto le contesta 42501 (probe P531). Si alguien parchea el `readOnly` desde la
// consola del navegador, el servidor lo sigue rechazando.
export default function ProspectoFichaPage() {
  const { id = '' } = useParams()
  const { perfil } = useAuth()
  const esSupervisor = perfil?.rol === 'supervisor_comercial'

  const [p, setP] = useState<Prospecto | null>(null)
  const [contactos, setContactos] = useState<Contacto[]>([])
  const [estados, setEstados] = useState<ItemCatalogo[]>([])
  const [tipos, setTipos] = useState<ItemCatalogo[]>([])
  const [cargando, setCargando] = useState(true)

  // estado
  const [estadoSel, setEstadoSel] = useState('')
  const [motivo, setMotivo] = useState('')
  const [errEstado, setErrEstado] = useState<ErrorInline>(null)
  const [guardandoEstado, setGuardandoEstado] = useState(false)

  // datos
  const [nombre, setNombre] = useState('')
  const [tipo, setTipo] = useState('')
  const [direccion, setDireccion] = useState('')
  const [notas, setNotas] = useState('')
  const [errDatos, setErrDatos] = useState<ErrorInline>(null)

  // contacto nuevo
  const [cNombre, setCNombre] = useState('')
  const [cPuesto, setCPuesto] = useState('')
  const [cEmail, setCEmail] = useState('')
  const [errContacto, setErrContacto] = useState<ErrorInline>(null)
  const [visitas, setVisitas] = useState<VisitaComercial[]>([])

  const cargar = async () => {
    setCargando(true)
    const [pr, co, es, ti, vs] = await Promise.all([
      obtenerProspecto(id), listarContactos(id), listarEstados(), listarTipos(), visitasDelProspecto(id),
    ])
    if (pr.error) reportarError(pr.error)
    const fila = (pr.data ?? null) as unknown as Prospecto | null
    setP(fila)
    if (fila) {
      setEstadoSel(fila.estado_pipeline)
      setMotivo(fila.motivo_perdida ?? '')
      setNombre(fila.nombre); setTipo(fila.tipo)
      setDireccion(fila.direccion ?? ''); setNotas(fila.notas ?? '')
    }
    if (co.data) setContactos(co.data as Contacto[])
    if (es.data) setEstados(es.data as ItemCatalogo[])
    if (ti.data) setTipos(ti.data as ItemCatalogo[])
    if (vs.data) setVisitas(vs.data as unknown as VisitaComercial[])
    setCargando(false)
  }

  useEffect(() => { void cargar() }, [id])

  const esTerminal = (codigo: string) => estados.find(e => e.codigo === codigo)?.es_terminal ?? false

  const onGuardarEstado = async () => {
    if (!p) return
    setErrEstado(null); setGuardandoEstado(true)
    const anterior = p.estado_pipeline
    const { error } = await cambiarEstado(id, estadoSel, motivo || null)
    setGuardandoEstado(false)
    if (error) {
      reportarError(error, {
        setInline: setErrEstado,
        // PA012: el estado NO cambió, el selector tiene que volver a donde estaba.
        onRevertir: () => setEstadoSel(anterior),
        onRecargar: () => void cargar(),
      })
      return
    }
    toast.success('Estado actualizado')
    void cargar()
  }

  const onGuardarDatos = async () => {
    if (!p) return
    setErrDatos(null)
    const { error } = await actualizarProspecto({
      id, nombre, tipo, direccion: direccion || null, lat: p.lat, lng: p.lng,
      notas: notas || null, empresaProveedoraId: p.empresa_proveedora_id,
    })
    if (error) { reportarError(error, { setInline: setErrDatos, onRecargar: () => void cargar() }); return }
    toast.success('Datos guardados')
    void cargar()
  }

  const onAgregarContacto = async () => {
    setErrContacto(null)
    const { error } = await guardarContacto({
      prospectoId: id, nombre: cNombre, puesto: cPuesto || null, email: cEmail || null,
    })
    if (error) {
      reportarError(error, { setInline: setErrContacto, onRecargar: () => void cargar() })
      return
    }
    toast.success('Contacto agregado')
    setCNombre(''); setCPuesto(''); setCEmail('')
    void cargar()
  }

  if (cargando) return <p className="text-sm text-gray-500">Cargando…</p>

  // La policy no devolvió la fila. Es el MISMO mensaje que daría un id inexistente, a propósito:
  // el backend tampoco distingue (P521), y el front no debe filtrar existencia por su cuenta.
  if (!p) {
    return (
      <div className="rounded-lg border bg-white p-6">
        <p className="text-sm text-gray-700">No encontramos ese prospecto en tu cartera.</p>
        <Link to="/comercial/prospectos" className="mt-3 inline-block text-sm text-[#1E5C8E]">← Volver</Link>
      </div>
    )
  }

  const err = (e: ErrorInline, campo: string) =>
    e && e.campo === campo ? <p className="mt-1 text-xs text-red-600">{e.mensaje}</p> : null

  return (
    <div className="space-y-4">
      <Link to="/comercial/prospectos" className="inline-flex items-center gap-1 text-sm text-[#1E5C8E]">
        <ArrowLeft className="h-4 w-4" /> Volver
      </Link>

      {/* ---- datos ---- */}
      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Datos</h2>
          {esSupervisor && (
            <span className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-600">Solo lectura</span>
          )}
        </div>
        <div className="mt-3 space-y-3">
          <div>
            <label className="text-xs text-gray-600">Nombre</label>
            <input
              value={nombre} onChange={(e) => setNombre(e.target.value)} readOnly={esSupervisor}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm read-only:bg-gray-50 read-only:text-gray-600"
            />
            {err(errDatos, 'nombre')}
          </div>
          <div>
            <label className="text-xs text-gray-600">Tipo</label>
            <select
              value={tipo} onChange={(e) => setTipo(e.target.value)} disabled={esSupervisor}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm disabled:bg-gray-50 disabled:text-gray-600"
            >
              {tipos.map(t => <option key={t.codigo} value={t.codigo}>{t.etiqueta}</option>)}
            </select>
            {err(errDatos, 'catalogo')}
          </div>
          <div>
            <label className="text-xs text-gray-600">Dirección</label>
            <input
              value={direccion} onChange={(e) => setDireccion(e.target.value)} readOnly={esSupervisor}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm read-only:bg-gray-50 read-only:text-gray-600"
            />
          </div>
          <div>
            <label className="text-xs text-gray-600">Notas</label>
            <textarea
              value={notas} onChange={(e) => setNotas(e.target.value)} readOnly={esSupervisor} rows={2}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm read-only:bg-gray-50 read-only:text-gray-600"
            />
          </div>
          {!esSupervisor && (
            <button
              type="button" onClick={onGuardarDatos}
              className="rounded-md bg-[#1E5C8E] px-3 py-1.5 text-sm text-white hover:bg-[#17496f]"
            >
              Guardar datos
            </button>
          )}
        </div>
      </section>

      {/* ---- visitas ---- */}
      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Visitas</h2>
          <span className="text-xs text-gray-500">{visitas.length}</span>
        </div>
        {/* Visible para asesor y supervisor: quien puede agendar lo decide la RPC (42501). */}
        <div className="mt-2">
          <AgendarVisita prospectoId={id} onAgendada={() => void cargar()} />
        </div>
        {visitas.length === 0 ? (
          <p className="mt-3 text-sm text-gray-500">Sin visitas todavía.</p>
        ) : (
          <ul className="mt-3 divide-y">
            {visitas.map(vi => (
              <li key={vi.id} className="py-2" data-testid={`visita-${vi.id}`}>
                <div className="flex items-start justify-between gap-3">
                  <Link to={`/comercial/visitas/${vi.id}`} className="min-w-0 text-sm hover:text-[#1E5C8E]">
                    <span className="font-medium text-gray-900">{fmtFecha(vi.fecha_planificada)}</span>
                    <span className="text-gray-600"> · {fmtHora(vi.hora_planificada)}</span>
                  </Link>
                  <div className="flex shrink-0 items-center gap-2 text-xs">
                    {vi.checkin_at && (vi.checkin_verificado
                      ? <span className="flex items-center gap-1 text-green-700"><CheckCircle2 className="h-3.5 w-3.5" />verificada</span>
                      : !vi.checkin_con_ubicacion
                        ? <span className="flex items-center gap-1 text-gray-500"><MapPinOff className="h-3.5 w-3.5" />sin ubicación</span>
                        : <span className="flex items-center gap-1 text-amber-700"><AlertTriangle className="h-3.5 w-3.5" />sin verificar</span>)}
                    <span className="rounded-full bg-gray-100 px-2 py-0.5 text-gray-700">{vi.estado}</span>
                  </div>
                </div>
                {vi.estado === 'cancelada' && vi.cancelacion_motivo && (
                  <p className="mt-1 text-xs text-gray-500">Cancelada: {vi.cancelacion_motivo}</p>
                )}
                <AccionesVisitaPlanificada visita={vi} onCambio={() => void cargar()} />
              </li>
            ))}
          </ul>
        )}
        <Link to="/comercial/hoy" className="mt-3 inline-block text-sm text-[#1E5C8E]">Ir a mi jornada →</Link>
      </section>

      {/* ---- estado ---- */}
      <section className="rounded-lg border bg-white p-4">
        <h2 className="font-semibold text-gray-900">Estado</h2>
        <div className="mt-3 space-y-3">
          <div>
            <select
              id="estado" value={estadoSel} onChange={(e) => setEstadoSel(e.target.value)}
              className="w-full rounded border px-2 py-1.5 text-sm"
            >
              {estados.map(e => <option key={e.codigo} value={e.codigo}>{e.etiqueta}</option>)}
            </select>
            {err(errEstado, 'catalogo')}
          </div>
          {estadoSel === 'perdido' && (
            <div>
              <label className="text-xs text-gray-600">Motivo de la pérdida</label>
              <input
                id="motivo_perdida" value={motivo} onChange={(e) => setMotivo(e.target.value)}
                className="mt-1 w-full rounded border px-2 py-1.5 text-sm"
                placeholder="Por qué se perdió"
              />
              {/* PA011 aterriza acá, pegado al campo: es un campo que falta, no un error de sistema. */}
              {err(errEstado, 'motivo_perdida')}
            </div>
          )}
          <button
            type="button" onClick={onGuardarEstado} disabled={guardandoEstado}
            className="rounded-md bg-[#1E5C8E] px-3 py-1.5 text-sm text-white hover:bg-[#17496f] disabled:opacity-50"
          >
            Guardar estado
          </button>
          {esTerminal(p.estado_pipeline) && (
            <p className="text-xs text-gray-500">
              Este prospecto está cerrado ({p.estado_pipeline}). Reabrirlo es del administrador del país.
            </p>
          )}
        </div>
      </section>

      {/* ---- contactos ---- */}
      <section className="rounded-lg border bg-white p-4">
        <h2 className="font-semibold text-gray-900">Contactos</h2>
        {contactos.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">Sin contactos todavía.</p>
        ) : (
          <ul className="mt-2 divide-y">
            {contactos.map(c => (
              <li key={c.id} className="py-2 text-sm">
                <span className="font-medium text-gray-900">{c.nombre}</span>
                {c.puesto && <span className="text-gray-500"> · {c.puesto}</span>}
                {c.email && <span className="block text-xs text-gray-500">{c.email}</span>}
              </li>
            ))}
          </ul>
        )}
        <div className="mt-3 grid gap-2 sm:grid-cols-3">
          <input id="c_nombre" value={cNombre} onChange={(e) => setCNombre(e.target.value)}
            placeholder="Nombre" className="rounded border px-2 py-1.5 text-sm" />
          <input value={cPuesto} onChange={(e) => setCPuesto(e.target.value)}
            placeholder="Puesto" className="rounded border px-2 py-1.5 text-sm" />
          <input value={cEmail} onChange={(e) => setCEmail(e.target.value)}
            placeholder="Email" className="rounded border px-2 py-1.5 text-sm" />
        </div>
        {err(errContacto, 'nombre')}
        <button
          type="button" onClick={onAgregarContacto}
          className="mt-2 rounded-md border border-[#1E5C8E] px-3 py-1.5 text-sm text-[#1E5C8E] hover:bg-blue-50"
        >
          Agregar contacto
        </button>
      </section>
    </div>
  )
}
