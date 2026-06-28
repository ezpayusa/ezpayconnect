import { useMemo, useState } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { useConsentimientoPaciente } from '@/webapp/hooks/useConsentimientoPaciente'
import type { ConsentimientoVigente } from '@/webapp/hooks/useConsentimientoPaciente'
import { Card, CardContent } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import { ShieldCheck, Loader2, ChevronDown, AlertTriangle } from 'lucide-react'

export default function WebAppAutorizaciones() {
  const { perfil } = useWebAppAuth()
  const pacienteId = perfil?.id
  const { catalogo, estado, cargando, registrar } = useConsentimientoPaciente(pacienteId)
  const [guardando, setGuardando] = useState<string | null>(null)

  // Mapa derivado codigo→vigente para el merge catálogo×estado.
  const vigentePorCodigo = useMemo(() => {
    const m: Record<string, ConsentimientoVigente> = {}
    for (const v of estado) m[v.codigo] = v
    return m
  }, [estado])

  const onToggle = async (codigo: string, nuevo: boolean) => {
    if (!pacienteId) return
    setGuardando(codigo)
    await registrar(pacienteId, codigo, nuevo)
    setGuardando(null)
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Autorizaciones</h1>
        <p className="text-slate-500 mt-1">Controlá qué permisos otorgás sobre tus datos. Podés cambiarlos cuando quieras.</p>
      </div>

      {cargando && (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-sky-500" />
        </div>
      )}

      {!cargando && catalogo.length === 0 && (
        <div className="text-center py-12">
          <ShieldCheck className="h-12 w-12 text-slate-300 mx-auto mb-3" />
          <p className="text-slate-500">No hay autorizaciones disponibles</p>
        </div>
      )}

      {!cargando && catalogo.map((permiso) => {
        const vigente = vigentePorCodigo[permiso.codigo]
        const concedido = vigente?.concedido ?? false
        const esBorrador = permiso.texto_legal.startsWith('[BORRADOR')
        const ocupado = guardando === permiso.codigo
        return (
          <Card key={permiso.codigo}>
            <CardContent className="p-4 space-y-3">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <h2 className="font-semibold text-slate-800">{permiso.etiqueta}</h2>
                  <p className={`text-xs mt-0.5 font-medium ${concedido ? 'text-emerald-600' : 'text-slate-400'}`}>
                    {concedido ? 'Autorizado' : 'No autorizado'}
                  </p>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  {ocupado && <Loader2 className="h-4 w-4 animate-spin text-slate-400" />}
                  {/* Botón = control primario visible (el portal paciente no define los tokens de tema
                      bg-primary/bg-input → el track del Switch sale transparente). Switch = secundario. */}
                  <button
                    type="button"
                    onClick={() => onToggle(permiso.codigo, !concedido)}
                    disabled={cargando || ocupado || !pacienteId}
                    className={`px-3 py-1.5 rounded-md text-sm font-medium border transition-colors disabled:opacity-50 ${
                      concedido
                        ? 'bg-emerald-500 text-white border-emerald-500 hover:bg-emerald-600'
                        : 'bg-white text-slate-700 border-slate-300 hover:bg-slate-50'
                    }`}
                  >
                    {concedido ? 'Autorizado' : 'Autorizar'}
                  </button>
                  <Switch
                    checked={concedido}
                    disabled={cargando || ocupado || !pacienteId}
                    onCheckedChange={(v) => onToggle(permiso.codigo, v)}
                    aria-label={`Autorizar ${permiso.etiqueta}`}
                    className="data-[state=checked]:!bg-emerald-500 data-[state=unchecked]:!bg-slate-300 border border-slate-300"
                  />
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
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}
