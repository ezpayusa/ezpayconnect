import { useEffect, useState, useCallback } from 'react'
import { useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { UserPlus, Pencil, CheckCircle2, XCircle, IdCard, EyeOff, AlertTriangle } from 'lucide-react'
import {
  perfilesSinFicha, supervisoresDelPais, listarFichasDePais, guardarAsesorPerfil, asignarSupervisor,
  asesoresConNombre, mapaAsesores, nombreAsesor, apagarTarjetaDeAsesor,
  type FichaAsesor, type PerfilSinFicha, type SupervisorCandidato, type AsesorConNombre,
} from '@/comercial/lib/api'
import { reportarError, type ErrorInline } from '@/comercial/lib/reportarError'

// Fichas de asesor del país (D12). Cuelga del AdminLayout con el AdminRoute que ya confina al
// admin_pais a su propio /pais/{su pais_id}.
//
// EL ALTA SON DOS PASOS Y ESTA PANTALLA ES EL SEGUNDO. `crear-empleado` (Asignación de Roles, sólo
// super_admin) crea la CUENTA: auth.users + perfiles + usuario_roles, y NO toca asesores_perfil.
// `guardar_asesor_perfil` llena la FICHA y rechaza con PA009 si el perfil todavía no tiene rol
// comercial. Por eso la sección A lista perfiles que ya existen: acá no se crean cuentas.
//
// El `p_pais_id` es SIEMPRE el de la ruta y no tiene control de UI: mover una ficha de país exige
// autoridad sobre los dos (PA014) y es otra operación, no un campo de este formulario.
//
// Las dos RPCs de lectura niegan devolviendo VACÍO, no 42501. Una lista vacía puede ser "no hay
// nadie" o "no sos admin de este país", y desde acá no se distinguen: por eso los textos de vacío
// explican el caso normal en vez de sugerir un error de carga.

type Form = {
  codigo_asesor: string; cargo: string; territorio: string
  telefono: string; celular: string; fecha_ingreso: string; bio: string; activo: boolean
}

const FORM_VACIO: Form = {
  codigo_asesor: '', cargo: '', territorio: '',
  telefono: '', celular: '', fecha_ingreso: '', bio: '', activo: true,
}

// Los campos que este formulario SÍ sabe pintar. Un error inline dirigido a cualquier otro campo
// —PA014 apunta a `pais_id`, PA008/PA009 a `asesor_id`, y acá no hay ninguno de los dos— quedaría
// invisible. Se pinta al pie en vez de perderse.
const CAMPOS_DEL_FORM = ['codigo_asesor', 'cargo', 'territorio', 'telefono', 'celular',
                         'fecha_ingreso', 'bio', 'nombre']

export default function AsesoresPaisPage() {
  const { paisId = '' } = useParams()
  const [pendientes, setPendientes] = useState<PerfilSinFicha[]>([])
  const [fichas, setFichas] = useState<FichaAsesor[]>([])
  const [candidatos, setCandidatos] = useState<SupervisorCandidato[]>([])
  const [nombres, setNombres] = useState<Map<string, AsesorConNombre>>(new Map())
  const [cargando, setCargando] = useState(true)

  // Formulario compartido alta/edición. `editando` guarda el id del perfil al que le pertenece.
  const [editando, setEditando] = useState<string | null>(null)
  const [nuevo, setNuevo] = useState(false)
  const [form, setForm] = useState<Form>(FORM_VACIO)
  const [err, setErr] = useState<ErrorInline>(null)
  const [guardando, setGuardando] = useState(false)
  // El error del selector de supervisor vive POR FILA: el `err` global es del formulario.
  const [errSup, setErrSup] = useState<{ id: string; mensaje: string } | null>(null)
  const [asignando, setAsignando] = useState<string | null>(null)
  // Confirmación de apagado, una por vez: guarda el id de la ficha cuya tarjeta se está por bajar.
  const [confirmandoApagar, setConfirmandoApagar] = useState<string | null>(null)
  const [apagando, setApagando] = useState<string | null>(null)

  const cargar = useCallback(async () => {
    setCargando(true)
    const [sf, fi, sv, nom] = await Promise.all([
      perfilesSinFicha(paisId), listarFichasDePais(paisId), supervisoresDelPais(paisId), asesoresConNombre(),
    ])
    if (sf.error) reportarError(sf.error); else setPendientes((sf.data ?? []) as PerfilSinFicha[])
    if (fi.error) reportarError(fi.error); else setFichas((fi.data ?? []) as unknown as FichaAsesor[])
    if (sv.error) reportarError(sv.error); else setCandidatos((sv.data ?? []) as SupervisorCandidato[])
    if (nom.error) reportarError(nom.error); else setNombres(mapaAsesores(nom.data as AsesorConNombre[] | null))
    setCargando(false)
  }, [paisId])

  useEffect(() => { void cargar() }, [cargar])

  const cerrar = () => { setEditando(null); setNuevo(false); setForm(FORM_VACIO); setErr(null) }

  const abrirAlta = (p: PerfilSinFicha) => {
    setErr(null); setNuevo(true); setEditando(p.id); setForm(FORM_VACIO)
  }

  const abrirEdicion = (f: FichaAsesor) => {
    setErr(null); setNuevo(false); setEditando(f.id)
    setForm({
      codigo_asesor: f.codigo_asesor ?? '',
      cargo: f.cargo ?? '', territorio: f.territorio ?? '',
      telefono: f.telefono ?? '', celular: f.celular ?? '',
      fecha_ingreso: f.fecha_ingreso ?? '', bio: f.bio ?? '', activo: f.activo,
    })
  }

  const onGuardar = async () => {
    if (!editando) return
    setErr(null)
    if (!form.codigo_asesor.trim()) {
      setErr({ campo: 'codigo_asesor', mensaje: 'El código del asesor es obligatorio.' }); return
    }
    setGuardando(true)
    const { error } = await guardarAsesorPerfil({
      asesorId: editando,
      codigoAsesor: form.codigo_asesor.trim(),
      paisId,
      cargo: form.cargo.trim() || null,
      territorio: form.territorio.trim() || null,
      telefono: form.telefono.trim() || null,
      celular: form.celular.trim() || null,
      fechaIngreso: form.fecha_ingreso || null,
      bio: form.bio.trim() || null,
      activo: form.activo,
    })
    setGuardando(false)
    if (error) {
      const m = reportarError(error, { setInline: setErr })
      // El 23505 del mapa es genérico A PROPÓSITO: el mismo código sale de tres UNIQUE distintos y
      // desde el mapa no se sabe cuál fue. Acá sí se sabe: el único de esta pantalla es
      // (pais_id, codigo_asesor).
      if (m.code === '23505') {
        setErr({ campo: 'codigo_asesor', mensaje: 'Ya hay otra ficha con ese código en este país. Elegí otro.' })
      }
      return
    }
    toast.success(nuevo ? 'Ficha creada' : 'Ficha actualizada')
    cerrar()
    void cargar()
  }

  const onSupervisor = async (f: FichaAsesor, valor: string) => {
    setErrSup(null); setAsignando(f.id)
    const { error } = await asignarSupervisor(f.id, valor || null)
    setAsignando(null)
    if (error) {
      const m = reportarError(error, {
        setInline: (v) => setErrSup(v ? { id: f.id, mensaje: v.mensaje } : null),
      })
      // PA004 (máximo dos niveles) llega con destino toast y puede aparecer con un candidato que SÍ
      // está en el selector: `comercial_supervisores_del_pais` cubre rol, ficha activa y país, pero
      // la regla de dos niveles depende de a quién supervisa ya ese candidato y no se puede
      // anticipar. Que el rechazo se vea PEGADO A LA FILA y no en un toast que se va.
      if (m.destino !== 'inline') setErrSup({ id: f.id, mensaje: m.mensaje })
      return
    }
    toast.success(valor ? 'Supervisor asignado' : 'Supervisor desasignado')
    void cargar()
  }

  // SOLO APAGA. Encender es del asesor —es su cara y su teléfono— y `tarjeta_apagar_de_asesor` ni
  // siquiera acepta el caso: no hay un parámetro que lo permita. Esta pantalla no puede publicar la
  // tarjeta de nadie aunque quisiera.
  const onApagarTarjeta = async (f: FichaAsesor) => {
    setApagando(f.id)
    const { error } = await apagarTarjetaDeAsesor(f.id)
    setApagando(null)
    setConfirmandoApagar(null)
    if (error) { reportarError(error); return }
    toast.success('Tarjeta despublicada. El enlace de ese asesor dejó de responder.')
    void cargar()
  }

  const errDe = (campo: string) =>
    err?.campo === campo ? <p className="mt-1 text-xs text-red-600">{err.mensaje}</p> : null

  const nombreDe = (id: string) => nombreAsesor(id, nombres)

  if (cargando) return <p className="p-4 text-sm text-gray-500">Cargando fichas…</p>

  const formulario = (
    <div className="mt-3 rounded border bg-gray-50 p-3">
      <p className="text-xs text-gray-600">
        {nuevo ? 'Nueva ficha para ' : 'Editando la ficha de '}
        <span className="font-medium text-gray-900">{editando ? nombreDe(editando) : ''}</span>
      </p>
      <div className="mt-2 grid gap-2 sm:grid-cols-3">
        <div>
          <label className="text-xs text-gray-600">Código de asesor</label>
          <input id="codigo_asesor" value={form.codigo_asesor}
            onChange={(e) => setForm({ ...form, codigo_asesor: e.target.value })}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" placeholder="GT-ASE-03" />
          {errDe('codigo_asesor')}
        </div>
        <div>
          <label className="text-xs text-gray-600">Cargo</label>
          <input id="cargo" value={form.cargo} onChange={(e) => setForm({ ...form, cargo: e.target.value })}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          {errDe('cargo')}
        </div>
        <div>
          <label className="text-xs text-gray-600">Territorio</label>
          <input id="territorio" value={form.territorio}
            onChange={(e) => setForm({ ...form, territorio: e.target.value })}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          {errDe('territorio')}
        </div>
        <div>
          <label className="text-xs text-gray-600">Teléfono</label>
          <input id="telefono" value={form.telefono}
            onChange={(e) => setForm({ ...form, telefono: e.target.value })}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
        </div>
        <div>
          <label className="text-xs text-gray-600">Celular</label>
          <input id="celular" value={form.celular}
            onChange={(e) => setForm({ ...form, celular: e.target.value })}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
        </div>
        <div>
          <label className="text-xs text-gray-600">Fecha de ingreso</label>
          <input type="date" id="fecha_ingreso" value={form.fecha_ingreso}
            onChange={(e) => setForm({ ...form, fecha_ingreso: e.target.value })}
            className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
        </div>
      </div>
      <div className="mt-2">
        <label className="text-xs text-gray-600">Bio (opcional)</label>
        <textarea id="bio" value={form.bio} onChange={(e) => setForm({ ...form, bio: e.target.value })}
          rows={2} className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
      </div>
      <label className="mt-2 flex items-center gap-2 text-sm text-gray-700">
        <input type="checkbox" id="activo" checked={form.activo}
          onChange={(e) => setForm({ ...form, activo: e.target.checked })} />
        Ficha activa
      </label>
      {/* Un inline dirigido a un campo que este formulario no pinta (PA014 -> pais_id,
          PA008/PA009 -> asesor_id) quedaría invisible. Se muestra acá en vez de perderse. */}
      {err && !CAMPOS_DEL_FORM.includes(err.campo) && (
        <p className="mt-2 text-xs text-red-600">{err.mensaje}</p>
      )}
      <div className="mt-3 flex gap-2">
        <button type="button" id="guardar-ficha" onClick={() => void onGuardar()}
          disabled={guardando || !form.codigo_asesor.trim()}
          className="rounded-md bg-[#1E5C8E] px-3 py-1.5 text-sm text-white hover:bg-[#17496f] disabled:opacity-50">
          {guardando ? 'Guardando…' : nuevo ? 'Guardar ficha nueva' : 'Guardar cambios'}
        </button>
        <button type="button" onClick={cerrar} disabled={guardando}
          className="rounded-md border border-gray-300 px-3 py-1.5 text-sm text-gray-700 disabled:opacity-50">
          Cerrar
        </button>
      </div>
    </div>
  )

  return (
    <div className="space-y-5 p-4">
      <h1 className="text-xl font-semibold text-gray-900">Fichas de asesor del país</h1>

      {/* ---- A: perfiles sin ficha ---- */}
      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Perfiles sin ficha</h2>
          <span className="text-xs text-gray-500">{pendientes.length}</span>
        </div>
        {pendientes.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">
            No hay perfiles comerciales pendientes de ficha en este país. Las cuentas las crea un
            super_admin desde Asignación de Roles; acá se les completa la ficha después.
          </p>
        ) : (
          <ul className="mt-2 divide-y">
            {pendientes.map(p => (
              <li key={p.id} className="flex items-center justify-between gap-3 py-2">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-gray-900">{p.nombre_completo ?? '(sin nombre)'}</p>
                  <p className="text-xs text-gray-500">{p.rol.replace(/_/g, ' ')}</p>
                </div>
                <button type="button" data-testid={`crear-ficha-${p.id}`} onClick={() => abrirAlta(p)}
                  className="inline-flex shrink-0 items-center gap-1 rounded-md border border-[#1E5C8E] px-3 py-1.5 text-sm text-[#1E5C8E] hover:bg-blue-50">
                  <UserPlus className="h-4 w-4" />Crear ficha
                </button>
              </li>
            ))}
          </ul>
        )}
        {nuevo && editando && formulario}
      </section>

      {/* ---- B: fichas existentes ---- */}
      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Fichas del país</h2>
          <span className="text-xs text-gray-500">{fichas.length}</span>
        </div>
        {fichas.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">Todavía no hay fichas de asesor en este país.</p>
        ) : (
          <ul className="mt-2 divide-y">
            {fichas.map(f => (
              <li key={f.id} className="py-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-gray-900">{nombreDe(f.id)}</p>
                    <p className="mt-0.5 text-xs text-gray-500">
                      {f.codigo_asesor}
                      {f.cargo && <> · {f.cargo}</>}
                      {f.territorio && <> · {f.territorio}</>}
                    </p>
                    <p className="mt-0.5 text-xs text-gray-600">
                      {/* "sin supervisor" es un estado VÁLIDO, no un dato faltante. */}
                      Supervisor: {f.supervisor_id ? nombreDe(f.supervisor_id) : 'sin supervisor'}
                    </p>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs ${
                      f.activo ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-600'}`}>
                      {f.activo ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                      {f.activo ? 'activa' : 'inactiva'}
                    </span>
                    {/* Estado de la TARJETA PÚBLICA, distinto del `activo` de la ficha: una ficha
                        activa puede tener la tarjeta apagada, que es el default. */}
                    <span data-testid={`tarjeta-estado-${f.id}`}
                      className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs ${
                        f.tarjeta_publica ? 'bg-blue-100 text-blue-800' : 'bg-gray-100 text-gray-600'}`}>
                      <IdCard className="h-3 w-3" />
                      {f.tarjeta_publica ? 'tarjeta publicada' : 'tarjeta no publicada'}
                    </span>
                    {f.tarjeta_publica && (
                      <button type="button" data-testid={`apagar-tarjeta-${f.id}`}
                        onClick={() => setConfirmandoApagar(f.id)} disabled={apagando === f.id}
                        className="inline-flex items-center gap-1 rounded border border-amber-300 px-2 py-1 text-xs text-amber-800 hover:bg-amber-50 disabled:opacity-50">
                        <EyeOff className="h-3.5 w-3.5" />Despublicar
                      </button>
                    )}
                    <button type="button" data-testid={`editar-${f.id}`} onClick={() => abrirEdicion(f)}
                      className="inline-flex items-center gap-1 rounded border border-gray-300 px-2 py-1 text-xs text-gray-700 hover:bg-gray-50">
                      <Pencil className="h-3.5 w-3.5" />Editar
                    </button>
                  </div>
                </div>

                {/* Confirmación explícita. Dice las DOS cosas: que el enlace muere ya, y que esto
                    NO es permanente — el asesor puede volver a publicarla desde su propia pantalla.
                    Apagar no es censura y la UI no tiene que sugerir que lo es. */}
                {confirmandoApagar === f.id && (
                  <div data-testid={`confirmar-apagar-${f.id}`}
                    className="mt-2 rounded-md border border-amber-300 bg-amber-50 p-3">
                    <p className="flex items-start gap-2 text-sm text-amber-900">
                      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                      <span>
                        El enlace público de <strong>{nombreDe(f.id)}</strong> deja de responder de
                        inmediato: quien lo tenga va a ver "tarjeta no disponible", foto incluida.
                        No es permanente — el asesor puede volver a publicarla cuando quiera desde
                        su propia pantalla, con el mismo enlace.
                      </span>
                    </p>
                    <div className="mt-3 flex gap-2">
                      <button type="button" data-testid={`confirmar-apagar-si-${f.id}`}
                        onClick={() => void onApagarTarjeta(f)} disabled={apagando === f.id}
                        className="rounded-md bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-50">
                        Sí, despublicar
                      </button>
                      <button type="button" onClick={() => setConfirmandoApagar(null)}
                        disabled={apagando === f.id}
                        className="rounded-md border px-3 py-1.5 text-sm text-gray-700 disabled:opacity-50">
                        Cancelar
                      </button>
                    </div>
                  </div>
                )}

                <div className="mt-2">
                  <label className="text-xs text-gray-600">Supervisor</label>
                  <select data-testid={`supervisor-${f.id}`} value={f.supervisor_id ?? ''}
                    disabled={asignando === f.id}
                    onChange={(e) => void onSupervisor(f, e.target.value)}
                    className="mt-1 w-full rounded border px-2 py-1.5 text-sm disabled:opacity-50 sm:w-72">
                    <option value="">— sin supervisor —</option>
                    {candidatos.filter(c => c.id !== f.id).map(c => (
                      <option key={c.id} value={c.id}>{c.nombre_completo ?? c.id}</option>
                    ))}
                  </select>
                  {errSup?.id === f.id && <p className="mt-1 text-xs text-red-600">{errSup.mensaje}</p>}
                </div>

                {!nuevo && editando === f.id && formulario}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
