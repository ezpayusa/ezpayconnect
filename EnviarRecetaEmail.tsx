import { useState } from 'react'
import { useEnviarReceta } from '@/hooks/useEnviarReceta'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Checkbox } from '@/components/ui/checkbox'
import { Mail, Loader2, CheckCircle, AlertCircle } from 'lucide-react'

interface EnviarRecetaEmailProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  receta: {
    id: number
    paciente_id: number
    paciente_nombre?: string
    paciente_email?: string
    instrucciones_generales?: string
  } | null
  medicamentos: any[]
  medicoNombre?: string
}

export default function EnviarRecetaEmail({ 
  open, 
  onOpenChange, 
  receta, 
  medicamentos,
  medicoNombre 
}: EnviarRecetaEmailProps) {
  const { enviarReceta, enviando, error, exito, setError, setExito } = useEnviarReceta()
  const [email, setEmail] = useState(receta?.paciente_email || '')
  const [solicitarConfirmacion, setSolicitarConfirmacion] = useState(false)

  const handleEnviar = async () => {
    if (!email || !receta) return

    const result = await enviarReceta({
      to: email,
      pacienteNombre: receta.paciente_nombre || `Paciente #${receta.paciente_id}`,
      medicoNombre: medicoNombre || 'Doctor',
      medicamentos: medicamentos,
      instruccionesGenerales: receta.instrucciones_generales || undefined,
      solicitarConfirmacion,
    })

    if (result.success) {
      setTimeout(() => {
        onOpenChange(false)
        setExito(false)
        setEmail('')
        setSolicitarConfirmacion(false)
      }, 2000)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Mail className="h-5 w-5 text-[#1E5C8E]" />
            Enviar Receta por Email
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Email del paciente */}
          <div className="space-y-2">
            <Label htmlFor="email">Email del paciente *</Label>
            <Input
              id="email"
              type="email"
              placeholder="paciente@email.com"
              value={email}
              onChange={(e) => {
                setEmail(e.target.value)
                setError(null)
              }}
              disabled={enviando || exito}
            />
          </div>

          {/* Preview de medicamentos */}
          {medicamentos.length > 0 && (
            <div className="bg-[#e8f0f8] rounded-lg p-3 space-y-2">
              <p className="text-sm font-medium text-[#1a2a3a]">Medicamentos ({medicamentos.length})</p>
              {medicamentos.slice(0, 3).map((med, i) => (
                <p key={i} className="text-xs text-[#8a9aaa]">
                  {i + 1}. {med.nombre_medicamento} - {med.dosis}
                </p>
              ))}
              {medicamentos.length > 3 && (
                <p className="text-xs text-[#8a9aaa]">... y {medicamentos.length - 3} más</p>
              )}
            </div>
          )}

          {/* Checkbox confirmación */}
          <div className="flex items-start gap-2">
            <Checkbox
              id="confirmacion"
              checked={solicitarConfirmacion}
              onCheckedChange={(checked) => setSolicitarConfirmacion(checked as boolean)}
              disabled={enviando || exito}
            />
            <Label htmlFor="confirmacion" className="text-sm font-normal cursor-pointer">
              Solicitar confirmación de recepción al paciente
            </Label>
          </div>

          {/* Mensajes de estado */}
          {error && (
            <div className="flex items-center gap-2 p-3 bg-red-50 rounded-lg">
              <AlertCircle className="h-4 w-4 text-red-500" />
              <p className="text-sm text-red-600">{error}</p>
            </div>
          )}

          {exito && (
            <div className="flex items-center gap-2 p-3 bg-green-50 rounded-lg">
              <CheckCircle className="h-4 w-4 text-green-500" />
              <p className="text-sm text-green-600">¡Receta enviada exitosamente!</p>
            </div>
          )}

          {/* Botones */}
          <div className="flex justify-end gap-3">
            <Button
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={enviando}
            >
              Cancelar
            </Button>
            <Button
              onClick={handleEnviar}
              disabled={!email || enviando || exito}
              className="bg-[#1E5C8E] hover:bg-[#3A8ABF]"
            >
              {enviando ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Enviando...
                </>
              ) : (
                <>
                  <Mail className="h-4 w-4 mr-2" />
                  Enviar Receta
                </>
              )}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
