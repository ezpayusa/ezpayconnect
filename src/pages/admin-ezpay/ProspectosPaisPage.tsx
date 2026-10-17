import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  listarProspectosDePais, listarAsesores, listarTipos, listarEstados,
  crearProspecto, reasignarProspecto, asesoresConNombre, mapaAsesores, nombreAsesor,
  obtenerProspecto, actualizarProspecto, geocodificarDireccion, coordenadasValidas,
  type Prospecto, type ItemCatalogo, type AsesorConNombre,
} from '@/comercial/lib/api'
import { reportarError, type ErrorInline } from '@/comercial/lib/reportarError'
import MapaInteractivo from '@/components/MapaInteractivo'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'

// Ubicación del prospecto: es contra esta coordenada que checkin_visita_comercial mide la
// distancia del asesor. Sin ella el check-in nunca sale verificado.
//
// Un pin solo cuenta como FIJADO si vino de la geocodificación o de un click/arrastre en el mapa.
// MapaInteractivo arranca centrado en Ciudad de Guatemala cuando no recibe coordenada, y ese
// centro NO es un dato: guardarlo pondría a todos los prospectos sin ubicación en el mismo punto.
type Ubicacion = {
  direccion: string
  lat: number | null
  lng: number | null
  pinFijado: boolean
}

const UBICACION_VACIA: Ubicacion = { direccion: '', lat: null, lng: null, pinFijado: false }

const pinValido = (u: Ubicacion) => u.pinFijado && coordenadasValidas(u.lat, u.lng)

function EditorUbicacion({ valor, onChange, mapaInicial = false }: {
  valor: Ubicacion
  onChange: (u: Ubicacion) => void
  /** Mostrar el mapa desde el inicio (el diálogo de una fila que ya tiene coordenada). */
  mapaInicial?: boolean
}) {
  const [buscando, setBuscando] = useState(false)
  const [mostrarMapa, setMostrarMapa] = useState(mapaInicial)
  // El center de MapContainer solo se aplica al montar: tras cada búsqueda se re-monta el mapa
  // para que quede centrado en el resultado y no en el punto anterior.
  const [mapaKey, setMapaKey] = useState(0)

  const onBuscar = async () => {
    setBuscando(true)
    const r = await geocodificarDireccion(valor.direccion)
    setBuscando(false)
    if (r) {
      onChange({ ...valor, lat: r.lat, lng: r.lng, pinFijado: true })
      toast.success('Ubicación encontrada: ajusta el pin si hace falta')
    } else {
      toast.warning('No se encontró la dirección: marca el punto en el mapa')
    }
    setMapaKey(k => k + 1)
    setMostrarMapa(true)
  }

  return (
    <div className="space-y-2">
      <div>
        <label className="text-xs text-gray-600">Dirección (opcional)</label>
        <div className="mt-1 flex gap-2">
          <input value={valor.direccion} onChange={(e) => onChange({ ...valor, direccion: e.target.value })}
            className="w-full rounded border px-2 py-1.5 text-sm" placeholder="6a Avenida 12-45, Zona 10" />
          <button type="button" onClick={() => void onBuscar()} disabled={buscando || !valor.direccion.trim()}
            className="shrink-0 rounded-md border px-3 py-1.5 text-sm hover:bg-gray-50 disabled:opacity-50">
            {buscando ? 'Buscando…' : 'Buscar en el mapa'}
          </button>
        </div>
      </div>
      {mostrarMapa && (
        <MapaInteractivo
          key={mapaKey}
          lat={valor.pinFijado ? valor.lat : null}
          lng={valor.pinFijado ? valor.lng : null}
          onChange={(lat, lng) => onChange({ ...valor, lat, lng, pinFijado: true })}
          height="260px"
        />
      )}
      {pinValido(valor) ? (
        <p className="text-xs text-green-700">Ubicación marcada.</p>
      ) : (
        <p className="text-xs text-amber-700">
          Sin ubicación: el check-in del asesor no se podrá verificar hasta que la cargues
        </p>
      )}
    </div>
  )
}

// Sin embed a perfiles: la ficha da codigo/pais y la RPC de la mig 283 da el nombre.
type Asesor = {
  id: string
  codigo_asesor: string
  pais_id: string
}

// Prospectos del país: lista + alta + reasignación. Cuelga del AdminLayout existente y usa el
// AdminRoute que ya confina al admin_pais a su propio /pais/{su pais_id}.
//
// El .eq('pais_id', paisId) de listarProspectosDePais es un SELECTOR DE VISTA —esta ruta está
// parametrizada por :paisId y un super_admin ve varios países—, no un permiso: sólo puede achicar
// lo que la policy de la 264 ya permitió. Si un admin de otro país forzara la URL, la policy le
// devuelve 0 filas y toda RPC le contesta 42501.
export default function ProspectosPaisPage() {
  const { paisId = '' } = useParams()
  const [filas, setFilas] = useState<Prospecto[]>([])
  const [asesores, setAsesores] = useState<Asesor[]>([])
  const [tipos, setTipos] = useState<ItemCatalogo[]>([])
  const [estados, setEstados] = useState<ItemCatalogo[]>([])
  const [nombres, setNombres] = useState<Map<string, AsesorConNombre>>(new Map())
  const [cargando, setCargando] = useState(true)

  // alta
  const [nombre, setNombre] = useState('')
  const [tipo, setTipo] = useState('')
  const [asesorId, setAsesorId] = useState('')
  const [creando, setCreando] = useState(false)
  const [errAlta, setErrAlta] = useState<ErrorInline>(null)
  const [ubicAlta, setUbicAlta] = useState<Ubicacion>(UBICACION_VACIA)
  // El editor se re-monta al limpiar el alta, así el mapa también se cierra.
  const [altaKey, setAltaKey] = useState(0)

  // ubicación de una fila
  const [editando, setEditando] = useState<Prospecto | null>(null)
  const [ubicEdit, setUbicEdit] = useState<Ubicacion>(UBICACION_VACIA)
  const [guardandoUbic, setGuardandoUbic] = useState(false)

  const cargar = async () => {
    setCargando(true)
    const [pr, as, ti, es, nom] = await Promise.all([
      listarProspectosDePais(paisId), listarAsesores(), listarTipos(), listarEstados(), asesoresConNombre(),
    ])
    if (nom.error) reportarError(nom.error); else setNombres(mapaAsesores(nom.data as AsesorConNombre[] | null))
    if (pr.error) reportarError(pr.error)
    else setFilas((pr.data ?? []) as unknown as Prospecto[])
    if (as.data) {
      const fichas = as.data as unknown as Asesor[]
      setAsesores(fichas)
      // el país de la URL cambió y el asesor elegido era del anterior: se suelta en vez de viajar
      setAsesorId(prev => (prev && fichas.some(a => a.id === prev && a.pais_id === paisId) ? prev : ''))
    }
    if (ti.data) { setTipos(ti.data as ItemCatalogo[]); if (!tipo) setTipo((ti.data[0] as ItemCatalogo)?.codigo ?? '') }
    if (es.data) setEstados(es.data as ItemCatalogo[])
    setCargando(false)
  }

  useEffect(() => { void cargar() }, [paisId])

  const etiquetaEstado = (c: string) => estados.find(e => e.codigo === c)?.etiqueta ?? c
  // El codigo va SIEMPRE entre parentesis, como dato secundario: nunca ocupa el lugar del nombre.
  const etiquetaAsesor = (a: Asesor) => `${nombreAsesor(a.id, nombres, a.codigo_asesor)} (${a.codigo_asesor})`

  // Los asesores que la policy deja ver pueden ser de VARIOS países: un super_admin los ve todos.
  // Esta ruta está parametrizada por :paisId, así que ofrecer los de otro país es invitar a un
  // error que la RPC después rechaza con PA008/PA009 — un rechazo evitable no es una validación,
  // es una pantalla que dejó elegir mal. Igual que el .eq de listarProspectosDePais, el filtro es
  // SELECTOR DE VISTA y no un permiso: sólo achica lo que la policy ya permitió.
  const asesoresDelPais = asesores.filter(a => a.pais_id === paisId)

  const onCrear = async () => {
    setErrAlta(null); setCreando(true)
    const conPin = pinValido(ubicAlta)
    let res: Awaited<ReturnType<typeof crearProspecto>>
    try {
      res = await crearProspecto({
        nombre, tipo, asesorId, direccion: ubicAlta.direccion,
        lat: conPin ? ubicAlta.lat : null, lng: conPin ? ubicAlta.lng : null,
      })
    } catch (e) {
      setCreando(false)
      if (e instanceof Error && e.message === 'coordenadas_invalidas') {
        toast.error('La ubicación no es válida: vuelve a marcar el punto')
      } else {
        reportarError(e)
      }
      return
    }
    setCreando(false)
    if (res.error) {
      // PA008/PA009 caen inline en el selector de asesor; PA010 en el de tipo; 42501 a toast.
      reportarError(res.error, { setInline: setErrAlta, onRecargar: () => void cargar() })
      return
    }
    toast.success('Prospecto creado')
    setNombre('')
    setUbicAlta(UBICACION_VACIA)
    setAltaKey(k => k + 1)
    void cargar()
  }

  const abrirUbicacion = (p: Prospecto) => {
    const tiene = coordenadasValidas(p.lat, p.lng)
    setUbicEdit({
      direccion: p.direccion ?? '',
      lat: tiene ? p.lat : null, lng: tiene ? p.lng : null, pinFijado: tiene,
    })
    setEditando(p)
  }

  const onGuardarUbicacion = async () => {
    if (!editando || !pinValido(ubicEdit)) return
    setGuardandoUbic(true)
    try {
      // actualizar_prospecto reescribe los 8 campos. La fila de la lista puede estar vieja (el
      // asesor pudo editar nombre o notas desde que se cargó): se relee FRESCA y solo se cambian
      // dirección y coordenada. Sin fila fresca no se escribe nada.
      const fresca = await obtenerProspecto(editando.id)
      if (fresca.error) { reportarError(fresca.error, { onRecargar: () => void cargar() }); return }
      const f = fresca.data as unknown as Prospecto | null
      if (!f) {
        toast.error('No se pudo leer el prospecto: recarga la página e inténtalo de nuevo')
        return
      }
      const { error } = await actualizarProspecto({
        id: f.id, nombre: f.nombre, tipo: f.tipo, notas: f.notas,
        empresaProveedoraId: f.empresa_proveedora_id,
        direccion: ubicEdit.direccion.trim() || null, lat: ubicEdit.lat, lng: ubicEdit.lng,
      })
      if (error) { reportarError(error, { onRecargar: () => void cargar() }); return }
      setEditando(null)
      toast.success('Ubicación guardada')
      void cargar()
    } finally {
      setGuardandoUbic(false)
    }
  }

  const onReasignar = async (prospectoId: string, nuevo: string) => {
    const { error } = await reasignarProspecto(prospectoId, nuevo)
    if (error) { reportarError(error, { onRecargar: () => void cargar() }); return }
    toast.success('Prospecto reasignado')
    void cargar()
  }

  const err = (campo: string) =>
    errAlta && errAlta.campo === campo ? <p className="mt-1 text-xs text-red-600">{errAlta.mensaje}</p> : null

  return (
    <div className="space-y-5 p-4">
      <h1 className="text-xl font-semibold text-gray-900">Prospectos del país</h1>

      <section className="rounded-lg border bg-white p-4">
        <h2 className="font-semibold text-gray-900">Nuevo prospecto</h2>
        <div className="mt-3 grid gap-3 sm:grid-cols-3">
          <div>
            <label className="text-xs text-gray-600">Nombre</label>
            <input id="nombre" value={nombre} onChange={(e) => setNombre(e.target.value)}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm" placeholder="Farmacia San José" />
            {err('nombre')}
          </div>
          <div>
            <label className="text-xs text-gray-600">Tipo</label>
            <select id="tipo" value={tipo} onChange={(e) => setTipo(e.target.value)}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm">
              {tipos.map(t => <option key={t.codigo} value={t.codigo}>{t.etiqueta}</option>)}
            </select>
            {err('catalogo')}
          </div>
          <div>
            <label className="text-xs text-gray-600">Asesor</label>
            <select id="asesor_id" value={asesorId} onChange={(e) => setAsesorId(e.target.value)}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm">
              <option value="">— elegir —</option>
              {asesoresDelPais.map(a => <option key={a.id} value={a.id}>{etiquetaAsesor(a)}</option>)}
            </select>
            {/* Un selector vacío sin explicación se lee como un error de carga. Esto dice qué pasa. */}
            {!cargando && asesoresDelPais.length === 0 && (
              <p className="mt-1 text-xs text-amber-700">No hay asesores activos en este país.</p>
            )}
            {err('asesor_id')}
          </div>
        </div>
        <div className="mt-3">
          <EditorUbicacion key={altaKey} valor={ubicAlta} onChange={setUbicAlta} />
        </div>
        <button type="button" onClick={onCrear} disabled={creando || !nombre || !asesorId}
          className="mt-3 rounded-md bg-[#1E5C8E] px-3 py-1.5 text-sm text-white hover:bg-[#17496f] disabled:opacity-50">
          Crear prospecto
        </button>
      </section>

      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Prospectos</h2>
          <span className="text-xs text-gray-500">{filas.length}</span>
        </div>
        {cargando ? (
          <p className="mt-2 text-sm text-gray-500">Cargando…</p>
        ) : filas.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">Todavía no hay prospectos en este país.</p>
        ) : (
          <table className="mt-3 w-full text-sm">
            <thead>
              <tr className="border-b text-left text-xs uppercase text-gray-500">
                <th className="py-2">Nombre</th><th>Tipo</th><th>Estado</th><th>Asesor</th><th>Ubicación</th>
              </tr>
            </thead>
            <tbody>
              {filas.map(p => (
                <tr key={p.id} className="border-b last:border-0">
                  <td className="py-2 font-medium text-gray-900">{p.nombre}</td>
                  <td className="text-gray-600">{p.tipo.replace(/_/g, ' ')}</td>
                  <td>
                    <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs">{etiquetaEstado(p.estado_pipeline)}</span>
                  </td>
                  <td>
                    {/* Reasignar = la RPC. El select no decide nada: reasignar_prospecto es
                        exclusiva del admin de país y rechaza a cualquier otro con 42501. */}
                    <select
                      value={p.asesor_id}
                      onChange={(e) => void onReasignar(p.id, e.target.value)}
                      className="rounded border px-1.5 py-1 text-xs"
                    >
                      {asesoresDelPais.map(a => <option key={a.id} value={a.id}>{etiquetaAsesor(a)}</option>)}
                    </select>
                  </td>
                  <td>
                    <div className="flex items-center gap-2">
                      {coordenadasValidas(p.lat, p.lng) ? (
                        <span className="rounded-full bg-green-50 px-2 py-0.5 text-xs text-green-700">Con ubicación</span>
                      ) : (
                        <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs text-amber-700">Sin ubicación</span>
                      )}
                      <button type="button" onClick={() => abrirUbicacion(p)}
                        className="rounded border px-2 py-0.5 text-xs hover:bg-gray-50">
                        Ubicación
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <Dialog open={!!editando} onOpenChange={(abierto) => { if (!abierto && !guardandoUbic) setEditando(null) }}>
        <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Ubicación de {editando?.nombre}</DialogTitle>
          </DialogHeader>
          {editando && (
            <EditorUbicacion key={editando.id} valor={ubicEdit} onChange={setUbicEdit}
              mapaInicial={ubicEdit.pinFijado} />
          )}
          <div className="mt-2 flex justify-end gap-2">
            <button type="button" onClick={() => setEditando(null)} disabled={guardandoUbic}
              className="rounded-md border px-3 py-1.5 text-sm hover:bg-gray-50 disabled:opacity-50">
              Cancelar
            </button>
            <button type="button" onClick={() => void onGuardarUbicacion()}
              disabled={guardandoUbic || !pinValido(ubicEdit)}
              className="rounded-md bg-[#1E5C8E] px-3 py-1.5 text-sm text-white hover:bg-[#17496f] disabled:opacity-50">
              {guardandoUbic ? 'Guardando…' : 'Guardar'}
            </button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
