import { useRef, useState } from 'react'
import type { ChangeEvent } from 'react'
import { useDocumentosPaciente } from '@/hooks/useDocumentosPaciente'
import { FileText, Loader2, Eye, Download, Upload } from 'lucide-react'

const TIPOS = [
  { value: 'consentimiento_firmado', label: 'Consentimiento firmado' },
  { value: 'examen_externo', label: 'Examen externo' },
  { value: 'identificacion', label: 'Identificación' },
  { value: 'otro', label: 'Otro' },
]

/**
 * Lista + subida de documentos del paciente (bucket privado → signed URL). Reusable.
 * Subida solo si editable; el gate real lo aplican los RPCs (staff con pertenencia).
 */
export function DocumentosPaciente({ pacienteId, editable = false }: { pacienteId: number; editable?: boolean }) {
  const { documentos, cargando, subiendo, subir, abrir } = useDocumentosPaciente(pacienteId)
  const [tipo, setTipo] = useState('consentimiento_firmado')
  const [descripcion, setDescripcion] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const onFile = (e: ChangeEvent<HTMLInputElement>) => setFile(e.target.files?.[0] ?? null)

  const onSubir = async () => {
    if (!file) return
    const ok = await subir(pacienteId, file, tipo, descripcion.trim() || null)
    if (ok) {
      setFile(null)
      setDescripcion('')
      if (inputRef.current) inputRef.current.value = ''
    }
  }

  const fmtFecha = (s: string) => new Date(s).toLocaleDateString('es-ES', { day: '2-digit', month: 'short', year: 'numeric' })
  const tipoLabel = (v: string) => TIPOS.find((t) => t.value === v)?.label ?? v

  return (
    <div className="space-y-4">
      {editable && (
        <div className="flex flex-wrap items-end gap-2 bg-slate-50 border rounded-lg p-3">
          <div className="flex flex-col">
            <label className="text-xs text-slate-500 mb-1">Tipo</label>
            <select
              value={tipo}
              onChange={(e) => setTipo(e.target.value)}
              disabled={subiendo}
              className="border rounded-md px-2 py-1.5 text-sm bg-white"
            >
              {TIPOS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          <div className="flex flex-col flex-1 min-w-[180px]">
            <label className="text-xs text-slate-500 mb-1">Descripción (opcional)</label>
            <input
              value={descripcion}
              onChange={(e) => setDescripcion(e.target.value)}
              disabled={subiendo}
              placeholder="Ej. Consentimiento de grabación firmado"
              className="border rounded-md px-2 py-1.5 text-sm"
            />
          </div>
          <div className="flex flex-col">
            <label className="text-xs text-slate-500 mb-1">Archivo (imagen o PDF)</label>
            <input
              ref={inputRef}
              type="file"
              accept="image/*,application/pdf"
              onChange={onFile}
              disabled={subiendo}
              className="text-sm"
            />
          </div>
          <button
            type="button"
            onClick={onSubir}
            disabled={subiendo || !file}
            className="inline-flex items-center gap-1 px-3 py-1.5 rounded-md bg-[#1E5C8E] text-white text-sm font-medium hover:bg-[#164a70] disabled:opacity-50"
          >
            {subiendo ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />} Subir
          </button>
        </div>
      )}

      {cargando ? (
        <div className="flex items-center justify-center py-8">
          <Loader2 className="h-6 w-6 animate-spin text-slate-400" />
        </div>
      ) : documentos.length === 0 ? (
        <div className="text-center py-8 text-slate-400">
          <FileText className="h-10 w-10 mx-auto mb-2 text-slate-300" />
          <p className="text-sm">No hay documentos</p>
        </div>
      ) : (
        <ul className="divide-y border rounded-lg">
          {documentos.map((d) => (
            <li key={d.id} className="flex items-center justify-between gap-3 p-3">
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-medium bg-slate-100 text-slate-600 rounded px-2 py-0.5">{tipoLabel(d.tipo)}</span>
                  <span className="text-xs text-slate-400">{fmtFecha(d.created_at)}</span>
                </div>
                {d.descripcion && <p className="text-sm text-slate-600 mt-0.5 truncate">{d.descripcion}</p>}
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <button type="button" onClick={() => abrir(d.path)} className="inline-flex items-center gap-1 text-xs text-sky-600 hover:underline">
                  <Eye className="h-3.5 w-3.5" /> Ver
                </button>
                <button type="button" onClick={() => abrir(d.path, true)} className="inline-flex items-center gap-1 text-xs text-slate-600 hover:underline">
                  <Download className="h-3.5 w-3.5" /> Descargar
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
