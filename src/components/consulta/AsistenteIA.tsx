import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { useConsentimientoGate } from '@/hooks/useConsentimientoGate'
import {
  Brain,
  Loader2,
  AlertTriangle,
  CheckCircle2,
  FlaskConical,
  Pill,
  BookOpen,
  Stethoscope,
  Copy,
  ShieldOff,
} from 'lucide-react'

interface SugerenciasIA {
  disclaimer: string
  diagnosticos_diferenciales: { nombre: string; probabilidad: string; justificacion: string }[]
  examenes_recomendados: string[]
  opciones_farmacologicas: { nombre: string; nota: string }[]
  contraindicaciones: string[]
  referencias_guias: string[]
  notas_adicionales: string
}

interface AsistenteIAProps {
  contexto: {
    edad?: number
    genero?: string | null
    peso_kg?: string
    motivo_consulta?: string
    subjetivo?: string
    objetivo?: string
    presion_arterial?: string
    temperatura?: string
    frecuencia_cardiaca?: string
    alergias?: string | null
    medicamentos_en_uso?: string | null
    antecedentes?: string | null
  }
  onCopiarSugerencia?: (texto: string) => void
  pacienteId: number
}

export default function AsistenteIA({ contexto, onCopiarSugerencia, pacienteId }: AsistenteIAProps) {
  // Gate UX (la barrera real la aplica el edge): evita el intento si el paciente revocó el uso de IA.
  const { permitido } = useConsentimientoGate(pacienteId)
  const iaBloqueada = !permitido('asistente_ia')
  const [sugerencias, setSugerencias] = useState<SugerenciasIA | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [needsConfig, setNeedsConfig] = useState(false)

  const analizar = async () => {
    setLoading(true)
    setError('')
    setNeedsConfig(false)
    try {
      const { data, error } = await supabase.functions.invoke('asistente-ia', {
        body: {
          paciente_id: pacienteId,
          contexto: {
            edad: contexto.edad,
            genero: contexto.genero || undefined,
            peso_kg: contexto.peso_kg ? parseFloat(contexto.peso_kg) : undefined,
            motivo_consulta: contexto.motivo_consulta,
            subjetivo: contexto.subjetivo,
            objetivo: contexto.objetivo,
            signos_vitales: {
              presion_arterial: contexto.presion_arterial,
              temperatura: contexto.temperatura ? parseFloat(contexto.temperatura) : undefined,
              frecuencia_cardiaca: contexto.frecuencia_cardiaca ? parseInt(contexto.frecuencia_cardiaca) : undefined,
            },
            alergias: contexto.alergias || undefined,
            medicamentos_actuales: contexto.medicamentos_en_uso || undefined,
            antecedentes: contexto.antecedentes || undefined,
          }
        }
      })

      if (error) throw error
      if (data?.needsConfig) {
        setNeedsConfig(true)
        return
      }
      setSugerencias(data?.sugerencias || null)
    } catch (e: any) {
      setError(e.message || 'Error al consultar IA')
      toast.error('Error: ' + e.message)
    } finally {
      setLoading(false)
    }
  }

  const copiarTodo = () => {
    if (!sugerencias) return
    const texto = `
DIAGNOSTICOS DIFERENCIALES:
${sugerencias.diagnosticos_diferenciales.map(d => `- ${d.nombre} (${d.probabilidad}): ${d.justificacion}`).join('\n')}

EXAMENES RECOMENDADOS:
${sugerencias.examenes_recomendados.map(e => `- ${e}`).join('\n')}

OPCIONES FARMACOLOGICAS:
${sugerencias.opciones_farmacologicas.map(o => `- ${o.nombre}: ${o.nota}`).join('\n')}

CONTRAINDICACIONES:
${sugerencias.contraindicaciones.map(c => `- ${c}`).join('\n')}

REFERENCIAS:
${sugerencias.referencias_guias.map(r => `- ${r}`).join('\n')}
`.trim()
    navigator.clipboard.writeText(texto)
    if (onCopiarSugerencia) onCopiarSugerencia(texto)
    toast.success('Sugerencias copiadas')
  }

  return (
    <div className="space-y-4">
      <div className="bg-purple-50 border border-purple-200 rounded-lg p-3 text-xs text-purple-700 flex items-start gap-2">
        <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
        <div>
          <p className="font-medium">Sugerencia de IA generada automaticamente</p>
          <p>NO es un diagnostico medico. El medico tratante debe verificar toda la informacion antes de prescribir.</p>
        </div>
      </div>

      {iaBloqueada ? (
        <div className="flex items-center gap-2 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-3 py-2">
          <ShieldOff className="h-4 w-4 shrink-0" />
          El paciente revocó el uso de IA. Captúralo en Consentimiento.
        </div>
      ) : (
        <Button
          onClick={analizar}
          disabled={loading}
          className="w-full bg-purple-600 hover:bg-purple-700"
        >
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin mr-2" />
          ) : (
            <Brain className="h-4 w-4 mr-2" />
          )}
          {loading ? 'Analizando...' : 'Analizar consulta con IA'}
        </Button>
      )}

      {needsConfig && (
        <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-sm text-amber-700">
          <p className="font-medium">Asistente IA no configurado</p>
          <p className="text-xs mt-1">El administrador debe configurar OPENAI_API_KEY en los secrets de Supabase.</p>
        </div>
      )}

      {error && !needsConfig && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {sugerencias && (
        <div className="space-y-3">
          {/* Diagnosticos */}
          <Card>
            <CardContent className="p-3">
              <h4 className="text-sm font-semibold flex items-center gap-2 mb-2">
                <Stethoscope className="h-4 w-4 text-purple-600" />
                Diagnosticos Diferenciales
              </h4>
              <div className="space-y-2">
                {sugerencias.diagnosticos_diferenciales.map((d, i) => (
                  <div key={i} className="bg-slate-50 p-2 rounded">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium">{d.nombre}</span>
                      <Badge variant="outline" className="text-[10px]">{d.probabilidad}</Badge>
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">{d.justificacion}</p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          {/* Examenes */}
          {sugerencias.examenes_recomendados.length > 0 && (
            <Card>
              <CardContent className="p-3">
                <h4 className="text-sm font-semibold flex items-center gap-2 mb-2">
                  <FlaskConical className="h-4 w-4 text-blue-600" />
                  Examenes Recomendados
                </h4>
                <ul className="space-y-1">
                  {sugerencias.examenes_recomendados.map((e, i) => (
                    <li key={i} className="text-sm flex items-center gap-2">
                      <CheckCircle2 className="h-3 w-3 text-blue-500" />
                      {e}
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          )}

          {/* Farmacologicas */}
          {sugerencias.opciones_farmacologicas.length > 0 && (
            <Card>
              <CardContent className="p-3">
                <h4 className="text-sm font-semibold flex items-center gap-2 mb-2">
                  <Pill className="h-4 w-4 text-emerald-600" />
                  Opciones Farmacologicas
                </h4>
                <div className="space-y-2">
                  {sugerencias.opciones_farmacologicas.map((o, i) => (
                    <div key={i} className="bg-slate-50 p-2 rounded text-sm">
                      <span className="font-medium">{o.nombre}</span>
                      <p className="text-xs text-muted-foreground">{o.nota}</p>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}

          {/* Contraindicaciones */}
          {sugerencias.contraindicaciones.length > 0 && (
            <Card className="border-red-200">
              <CardContent className="p-3">
                <h4 className="text-sm font-semibold flex items-center gap-2 mb-2 text-red-700">
                  <AlertTriangle className="h-4 w-4" />
                  Contraindicaciones / Precauciones
                </h4>
                <ul className="space-y-1">
                  {sugerencias.contraindicaciones.map((c, i) => (
                    <li key={i} className="text-sm text-red-600 flex items-center gap-2">
                      <AlertTriangle className="h-3 w-3" />
                      {c}
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          )}

          {/* Referencias */}
          {sugerencias.referencias_guias.length > 0 && (
            <Card>
              <CardContent className="p-3">
                <h4 className="text-sm font-semibold flex items-center gap-2 mb-2">
                  <BookOpen className="h-4 w-4 text-amber-600" />
                  Referencias a Guias Clinicas
                </h4>
                <ul className="space-y-1">
                  {sugerencias.referencias_guias.map((r, i) => (
                    <li key={i} className="text-xs text-muted-foreground">{r}</li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          )}

          <Button variant="outline" size="sm" className="w-full" onClick={copiarTodo}>
            <Copy className="h-4 w-4 mr-2" /> Copiar todo al portapapeles
          </Button>
        </div>
      )}
    </div>
  )
}
