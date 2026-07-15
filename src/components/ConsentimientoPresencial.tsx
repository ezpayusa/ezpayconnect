import { useMemo, useRef, useState } from 'react'
import type { ChangeEvent } from 'react'
import { useConsentimientoPresencial } from '@/hooks/useConsentimientoPresencial'
import type { ConsentimientoVigente } from '@/hooks/useConsentimientoPresencial'
import FirmaPad from '@/repartidor/components/FirmaPad'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import { ShieldCheck, ChevronDown, AlertTriangle, PenLine, Upload, Loader2 } from 'lucide-react'

/**
 * Captura presencial de consentimiento (staff). Por permiso: firmar (FirmaPad) o subir papel para conceder;
 * revocar sin prueba. Reusable en PacienteDetallePage (médico) y ModalAdmisión (asistente).
 */
export function ConsentimientoPresencial({ pacienteId }: { pacienteId: number }) {
  const { catalogo, estado, cargando, subiendo, concederConFirma, concederConScan, revocar } = useConsentimientoPresencial(pacienteId)
  const [firmandoCodigo, setFirmandoCodigo] = useState<string | null>(null)
  const [scanCodigo, setScanCodigo] = useState<string | null>(null)
  const [ocupado, setOcupado] = useState<string | null>(null)
  const scanRef = useRef<HTMLInputElement>(null)

  const vigentePorCodigo = useMemo(() => {
    const m: Record<string, ConsentimientoVigente> = {}
    for (const v of estado) m[v.codigo] = v
    return m
  }, [estado])

  const onFirmaSave = async (blob: Blob) => {
    const codigo = firmandoCodigo
    if (!codigo) return
    setOcupado(codigo)
    await concederConFirma(pacienteId, codigo, blob)
    setOcupado(null)
    setFirmandoCodigo(null)
  }

  const pedirScan = (codigo: string) => { setScanCodigo(codigo); scanRef.current?.click() }
  const onScan = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    const codigo = scanCodigo
    e.target.value = ''
    if (!file || !codigo) return
    setOcupado(codigo)
    await concederConScan(pacienteId, codigo, file)
    setOcupado(null)
    setScanCodigo(null)
  }

  const onRevocar = async (codigo: string) => {
    setOcupado(codigo)
    await revocar(pacienteId, codigo)
    setOcupado(null)
  }

  return (
    <div className="space-y-3">
      {cargando && (
        <div className="flex justify-center py-6"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
      )}

      {!cargando && catalogo.length === 0 && (
        <div className="text-center py-6 text-slate-400">
          <ShieldCheck className="h-10 w-10 mx-auto mb-2 text-slate-300" />
          <p className="text-sm">No hay permisos disponibles</p>
        </div>
      )}

      {!cargando && catalogo.map((permiso) => {
        const vigente = vigentePorCodigo[permiso.codigo]
        const concedido = vigente?.concedido ?? false
        const esBorrador = permiso.texto_legal.startsWith('[BORRADOR')
        const busy = ocupado === permiso.codigo || subiendo
        return (
          <div key={permiso.codigo} className="border rounded-lg p-3 space-y-2">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0 flex-1">
                <h3 className="font-semibold text-slate-800">{permiso.etiqueta}</h3>
                <p className={`text-xs mt-0.5 font-medium ${concedido ? 'text-emerald-600' : 'text-slate-400'}`}>
                  {concedido ? `Autorizado${vigente?.via ? ` (${vigente.via})` : ''}` : 'No autorizado'}
                </p>
              </div>
              <div className="flex items-center gap-2 shrink-0 w-full sm:w-auto">
                {busy && <Loader2 className="h-4 w-4 animate-spin text-slate-400" />}
                {concedido ? (
                  <button
                    type="button"
                    onClick={() => onRevocar(permiso.codigo)}
                    disabled={busy}
                    className="flex-1 sm:flex-none justify-center px-3 py-1.5 rounded-md text-sm font-medium border border-red-300 text-red-600 hover:bg-red-50 disabled:opacity-50"
                  >
                    Revocar
                  </button>
                ) : (
                  <>
                    <button
                      type="button"
                      onClick={() => setFirmandoCodigo(permiso.codigo)}
                      disabled={busy}
                      className="flex-1 sm:flex-none justify-center inline-flex items-center gap-1 px-3 py-1.5 rounded-md text-sm font-medium bg-[#1E5C8E] text-white hover:bg-[#164a70] disabled:opacity-50"
                    >
                      <PenLine className="h-4 w-4" /> Firmar
                    </button>
                    <button
                      type="button"
                      onClick={() => pedirScan(permiso.codigo)}
                      disabled={busy}
                      className="flex-1 sm:flex-none justify-center inline-flex items-center gap-1 px-3 py-1.5 rounded-md text-sm font-medium border border-slate-300 text-slate-700 hover:bg-slate-50 disabled:opacity-50"
                    >
                      <Upload className="h-4 w-4" /> Subir papel
                    </button>
                  </>
                )}
              </div>
            </div>

            {esBorrador && (
              <div className="flex items-center gap-2 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-2 py-1">
                <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
                Texto de desarrollo — no es el texto legal definitivo.
              </div>
            )}

            <Collapsible>
              <CollapsibleTrigger className="flex items-center gap-1 text-xs text-sky-600 hover:underline">
                <ChevronDown className="h-3.5 w-3.5" /> Ver texto
              </CollapsibleTrigger>
              <CollapsibleContent>
                <p className="text-sm text-slate-600 mt-2 leading-relaxed">{permiso.texto_legal}</p>
              </CollapsibleContent>
            </Collapsible>
          </div>
        )
      })}

      {/* input scan compartido (un permiso a la vez vía scanCodigo) */}
      <input ref={scanRef} type="file" accept="image/*,application/pdf" className="hidden" onChange={onScan} />

      {/* FirmaPad fullscreen (un permiso a la vez) */}
      {firmandoCodigo && (
        <FirmaPad
          folio={firmandoCodigo}
          onSave={onFirmaSave}
          onCancel={() => setFirmandoCodigo(null)}
          saving={ocupado === firmandoCodigo}
        />
      )}
    </div>
  )
}
