import { useState } from 'react'
import { useWhatsApp } from '@/hooks/useWhatsApp'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'
import { MessageCircle, Send, Smartphone, Check, X, Clock } from 'lucide-react'

interface Props {
  cita: any
  paciente: any
}

export default function BotonWhatsAppCita({ cita, paciente }: Props) {
  const { crearRecordatorioCita, simularEnvio, simularRespuesta, sending } = useWhatsApp()
  const [showDialog, setShowDialog] = useState(false)
  const [mensajeCreado, setMensajeCreado] = useState<any>(null)
  const [respuestaSimulada, setRespuestaSimulada] = useState('')

  const handleCrearMensaje = async () => {
    if (!paciente?.telefono) {
      alert('El paciente no tiene teléfono registrado')
      return
    }

    const result = await crearRecordatorioCita({
      paciente_id: String(paciente.id),
      cita_id: String(cita.id),
      telefono: paciente.telefono,
      nombre_paciente: `${paciente.nombre} ${paciente.apellido}`,
      fecha_cita: cita.fecha,
      hora_cita: cita.hora_inicio,
      motivo: cita.motivo
    })

    if (result.success) {
      setMensajeCreado(result.data)
    }
  }

  const handleSimularEnvio = async () => {
    if (!mensajeCreado) return
    await simularEnvio(mensajeCreado.id)
    setMensajeCreado({ ...mensajeCreado, estado: 'enviado' })
  }

  const handleSimularRespuesta = async () => {
    if (!mensajeCreado || !respuestaSimulada) return
    await simularRespuesta(mensajeCreado.id, respuestaSimulada)
    setMensajeCreado({ ...mensajeCreado, estado: 'respondido', respuesta: respuestaSimulada })
    setRespuestaSimulada('')
  }

  const getEstadoColor = (estado: string) => {
    switch (estado) {
      case 'pendiente': return 'bg-yellow-100 text-yellow-700'
      case 'enviado': return 'bg-blue-100 text-blue-700'
      case 'entregado': return 'bg-purple-100 text-purple-700'
      case 'leido': return 'bg-green-100 text-green-700'
      case 'respondido': return 'bg-green-100 text-green-700'
      case 'error': return 'bg-red-100 text-red-700'
      default: return 'bg-gray-100 text-gray-700'
    }
  }

  const getEstadoIcono = (estado: string) => {
    switch (estado) {
      case 'pendiente': return <Clock className="h-4 w-4" />
      case 'enviado': return <Send className="h-4 w-4" />
      case 'respondido': return <Check className="h-4 w-4" />
      default: return <MessageCircle className="h-4 w-4" />
    }
  }

  return (
    <>
      <Button 
        variant="outline" 
        size="sm" 
        onClick={() => setShowDialog(true)}
        className="border-green-500 text-green-600 hover:bg-green-50"
      >
        <MessageCircle className="h-4 w-4 mr-2" /> WhatsApp
      </Button>

      <Dialog open={showDialog} onOpenChange={setShowDialog}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Smartphone className="h-5 w-5 text-green-600" />
              Recordatorio por WhatsApp
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            {/* Info del paciente */}
            <div className="p-3 bg-[#f8fafc] rounded-lg">
              <p className="text-sm font-medium">{paciente?.nombre} {paciente?.apellido}</p>
              <p className="text-xs text-[#8a9aaa]">📱 {paciente?.telefono || 'Sin teléfono'}</p>
              <p className="text-xs text-[#8a9aaa]">📅 {cita?.fecha} - {cita?.hora_inicio}</p>
            </div>

            {/* Estado del mensaje */}
            {mensajeCreado && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <Badge variant="outline" className={getEstadoColor(mensajeCreado.estado)}>
                    {getEstadoIcono(mensajeCreado.estado)}
                    <span className="ml-1">{mensajeCreado.estado.toUpperCase()}</span>
                  </Badge>
                  <span className="text-xs text-[#8a9aaa]">
                    {new Date(mensajeCreado.created_at).toLocaleString('es-GT')}
                  </span>
                </div>

                {/* Vista previa del mensaje */}
                <div className="p-3 bg-green-50 rounded-lg border border-green-200">
                  <p className="text-xs text-green-700 font-medium mb-1">Vista previa del mensaje:</p>
                  <p className="text-sm text-green-800 whitespace-pre-line">{mensajeCreado.mensaje}</p>
                </div>

                {/* Botón simular envío */}
                {mensajeCreado.estado === 'pendiente' && (
                  <Button onClick={handleSimularEnvio} className="w-full bg-green-600 hover:bg-green-700">
                    <Send className="h-4 w-4 mr-2" /> Simular Envío (Meta Business)
                  </Button>
                )}

                {/* Simular respuesta del paciente */}
                {mensajeCreado.estado === 'enviado' && (
                  <div className="space-y-2">
                    <p className="text-sm font-medium">Simular respuesta del paciente:</p>
                    <div className="flex gap-2">
                      <Button 
                        variant="outline" 
                        size="sm" 
                        onClick={() => setRespuestaSimulada('SI')}
                        className="flex-1 border-green-500 text-green-600"
                      >
                        <Check className="h-4 w-4 mr-1" /> SI
                      </Button>
                      <Button 
                        variant="outline" 
                        size="sm" 
                        onClick={() => setRespuestaSimulada('NO')}
                        className="flex-1 border-red-500 text-red-600"
                      >
                        <X className="h-4 w-4 mr-1" /> NO
                      </Button>
                    </div>
                    {respuestaSimulada && (
                      <Button onClick={handleSimularRespuesta} className="w-full bg-blue-600 hover:bg-blue-700">
                        <MessageCircle className="h-4 w-4 mr-2" /> Enviar respuesta simulada
                      </Button>
                    )}
                  </div>
                )}

                {/* Mostrar respuesta */}
                {mensajeCreado.respuesta && (
                  <div className="p-3 bg-blue-50 rounded-lg border border-blue-200">
                    <p className="text-xs text-blue-700 font-medium">Respuesta del paciente:</p>
                    <p className="text-sm text-blue-800 font-medium">{mensajeCreado.respuesta}</p>
                    <p className="text-xs text-blue-600 mt-1">
                      {new Date(mensajeCreado.respondido_en || '').toLocaleString('es-GT')}
                    </p>
                  </div>
                )}
              </div>
            )}

            {/* Botón crear mensaje */}
            {!mensajeCreado && (
              <Button 
                onClick={handleCrearMensaje} 
                disabled={sending || !paciente?.telefono}
                className="w-full bg-green-600 hover:bg-green-700"
              >
                <MessageCircle className="h-4 w-4 mr-2" /> 
                {sending ? 'Creando...' : 'Crear mensaje de recordatorio'}
              </Button>
            )}

            {!paciente?.telefono && (
              <p className="text-xs text-red-500 text-center">
                El paciente no tiene teléfono registrado. Agregue uno en la ficha del paciente.
              </p>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}
