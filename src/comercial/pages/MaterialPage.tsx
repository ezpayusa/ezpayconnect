import { useEffect, useState } from 'react'
import { FileText, Image as ImageIcon, Film } from 'lucide-react'
import { listarMaterial, urlFirmadaMaterial, type Material } from '../lib/material'
import { reportarError } from '../lib/reportarError'

const icono = (mime: string | null) =>
  mime?.startsWith('video') ? Film : mime?.startsWith('image') ? ImageIcon : FileText

// Material de referencia para el asesor y el supervisor. SOLO LECTURA — y no por ausencia de
// botones: `guardar_material_comercial` está atada a `puede_admin_pais`, así que un comercial que
// la llame igual recibe 42501.
//
// No hay ningún filtro de país ni de `activo` acá: los pone la policy de la mig 278. Ponerlos en
// el cliente sería fingir un control — el dato viajaría igual en el payload.
export default function MaterialPage() {
  const [items, setItems] = useState<Material[]>([])
  const [cargando, setCargando] = useState(true)

  useEffect(() => {
    void (async () => {
      const { data, error } = await listarMaterial()
      if (error) reportarError(error); else setItems((data ?? []) as unknown as Material[])
      setCargando(false)
    })()
  }, [])

  const abrir = async (path: string) => {
    const { data, error } = await urlFirmadaMaterial(path)
    if (error || !data?.signedUrl) { reportarError(error ?? { message: 'sin url' }); return }
    window.open(data.signedUrl, '_blank', 'noopener')
  }

  if (cargando) return <p className="text-sm text-gray-500">Cargando…</p>

  return (
    <div className="space-y-3">
      <div>
        <h1 className="font-semibold text-gray-900">Material de referencia</h1>
        <p className="mt-0.5 text-xs text-gray-500">
          Lo publica el administrador de tu país. {items.length} archivo(s).
        </p>
      </div>

      {items.length === 0 ? (
        <p className="rounded-lg border border-dashed bg-white p-6 text-sm text-gray-600">
          Todavía no hay material publicado para tu país.
        </p>
      ) : (
        <ul className="space-y-2">
          {items.map(m => {
            const Icono = icono(m.mime)
            return (
              <li key={m.id}>
                <button type="button" onClick={() => void abrir(m.storage_path)}
                  className="flex w-full items-start gap-3 rounded-lg border bg-white p-3 text-left hover:border-[#1E5C8E]">
                  <Icono className="mt-0.5 h-5 w-5 shrink-0 text-[#1E5C8E]" />
                  <div className="min-w-0">
                    <p className="truncate font-medium text-gray-900">{m.titulo}</p>
                    {m.descripcion && <p className="mt-0.5 text-xs text-gray-600">{m.descripcion}</p>}
                    <p className="mt-0.5 text-xs text-gray-400">
                      {m.mime ?? 'archivo'}
                      {m.bytes != null && ` · ${(m.bytes / 1024 / 1024).toFixed(1)} MB`}
                    </p>
                  </div>
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
