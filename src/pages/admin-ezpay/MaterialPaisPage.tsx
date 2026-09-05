import { useEffect, useState, useCallback } from 'react'
import { useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { FileText, Image as ImageIcon, Film, Eye, EyeOff, Trash2, AlertTriangle } from 'lucide-react'
import {
  listarMaterialDePais, subirMaterial, activarMaterial, urlFirmadaMaterial, borrarMaterial,
  validarMaterial, ACCEPT_MATERIAL, type Material,
} from '@/comercial/lib/material'
import { reportarError, type ErrorInline } from '@/comercial/lib/reportarError'

const icono = (mime: string | null) =>
  mime?.startsWith('video') ? Film : mime?.startsWith('image') ? ImageIcon : FileText

// Material del país: subir, listar y activar/desactivar. Cuelga del AdminLayout, con el AdminRoute
// que ya confina al admin_pais a su propio /pais/{su pais_id}.
//
// El `.eq('pais_id', paisId)` es un SELECTOR DE VISTA (un super_admin ve varios países), no un
// permiso: sólo puede achicar lo que la policy ya permitió. Y el admin ve TAMBIÉN lo desactivado
// —lo necesita para reactivarlo—, cosa que resuelve la policy de la 278, no un filtro de acá.
//
// BORRAR NO ENTRA. Desactivar deja la fila y el objeto. Que se pueda borrar material —igual que
// borrar adjuntos de visita— es una decisión de producto pendiente; las dos van juntas.
export default function MaterialPaisPage() {
  const { paisId = '' } = useParams()
  const [items, setItems] = useState<Material[]>([])
  const [cargando, setCargando] = useState(true)
  const [titulo, setTitulo] = useState('')
  const [descripcion, setDescripcion] = useState('')
  const [progreso, setProgreso] = useState<number | null>(null)
  const [err, setErr] = useState<ErrorInline>(null)
  const [huerfano, setHuerfano] = useState<string | null>(null)
  const [trabajando, setTrabajando] = useState(false)
  // Confirmación y estado de borrado, POR ÍTEM: el `trabajando` global es de la subida.
  const [confirmando, setConfirmando] = useState<string | null>(null)
  const [borrando, setBorrando] = useState<string | null>(null)
  const [errBorrado, setErrBorrado] = useState<{ id: string; mensaje: string } | null>(null)

  const cargar = useCallback(async () => {
    setCargando(true)
    const { data, error } = await listarMaterialDePais(paisId)
    if (error) reportarError(error); else setItems((data ?? []) as unknown as Material[])
    setCargando(false)
  }, [paisId])

  useEffect(() => { void cargar() }, [cargar])

  const onSubir = async (archivo: File | null) => {
    if (!archivo) return
    setErr(null); setHuerfano(null)
    if (!titulo.trim()) { setErr({ campo: 'titulo', mensaje: 'Ponele un título antes de subir.' }); return }
    const motivo = validarMaterial(archivo)
    if (motivo) { setErr({ campo: 'archivo', mensaje: motivo }); return }

    setTrabajando(true); setProgreso(0)
    const { error, huerfano: h } = await subirMaterial(
      { paisId, titulo: titulo.trim(), descripcion: descripcion.trim() || null }, archivo, setProgreso)
    setTrabajando(false); setProgreso(null)
    if (error) {
      reportarError(error, { setInline: setErr, onRecargar: () => void cargar() })
      if (h) setHuerfano(h)
      return
    }
    toast.success('Material publicado')
    setTitulo(''); setDescripcion('')
    void cargar()
  }

  const onActivar = async (m: Material) => {
    const { error } = await activarMaterial(m.id, !m.activo)
    if (error) { reportarError(error, { onRecargar: () => void cargar() }); return }
    toast.success(m.activo ? 'Material desactivado' : 'Material reactivado')
    void cargar()
  }

  const onBorrar = async (m: Material) => {
    setErrBorrado(null); setBorrando(m.id)
    const { fase, error } = await borrarMaterial(m)
    setBorrando(null)

    if (fase === 'rpc') {
      // No pasó nada: la fila sigue y el objeto también. El error va INLINE en el ítem.
      const mapeado = reportarError(error, {
        setInline: (v) => setErrBorrado(v ? { id: m.id, mensaje: v.mensaje } : null),
      })
      if (mapeado.destino !== 'inline') setErrBorrado({ id: m.id, mensaje: mapeado.mensaje })
      return
    }

    setConfirmando(null)

    if (fase === 'storage') {
      // La fila YA NO EXISTE y el archivo quedó. Esto NO se pinta como éxito: se avisa y se
      // recarga igual, porque la lista cambió de verdad.
      reportarError(error)
      toast.warning('Se eliminó el registro pero el archivo no pudo borrarse; volvé a intentar.')
      void cargar()
      return
    }

    toast.success('Material eliminado')
    void cargar()
  }

  const abrir = async (path: string) => {
    const { data, error } = await urlFirmadaMaterial(path)
    if (error || !data?.signedUrl) { reportarError(error ?? { message: 'sin url' }); return }
    window.open(data.signedUrl, '_blank', 'noopener')
  }

  return (
    <div className="space-y-5 p-4">
      <h1 className="text-xl font-semibold text-gray-900">Material comercial del país</h1>

      <section className="rounded-lg border bg-white p-4">
        <h2 className="font-semibold text-gray-900">Publicar</h2>
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <div>
            <label className="text-xs text-gray-600">Título</label>
            <input id="titulo" value={titulo} onChange={(e) => setTitulo(e.target.value)}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm" placeholder="Folleto de producto 2026" />
            {err?.campo === 'titulo' && <p className="mt-1 text-xs text-red-600">{err.mensaje}</p>}
          </div>
          <div>
            <label className="text-xs text-gray-600">Descripción (opcional)</label>
            <input id="descripcion" value={descripcion} onChange={(e) => setDescripcion(e.target.value)}
              className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </div>
        </div>
        <input type="file" id="archivo-material" accept={ACCEPT_MATERIAL} disabled={trabajando}
          onChange={(e) => void onSubir(e.target.files?.[0] ?? null)} className="mt-3 block w-full text-xs" />
        {progreso != null && (
          <div className="mt-2">
            <div className="h-1.5 w-full overflow-hidden rounded bg-gray-200">
              <div className="h-full bg-[#1E5C8E] transition-all" style={{ width: `${progreso}%` }} />
            </div>
            <p className="mt-1 text-xs text-gray-600">Subiendo… {progreso}%</p>
          </div>
        )}
        {err && err.campo !== 'titulo' && <p id="err-material" className="mt-2 text-xs text-red-600">{err.mensaje}</p>}
        {huerfano && (
          <p className="mt-1 text-xs text-amber-800">
            No se pudo limpiar el archivo a medio subir. Avisale a soporte:
            <span className="font-mono"> {huerfano}</span>
          </p>
        )}
      </section>

      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Publicado</h2>
          <span className="text-xs text-gray-500">{items.length}</span>
        </div>
        {cargando ? <p className="mt-2 text-sm text-gray-500">Cargando…</p>
          : items.length === 0 ? <p className="mt-2 text-sm text-gray-500">Nada publicado todavía.</p> : (
          <ul className="mt-2 divide-y">
            {items.map(m => {
              const Icono = icono(m.mime)
              return (
                <li key={m.id} className="py-2">
                <div className="flex items-center gap-3">
                  <Icono className="h-5 w-5 shrink-0 text-[#1E5C8E]" />
                  <div className="min-w-0 flex-1">
                    <button type="button" onClick={() => void abrir(m.storage_path)}
                      className="truncate text-sm font-medium text-gray-900 hover:text-[#1E5C8E]">
                      {m.titulo}
                    </button>
                    <p className="text-xs text-gray-500">
                      {m.mime ?? 'archivo'}{m.bytes != null && ` · ${(m.bytes / 1024 / 1024).toFixed(1)} MB`}
                      {!m.activo && ' · DESACTIVADO (los asesores no lo ven)'}
                    </p>
                  </div>
                  <button type="button" onClick={() => void onActivar(m)}
                    className={`flex shrink-0 items-center gap-1 rounded border px-2 py-1 text-xs ${
                      m.activo ? 'border-gray-300 text-gray-700' : 'border-[#1E5C8E] text-[#1E5C8E]'}`}>
                    {m.activo ? <><EyeOff className="h-3.5 w-3.5" />Desactivar</> : <><Eye className="h-3.5 w-3.5" />Reactivar</>}
                  </button>
                  {/* El disabled es cortesía. La barrera es que borrar_material_comercial está
                      atada a puede_admin_pais y contesta 42501 (probes P579/P581). */}
                  <button type="button" data-testid={`btn-eliminar-${m.id}`}
                    onClick={() => { setErrBorrado(null); setConfirmando(m.id) }}
                    disabled={borrando === m.id}
                    className="flex shrink-0 items-center gap-1 rounded border border-red-300 px-2 py-1 text-xs text-red-700 hover:bg-red-50 disabled:opacity-50">
                    <Trash2 className="h-3.5 w-3.5" />Eliminar
                  </button>
                </div>

                {/* Confirmación explícita, con el título del material a la vista. La diferencia
                    entre Desactivar y Eliminar se dice acá, que es donde la decisión se toma. */}
                {confirmando === m.id && (
                  <div data-testid={`confirmar-${m.id}`}
                    className="mt-2 rounded border border-red-200 bg-red-50 p-3 text-sm">
                    <p className="flex items-start gap-1.5 text-red-900">
                      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                      <span>
                        ¿Eliminar <b>{m.titulo}</b>? Se elimina definitivamente el archivo y su
                        registro. Si solo querés ocultarlo a los asesores, usá Desactivar.
                      </span>
                    </p>
                    <div className="mt-2 flex gap-2">
                      <button type="button" onClick={() => setConfirmando(null)}
                        disabled={borrando === m.id}
                        className="rounded border border-gray-300 px-3 py-1 text-xs text-gray-700 disabled:opacity-50">
                        Cancelar
                      </button>
                      <button type="button" data-testid={`confirmar-eliminar-${m.id}`}
                        onClick={() => void onBorrar(m)} disabled={borrando === m.id}
                        className="rounded bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-700 disabled:opacity-50">
                        {borrando === m.id ? 'Eliminando…' : 'Eliminar definitivamente'}
                      </button>
                    </div>
                  </div>
                )}

                {/* Falla del RPC: no pasó nada, la fila sigue. El error vive pegado al ítem. */}
                {errBorrado?.id === m.id && (
                  <p data-testid={`err-eliminar-${m.id}`} className="mt-1 text-xs text-red-600">
                    {errBorrado.mensaje}
                  </p>
                )}
                </li>
              )
            })}
          </ul>
        )}
        {/* nada acá: la confirmación se pinta dentro de cada ítem */}
        <p className="mt-3 text-xs text-gray-500">
          Desactivar no borra: el archivo queda y lo podés reactivar. Los asesores dejan de verlo.
        </p>
      </section>
    </div>
  )
}
