import { useState } from 'react'
import { archivoDeResultado } from '@/components/visor/useVisor'
import type { ArchivoVisor } from '@/components/visor/VisorArchivos'
import type { RevisionExamen } from '@/lib/correccionResultados'
import { ChevronDown, ChevronRight, FileText, History } from 'lucide-react'

interface Props {
  revisiones: RevisionExamen[]
  abrir: (archivos: ArchivoVisor[]) => void
}

// Historial de correcciones de UN examen: cada fila guarda los valores que había ANTES de esa
// corrección. Solo para el equipo clínico — el paciente no lo ve (la RLS de examen_revisiones lo excluye).
export default function HistorialRevisionesExamen({ revisiones, abrir }: Props) {
  const [abierto, setAbierto] = useState(false)
  if (revisiones.length === 0) return null

  return (
    <div className="mt-3">
      <button type="button" onClick={() => setAbierto((a) => !a)}
        className="inline-flex items-center gap-1 text-sm text-gray-600 hover:text-[#1E5C8E]">
        {abierto ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        <History size={16} /> Historial de revisiones ({revisiones.length})
      </button>
      {abierto && (
        <ol className="mt-2 space-y-2">
          {revisiones.map((r) => { const archivoAnterior = r.archivo_url_anterior; return (
            <li key={r.id} className="bg-white border rounded-lg p-3 text-sm">
              <div className="flex items-center justify-between gap-2 flex-wrap text-xs text-gray-500">
                <span className="font-medium text-gray-700">Revisión {r.revision}</span>
                <span>{new Date(r.corregido_at).toLocaleString('es-GT')}</span>
              </div>
              <p className="mt-1"><span className="text-gray-500">Motivo:</span> {r.motivo}</p>
              <div className="mt-2 border-t pt-2">
                <p className="text-xs text-gray-500 mb-1">Resultado anterior</p>
                {r.resultados_anterior
                  ? <p className="text-gray-700 whitespace-pre-wrap">{r.resultados_anterior}</p>
                  : <p className="text-gray-400 italic">Sin texto</p>}
                {archivoAnterior && (
                  <button type="button" onClick={() => abrir([archivoDeResultado(archivoAnterior)])}
                    className="mt-1 inline-flex items-center gap-1 text-[#1E5C8E] hover:underline">
                    <FileText size={14} /> Ver archivo anterior
                  </button>
                )}
              </div>
            </li>
          ) })}
        </ol>
      )}
    </div>
  )
}
