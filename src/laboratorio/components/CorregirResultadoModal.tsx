import { useState } from 'react'
import type { OrdenExamen } from '@/laboratorio/hooks/useLaboratorio'
import { archivoDeResultado } from '@/components/visor/useVisor'
import type { ArchivoVisor } from '@/components/visor/VisorArchivos'
import { ACCEPT_RESULTADO, MOTIVO_MAX, validarCorreccion } from '@/lib/correccionResultados'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import { AlertTriangle, FileText, Loader2, PencilLine, X } from 'lucide-react'

interface Props {
  examen: OrdenExamen
  abrir: (archivos: ArchivoVisor[]) => void
  onCerrar: () => void
  onCorregir: (examenId: number, motivo: string, resultados: string, archivo: File | null) => Promise<boolean>
}

// Corrección de un resultado ya COMPLETADO. El textarea arranca con el resultado vigente: la RPC
// guarda el texto que recibe aunque venga vacío, así que un textarea en blanco borraría el vigente.
export default function CorregirResultadoModal({ examen, abrir, onCerrar, onCorregir }: Props) {
  const [motivo, setMotivo] = useState('')
  const [resultado, setResultado] = useState(examen.resultados ?? '')
  const [archivo, setArchivo] = useState<File | null>(null)
  const [guardando, setGuardando] = useState(false)

  const archivoVigente = examen.archivo_url
  const aviso = validarCorreccion(
    { motivo, resultados: resultado, hayArchivoNuevo: !!archivo },
    { resultados: examen.resultados, archivo_url: examen.archivo_url },
  )

  const enviar = async () => {
    if (aviso) return
    setGuardando(true)
    const ok = await onCorregir(examen.id, motivo, resultado, archivo)
    setGuardando(false)
    if (ok) onCerrar()
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={onCerrar}>
      <Card className="w-full max-w-lg bg-white shadow-xl max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <CardContent className="p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold flex items-center gap-2">
              <PencilLine className="h-5 w-5 text-[#0E7C6B]" /> Corregir resultado · {examen.tipo}
            </h2>
            <button onClick={onCerrar}><X className="h-5 w-5 text-gray-400" /></button>
          </div>

          {examen.liberado_al_paciente && (
            <div className="flex items-start gap-2 text-sm bg-amber-50 border border-amber-200 rounded-lg p-2 text-amber-800">
              <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
              <span>Este resultado ya fue liberado: el paciente y el médico serán notificados de la corrección.</span>
            </div>
          )}

          <div className="space-y-2">
            <Label>Motivo de la corrección *</Label>
            <Textarea rows={2} value={motivo} maxLength={MOTIVO_MAX} onChange={(e) => setMotivo(e.target.value)}
              placeholder="Ej: error de transcripción en el valor de glucosa" />
            <p className={`text-xs text-right ${motivo.trim().length > MOTIVO_MAX ? 'text-red-600' : 'text-muted-foreground'}`}>
              {motivo.trim().length}/{MOTIVO_MAX}
            </p>
          </div>

          <div className="space-y-2">
            <Label>Resultado / valores</Label>
            <Textarea rows={6} value={resultado} onChange={(e) => setResultado(e.target.value)} />
            <p className="text-xs text-muted-foreground">
              Se guarda este texto tal como quede. Si lo vaciás, el resultado queda solo con el archivo.
            </p>
          </div>

          {archivoVigente && (
            <button type="button" onClick={() => abrir([archivoDeResultado(archivoVigente)])}
              className="flex items-center gap-2 text-sm text-[#0E7C6B] hover:underline">
              <FileText className="h-4 w-4" /> Ver archivo vigente
            </button>
          )}

          <div className="space-y-2">
            <Label>Reemplazar archivo (opcional)</Label>
            <input
              type="file"
              accept={ACCEPT_RESULTADO}
              onChange={(e) => setArchivo(e.target.files?.[0] || null)}
              className="block w-full text-sm text-gray-600 file:mr-3 file:py-2 file:px-3 file:rounded-lg file:border-0 file:bg-[#0E7C6B] file:text-white hover:file:bg-[#0a5e51] file:cursor-pointer"
            />
            {archivo && <p className="text-xs text-muted-foreground">Seleccionado: {archivo.name}</p>}
          </div>

          {aviso && motivo.trim() !== '' && <p className="text-xs text-amber-700">{aviso}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={onCerrar}>Cancelar</Button>
            <Button className="bg-[#0E7C6B] hover:bg-[#0a5e51]" onClick={enviar} disabled={guardando || !!aviso}>
              {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null} Guardar corrección
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
